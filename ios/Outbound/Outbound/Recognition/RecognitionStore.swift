import Foundation
import SwiftUI

enum RecognitionFamily: String, Codable, CaseIterable {
    case showedUp
    case momentum
    case social
}

enum RecognitionBadgeID: String, Codable, CaseIterable, Identifiable {
    case firstStep
    case shortCounts
    case backInMotion
    case weekClosedWell
    case threeThisWeek
    case keptItEasy
    case finishedWhatYouStarted
    case steadyReturn
    case goodTeammate
    case relayPlayer
    case rivalEdge
    case photoFinish

    var id: String { rawValue }
}

struct RecognitionDefinition: Equatable {
    let id: RecognitionBadgeID
    let family: RecognitionFamily
    let title: String
    let symbolName: String
    let shareEligible: Bool
    let priority: Int
}

struct RecognitionAward: Codable, Identifiable, Equatable {
    let id: UUID
    let badgeID: RecognitionBadgeID
    let earnedAt: Date
    let sourceActivityID: UUID?
}

struct RecognitionPreview: Identifiable, Equatable {
    let badgeID: RecognitionBadgeID
    let title: String
    let symbolName: String
    let coachLine: String

    var id: RecognitionBadgeID { badgeID }
}

struct RecognitionSupportEvent: Codable, Hashable {
    let postID: String
    let createdAt: Date
}

struct RecognitionWeekMarker: Hashable {
    let yearForWeekOfYear: Int
    let weekOfYear: Int
}

@MainActor
final class RecognitionStore: ObservableObject {
    @Published private(set) var awards: [RecognitionAward]
    @Published private(set) var supportEvents: [RecognitionSupportEvent]
    @Published private(set) var sharedActivityIDs: Set<UUID>
    @Published private(set) var joinedClubIDs: Set<String>
    @Published private(set) var claimedRivalEdge = false

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let awardsKey = "recognition_store_awards_v1"
    private let supportEventsKey = "recognition_store_support_events_v1"
    private let sharedActivitiesKey = "recognition_store_shared_activities_v1"
    private let joinedClubsKey = "recognition_store_joined_clubs_v1"
    private let rivalEdgeKey = "recognition_store_claimed_rival_edge_v1"

    init(
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.defaults = defaults
        self.calendar = calendar
        self.awards = Self.decode([RecognitionAward].self, from: defaults.data(forKey: awardsKey)) ?? []
        self.supportEvents = Self.decode([RecognitionSupportEvent].self, from: defaults.data(forKey: supportEventsKey)) ?? []
        self.sharedActivityIDs = Set(Self.decode([UUID].self, from: defaults.data(forKey: sharedActivitiesKey)) ?? [])
        self.joinedClubIDs = Set(Self.decode([String].self, from: defaults.data(forKey: joinedClubsKey)) ?? ["sf-dawn"])
        self.claimedRivalEdge = defaults.bool(forKey: rivalEdgeKey)
        trimStaleSupportEvents()
        awards.sort { $0.earnedAt > $1.earnedAt }
    }

    var latestAward: RecognitionAward? {
        awards.first
    }

    var todayHighlight: RecognitionPreview? {
        guard let latestAward, isHighlightStillFresh(latestAward.earnedAt) else { return nil }
        return preview(for: latestAward.badgeID)
    }

    var socialHighlight: RecognitionPreview? {
        guard let latestAward, isHighlightStillFresh(latestAward.earnedAt) else { return nil }
        let definition = Self.definition(for: latestAward.badgeID)
        guard definition.family == .social else { return nil }
        return preview(for: latestAward.badgeID)
    }

    var importantMilestoneHighlight: RecognitionPreview? {
        guard let award = awards.first(where: { isImportantMilestone($0.badgeID) && isHighlightStillFresh($0.earnedAt) }) else {
            return nil
        }
        return preview(for: award.badgeID)
    }

    func recentAwards(limit: Int) -> [RecognitionPreview] {
        Array(awards.prefix(limit)).map { preview(for: $0.badgeID) }
    }

    func recognitions(for activityID: UUID) -> [RecognitionPreview] {
        awards
            .filter { $0.sourceActivityID == activityID }
            .sorted { Self.definition(for: $0.badgeID).priority > Self.definition(for: $1.badgeID).priority }
            .map { preview(for: $0.badgeID) }
    }

