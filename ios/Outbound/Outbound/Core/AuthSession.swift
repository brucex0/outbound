import Foundation

nonisolated struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let email: String?
    // Optional so sessions written before this field existed remain decodable.
    let onboardingCompleted: Bool?
    let termsAcceptedVersion: Int?

    nonisolated func withOnboardingCompleted(_ completed: Bool) -> AuthenticatedUser {
        AuthenticatedUser(
            id: id,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            email: email,
            onboardingCompleted: completed,
            termsAcceptedVersion: termsAcceptedVersion
        )
    }

    nonisolated func withTermsAccepted(version: Int) -> AuthenticatedUser {
        AuthenticatedUser(
            id: id,
            username: username,
            displayName: displayName,
            avatarUrl: avatarUrl,
            email: email,
            onboardingCompleted: onboardingCompleted,
            termsAcceptedVersion: version
        )
    }
}

nonisolated struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let accessTokenExpiresAt: Date
    let refreshToken: String
    let refreshTokenExpiresAt: Date
    let refreshRecovery: Bool?
    let currentTermsVersion: Int?
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
            currentTermsVersion: currentTermsVersion,
            user: user.withOnboardingCompleted(completed)
        )
    }

    nonisolated func withTermsAccepted(version: Int) -> AuthSession {
        AuthSession(
            accessToken: accessToken,
            accessTokenExpiresAt: accessTokenExpiresAt,
            refreshToken: refreshToken,
            refreshTokenExpiresAt: refreshTokenExpiresAt,
            refreshRecovery: refreshRecovery,
            currentTermsVersion: max(currentTermsVersion ?? 0, version),
            user: user.withTermsAccepted(version: version)
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
    let termsVersion = PlainstrideLegal.currentTermsVersion
}

struct RefreshSessionRequest: Encodable { let refreshToken: String }
struct LogoutSessionRequest: Encodable { let refreshToken: String? }
struct DebugPersonaSessionRequest: Encodable {
    let persona: String
    let platform = "ios"
    let deviceLabel: String?
    let termsVersion = PlainstrideLegal.currentTermsVersion
}
struct TermsAcceptanceRequest: Encodable { let termsVersion: Int }
struct TermsAcceptanceResponse: Decodable { let termsVersion: Int; let acceptedAt: Date }
struct DeleteAccountRequest: Encodable { let identityToken: String; let authorizationCode: String; let rawNonce: String }
