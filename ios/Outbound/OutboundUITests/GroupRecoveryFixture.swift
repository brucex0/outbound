import Foundation
import Network
import XCTest

/// A loopback-only API owned by the test. It survives app restarts without an
/// externally launched Python process, a fixed port, or production credentials.
final class GroupRecoveryFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "GroupRecoveryFixture")
    private let lock = NSLock()
    private var paths: [String] = []

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

    func requestCount(_ path: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return paths.filter { $0 == path }.count
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, complete, error in
            guard let self else { connection.cancel(); return }
            var bytes = buffered
            if let data { bytes.append(data) }
            guard let headers = String(data: bytes, encoding: .utf8), headers.contains("\r\n\r\n") else {
                if complete || error != nil { connection.cancel() }
                else { self.receive(connection, buffered: bytes) }
                return
            }
            let request = headers.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard request.count >= 2 else { connection.cancel(); return }
            let path = String(request[1]).components(separatedBy: "?")[0]
            self.lock.lock()
            self.paths.append("\(request[0]) \(path)")
            self.lock.unlock()
            let payload: [String: Any]
            let status: Int
            if path == "/social/activity-events/ui-recovery-event" {
                payload = Self.event(); status = 200
            } else if path.hasPrefix("/live/group-runs/") {
                payload = Self.group(); status = 200
            } else {
                payload = ["error": "synthetic_fixture_unavailable"]; status = 404
            }
            let body = try! JSONSerialization.data(withJSONObject: payload)
            var response = Data("HTTP/1.1 \(status) \(status == 200 ? "OK" : "Not Found")\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(body)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private static let names = ["Fixture Runner", "Alice Chen", "Alice Lee", "Maya Rivera", "Jordan Park", "Alex Li", "Rina Test"]
    private static var people: [[String: Any]] {
        names.enumerated().map { ["id": "person-\($0.offset + 1)", "displayName": $0.element, "avatarUrl": NSNull()] }
    }
    private static func timestamp(_ offset: Double = 0) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }
    private static func group() -> [String: Any] {
        ["id": "ui-recovery-live", "activityEventId": "ui-recovery-event", "status": "active",
         "title": "Recovery group run", "sport": "run", "creatorUserId": "person-1", "currentUserId": "person-1",
         "startedAt": timestamp(-60), "expiresAt": timestamp(3_600), "endedAt": NSNull(),
         "inviteToken": NSNull(), "inviteURL": NSNull(),
         "participants": people.enumerated().map { index, person -> [String: Any] in
             ["id": "member-\(index + 1)", "userId": person["id"]!, "displayName": person["displayName"]!,
              "status": "active", "joinedAt": timestamp(-60), "leftAt": NSNull(), "lastLocationAt": timestamp(),
              "lastLocation": ["latitude": 47.67 + Double(index) * 0.001, "longitude": -122.12],
              "lastActivitySnapshot": ["elapsedSeconds": 60, "distanceM": 100]]
         }]
    }
    private static func event() -> [String: Any] {
        ["id": "ui-recovery-event", "title": "Recovery group run", "activityType": "running",
         "startsAt": timestamp(-60), "endsAt": timestamp(3_600), "locationName": NSNull(), "paceNote": NSNull(),
         "group": NSNull(), "creator": people[0], "groups": [], "attendeeCount": people.count,
         "currentUserGoing": true, "compatibility": NSNull(), "status": "active", "canParticipate": true,
         "participants": people.map { ["person": $0, "status": "going", "outcome": NSNull(), "startedAt": timestamp(-30)] }]
    }
    private enum FixtureError: Error { case failedToStart }
}
