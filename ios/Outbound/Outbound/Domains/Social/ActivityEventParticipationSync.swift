import Foundation

/// Account-scoped durable intents survive offline starts, discards, and app restarts.
@MainActor
final class ActivityEventParticipationSync {
    static let shared = ActivityEventParticipationSync()
    private struct Intent: Codable {
        var startedAt: Date
        var finishedWithoutRecording: Bool
    }
    private var isFlushing = false
    private func key(_ account: String) -> String { "activity-event-participation.\(account)" }
    private func read(_ account: String) -> [String: Intent] {
        guard let data = UserDefaults.standard.data(forKey: key(account)) else { return [:] }
        do { return try JSONDecoder().decode([String: Intent].self, from: data) }
        catch {
            ActivityDiagnosticLog.error(.persistence, "Event participation queue decode failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return [:]
        }
    }
    private func write(_ intents: [String: Intent], account: String) {
        do { UserDefaults.standard.set(try JSONEncoder().encode(intents), forKey: key(account)) }
        catch { ActivityDiagnosticLog.error(.persistence, "Event participation queue encode failed error=\(ActivityDiagnosticLog.errorCategory(error))") }
    }
    func enqueueStart(eventID: String) {
        guard let account = AuthStore.currentUserId else { return }
        var intents = read(account)
        if intents[eventID] == nil { intents[eventID] = Intent(startedAt: Date(), finishedWithoutRecording: false) }
        write(intents, account: account)
    }
    func enqueueFinishWithoutRecording(eventID: String) {
        guard let account = AuthStore.currentUserId else { return }
        var intents = read(account)
        // If start already synced, this timestamp is ignored by the idempotent endpoint.
        var intent = intents[eventID] ?? Intent(startedAt: Date(), finishedWithoutRecording: false)
        intent.finishedWithoutRecording = true
        intents[eventID] = intent
        write(intents, account: account)
    }
    func flush() async {
        guard !isFlushing, let account = AuthStore.currentUserId else { return }
        isFlushing = true
        defer { isFlushing = false }
        for (eventID, intent) in read(account) {
            guard AuthStore.currentUserId == account else { return }
            do {
                _ = try await APIClient.shared.startActivityEvent(id: eventID, startedAt: intent.startedAt)
                guard AuthStore.currentUserId == account else { return }
                if intent.finishedWithoutRecording {
                    _ = try await APIClient.shared.markActivityEventWithoutRecording(id: eventID)
                }
                var latest = read(account)
                // A discard can arrive while the start request is in flight.
                if latest[eventID]?.finishedWithoutRecording == intent.finishedWithoutRecording {
                    latest.removeValue(forKey: eventID)
                    write(latest, account: account)
                }
            } catch {
                if Task.isCancelled { return }
                ActivityDiagnosticLog.error(.persistence, "Event participation sync failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                if case let APIError.http(status, _, _) = error, [403, 404, 410].contains(status) {
                    var latest = read(account)
                    latest.removeValue(forKey: eventID)
                    write(latest, account: account)
                }
            }
        }
    }
}
