import Foundation

/// Reads a Strava data export and turns it into importable activities.
///
/// The export is not a documented, stable format, so the importer is deliberately forgiving:
///
/// - `activities.csv` supplies names, sports, dates, and `Filename` links when it is present.
/// - Parsed GPX and TCX files are authoritative for duration, distance, heart rate, and route.
/// - Rows whose file cannot be read (most commonly compressed FIT) still import as summary-only
///   activities when the export provides a usable date and duration.
/// - Nothing is invented: when a value cannot be recovered it stays `nil`.
nonisolated enum StravaExportImporter {
    static let supportedFileExtensions: Set<String> = ["gpx", "tcx"]

    static func review(
        sourceName: String,
        entries: [ImportedArchiveFile],
        existingExternalIDs: Set<String>
    ) -> StravaImportReview {
        var skipped: [StravaImportSkip] = []
        var candidates: [StravaImportCandidate] = []

        let decompressed = decompress(entries, skipped: &skipped)
        let summary = StravaExportSummary.parse(from: decompressed)

        var parsedByFileName: [String: ParsedActivityFile] = [:]
        var activityFiles: [ImportedArchiveFile] = []

        for entry in decompressed where isActivityFile(entry) {
            activityFiles.append(entry)
            guard supportedFileExtensions.contains(entry.fileExtension) else { continue }
            guard let parsed = ActivityFileParser.parse(data: entry.data) else {
                skipped.append(.init(id: "unreadable:\(entry.path)", fileName: entry.lastPathComponent, reason: .unreadableFile))
                continue
            }
            // Archives should hold one file per activity. If a duplicate name appears, the first
            // successfully parsed file stays authoritative so the review is deterministic.
            if parsedByFileName[entry.lastPathComponent] == nil {
                parsedByFileName[entry.lastPathComponent] = parsed
            }
        }

        let distanceUnit = StravaExportSummary.inferredDistanceUnit(
            rows: summary.rows,
            parsedByFileName: parsedByFileName
        )

        var seenExternalIDs = existingExternalIDs
        var matchedFileNames = Set<String>()

        // Summary rows keep their vendor identity, so repeat imports stay idempotent.
        for row in summary.rows {
            guard let externalID = row.externalID else { continue }
            if let fileName = row.fileName {
                matchedFileNames.insert((fileName as NSString).lastPathComponent.lowercased())
            }

            guard let startedAt = row.startedAt ?? parsedByFileName[normalizedFileName(row.fileName)]?.startedAt else {
                if row.fileName != nil {
                    skipped.append(.init(id: "date:\(externalID)", fileName: row.fileName ?? "", reason: .missingDate))
                }
                continue
            }

            let parsed = parsedByFileName[normalizedFileName(row.fileName)]
            let distance: Double?
            if let parsedDistance = parsed?.distanceMeters, parsedDistance > 0 {
                distance = parsedDistance
            } else if let value = row.distanceValue, let unit = distanceUnit {
                distance = unit.meters(fromExportValue: value)
            } else {
                distance = nil
            }
            let duration = parsed?.durationSeconds ?? row.elapsedSeconds

            guard let duration, duration > 0 else {
                skipped.append(.init(id: "metrics:\(externalID)", fileName: row.fileName ?? "", reason: .missingMetrics))
                continue
            }
            guard !seenExternalIDs.contains(externalID) else {
                skipped.append(.init(id: externalID, fileName: row.fileName ?? "", reason: .duplicate))
                continue
            }

            seenExternalIDs.insert(externalID)
            candidates.append(
                StravaImportCandidate(
                    id: externalID,
                    title: row.title ?? parsed?.titleFromFile ?? "",
                    sport: row.sport ?? parsed?.sport ?? .other,
                    startedAt: parsed?.startedAt ?? startedAt,
                    durationSeconds: duration,
                    distanceMeters: distance,
                    elevationGainMeters: parsed?.elevationGainMeters,
                    averageHeartRateBPM: parsed?.averageHeartRateBPM,
                    maxHeartRateBPM: parsed?.maxHeartRateBPM,
                    averageCadence: parsed?.averageCadence,
                    routePoints: parsed?.routePoints ?? [],
                    origin: parsed != nil ? .activityFile : .exportSummary,
                    fileName: row.fileName,
                    externalID: externalID
                )
            )
        }

        // Files without a matching summary row still import, using a stable path-derived identity.
        for file in activityFiles {
            let normalizedName = file.lastPathComponent.lowercased()
            guard !matchedFileNames.contains(normalizedName) else { continue }
            let externalID = "strava-file:\(file.path)"
            guard let parsed = parsedByFileName[file.lastPathComponent], let startedAt = parsed.startedAt else {
                skipped.append(.init(id: "file:\(file.path)", fileName: file.lastPathComponent, reason: .unreadableFile))
                continue
            }
            guard !seenExternalIDs.contains(externalID) else {
                skipped.append(.init(id: externalID, fileName: file.lastPathComponent, reason: .duplicate))
                continue
            }
            seenExternalIDs.insert(externalID)
            candidates.append(
                StravaImportCandidate(
                    id: externalID,
                    title: parsed.titleFromFile ?? "",
                    sport: parsed.sport ?? .other,
                    startedAt: startedAt,
                    durationSeconds: parsed.durationSeconds ?? 0,
                    distanceMeters: parsed.distanceMeters,
                    elevationGainMeters: parsed.elevationGainMeters,
                    averageHeartRateBPM: parsed.averageHeartRateBPM,
                    maxHeartRateBPM: parsed.maxHeartRateBPM,
                    averageCadence: parsed.averageCadence,
                    routePoints: parsed.routePoints,
                    origin: .activityFile,
                    fileName: file.lastPathComponent,
                    externalID: externalID
                )
            )
        }

        if candidates.isEmpty, activityFiles.isEmpty, summary.rows.isEmpty {
            skipped.append(.init(id: "empty", fileName: sourceName, reason: .noActivityFiles))
        }

        return StravaImportReview(
            sourceName: sourceName,
            candidates: candidates.sorted { $0.startedAt > $1.startedAt },
            skipped: skipped
        )
    }

    // MARK: - Helpers

    private static func normalizedFileName(_ fileName: String?) -> String {
        guard let fileName else { return "" }
        return (fileName as NSString).lastPathComponent.lowercased()
    }

    /// Only files that look like export activity payloads are considered; the archive also carries
    /// photos, club data, and social data that Plainstride intentionally ignores.
    private static func isActivityFile(_ entry: ImportedArchiveFile) -> Bool {
        let ext = entry.fileExtension
        if supportedFileExtensions.contains(ext) || ext == "fit" { return true }
        return entry.path.contains("activities/")
    }

    private static func decompress(
        _ entries: [ImportedArchiveFile],
        skipped: inout [StravaImportSkip]
    ) -> [ImportedArchiveFile] {
        entries.map { entry in
            guard entry.fileExtension == "gz" else { return entry }
            guard let expanded = try? ImportArchiveReader.gunzip(entry.data) else {
                skipped.append(.init(id: "gz:\(entry.path)", fileName: entry.lastPathComponent, reason: .unreadableFile))
                return entry
            }
            return ImportedArchiveFile(path: String(entry.path.dropLast(3)), data: expanded)
        }
    }
}

