import Foundation

/// Parses GPX and TCX activity files into a normalized `ParsedActivityFile`.
///
/// The two formats share enough structure that one tolerant delegate handles both: it matches on
/// normalized (lowercased, namespace-stripped) element names and only records values inside a track
/// point. FIT files are binary and intentionally unsupported here.
nonisolated enum ActivityFileParser {
    /// Upper bound on parsed route samples so a malformed file cannot exhaust memory.
    static let maximumRoutePoints = 200_000

    static func parse(data: Data) -> ParsedActivityFile? {
        let delegate = ActivityXMLParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else { return nil }
        return delegate.makeResult()
    }
}

/// Mutable accumulator that XMLParser feeds synchronously on the calling thread.
final class ActivityXMLParserDelegate: NSObject, XMLParserDelegate {
    private var format: Format?
    private var activitySportAttribute: String?
    private var titleFromFile: String?

    private var routePoints: [ImportedRoutePoint] = []
    private var pendingPoint: ImportedRoutePoint?
    private var pendingSegmentStart = false

    private var startTime: Date?
    private var endTime: Date?
    private var lapDurationSeconds: Double?
    private var lapDistanceMeters: Double?
    private var trackDistanceMeters: Double?
    private var elevationGain: Double = 0
    private var lastAltitude: Double?
    private var heartRateSamples: [Int] = []
    private var cadenceSamples: [Int] = []

    private var elementStack: [String] = []
    private var textBuffer = ""
    private var inTrackPoint = false
    private var inLap = false
    private var nextPointStartsSegment = false
    private var reachedPointLimit = false

    private enum Format {
        case gpx
        case tcx
    }

