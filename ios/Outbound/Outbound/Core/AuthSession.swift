import Foundation

nonisolated struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let email: String?
    // Optional so sessions written before this field existed remain decodable.
    let onboardingCompleted: Bool?

    nonisolated func withOnboardingCompleted(_ completed: Bool) -> AuthenticatedUser {
        AuthenticatedUser(
            id: id,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            email: email,
            onboardingCompleted: completed
        )
    }
}

nonisolated struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let refreshRecovery: Bool?
    let user: AuthenticatedUser

    nonisolated var isRefreshUsable: Bool { refreshTokenExpiresAt > Date() }
    nonisolated func hasUsableAccessToken(at date: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        accessTokenExpiresAt.timeIntervalSince(date) > leeway
    }

    nonisolated func withOnboardingCompleted(_ completed: Bool) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            refreshRecovery: refreshRecovery,
            user: user.withOnboardingCompleted(completed)
        )
    }
}

struct AppleSessionRequest: Encodable {
    let identityToken: String
    let authorizationCode: String
    let rawNonce: String
    let givenName: String?
    let familyName: String?
    let platform = "ios"
    let deviceLabel: String?
}

struct RefreshSessionRequest: Encodable { let refreshToken: String }
struct LogoutSessionRequest: Encodable { let refreshToken: String? }
struct DebugPersonaSessionRequest: Encodable { let persona: String; let platform = "ios"; let deviceLabel: String? }
struct DeleteAccountRequest: Encodable { let identityToken: String; let authorizationCode: String; let rawNonce: String }