/// Distance units as written by the Strava export. The CSV does not record its unit, so the importer
/// infers it by comparing summary rows against files it parsed successfully.
nonisolated enum ExportDistanceUnit: Sendable, Equatable {
    case meters
    case kilometers
    case miles

    func meters(fromExportValue value: Double) -> Double {
        switch self {
        case .meters: value
        case .kilometers: value * 1_000
        case .miles: value * 1_609.344
        }
    }
}

/// The subset of one `activities.csv` row the importer uses.
nonisolated struct StravaExportRow: Sendable, Equatable {
    let activityID: String?
    let startedAt: Date?
    let title: String?
    let sport: ImportedActivitySport?
    let elapsedSeconds: Int?
    let distanceValue: Double?
    let fileName: String?

    var externalID: String? {
        guard let activityID, !activityID.isEmpty else { return nil }
        return "strava:\(activityID)"
    }
}

nonisolated struct StravaExportSummary: Sendable, Equatable {
    let rows: [StravaExportRow]

    static let empty = StravaExportSummary(rows: [])

    /// Finds and parses `activities.csv` anywhere in the export.
    static func parse(from entries: [ImportedArchiveFile]) -> StravaExportSummary {
        guard let csv = entries.first(where: { $0.lastPathComponent.lowercased() == "activities.csv" })
            ?? entries.first(where: { $0.fileExtension == "csv" })
        else { return .empty }
        guard let text = String(data: csv.data, encoding: .utf8) else { return .empty }
        return parseCSV(text)
    }

    static func parseCSV(_ text: String) -> StravaExportSummary {
        let table = CSVTable(text)
        guard let header = table.rows.first else { return .empty }
        let columns = Dictionary(
            header.enumerated().map { (normalizedHeader($0.element), $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )

        func value(_ row: [String], _ keys: [String]) -> String? {
            for key in keys {
                if let index = columns[key], index < row.count {
                    let trimmed = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { return trimmed }
                }
            }
            return nil
        }

        let rows: [StravaExportRow] = table.rows.dropFirst().compactMap { row in
            guard !row.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else { return nil }
            let activityID = value(row, ["activityid"])
            let title = value(row, ["activityname"])
            return StravaExportRow(
                activityID: activityID,
                startedAt: value(row, ["activitydate"]).flatMap(ActivityFileParser.date(fromVendorString:)),
                title: title.flatMap { $0.isEmpty ? nil : $0 },
                sport: ImportedActivitySport.from(vendorValue: value(row, ["activitytype"])),
                elapsedSeconds: value(row, ["elapsedtime"]).flatMap(seconds(fromString:))
                    ?? value(row, ["movingtime"]).flatMap(seconds(fromString:)),
                distanceValue: value(row, ["distance"]).flatMap(Double.init),
                fileName: value(row, ["filename"])
            )
        }
        return StravaExportSummary(rows: rows)
    }

    /// Derives the export distance unit from rows where both the summary value and a parsed file exist.
    /// Returns `nil` when the evidence is missing or ambiguous, so summary-only rows omit distance
    /// rather than reporting a wrong one.
    static func inferredDistanceUnit(
        rows: [StravaExportRow],
        parsedByFileName: [String: ParsedActivityFile]
    ) -> ExportDistanceUnit? {
        var ratios: [Double] = []
        for row in rows {
            guard let value = row.distanceValue, value > 0, let fileName = row.fileName else { continue }
            let normalized = (fileName as NSString).lastPathComponent.lowercased()
            guard let meters = parsedByFileName[normalized]?.distanceMeters, meters > 500 else { continue }
            ratios.append(value / meters)
        }
        guard ratios.count >= 2 else { return nil }
        let sorted = ratios.sorted()
        let median = sorted[sorted.count / 2]

        let candidates: [(ExportDistanceUnit, Double)] = [
            (.meters, 1),
            (.kilometers, 1 / 1_000.0),
            (.miles, 1 / 1_609.344)
        ]
        let best = candidates.min { abs($0.1 - median) < abs($1.1 - median) }
        guard let best, abs(best.1 - median) <= best.1 * 0.2 else { return nil }
        return best.0
    }

    private static func normalizedHeader(_ header: String) -> String {
        header.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func seconds(fromString value: String) -> Int? {
        let cleaned = value.replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(cleaned), seconds.isFinite, seconds >= 0 else { return nil }
        return Int(seconds.rounded())
    }
}

/// Minimal RFC 4180 CSV reader that understands quoted fields, embedded commas, and newlines.
nonisolated struct CSVTable: Sendable, Equatable {
    let rows: [[String]]

    init(_ text: String) {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var index = text.startIndex

        func endField() {
            row.append(field)
            field = ""
        }
        func endRow() {
            endField()
            rows.append(row)
            row = []
        }

        while index < text.endIndex {
            let character = text[index]
            if inQuotes {
                if character == "\"" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\"" {
                        field.append("\"")
                        index = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"":
                    inQuotes = true
                case ",":
                    endField()
                case "\r":
                    break
                case "\n":
                    endRow()
                default:
                    field.append(character)
                }
            }
            index = text.index(after: index)
        }

        if !field.isEmpty || !row.isEmpty {
            endRow()
        }
        rows.removeAll { $0.allSatisfy { $0.isEmpty } }
        self.rows = rows
    }
}
