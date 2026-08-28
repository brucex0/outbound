import Foundation

extension Notification.Name {
    static let outboundAuthenticationExpired = Notification.Name("OutboundAuthenticationExpired")
    static let outboundAuthenticationSessionRecovered = Notification.Name("OutboundAuthenticationSessionRecovered")
}

enum AuthenticationSessionRecovery: String, Sendable {
    case rotationRace = "rotation_race"
    case staleAccessRejection = "stale_access_rejection"
    case newerPersistedSession = "newer_persisted_session"
    case transientRefreshFailure = "transient_refresh_failure"
}

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
        return try await refresh(using: session)
    }

    func refreshAfterUnauthorized(rejectedAccessToken: String?) async throws -> String? {
        guard let session else { return nil }
        if let rejectedAccessToken,
           rejectedAccessToken != session.accessToken,
           session.hasUsableAccessToken(leeway: 0) {
            notifyRecovery(.staleAccessRejection)
            return session.accessToken
        }
        return try await refresh(using: session)
    }

    private func refresh(using snapshot: AuthSession) async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        let attemptedRefreshToken = snapshot.refreshToken
        let task = Task { try await APIClient.shared.refreshSession(refreshToken: attemptedRefreshToken) }
        refreshTask = task; defer { refreshTask = nil }
        do {
            let replacement = try await task.value
            try replace(replacement)
            if replacement.refreshRecovery == true { notifyRecovery(.rotationRace) }
            return replacement.accessToken
        } catch {
            if let persisted = try? repository.load(),
               persisted.refreshToken != attemptedRefreshToken,
               persisted.isRefreshUsable {
                session = persisted
                notifyRecovery(.newerPersistedSession)
                return persisted.accessToken
            }
            if error.isPermanentSessionRefreshFailure {
                clear(notify: true)
            } else {
                notifyRecovery(.transientRefreshFailure)
            }
            throw error
        }
    }

    private func notifyRecovery(_ recovery: AuthenticationSessionRecovery) {
        Task { @MainActor in
            NotificationCenter.default.post(
                name: .outboundAuthenticationSessionRecovered,
                object: recovery
            )
        }
    }
}
