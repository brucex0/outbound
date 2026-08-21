import Foundation

extension Notification.Name { static let outboundAuthenticationExpired = Notification.Name("OutboundAuthenticationExpired") }

actor SessionCoordinator {
    static let shared = SessionCoordinator()
    private let repository: SessionPersisting
    private var session: AuthSession?
    private var refreshTask: Task<AuthSession, Error>?

    init(repository: SessionPersisting = KeychainSessionRepository()) {
        self.repository = repository
        self.session = try? repository.load()
        if session?.isRefreshUsable != true { session = nil; try? repository.delete() }
    }

    func storedSession() -> AuthSession? { session }
    func replace(_ value: AuthSession) throws { try repository.replace(value); session = value }
    func clear(notify: Bool = false) {
        session = nil; try? repository.delete()
        if notify { Task { @MainActor in NotificationCenter.default.post(name: .outboundAuthenticationExpired, object: nil) } }
    }

    func accessToken() async throws -> String? {
        guard let session else { return nil }
        if session.hasUsableAccessToken() { return session.accessToken }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { try await APIClient.shared.refreshSession(refreshToken: session.refreshToken) }
        refreshTask = task
        defer { refreshTask = nil }
        do { let replacement = try await task.value; try replace(replacement); return replacement.accessToken }
        catch { clear(notify: true); throw error }
    }

    func refreshAfterUnauthorized() async throws -> String? {
        guard let session else { return nil }
        if let refreshTask { return try await refreshTask.value.accessToken }
        let task = Task { try await APIClient.shared.refreshSession(refreshToken: session.refreshToken) }
        refreshTask = task; defer { refreshTask = nil }
        do { let replacement = try await task.value; try replace(replacement); return replacement.accessToken }
        catch { clear(notify: true); throw error }
    }
}
