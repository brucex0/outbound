import Foundation

enum PlainstrideLinks {
    static let webOrigin = URL(string: "https://plainstride.ai")!
    static let appInvitation = webOrigin.appending(path: "invite")

    static func activityEventInvitation(token: String) -> URL {
        webOrigin
            .appending(path: "invite")
            .appending(path: "activity")
            .appending(path: token)
    }

    static func connectionCode(from url: URL) -> String? {
        guard url.scheme == "https", url.host == webOrigin.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 2,
              components[0] == "connect" else { return nil }
        return normalizedPersonalCode(components[1])
    }

    static func liveGroupToken(from url: URL) -> String? {
        guard url.scheme == "https", url.host == webOrigin.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        if components.count == 3,
           components[0] == "live",
           components[1] == "group" {
            return components[2]
        }
        if components.count == 3,
           components[0] == "invite",
           components[1] == "group" {
            return components[2]
        }
        return nil
    }

    static func activityEventToken(from url: URL) -> String? {
        guard url.scheme == "https", url.host == webOrigin.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "invite",
              components[1] == "activity" else { return nil }
        return components[2]
    }

    static func referralCode(from url: URL) -> String? {
        guard url.scheme == "https", url.host == webOrigin.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "invite",
              components[1] == "r" else { return nil }
        return normalizedPersonalCode(components[2])
    }

    static func personalInvitationCode(from url: URL) -> String? {
        connectionCode(from: url) ?? referralCode(from: url)
    }

    private static func normalizedPersonalCode(_ value: String) -> String? {
        let normalized = value.lowercased()
        guard normalized.utf8.count == 8,
              normalized.utf8.allSatisfy({ byte in
                  (97...122).contains(byte) || (48...57).contains(byte)
              }) else { return nil }
        return normalized
    }
}
