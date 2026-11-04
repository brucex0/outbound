import Ably
import Foundation

/// A single SDK connection is shared by the live session and its channel.
/// Authentication callbacks always ask the API for a fresh, session-scoped token.
final class AblySessionTransport {
    private let realtime: ARTRealtime
    private let channel: ARTRealtimeChannel

    init(kind: String, sessionID: String, api: APIClient = .shared, onMessage: @escaping (ARTMessage) -> Void) {
        let options = ARTClientOptions()
        options.authCallback = { _, callback in
            Task {
                do {
                    let token = try await api.issueRealtimeToken(kind: kind, sessionID: sessionID)
                    callback(token.token as ARTTokenDetailsCompatible, nil)
                } catch {
                    callback(nil, error)
                }
            }
        }
        realtime = ARTRealtime(options: options)
        channel = realtime.channels.get("plainstride:\(kind):\(sessionID)")
        channel.subscribe { message in onMessage(message) }
    }

    func publishLocation(_ payload: [String: Any]) {
        channel.publish("location", data: payload) { error in
            guard let error else { return }
            ActivityDiagnosticLog.error(.sync, "Live location publish failed code=\(error.code)")
        }
    }

    func close() {
        channel.unsubscribe()
        realtime.close()
    }
}

/// Shared wire format for iOS/Android GPS measurement timestamps.
enum LiveLocationTimestamp {
    static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    static func date(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}
