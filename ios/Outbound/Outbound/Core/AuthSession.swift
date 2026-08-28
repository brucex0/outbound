import Foundation

nonisolated struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let email: String?
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