    func topRecognition(for activityID: UUID) -> RecognitionPreview? {
        recognitions(for: activityID).first
    }

    func previewPostRunRecognition(
        summary: ActivitySummary,
        priorActivities: [SavedActivity],
        readiness: DailyReadiness?,
        intent: SessionIntent?,
        goalProgress: GoalProgressSnapshot?,
        photoCount: Int,
        now: Date = Date()
    ) -> [RecognitionPreview] {
        let candidate = ActivityCandidate(
            sourceActivityID: nil,
            startedAt: summary.startedAt,
            durationSecs: summary.durationSecs,
            photoCount: photoCount
        )

        return candidateBadgeIDs(
            for: candidate,
            priorActivities: priorActivities,
            readiness: readiness,
            intent: intent,
            goalProgress: goalProgress,
            now: now
        )
        .map(preview(for:))
    }

    func recordSavedActivity(
        _ activity: SavedActivity,
        priorActivities: [SavedActivity],
        readiness: DailyReadiness?,
        intent: SessionIntent?,
        goalProgress: GoalProgressSnapshot?,
        now: Date = Date()
    ) -> [RecognitionAward] {
        let candidate = ActivityCandidate(
            sourceActivityID: activity.id,
            startedAt: activity.startedAt,
            durationSecs: activity.durationSecs,
            photoCount: activity.photos.count
        )

        let newAwards = candidateBadgeIDs(
            for: candidate,
            priorActivities: priorActivities,
            readiness: readiness,
            intent: intent,
            goalProgress: goalProgress,
            now: now
        )
        .compactMap { awardBadgeIfNeeded($0, sourceActivityID: activity.id, now: now) }

        if !newAwards.isEmpty {
            persistAwards()
        }
        return newAwards
    }

    func toggleShare(for activity: SavedActivity, now: Date = Date()) -> [RecognitionAward] {
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

    func toggleClubMembership(clubID: String, now: Date = Date()) -> [RecognitionAward] {
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

    func registerCheer(for postID: String, now: Date = Date()) -> [RecognitionAward] {
        trimStaleSupportEvents(now: now)

        guard !supportEvents.contains(where: { $0.postID == postID && calendar.isDate($0.createdAt, equalTo: now, toGranularity: .weekOfYear) }) else {
            return []
        }

        supportEvents.append(RecognitionSupportEvent(postID: postID, createdAt: now))
        persistSupportEvents()

        let currentWeekPosts = Set(
            supportEvents
                .filter { isSameWeek($0.createdAt, now) }
                .map(\.postID)
        )

        guard currentWeekPosts.count >= 3 else { return [] }
        guard let award = awardBadgeIfNeeded(.goodTeammate, sourceActivityID: nil, now: now) else { return [] }
        persistAwards()
        return [award]
    }

    func claimRivalEdge(now: Date = Date()) -> [RecognitionAward] {
        guard !claimedRivalEdge else { return [] }
        claimedRivalEdge = true
        defaults.set(true, forKey: rivalEdgeKey)
        guard let award = awardBadgeIfNeeded(.rivalEdge, sourceActivityID: nil, now: now) else { return [] }
        persistAwards()
        return [award]
    }

    func preview(for badgeID: RecognitionBadgeID) -> RecognitionPreview {
        RecognitionPreview(
            badgeID: badgeID,
            title: Self.definition(for: badgeID).title,
            symbolName: Self.definition(for: badgeID).symbolName,
            coachLine: Self.coachLine(for: badgeID)
        )
    }

    private func candidateBadgeIDs(
        for candidate: ActivityCandidate,
        priorActivities: [SavedActivity],
        readiness: DailyReadiness?,
        intent: SessionIntent?,
        goalProgress: GoalProgressSnapshot?,
        now: Date
    ) -> [RecognitionBadgeID] {
        var badgeIDs: [RecognitionBadgeID] = []

        if priorActivities.isEmpty {
            badgeIDs.append(.firstStep)
        }

        if candidate.durationSecs < 15 * 60 {
            badgeIDs.append(.shortCounts)
        }

        if isComeback(candidate.startedAt, priorActivities: priorActivities) {
            badgeIDs.append(.backInMotion)
        }

        if isFinalDayOfWeek(candidate.startedAt) {
            badgeIDs.append(.weekClosedWell)
        }

        if goalProgress?.isComplete == true {
            badgeIDs.append(.threeThisWeek)
        }

        if isEasyEffort(readiness: readiness, intent: intent) {
            badgeIDs.append(.keptItEasy)
        }

        if activitiesThisWeek(priorActivities, containing: candidate.startedAt) + 1 >= 3 {
            badgeIDs.append(.finishedWhatYouStarted)
        }

        if spansTwoWeeksWithinReturnWindow(candidate.startedAt, priorActivities: priorActivities) {
            badgeIDs.append(.steadyReturn)
        }

        let notYetEarned = badgeIDs.filter { !hasAwarded($0) }
        return notYetEarned.sorted { Self.definition(for: $0).priority > Self.definition(for: $1).priority }
    }

    private func activitiesThisWeek(_ activities: [SavedActivity], containing date: Date) -> Int {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return 0 }
        return activities.filter { week.contains($0.startedAt) }.count
    }

    private func isComeback(_ date: Date, priorActivities: [SavedActivity]) -> Bool {
        let candidateDay = calendar.startOfDay(for: date)
        guard let sevenDaysBack = calendar.date(byAdding: .day, value: -7, to: candidateDay) else { return false }
        return !priorActivities.contains {
            let started = $0.startedAt
            return started >= sevenDaysBack && started < candidateDay
        }
    }

    private func isFinalDayOfWeek(_ date: Date) -> Bool {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date),
              let lastDay = calendar.date(byAdding: .day, value: 6, to: week.start) else {
            return false
        }
        return calendar.isDate(date, inSameDayAs: lastDay)
    }

