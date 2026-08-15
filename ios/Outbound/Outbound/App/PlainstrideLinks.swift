import Foundation

enum PlainstrideLinks {
    static let webOrigin = URL(string: "https://run.plainstride.com")!
    static let appInvitation = webOrigin.appending(path: "invite")

    static func scheduledRunInvitation(token: String) -> URL {
        webOrigin
            .appending(path: "invite")
            .appending(path: "run")
            .appending(path: token)
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

    static func futureActivityToken(from url: URL) -> String? {
        guard url.scheme == "https", url.host == webOrigin.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "invite",
              components[1] == "run" else { return nil }
        return components[2]
    }

    static func referralCode(from url: URL) -> String? {
        guard url.scheme == "https", url.host == webOrigin.host else { return nil }
        let components = url.pathComponents.filter { $0 != "/" }
        guard components.count == 3,
              components[0] == "invite",
              components[1] == "r" else { return nil }
        return components[2]
    }
}
