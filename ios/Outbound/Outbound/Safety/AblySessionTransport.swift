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
        channel.publish("location", data: payload) { _ in }
    }

    func close() {
        channel.unsubscribe()
        realtime.close()
    }
}