    private func isEasyEffort(readiness: DailyReadiness?, intent: SessionIntent?) -> Bool {
        if readiness == .lowEnergy || readiness == .stressed {
            return true
        }

        guard let intent else { return false }
        let haystack = "\(intent.id) \(intent.title) \(intent.detail) \(intent.coachLine)".lowercased()
        let hints = ["easy", "reset", "fresh", "comeback", "light", "walk", "recovery"]
        return hints.contains { haystack.contains($0) }
    }

    private func spansTwoWeeksWithinReturnWindow(_ date: Date, priorActivities: [SavedActivity]) -> Bool {
        guard let startWindow = calendar.date(byAdding: .day, value: -21, to: date) else { return false }

        var markers = Set<RecognitionWeekMarker>()
        markers.insert(weekMarker(for: date))

        for activity in priorActivities where activity.startedAt >= startWindow && activity.startedAt <= date {
            markers.insert(weekMarker(for: activity.startedAt))
        }

        return markers.count >= 2
    }

    private func weekMarker(for date: Date) -> RecognitionWeekMarker {
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return RecognitionWeekMarker(
            yearForWeekOfYear: components.yearForWeekOfYear ?? 0,
            weekOfYear: components.weekOfYear ?? 0
        )
    }

    private func hasAwarded(_ badgeID: RecognitionBadgeID) -> Bool {
        awards.contains { $0.badgeID == badgeID }
    }

