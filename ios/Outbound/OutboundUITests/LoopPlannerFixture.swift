import Foundation
import Network
import XCTest

/// Stateful, loopback-only HTTP fixture. App stores and mutation handlers use
/// the normal network path; only authentication and unrelated setup are seeded.
final class LoopPlannerFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "LoopPlannerFixture")
    private let lock = NSLock()
    private var requests: [(String, [String: Any])] = []
    private var rejectGeneration = false
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() throws -> String {
        let ready = XCTestExpectation(description: "Loop fixture ready")
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
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let port = listener.port else { throw NSError(domain: "LoopFixture", code: 1) }
        return "http://127.0.0.1:\(port.rawValue)"
    }

    func stop() { listener.cancel() }

    func failGeneration() {
        lock.lock(); defer { lock.unlock() }
        rejectGeneration = true
    }

    func bodies(_ path: String) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.0 == path }.map(\.1)
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            var data = buffered
            if let bytes { data.append(bytes) }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
                  let headers = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
                if complete || error != nil { connection.cancel() } else { self.receive(connection, buffered: data) }
                return
            }
            let contentLength = headers.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }).flatMap { Int($0.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces)) } ?? 0
            guard data.count >= boundary.upperBound + contentLength else {
                if complete || error != nil { connection.cancel() } else { self.receive(connection, buffered: data) }
                return
            }
            let firstLine = headers.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard firstLine.count >= 2 else { connection.cancel(); return }
            let target = String(firstLine[1])
            let path = target.components(separatedBy: "?")[0]
            let method = String(firstLine[0])
            let bodyData = data[boundary.upperBound..<(boundary.upperBound + contentLength)]
            let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
            self.lock.lock()
            self.requests.append(("\(method) \(target)", body))
            let (status, payload) = self.respond(method: method, path: path, target: target, body: body)
            self.lock.unlock()
            let json = try! JSONSerialization.data(withJSONObject: payload)
            var response = Data("HTTP/1.1 \(status) \(status < 400 ? "OK" : "Rejected")\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(json)
            let bytes = response
            self.queue.asyncAfter(deadline: .now() + (path == "/routes/generate" ? 2 : 0.15)) {
                connection.send(content: bytes, completion: .contentProcessed { _ in connection.cancel() })
            }
        }
    }

    private func respond(method: String, path: String, target: String, body: [String: Any]) -> (Int, [String: Any]) {
        if path == "/routes/generate", rejectGeneration {
            return (503, ["error": "Synthetic provider unavailable"])
        }
        if path == "/routes/generate", let start = body["start"] as? [String: Double],
           let latitude = start["latitude"], let longitude = start["longitude"], let distance = body["targetDistanceM"] as? Double {
            let radius = distance / (2 * Double.pi)
            let candidates: [[String: Any]] = [1.0, -1.0].enumerated().map { index, direction in
                let points: [[String: Double]] = (0...180).map { step in
                    let angle = Double(step) * 2 * Double.pi / 180
                    return ["latitude": latitude + direction * radius * (cos(angle) - 1) / 111320,
                            "longitude": longitude + radius * sin(angle) / (111320 * cos(latitude * Double.pi / 180))]
                }
                return ["id": "synthetic-loop-\(index)", "points": points, "distanceM": distance,
                        "deviationFraction": 0, "requestedStart": start, "snappedStart": start,
                        "elevationGainM": 10 + index, "attribution": "Synthetic HTTP regression fixture"]
            }
            return (200, ["candidates": candidates])
        }
        if path.hasPrefix("/routes/") { return (200, ["routes": []]) }
        return (200, [:])
    }
}
