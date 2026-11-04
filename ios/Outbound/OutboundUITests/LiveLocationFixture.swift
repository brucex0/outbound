import Foundation
import Network
import XCTest

/// Loopback-only live group API for the live-location freshness UI tests.
///
/// The roster deliberately mixes a fresh fix with a fix older than the 15-second
/// freshness window, and every recovery check/edit response reports an older
/// measurement than the join snapshot so a regression that trusts checkpoints
/// backwards would move the displayed age and coordinates backwards.
final class LiveLocationFixture: @unchecked Sendable {
    struct RecordedRequest {
        let method: String
        let path: String
        let body: [String: Any]
    }

    private let listener: NWListener
    private let queue = DispatchQueue(label: "LiveLocationFixture")
    private let lock = NSLock()
    private var requests: [RecordedRequest] = []


    static let sessionID = "ui-live-location"
    static let eventID = "ui-recovery-event"

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() throws -> String {
        let ready = XCTestExpectation(description: "Loopback fixture is ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let port = listener.port else {
            throw FixtureError.failedToStart
        }
        return "http://127.0.0.1:\(port.rawValue)"
    }

    func stop() { listener.cancel() }

    func count(_ method: String, _ path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.method == method && $0.path == path }.count
    }

    func bodies(_ method: String, _ path: String) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.method == method && $0.path == path }.map(\.body)
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffered
            if let data { bytes.append(data) }
            guard let head = String(data: bytes, encoding: .utf8),
                  let headerEnd = head.range(of: "\r\n\r\n") else {
                if complete || error != nil { connection.cancel() }
                else { self.receive(connection, buffered: bytes) }
                return
            }
            let header = head[..<headerEnd.lowerBound]
            let bodyStart = bytes.index(bytes.startIndex, offsetBy: head.distance(from: head.startIndex, to: headerEnd.upperBound))
            let body = bytes[bodyStart...]
            let contentLength = header
                .components(separatedBy: "\r\n")
                .first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":")[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            guard body.count >= contentLength else {
                if complete || error != nil { connection.cancel() }
                else { self.receive(connection, buffered: bytes) }
                return
            }
            let requestLine = header.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard requestLine.count >= 2 else { connection.cancel(); return }
            let method = String(requestLine[0])
            let path = String(requestLine[1]).components(separatedBy: "?").first ?? ""
            let json = (try? JSONSerialization.jsonObject(with: Data(body.prefix(contentLength)))) as? [String: Any] ?? [:]
            self.lock.lock()
            self.requests.append(RecordedRequest(method: method, path: path, body: json))
            self.lock.unlock()
            let payload = self.response(method: method, path: path, body: json)
            let encoded = try! JSONSerialization.data(withJSONObject: payload ?? ["error": "synthetic_fixture_unavailable"])
            let status = payload == nil ? 404 : 200
            var response = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\nContent-Type: application/json\r\nContent-Length: \(encoded.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(encoded)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func response(method: String, path: String, body: [String: Any]) -> [String: Any]? {
        if method == "GET", path == "/social/activity-events/\(Self.eventID)" { return event() }
        if method == "POST", path == "/live/group-runs/activity-events/\(Self.eventID)" { return group(participantsState: .joined) }
        if method == "GET", path == "/live/group-runs/\(Self.sessionID)" { return group(participantsState: .olderCheckpoint) }
        if method == "PATCH", path == "/live/group-runs/\(Self.sessionID)/participants/me/location" {
            return group(participantsState: .olderCheckpoint, currentUserBody: body)
        }
        if method == "POST", path == "/live/group-runs/\(Self.sessionID)/participants/me/finish" {
            return group(participantsState: .olderCheckpoint, currentUserStatus: "finished")
        }
        if method == "POST", path == "/live/group-runs/\(Self.sessionID)/participants/me/leave" {
            return group(participantsState: .olderCheckpoint, currentUserStatus: "left")
        }
        if method == "POST", path == "/live/group-runs/\(Self.sessionID)/end" {
            return group(participantsState: .olderCheckpoint, currentUserStatus: "left", status: "ended")
        }
        return nil
    }

    private enum ParticipantsState { case joined, olderCheckpoint }

    private static let names = ["Fixture Runner", "Alice Lee", "Maya Rivera"]
    private static var people: [[String: Any]] {
        names.enumerated().map { ["id": "person-\($0.offset + 1)", "displayName": $0.element, "avatarUrl": NSNull()] }
    }

    private func timestamp(_ offset: Double, from anchor: Date) -> String {
        ISO8601DateFormatter().string(from: anchor.addingTimeInterval(offset))
    }

    private func group(
        participantsState: ParticipantsState,
        currentUserBody: [String: Any] = [:],
        currentUserStatus: String = "active",
        status: String = "active"
    ) -> [String: Any] {
        // Group timestamps are anchored to the moment each roster is served. The
        // group API is realtime-only in this build, so nothing refreshes a seeded
        // fix afterwards and a pin must expire from the display clock alone.
        let anchor = Date()
        // The join snapshot is fresh; every later checkpoint reports an older
        // measurement at a different coordinate for Alice.
        let aliceOffset: Double = participantsState == .joined ? -2 : -45
        let aliceLatitude: Double = participantsState == .joined ? 47.671 : 47.700
        let mayaOffset: Double = -40
        let currentLatitude = (currentUserBody["latitude"] as? NSNumber)?.doubleValue ?? 47.670
        let currentLongitude = (currentUserBody["longitude"] as? NSNumber)?.doubleValue ?? -122.120
        let currentMeasuredAt = (currentUserBody["recordedAt"] as? String) ?? timestamp(0, from: anchor)
        let participants: [[String: Any]] = [
            [
                "id": "member-1", "userId": "person-1", "displayName": Self.names[0],
                "status": currentUserStatus, "joinedAt": timestamp(-60, from: anchor), "leftAt": NSNull(),
                "lastLocationAt": currentUserStatus == "active" ? currentMeasuredAt : NSNull(),
                "lastLocation": currentUserStatus == "active"
                    ? ["latitude": currentLatitude, "longitude": currentLongitude, "altitudeM": 12.0, "accuracyM": 5.0]
                    : NSNull(),
                "lastActivitySnapshot": ["elapsedSeconds": 45, "distanceM": 180.0, "paceSecondsPerKM": 320.0],
            ],
            [
                "id": "member-2", "userId": "person-2", "displayName": Self.names[1],
                "status": "active", "joinedAt": timestamp(-60, from: anchor), "leftAt": NSNull(),
                "lastLocationAt": timestamp(aliceOffset, from: anchor),
                "lastLocation": ["latitude": aliceLatitude, "longitude": -122.121, "altitudeM": 10.0, "accuracyM": 12.0],
                "lastActivitySnapshot": ["elapsedSeconds": 45, "distanceM": 190.0, "paceSecondsPerKM": 318.0],
            ],
            [
                "id": "member-3", "userId": "person-3", "displayName": Self.names[2],
                "status": "active", "joinedAt": timestamp(-60, from: anchor), "leftAt": NSNull(),
                "lastLocationAt": timestamp(mayaOffset, from: anchor),
                "lastLocation": ["latitude": 47.673, "longitude": -122.123, "altitudeM": 10.0, "accuracyM": NSNull()],
                "lastActivitySnapshot": ["elapsedSeconds": 45, "distanceM": 185.0, "paceSecondsPerKM": 322.0],
            ],
        ]
        return [
            "id": Self.sessionID, "activityEventId": Self.eventID, "status": status,
            "title": "Live location fixture", "sport": "run", "creatorUserId": "person-1",
            "currentUserId": "person-1", "startedAt": timestamp(-60, from: anchor), "expiresAt": timestamp(3_600, from: anchor),
            "endedAt": NSNull(), "inviteToken": NSNull(), "inviteURL": NSNull(),
            "participants": participants,
        ]
    }

    private func event() -> [String: Any] {
        let now = Date()
        return [
            "id": Self.eventID, "title": "Live location fixture", "activityType": "running",
            "startsAt": timestamp(-60, from: now), "endsAt": timestamp(3_600, from: now), "locationName": NSNull(),
            "paceNote": NSNull(), "group": NSNull(), "creator": Self.people[0], "groups": [],
            "attendeeCount": Self.people.count, "currentUserGoing": true, "compatibility": NSNull(),
            "status": "active", "canParticipate": true,
            "participants": Self.people.map {
                ["person": $0, "status": "going", "outcome": NSNull(), "startedAt": timestamp(-30, from: now)]
            },
        ]
    }

    private enum FixtureError: Error { case failedToStart }
}