    private func awardBadgeIfNeeded(
        _ badgeID: RecognitionBadgeID,
        sourceActivityID: UUID?,
        now: Date
    ) -> RecognitionAward? {
        guard !hasAwarded(badgeID) else { return nil }
        let award = RecognitionAward(
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

    private func isSameWeek(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, equalTo: rhs, toGranularity: .weekOfYear)
    }

    private func isHighlightStillFresh(_ date: Date) -> Bool {
        guard let cutoff = calendar.date(byAdding: .day, value: -3, to: Date()) else { return false }
        return date >= cutoff
    }

    private func isImportantMilestone(_ badgeID: RecognitionBadgeID) -> Bool {
        let definition = Self.definition(for: badgeID)
        return definition.priority >= 78 || definition.shareEligible
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

    static func definition(for badgeID: RecognitionBadgeID) -> RecognitionDefinition {
        switch badgeID {
        case .firstStep:
            return RecognitionDefinition(id: badgeID, family: .showedUp, title: "First Step", symbolName: "figure.walk.motion", shareEligible: false, priority: 70)
        case .shortCounts:
            return RecognitionDefinition(id: badgeID, family: .showedUp, title: "Short Counts", symbolName: "bolt.heart.fill", shareEligible: false, priority: 65)
        case .backInMotion:
            return RecognitionDefinition(id: badgeID, family: .showedUp, title: "Back In Motion", symbolName: "arrow.clockwise.heart", shareEligible: true, priority: 100)
        case .weekClosedWell:
            return RecognitionDefinition(id: badgeID, family: .showedUp, title: "Week Closed Well", symbolName: "calendar.badge.checkmark", shareEligible: false, priority: 60)
        case .threeThisWeek:
            return RecognitionDefinition(id: badgeID, family: .momentum, title: "Three This Week", symbolName: "target", shareEligible: true, priority: 90)
        case .keptItEasy:
            return RecognitionDefinition(id: badgeID, family: .momentum, title: "Kept It Easy", symbolName: "leaf.fill", shareEligible: false, priority: 75)
        case .finishedWhatYouStarted:
            return RecognitionDefinition(id: badgeID, family: .momentum, title: "Finished What You Started", symbolName: "checkmark.seal.fill", shareEligible: false, priority: 80)
        case .steadyReturn:
            return RecognitionDefinition(id: badgeID, family: .momentum, title: "Steady Return", symbolName: "waveform.path.ecg", shareEligible: false, priority: 72)
        case .goodTeammate:
            return RecognitionDefinition(id: badgeID, family: .social, title: "Good Teammate", symbolName: "hands.clap.fill", shareEligible: false, priority: 68)
        case .relayPlayer:
            return RecognitionDefinition(id: badgeID, family: .social, title: "Relay Player", symbolName: "person.3.sequence.fill", shareEligible: false, priority: 66)
        case .rivalEdge:
            return RecognitionDefinition(id: badgeID, family: .social, title: "Rival Edge", symbolName: "flag.checkered.2.crossed", shareEligible: true, priority: 78)
        case .photoFinish:
            return RecognitionDefinition(id: badgeID, family: .social, title: "Photo Finish", symbolName: "camera.aperture", shareEligible: true, priority: 64)
        }
    }

    static func coachLine(for badgeID: RecognitionBadgeID) -> String {
        switch badgeID {
        case .firstStep:
            return "You turned the first session into something real."
        case .shortCounts:
            return "You didn't wait for a bigger window. You used the one you had."
        case .backInMotion:
            return "You came back before it felt perfect. That's real momentum."
        case .weekClosedWell:
            return "You gave the week a clean finish instead of letting it drift."
        case .threeThisWeek:
            return "You followed through on the week you were trying to build."
        case .keptItEasy:
            return "You kept the effort honest. That kind of restraint builds trust."
        case .finishedWhatYouStarted:
            return "You kept the pattern alive long enough for it to feel like rhythm."
        case .steadyReturn:
            return "This isn't a one-off anymore. You're building your way back."
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

private struct ActivityCandidate {
    let sourceActivityID: UUID?
    let startedAt: Date
    let durationSecs: Int
    let photoCount: Int
}

struct RecognitionPill: View {
    let preview: RecognitionPreview
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 6 : 8) {
            Image(systemName: preview.symbolName)
                .font((compact ? Font.caption : .subheadline).weight(.bold))
            Text(preview.title)
                .font((compact ? Font.caption : .subheadline).weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, compact ? 10 : 12)
        .padding(.vertical, compact ? 6 : 8)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.18),
                    Color.yellow.opacity(0.12)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay {
            Capsule()
                .strokeBorder(Color.orange.opacity(0.2), lineWidth: 0.8)
        }
    }
}

struct RecognitionOrb: View {
    let preview: RecognitionPreview
    var size: CGFloat = 28

    var body: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.orange, Color.yellow.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                Circle()
                    .strokeBorder(Color.white.opacity(0.95), lineWidth: 2)
            }
            .overlay {
                Image(systemName: preview.symbolName)
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
            .shadow(color: .orange.opacity(0.28), radius: 8, y: 3)
    }
}

struct RecognitionHeroBadge: View {
    let preview: RecognitionPreview
    let secondaryCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                RecognitionOrb(preview: preview, size: 54)

                VStack(alignment: .leading, spacing: 4) {
                    Text(preview.title)
                        .font(.headline)
                    Text("Coach noticed this")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }

                Spacer()
            }

            Text(preview.coachLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if secondaryCount > 0 {
                Text("+\(secondaryCount) more recognition\(secondaryCount == 1 ? "" : "s") ready when you save.")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color.orange.opacity(0.14),
                    Color.yellow.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.18), lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
