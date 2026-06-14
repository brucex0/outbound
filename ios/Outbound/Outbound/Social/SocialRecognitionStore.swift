#if OUTBOUND_ENABLE_SOCIAL
import Combine
import Foundation
import SwiftUI

enum SocialRecognitionBadgeID: String, Codable, CaseIterable, Identifiable {
    case goodTeammate
    case relayPlayer
    case rivalEdge
    case photoFinish

    var id: String { rawValue }
}

struct SocialRecognitionAward: Codable, Identifiable, Equatable {
    let id: UUID
    let badgeID: SocialRecognitionBadgeID
    let earnedAt: Date
    let sourceActivityID: UUID?
}

struct SocialRecognitionPreview: Identifiable, Equatable {
    let badgeID: SocialRecognitionBadgeID
    let title: String
    let symbolName: String
    let coachLine: String

    var id: SocialRecognitionBadgeID { badgeID }
}

private struct SocialSupportEvent: Codable, Hashable {
    let postID: String
    let createdAt: Date
}

@MainActor
final class SocialRecognitionStore: ObservableObject {
    @Published private(set) var awards: [SocialRecognitionAward]
    @Published private(set) var supportEvents: [SocialSupportEvent]
    @Published private(set) var sharedActivityIDs: Set<UUID>
    @Published private(set) var joinedClubIDs: Set<String>
    @Published private(set) var claimedRivalEdge = false

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let awardsKey = "social_recognition_store_awards_v1"
    private let supportEventsKey = "social_recognition_store_support_events_v1"
    private let sharedActivitiesKey = "social_recognition_store_shared_activities_v1"
    private let joinedClubsKey = "social_recognition_store_joined_clubs_v1"
    private let rivalEdgeKey = "social_recognition_store_claimed_rival_edge_v1"

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.awards = Self.decode([SocialRecognitionAward].self, from: defaults.data(forKey: awardsKey)) ?? []
        self.supportEvents = Self.decode([SocialSupportEvent].self, from: defaults.data(forKey: supportEventsKey)) ?? []
        self.sharedActivityIDs = Set(Self.decode([UUID].self, from: defaults.data(forKey: sharedActivitiesKey)) ?? [])
        self.joinedClubIDs = Set(Self.decode([String].self, from: defaults.data(forKey: joinedClubsKey)) ?? ["sf-dawn"])
        self.claimedRivalEdge = defaults.bool(forKey: rivalEdgeKey)
        trimStaleSupportEvents()
        awards.sort { $0.earnedAt > $1.earnedAt }
    }

    var highlight: SocialRecognitionPreview? {
        guard let latestAward = awards.first, isHighlightStillFresh(latestAward.earnedAt) else { return nil }
        return preview(for: latestAward.badgeID)
    }

    func toggleShare(for activity: SavedActivity, now: Date = Date()) -> [SocialRecognitionAward] {
        let isSharing = !sharedActivityIDs.contains(activity.id)
        if isSharing {
            sharedActivityIDs.insert(activity.id)
        } else {
            sharedActivityIDs.remove(activity.id)
        }
        persistSharedActivities()

        guard isSharing, !activity.photos.isEmpty else { return [] }
        guard let award = awardBadgeIfNeeded(.photoFinish, sourceActivityID: activity.id, now: now) else { return [] }
        persistAwards()
        return [award]
    }

    func toggleClubMembership(clubID: String, now: Date = Date()) -> [SocialRecognitionAward] {
        let isJoining = !joinedClubIDs.contains(clubID)
        if isJoining {
            joinedClubIDs.insert(clubID)
        } else {
            joinedClubIDs.remove(clubID)
        }
        persistJoinedClubs()

        guard isJoining else { return [] }
        guard let award = awardBadgeIfNeeded(.relayPlayer, sourceActivityID: nil, now: now) else { return [] }
        persistAwards()
        return [award]
    }

    func registerCheer(for postID: String, now: Date = Date()) -> [SocialRecognitionAward] {
        trimStaleSupportEvents(now: now)

        guard !supportEvents.contains(where: { $0.postID == postID && calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear) }) else {
            return []
        }

        supportEvents.append(SocialSupportEvent(postID: postID, createdAt: now))
        persistSupportEvents()

        let currentWeekPosts = Set(
            supportEvents
                .filter { calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear) }
                .map(\.postID)
        )

        guard currentWeekPosts.count >= 3 else { return [] }
        guard let award = awardBadgeIfNeeded(.goodTeammate, sourceActivityID: nil, now: now) else { return [] }
        persistAwards()
        return [award]
    }

    func claimRivalEdge(now: Date = Date()) -> [SocialRecognitionAward] {
        guard !claimedRivalEdge else { return [] }
        claimedRivalEdge = true
        defaults.set(true, forKey: rivalEdgeKey)
        guard let award = awardBadgeIfNeeded(.rivalEdge, sourceActivityID: nil, now: now) else { return [] }
        persistAwards()
        return [award]
    }

    func preview(for badgeID: SocialRecognitionBadgeID) -> SocialRecognitionPreview {
        SocialRecognitionPreview(
            badgeID: badgeID,
            title: Self.title(for: badgeID),
            symbolName: Self.symbolName(for: badgeID),
            coachLine: Self.coachLine(for: badgeID)
        )
    }

    private func awardBadgeIfNeeded(
        _ badgeID: SocialRecognitionBadgeID,
        sourceActivityID: UUID?,
        now: Date
    ) -> SocialRecognitionAward? {
        guard !awards.contains(where: { $0.badgeID == badgeID }) else { return nil }
        let award = SocialRecognitionAward(
            id: UUID(),
            badgeID: badgeID,
            earnedAt: now,
            sourceActivityID: sourceActivityID
        )
        awards.insert(award, at: 0)
        return award
    }

    private func trimStaleSupportEvents(now: Date = Date()) {
        guard let oldestAllowed = calendar.date(byAdding: .day, value: -14, to: now) else { return }
        let trimmed = supportEvents.filter { $0.createdAt >= oldestAllowed }
        if trimmed != supportEvents {
            supportEvents = trimmed
            persistSupportEvents()
        }
    }

    private func isHighlightStillFresh(_ date: Date) -> Bool {
        guard let cutoff = calendar.date(byAdding: .day, value: -3, to: Date()) else { return false }
        return date >= cutoff
    }

    private func persistAwards() {
        guard let data = try? JSONEncoder().encode(awards) else { return }
        defaults.set(data, forKey: awardsKey)
    }

    private func persistSupportEvents() {
        guard let data = try? JSONEncoder().encode(supportEvents) else { return }
        defaults.set(data, forKey: supportEventsKey)
    }

    private func persistSharedActivities() {
        guard let data = try? JSONEncoder().encode(Array(sharedActivityIDs)) else { return }
        defaults.set(data, forKey: sharedActivitiesKey)
    }

    private func persistJoinedClubs() {
        guard let data = try? JSONEncoder().encode(Array(joinedClubIDs)) else { return }
        defaults.set(data, forKey: joinedClubsKey)
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func title(for badgeID: SocialRecognitionBadgeID) -> String {
        switch badgeID {
        case .goodTeammate:
            return "Good Teammate"
        case .relayPlayer:
            return "Relay Player"
        case .rivalEdge:
            return "Rival Edge"
        case .photoFinish:
            return "Photo Finish"
        }
    }

    private static func symbolName(for badgeID: SocialRecognitionBadgeID) -> String {
        switch badgeID {
        case .goodTeammate:
            return "hands.clap.fill"
        case .relayPlayer:
            return "person.3.sequence.fill"
        case .rivalEdge:
            return "flag.checkered.2.crossed"
        case .photoFinish:
            return "camera.aperture"
        }
    }

    private static func coachLine(for badgeID: SocialRecognitionBadgeID) -> String {
        switch badgeID {
        case .goodTeammate:
            return "You helped the week feel shared, not solo."
        case .relayPlayer:
            return "You stepped into the group instead of staying on the sideline."
        case .rivalEdge:
            return "You turned the week into something competitive and playful."
        case .photoFinish:
            return "You saved more than the stats. You kept the moment too."
        }
    }
}
#endif
