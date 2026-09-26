import Compression
import Foundation

/// A single file read out of a ZIP archive or a folder-style selection.
nonisolated struct ImportedArchiveFile: Sendable, Equatable {
    /// Lowercased, `/`-separated path inside the archive.
    let path: String
    let data: Data
}

nonisolated enum ImportArchiveError: Error, Equatable {
    case truncated
    case unsupportedCompression
    case zip64Unsupported
    case tooLarge
}

/// Minimal, dependency-free reader for the ZIP and gzip containers used by activity exports.
///
/// It intentionally supports only what activity archives contain: stored and deflated entries
/// without encryption, plus single-member gzip streams. Anything else surfaces as a typed error
/// so the import review can report an unreadable file instead of guessing.
nonisolated enum ImportArchiveReader {
    /// Upper bound for a single decompressed entry. Export archives hold one file per activity,
    /// so a generous cap still protects the app from a hostile or corrupt size header.
    static let maximumEntryBytes = 128 * 1024 * 1024

    /// Upper bound for everything decompressed from one selection. Reading a whole export at once
    /// keeps the importer simple; oversized archives fail with a clear message instead of
    /// exhausting memory.
    static let maximumTotalBytes = 512 * 1024 * 1024

    static func isZip(_ data: Data) -> Bool {
        data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06])
    }

    static func isGzip(_ data: Data) -> Bool {
        data.starts(with: [0x1F, 0x8B])
    }

    // MARK: - Gzip

    /// Decompresses a single-member gzip stream, including optional extra, name, and comment fields.
    static func gunzip(_ data: Data) throws -> Data {
        guard data.count > 18, isGzip(data) else { throw ImportArchiveError.truncated }
        let bytes = [UInt8](data)
        guard bytes[2] == 0x08 else { throw ImportArchiveError.unsupportedCompression }
        let flags = bytes[3]
        var index = 10

        if flags & 0x04 != 0 { // FEXTRA
            guard index + 2 <= bytes.count else { throw ImportArchiveError.truncated }
            let length = Int(bytes[index]) | (Int(bytes[index + 1]) << 8)
            index += 2 + length
        }
        if flags & 0x08 != 0 { // FNAME
            index = try skipZeroTerminated(bytes, from: index)
        }
        if flags & 0x10 != 0 { // FCOMMENT
            index = try skipZeroTerminated(bytes, from: index)
        }
        if flags & 0x02 != 0 { // FHCRC
            index += 2
        }
        guard index < bytes.count else { throw ImportArchiveError.truncated }

        let payload = Data(bytes[index...])
        return try inflateRaw(payload, expectedSize: nil)
    }

    private static func skipZeroTerminated(_ bytes: [UInt8], from index: Int) throws -> Int {
        var cursor = index
        while cursor < bytes.count, bytes[cursor] != 0 { cursor += 1 }
        guard cursor < bytes.count else { throw ImportArchiveError.truncated }
        return cursor + 1
    }

    // MARK: - ZIP

    static func zipEntries(in data: Data) throws -> [ImportedArchiveFile] {
        guard data.count > 22 else { throw ImportArchiveError.truncated }
        guard let endOffset = endOfCentralDirectoryOffset(in: data) else { throw ImportArchiveError.truncated }

        let entryCount = Int(readUInt16(data, at: endOffset + 10))
        let directoryOffset = Int(readUInt32(data, at: endOffset + 16))
        guard directoryOffset > 0, directoryOffset < data.count else { throw ImportArchiveError.truncated }

        var files: [ImportedArchiveFile] = []
        files.reserveCapacity(entryCount)
        var cursor = directoryOffset
        var totalBytes = 0

        for _ in 0..<entryCount {
            guard readUInt32(data, at: cursor) == 0x0201_4B50 else { throw ImportArchiveError.truncated }
            let method = readUInt16(data, at: cursor + 10)
            let compressedSize = Int(readUInt32(data, at: cursor + 20))
            let uncompressedSize = Int(readUInt32(data, at: cursor + 24))
            let nameLength = Int(readUInt16(data, at: cursor + 28))
            let extraLength = Int(readUInt16(data, at: cursor + 30))
            let commentLength = Int(readUInt16(data, at: cursor + 32))
            let localHeaderOffset = Int(readUInt32(data, at: cursor + 42))

            if compressedSize == 0xFFFF_FFFF || uncompressedSize == 0xFFFF_FFFF || localHeaderOffset == 0xFFFF_FFFF {
                throw ImportArchiveError.zip64Unsupported
            }

            let nameStart = cursor + 46
            guard nameStart + nameLength <= data.count else { throw ImportArchiveError.truncated }
            let name = String(decoding: data[(data.startIndex + nameStart)..<(data.startIndex + nameStart + nameLength)], as: UTF8.self)
            cursor = nameStart + nameLength + extraLength + commentLength

            guard !name.hasSuffix("/") else { continue } // directory entry
            totalBytes += uncompressedSize
            guard totalBytes <= maximumTotalBytes else { throw ImportArchiveError.tooLarge }
            guard let payload = entryPayload(
                in: data,
                localHeaderOffset: localHeaderOffset,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize
            ) else { continue }

            files.append(ImportedArchiveFile(path: name.lowercased(), data: payload))
        }
        return files
    }

    private static func entryPayload(
        in data: Data,
        localHeaderOffset: Int,
        method: UInt16,
        compressedSize: Int,
        uncompressedSize: Int
    ) -> Data? {
        guard readUInt32(data, at: localHeaderOffset) == 0x0403_4B50 else { return nil }
        let nameLength = Int(readUInt16(data, at: localHeaderOffset + 26))
        let extraLength = Int(readUInt16(data, at: localHeaderOffset + 28))
        let start = localHeaderOffset + 30 + nameLength + extraLength
        guard start >= 0, compressedSize >= 0, start + compressedSize <= data.count else { return nil }
        guard uncompressedSize <= maximumEntryBytes else { return nil }
        let payload = data[(data.startIndex + start)..<(data.startIndex + start + compressedSize)]

        switch method {
        case 0:
            return Data(payload)
        case 8:
            return try? inflateRaw(Data(payload), expectedSize: uncompressedSize)
        default:
            return nil
        }
    }

    /// Returns the offset of the end-of-central-directory record by scanning backwards for its signature.
    private static func endOfCentralDirectoryOffset(in data: Data) -> Int? {
        let minimumRecordSize = 22
        let maximumCommentLength = 65_535
        let earliest = max(0, data.count - minimumRecordSize - maximumCommentLength)
        var offset = data.count - minimumRecordSize
        while offset >= earliest {
            if readUInt32(data, at: offset) == 0x0605_4B50 { return offset }
            offset -= 1
        }
        return nil
    }

    // MARK: - Raw DEFLATE

    /// Inflates a raw DEFLATE stream. The buffer grows until the decoder stops filling it.
    static func inflateRaw(_ input: Data, expectedSize: Int?) throws -> Data {
        guard !input.isEmpty else { return Data() }
        var capacity = max(expectedSize ?? 0, input.count * 4, 64 * 1024)
        capacity = min(capacity, maximumEntryBytes)

        while true {
            if let decoded = attemptInflate(input, capacity: capacity) {
                if decoded.count < capacity || capacity >= maximumEntryBytes {
                    return decoded
                }
                // Output filled the buffer exactly, so it may have been truncated.
                capacity = min(capacity * 2, maximumEntryBytes)
                continue
            }
            guard capacity < maximumEntryBytes else { throw ImportArchiveError.truncated }
            capacity = min(capacity * 2, maximumEntryBytes)
        }
    }

    private static func attemptInflate(_ input: Data, capacity: Int) -> Data? {
        guard capacity > 0 else { return nil }
        var destination = [UInt8](repeating: 0, count: capacity)
        let written = input.withUnsafeBytes { raw -> Int in
            let source = raw.bindMemory(to: UInt8.self)
            guard let sourceAddress = source.baseAddress else { return 0 }
            return destination.withUnsafeMutableBufferPointer { buffer -> Int in
                guard let destinationAddress = buffer.baseAddress else { return 0 }
                return compression_decode_buffer(
                    destinationAddress,
                    capacity,
                    sourceAddress,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }
        guard written > 0 else { return nil }
        return Data(destination[0..<written])
    }

    // MARK: - Little-endian reads

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        let start = data.startIndex + offset
        return UInt16(data[start]) | (UInt16(data[start + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        let start = data.startIndex + offset
        return UInt32(data[start])
            | (UInt32(data[start + 1]) << 8)
            | (UInt32(data[start + 2]) << 16)
            | (UInt32(data[start + 3]) << 24)
    }
}

nonisolated extension ImportedArchiveFile {
    var fileExtension: String {
        (path as NSString).pathExtension
    }

    var lastPathComponent: String {
        (path as NSString).lastPathComponent
    }
}