    // MARK: - XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String]
    ) {
        let name = Self.normalizedName(elementName)
        elementStack.append(name)
        textBuffer = ""

        if format == nil {
            if name == "gpx" { format = .gpx }
            if name == "trainingcenterdatabase" || name == "activities" { format = .tcx }
        }

        switch name {
        case "trkseg", "track":
            if !routePoints.isEmpty || pendingPoint != nil { nextPointStartsSegment = true }
        case "trkpt", "trackpoint", "rtept":
            inTrackPoint = true
            pendingPoint = nil
            if reachedPointLimit { return }
            if name == "trkpt" || name == "rtept" {
                guard let latitude = attributeDict["lat"].flatMap(Double.init),
                      let longitude = attributeDict["lon"].flatMap(Double.init)
                else { return }
                pendingPoint = ImportedRoutePoint(
                    timestamp: nil,
                    latitude: latitude,
                    longitude: longitude,
                    altitude: nil,
                    startsNewSegment: nextPointStartsSegment
                )
                nextPointStartsSegment = false
            }
        case "lap":
            inLap = true
            if let start = attributeDict["StartTime"] ?? attributeDict["starttime"] {
                startTime = startTime ?? ActivityFileParser.date(fromVendorString: start)
            }
        case "activity":
            if let value = attributeDict["Sport"] ?? attributeDict["sport"] {
                activitySportAttribute = value
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inTrackPoint || elementStack.last.map({ Self.isTextualElement($0) }) == true else { return }
        textBuffer.append(string)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        let name = Self.normalizedName(elementName)
        let parentName = elementStack.count >= 2 ? elementStack[elementStack.count - 2] : nil
        let text = textBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
        elementStack.removeLast()
        textBuffer = ""

        switch name {
        case "trkpt", "rtept", "trackpoint":
            if let point = pendingPoint, !reachedPointLimit {
                routePoints.append(point)
                if routePoints.count >= ActivityFileParser.maximumRoutePoints { reachedPointLimit = true }
            }
            pendingPoint = nil
            inTrackPoint = false
        case "ele", "altitudemeters", "altitude":
            if inTrackPoint, let altitude = Double(text) { applyAltitude(altitude) }
        case "time":
            guard inTrackPoint || inLap else { break }
            if let date = ActivityFileParser.date(fromVendorString: text) {
                if inTrackPoint {
                    applyTimestamp(date)
                } else {
                    startTime = startTime ?? date
                    endTime = max(endTime ?? date, date)
                }
            }
        case "latitudedegrees":
            guard inTrackPoint, let latitude = Double(text) else { break }
            pendingPoint = ImportedRoutePoint(
                timestamp: pendingPoint?.timestamp,
                latitude: latitude,
                longitude: pendingPoint?.longitude ?? 0,
                altitude: pendingPoint?.altitude,
                startsNewSegment: pendingPoint?.startsNewSegment ?? nextPointStartsSegment
            )
            nextPointStartsSegment = false
        case "longitudedegrees":
            guard inTrackPoint, let longitude = Double(text), let existing = pendingPoint else { break }
            pendingPoint = ImportedRoutePoint(
                timestamp: existing.timestamp,
                latitude: existing.latitude,
                longitude: longitude,
                altitude: existing.altitude,
                startsNewSegment: existing.startsNewSegment
            )
        case "hr":
            guard inTrackPoint, let heartRate = Self.intValue(text), heartRate > 0, heartRate < 300 else { break }
            heartRateSamples.append(heartRate)
        case "value":
            // TCX wraps heart rate in `HeartRateBpm/Value`.
            guard inTrackPoint, parentName == "heartratebpm", let heartRate = Self.intValue(text),
                  heartRate > 0, heartRate < 300
            else { break }
            heartRateSamples.append(heartRate)
        case "cad", "cadence":
            guard inTrackPoint, let cadence = Self.intValue(text), cadence > 0, cadence < 400 else { break }
            cadenceSamples.append(cadence)
        case "type":
            // GPX track type, for example `running` or `cycling`.
            if format == .gpx, !inTrackPoint, !text.isEmpty, activitySportAttribute == nil {
                activitySportAttribute = text
            }
        case "totaltimeseconds":
            if let seconds = Double(text) { lapDurationSeconds = seconds }
        case "distancemeters":
            if let meters = Double(text) {
                if inTrackPoint {
                    trackDistanceMeters = meters
                } else {
                    lapDistanceMeters = meters
                }
            }
        case "name":
            if titleFromFile == nil, !inTrackPoint, format == .gpx, !text.isEmpty, text != "0" {
                titleFromFile = text
            }
        case "lap":
            inLap = false
        default:
            break
        }
    }

    // MARK: - Accumulation

    private func applyAltitude(_ altitude: Double) {
        if let previous = lastAltitude, altitude - previous > 1 {
            elevationGain += altitude - previous
        }
        lastAltitude = altitude
        guard var pending = pendingPoint else { return }
        pending = ImportedRoutePoint(
            timestamp: pending.timestamp,
            latitude: pending.latitude,
            longitude: pending.longitude,
            altitude: altitude,
            startsNewSegment: pending.startsNewSegment
        )
        pendingPoint = pending
    }

    private func applyTimestamp(_ date: Date) {
        if startTime == nil { startTime = date }
        endTime = max(endTime ?? date, date)
        guard let pending = pendingPoint else { return }
        pendingPoint = ImportedRoutePoint(
            timestamp: date,
            latitude: pending.latitude,
            longitude: pending.longitude,
            altitude: pending.altitude,
            startsNewSegment: pending.startsNewSegment
        )
    }

    // MARK: - Result

    func makeResult() -> ParsedActivityFile? {
        guard format != nil else { return nil }
        let resolvedSport = ImportedActivitySport.from(vendorValue: activitySportAttribute)

        var duration: Int?
        if let lapDurationSeconds, lapDurationSeconds > 0, lapDurationSeconds < 7 * 24 * 3_600 {
            duration = Int(lapDurationSeconds.rounded())
        } else if let startTime, let endTime, endTime > startTime {
            duration = Int(endTime.timeIntervalSince(startTime).rounded())
        }

        var distance = lapDistanceMeters ?? trackDistanceMeters
        if distance == nil, routePoints.count > 1 {
            distance = Self.routeDistanceMeters(routePoints)
        }

        let heartRate: [Int]? = heartRateSamples.isEmpty ? nil : heartRateSamples
        return ParsedActivityFile(
            sport: resolvedSport,
            startedAt: startTime,
            durationSeconds: duration,
            distanceMeters: distance.map { max(0, $0) },
            elevationGainMeters: elevationGain > 1 ? elevationGain : nil,
            averageHeartRateBPM: heartRate.map { Int((Double($0.reduce(0, +)) / Double($0.count)).rounded()) },
            maxHeartRateBPM: heartRate.map { $0.max() ?? 0 },
            averageCadence: cadenceSamples.isEmpty
                ? nil
                : Int((Double(cadenceSamples.reduce(0, +)) / Double(cadenceSamples.count)).rounded()),
            routePoints: routePoints,
            titleFromFile: titleFromFile
        )
    }

    // MARK: - Helpers

    private static func normalizedName(_ elementName: String) -> String {
        let stripped = elementName.split(separator: ":").last.map(String.init) ?? elementName
        return stripped.lowercased()
    }

    private static func isTextualElement(_ name: String) -> Bool {
        switch name {
        case "ele", "altitudemeters", "altitude", "time", "hr", "value", "cad", "cadence",
             "latitudedegrees", "longitudedegrees", "totaltimeseconds", "distancemeters", "name", "type":
            return true
        default:
            return false
        }
    }

    private static func intValue(_ text: String) -> Int? {
        guard let value = Double(text), value.isFinite, value >= 0 else { return nil }
        return Int(value.rounded())
    }

    /// Great-circle distance so imported activities always carry a usable distance even when the
    /// source file never wrote one.
    static func routeDistanceMeters(_ points: [ImportedRoutePoint]) -> Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for index in 1..<points.count {
            let previous = points[index - 1]
            let current = points[index]
            guard !current.startsNewSegment else { continue }
            total += haversineMeters(
                latitudeA: previous.latitude,
                longitudeA: previous.longitude,
                latitudeB: current.latitude,
                longitudeB: current.longitude
            )
        }
        return total
    }

    static func haversineMeters(
        latitudeA: Double,
        longitudeA: Double,
        latitudeB: Double,
        longitudeB: Double
    ) -> Double {
        let earthRadius = 6_371_008.8
        let latitudeDelta = (latitudeB - latitudeA) * .pi / 180
        let longitudeDelta = (longitudeB - longitudeA) * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(latitudeA * .pi / 180) * cos(latitudeB * .pi / 180)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return 2 * earthRadius * asin(min(1, sqrt(a)))
    }
}

nonisolated extension ActivityFileParser {
    /// Formats seen in activity exports across GPX, TCX, and Strava archive CSV rows.
    ///
    /// Formatters are created per call because they are not `Sendable`; imports run off the main
    /// actor, so a shared cache would need its own synchronization for little benefit.
    static func date(fromVendorString value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: trimmed) { return date }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }

        for format in fallbackFormats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    private static let fallbackFormats = [
        "MMM d, yyyy, h:mm:ss a",
        "MMM d, yyyy, HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
        "M/d/yyyy h:mm:ss a",
        "yyyy/MM/dd HH:mm:ss"
    ]
}
