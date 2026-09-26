import Foundation

/// Reads whatever the runner picked in the Files app — a Strava `.zip`, an unzipped export folder,
/// or a handful of `.gpx` / `.tcx` files — into a flat list of archive entries.
///
/// Only activity payloads are read. Photos, club data, and social data that a Strava export also
/// contains are skipped before they are ever loaded, so the import stays small and private.
nonisolated enum StravaImportFileReader {
    static let supportedExtensions: Set<String> = ["gpx", "tcx", "fit", "csv", "gz", "zip"]
    static let maximumFileCount = 20_000
    static let maximumFileBytes = 64 * 1024 * 1024
    static let maximumTotalBytes = 512 * 1024 * 1024

    struct ReadResult: Sendable {
        let sourceName: String
        let selectionCount: Int
        let entries: [ImportedArchiveFile]
        let skipped: [StravaImportSkip]
    }

    static func read(urls: [URL]) -> ReadResult {
        var entries: [ImportedArchiveFile] = []
        var skipped: [StravaImportSkip] = []
        var totalBytes = 0

        for url in urls {
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }

            let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            if isDirectory {
                readDirectory(url, entries: &entries, skipped: &skipped)
                continue
            }

            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
                skipped.append(.init(id: "read:\(url.lastPathComponent)", fileName: url.lastPathComponent, reason: .unreadableFile))
                continue
            }
            totalBytes += data.count
            guard totalBytes <= maximumTotalBytes else {
                skipped.append(.init(id: "size:\(url.lastPathComponent)", fileName: url.lastPathComponent, reason: .unreadableFile))
                continue
            }

            if ImportArchiveReader.isZip(data) {
                do {
                    entries.append(contentsOf: try ImportArchiveReader.zipEntries(in: data))
                } catch {
                    skipped.append(.init(id: "zip:\(url.lastPathComponent)", fileName: url.lastPathComponent, reason: .unreadableFile))
                }
            } else if ImportArchiveReader.isGzip(data) {
                let innerName = url.deletingPathExtension().lastPathComponent.lowercased()
                if let expanded = try? ImportArchiveReader.gunzip(data) {
                    entries.append(ImportedArchiveFile(path: innerName, data: expanded))
                } else {
                    skipped.append(.init(id: "gz:\(url.lastPathComponent)", fileName: url.lastPathComponent, reason: .unreadableFile))
                }
            } else {
                entries.append(ImportedArchiveFile(path: url.lastPathComponent.lowercased(), data: data))
            }
        }

        let sourceName = urls.count == 1 ? (urls.first?.lastPathComponent ?? "") : ""
        return ReadResult(
            sourceName: sourceName,
            selectionCount: urls.count,
            entries: entries,
            skipped: skipped
        )
    }

    private static func readDirectory(
        _ directory: URL,
        entries: inout [ImportedArchiveFile],
        skipped: inout [StravaImportSkip]
    ) {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return }

        let basePath = directory.standardizedFileURL.path
        let totalLimit = maximumTotalBytes
        var totalBytes = 0

        for case let fileURL as URL in enumerator {
            guard entries.count < maximumFileCount, totalBytes <= totalLimit else { break }
            let fileExtension = fileURL.pathExtension.lowercased()
            guard supportedExtensions.contains(fileExtension) else { continue }

            let values = try? fileURL.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else { continue }
            let size = values?.fileSize ?? 0
            guard size <= maximumFileBytes else {
                skipped.append(.init(id: "size:\(fileURL.lastPathComponent)", fileName: fileURL.lastPathComponent, reason: .unreadableFile))
                continue
            }
            guard let data = try? Data(contentsOf: fileURL, options: .mappedIfSafe) else { continue }
            totalBytes += data.count

            var relative = fileURL.standardizedFileURL.path
            if relative.hasPrefix(basePath) { relative = String(relative.dropFirst(basePath.count)) }
            relative = relative.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !relative.isEmpty else { continue }
            entries.append(ImportedArchiveFile(path: relative.lowercased(), data: data))
        }
    }
}
