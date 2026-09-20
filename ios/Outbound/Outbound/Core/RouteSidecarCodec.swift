import Foundation

nonisolated enum RouteSidecarCodec {
    private static let magic = Data([0x50, 0x53, 0x52, 0x54]) // PSRT
    private static let version: UInt8 = 1
    private static let coordinateScale = 1_000_000.0
    private static let elevationScale = 10.0

    static func encode(_ points: [SavedRoutePoint]) -> Data {
        guard points.count >= 2 else { return Data() }
        var data = magic
        data.append(version)
        appendVarint(UInt64(points.count), to: &data)
        var previousLatitude = Int64(0)
        var previousLongitude = Int64(0)
        var previousTimestamp = Int64(0)
        var previousAltitude: Int64 = 0
        for (index, point) in points.enumerated() {
            let latitude = Int64((point.latitude * coordinateScale).rounded())
            let longitude = Int64((point.longitude * coordinateScale).rounded())
            let timestamp = Int64(point.timestamp.timeIntervalSince1970.rounded())
            appendVarint(zigZag(index == 0 ? latitude : latitude - previousLatitude), to: &data)
            appendVarint(zigZag(index == 0 ? longitude : longitude - previousLongitude), to: &data)
            appendVarint(zigZag(index == 0 ? timestamp : timestamp - previousTimestamp), to: &data)
            var flags: UInt8 = point.startsNewSegment ? 1 : 0
            if point.altitude != nil { flags |= 2 }
            if point.verticalAccuracy != nil { flags |= 4 }
            data.append(flags)
            if let altitude = point.altitude {
                let scaled = Int64((altitude * elevationScale).rounded())
                appendVarint(zigZag(scaled - previousAltitude), to: &data)
                previousAltitude = scaled
            }
            if let accuracy = point.verticalAccuracy {
                appendVarint(UInt64(max(0, Int64((accuracy * elevationScale).rounded()))), to: &data)
            }
            previousLatitude = latitude
            previousLongitude = longitude
            previousTimestamp = timestamp
        }
        return data
    }

    static func decode(_ data: Data) throws -> [SavedRoutePoint] {
        guard data.count >= 6, data.prefix(4) == magic, data[4] == version else {
            throw RouteSidecarError.invalidFormat
        }
        var offset = 5
        let count = Int(try readVarint(data, offset: &offset))
        guard count >= 2, count <= 100_000 else { throw RouteSidecarError.invalidFormat }
        var points: [SavedRoutePoint] = []
        var previousLatitude: Int64 = 0
        var previousLongitude: Int64 = 0
        var previousTimestamp: Int64 = 0
        var previousAltitude: Int64 = 0
        for index in 0..<count {
            let latitude = previousLatitude + unZigZag(try readVarint(data, offset: &offset))
            let longitude = previousLongitude + unZigZag(try readVarint(data, offset: &offset))
            let timestamp = previousTimestamp + unZigZag(try readVarint(data, offset: &offset))
            guard offset < data.count else { throw RouteSidecarError.invalidFormat }
            let flags = data[offset]; offset += 1
            var altitude: Double?
            if flags & 2 != 0 {
                previousAltitude += unZigZag(try readVarint(data, offset: &offset))
                altitude = Double(previousAltitude) / elevationScale
            }
            let accuracy: Double?
            if flags & 4 != 0 {
                accuracy = Double(try readVarint(data, offset: &offset)) / elevationScale
            } else { accuracy = nil }
            points.append(SavedRoutePoint(
                timestamp: Date(timeIntervalSince1970: Double(timestamp)),
                latitude: Double(latitude) / coordinateScale,
                longitude: Double(longitude) / coordinateScale,
                altitude: altitude,
                verticalAccuracy: accuracy,
                startsNewSegment: flags & 1 != 0 || (index == 0)
            ))
            previousLatitude = latitude; previousLongitude = longitude; previousTimestamp = timestamp
        }
        return points
    }

    private static func zigZag(_ value: Int64) -> UInt64 { value >= 0 ? UInt64(value) * 2 : UInt64(-value) * 2 - 1 }
    private static func unZigZag(_ value: UInt64) -> Int64 { value & 1 == 0 ? Int64(value / 2) : -Int64(value / 2) - 1 }
    private static func appendVarint(_ value: UInt64, to data: inout Data) {
        var value = value
        while value >= 0x80 { data.append(UInt8(value & 0x7f) | 0x80); value >>= 7 }
        data.append(UInt8(value))
    }
    private static func readVarint(_ data: Data, offset: inout Int) throws -> UInt64 {
        var value: UInt64 = 0; var shift: UInt64 = 0
        while offset < data.count {
            let byte = data[offset]; offset += 1
            value |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift > 63 { throw RouteSidecarError.invalidFormat }
        }
        throw RouteSidecarError.invalidFormat
    }
}

nonisolated enum RouteSidecarError: Error { case invalidFormat }
