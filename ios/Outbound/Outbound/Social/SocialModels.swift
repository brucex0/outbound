#if OUTBOUND_ENABLE_SOCIAL
import SwiftUI

enum SocialFeedScope: String, CaseIterable, Identifiable {
    case squad = "Squad"
    case clubs = "Clubs"
    case rivals = "Rivals"

    var id: String { rawValue }
}

struct SocialPerson: Identifiable {
    let id: String
    let firstName: String
    let fullName: String
    let initials: String
    let tint: Color
    let isRunning: Bool
}

struct SocialFeedPost: Identifiable {
    let id: String
    let author: SocialPerson
    let context: String
    let caption: String
    let activity: SocialActivitySummary
    let kind: SocialPostKind
    let gradient: [Color]
    let isLive: Bool
    let cheers: Int
    let comments: Int
}

struct SocialActivitySummary {
    let routeName: String
    let distanceKm: Double
    let duration: String
    let pace: String

    func distanceText(unitSystem: MeasurementUnitSystem) -> String {
        unitSystem.distanceString(meters: distanceKm * 1000, fractionDigits: 1)
    }

    func paceText(unitSystem: MeasurementUnitSystem) -> String {
        guard let secondsPerKilometer else { return pace }
        return secondsPerKilometer.paceString(for: unitSystem)
    }

    private var secondsPerKilometer: Double? {
        let timePart = pace.split(separator: " ").first ?? Substring(pace)
        let pieces = timePart.split(separator: ":")
        guard pieces.count == 2,
              let minutes = Double(String(pieces[0])),
              let seconds = Double(String(pieces[1])) else {
            return nil
        }
        return minutes * 60 + seconds
    }
}

enum SocialPostKind {
    case run
    case relay
    case challenge

    var symbol: String {
        switch self {
        case .run: return "figure.run"
        case .relay: return "bolt.fill"
        case .challenge: return "flag.checkered"
        }
    }

    var tint: Color {
        switch self {
        case .run: return .orange
        case .relay: return .green
        case .challenge: return .blue
        }
    }
}

struct SocialClub: Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let symbol: String
    let tint: Color
    let memberInitials: [String]
    let memberCount: Int
    let nextRun: String
}

struct SocialChallenge: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let reward: String
    let progress: Double
    let tint: Color
}

struct SocialRival: Identifiable {
    let id: String
    let rank: Int
    let person: SocialPerson
    let weeklyKm: Double
    let delta: String
    let note: String

    func weeklyDistanceText(unitSystem: MeasurementUnitSystem) -> String {
        unitSystem.distanceString(meters: weeklyKm * 1000, fractionDigits: 1)
    }

    func deltaText(unitSystem: MeasurementUnitSystem) -> String {
        guard delta != "You" else { return delta }
        let sign = delta.hasPrefix("+") ? "+" : delta.hasPrefix("-") ? "-" : ""
        let unsignedDelta = delta
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " km", with: "")
        guard let kilometers = Double(unsignedDelta) else { return delta }
        return "\(sign)\(unitSystem.distanceString(meters: kilometers * 1000, fractionDigits: 1))"
    }
}
#endif
