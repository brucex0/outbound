import Foundation

struct AppUserProfileDTO: Codable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let avatarUrl: String?
    let bio: String?
}

struct AppUserProfileUpdateDTO: Codable, Sendable {
    let displayName: String
    let bio: String?
}
