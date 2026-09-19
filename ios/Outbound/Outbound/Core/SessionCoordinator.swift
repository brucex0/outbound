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

private enum SessionCoordinatorError: Error {
    case missingSession
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
    func replace(_ value: AuthSession) throws {
        try repository.replace(value)
        session = value
    }
    func markOnboardingResolved(_ status: OnboardingStatus) throws {
        guard let session else { return }
        try replace(session.withOnboardingStatus(status))
    }
    func markTermsAccepted(version: Int) throws {
        guard let session else { return }
        try replace(session.withTermsAccepted(version: version))
    }
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

    func refreshStoredSession() async throws -> AuthSession {
        guard let session else { throw SessionCoordinatorError.missingSession }
        _ = try await refresh(using: session)
        guard let refreshedSession = self.session else { throw SessionCoordinatorError.missingSession }
        return refreshedSession
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
                // A newer session was persisted by another in-process refresh
                // (single actor, so the keychain is authoritative here). Adopt
                // it, then make sure we hand back a usable access token: the
                // persisted access token may already be expired, in which case
                // refresh once against the persisted (current) refresh token.
                session = persisted
                notifyRecovery(.newerPersistedSession)
                if persisted.hasUsableAccessToken() { return persisted.accessToken }
                // refreshTask is still this invocation's (failed) task here;
                // clear it so the recursive refresh starts a new task using
                // the persisted (current) refresh token instead of re-awaiting
                // the failure. One level deep at most: the persisted token
                // equals the attempted token on any second pass.
                refreshTask = nil
                return try await refresh(using: persisted)
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
