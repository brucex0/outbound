import Combine
import Foundation
import SwiftUI

enum RecognitionFamily: String, Codable, CaseIterable {
    case showedUp
    case momentum

    var title: String {
        switch self {
        case .showedUp:
            String(localized: "recognition.family.showed_up", defaultValue: "Beginnings")
        case .momentum:
            String(localized: "recognition.family.momentum", defaultValue: "Progress")
        }
    }
}

enum RecognitionBadgeID: String, Codable, CaseIterable, Identifiable {
    case firstStep
    case backInMotion
    case weeklyFocusComplete
    case fourWeekRhythm
    case first5K
    case first10K
    case firstHalfMarathon
    case firstMarathon

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

struct RecognitionAwardDTO: Codable, Sendable {
    let id: UUID
    let badgeId: String
    let family: String
    let earnedAt: Date
    let sourceType: String
    let sourceActivityId: String?
    let sourceReferenceId: String?
    let ruleVersion: Int
    let shareEligible: Bool
}

struct RecognitionAwardsResponseDTO: Codable, Sendable {
    let awards: [RecognitionAwardDTO]
}

struct RecognitionClaimDTO: Codable, Sendable {
    let badgeId: String
    let earnedAt: Date
    let sourceActivityId: UUID?
    let sourceReferenceId: String?
}

struct RecognitionClaimsRequestDTO: Codable, Sendable {
    let claims: [RecognitionClaimDTO]
}

struct RecognitionPreview: Identifiable, Equatable {
    let badgeID: RecognitionBadgeID
    let title: String
    let symbolName: String
    let guideLine: String

    var id: RecognitionBadgeID { badgeID }
}

@MainActor
final class RecognitionStore: ObservableObject {
    @Published private(set) var awards: [RecognitionAward]
    @Published private(set) var isSyncing = false

    private let api: APIClient
    private let analyticsManager: AnalyticsManager?
    private let defaults: UserDefaults
    private let calendar: Calendar
    private let legacyAwardsKey = "recognition_store_awards_v1"
    private let legacyMigrationKey = "recognition_store_account_migration_v2"
    private var currentUserID: String?
    private var syncTask: Task<Void, Never>?

    init(
        api: APIClient? = nil,
        analyticsManager: AnalyticsManager? = nil,
        defaults: UserDefaults = .standard,
        calendar: Calendar = .current
    ) {
        self.api = api ?? .shared
        self.analyticsManager = analyticsManager
        self.defaults = defaults
        self.calendar = calendar
        self.awards = []
    }

    func activate(userID: String) {
        if currentUserID != userID {
            syncTask?.cancel()
            currentUserID = userID
            migrateLegacyAwardsIfNeeded()
            awards = cachedAwards(for: userID)
            awards.sort { $0.earnedAt > $1.earnedAt }
        }
    }

    func start(userID: String) async {
        activate(userID: userID)
        await refresh()
    }

    func refresh() async {
        guard currentUserID != nil, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            if !awards.isEmpty {
                _ = try await api.claimRecognitionAwards(awards.map { award in
                    RecognitionClaimDTO(
                        badgeId: award.badgeID.rawValue,
                        earnedAt: award.earnedAt,
                        sourceActivityId: award.sourceActivityID,
                        sourceReferenceId: nil
                    )
                })
            }
            let response = try await api.fetchRecognitionAwards(
                timeZoneIdentifier: TimeZone.current.identifier,
                firstWeekday: calendar.firstWeekday
            )
            let syncedAwards = response.awards.compactMap { award -> RecognitionAward? in
                guard let badgeID = RecognitionBadgeID(rawValue: award.badgeId) else { return nil }
                return RecognitionAward(
                    id: award.id,
                    badgeID: badgeID,
                    earnedAt: award.earnedAt,
                    sourceActivityID: award.sourceActivityId.flatMap(UUID.init(uuidString:))
                )
            }
            awards = syncedAwards.sorted { $0.earnedAt > $1.earnedAt }
            persistAwards()
            await analyticsManager?.track(.init(
                .recognitionSyncCompleted,
                properties: [
                    .countBucket: .string(ProductAnalyticsBucket.count(awards.count)),
                    .sourceType: .string("server")
                ]
            ))
        } catch {
            await analyticsManager?.track(.init(
                .recognitionSyncFailed,
                properties: [
                    .sourceType: .string("server"),
                    .errorCategory: .string(Self.syncErrorCategory(error))
                ]
            ))
        }
    }

    var latestAward: RecognitionAward? {
        awards.first
    }

    var todayHighlight: RecognitionPreview? {
        guard let latestAward, isHighlightStillFresh(latestAward.earnedAt) else { return nil }
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
        activityType: ActivityType,
        priorActivities: [SavedActivity],
        goalProgress: GoalProgressSnapshot?
    ) -> [RecognitionPreview] {
        let candidate = ActivityCandidate(
            activityType: activityType,
            startedAt: summary.startedAt,
            distanceM: summary.distanceM
        )

        return candidateBadgeIDs(
            for: candidate,
            priorActivities: priorActivities,
            goalProgress: goalProgress
        )
        .map(preview(for:))
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
        previewPostRunRecognition(
            summary: summary,
            activityType: intent?.resolvedActivityType ?? .running,
            priorActivities: priorActivities,
            goalProgress: goalProgress
        )
    }

    func recordSavedActivity(
        _ activity: SavedActivity,
        priorActivities: [SavedActivity],
        goalProgress: GoalProgressSnapshot?,
        now: Date = Date()
    ) -> [RecognitionAward] {
        let candidate = ActivityCandidate(
            activityType: activity.activityType,
            startedAt: activity.startedAt,
            distanceM: activity.distanceM
        )

        let newAwards = candidateBadgeIDs(
            for: candidate,
            priorActivities: priorActivities,
            goalProgress: goalProgress
        )
        .compactMap { awardBadgeIfNeeded($0, sourceActivityID: activity.id, now: now) }

        if !newAwards.isEmpty {
            persistAwards()
            scheduleSync()
            Task {
                await analyticsManager?.track(.init(
                    .recognitionAwarded,
                    properties: [
                        .countBucket: .string(ProductAnalyticsBucket.count(newAwards.count)),
                        .sourceType: .string("activity")
                    ]
                ))
            }
        }
        return newAwards
    }

    func recordSavedActivity(
        _ activity: SavedActivity,
        priorActivities: [SavedActivity],
        readiness: DailyReadiness?,
        intent: SessionIntent?,
        goalProgress: GoalProgressSnapshot?,
        now: Date = Date()
    ) -> [RecognitionAward] {
        recordSavedActivity(
            activity,
            priorActivities: priorActivities,
            goalProgress: goalProgress,
            now: now
        )
    }

    func preview(for badgeID: RecognitionBadgeID) -> RecognitionPreview {
        RecognitionPreview(
            badgeID: badgeID,
            title: Self.definition(for: badgeID).title,
            symbolName: Self.definition(for: badgeID).symbolName,
            guideLine: Self.guideLine(for: badgeID)
        )
    }

    private func candidateBadgeIDs(
        for candidate: ActivityCandidate,
        priorActivities: [SavedActivity],
        goalProgress: GoalProgressSnapshot?
    ) -> [RecognitionBadgeID] {
        var badgeIDs: [RecognitionBadgeID] = []

        if priorActivities.isEmpty {
            badgeIDs.append(.firstStep)
        }

        if isComeback(candidate.startedAt, priorActivities: priorActivities) {
            badgeIDs.append(.backInMotion)
        }

        if goalProgress?.isComplete == true {
            badgeIDs.append(.weeklyFocusComplete)
        }

        if hasFourWeekRhythm(candidate.startedAt, priorActivities: priorActivities) {
            badgeIDs.append(.fourWeekRhythm)
        }

        if [.running, .walking, .hiking].contains(candidate.activityType) {
            let distanceMilestones: [(RecognitionBadgeID, Double)] = [
                (.first5K, 5_000),
                (.first10K, 10_000),
                (.firstHalfMarathon, 21_097.5),
                (.firstMarathon, 42_195),
            ]
            badgeIDs.append(contentsOf: distanceMilestones.compactMap { badgeID, threshold in
                candidate.distanceM >= threshold ? badgeID : nil
            })
        }

        let notYetEarned = badgeIDs.filter { !hasAwarded($0) }
        return notYetEarned.sorted { Self.definition(for: $0).priority > Self.definition(for: $1).priority }
    }

    private func isComeback(_ date: Date, priorActivities: [SavedActivity]) -> Bool {
        let candidateDay = calendar.startOfDay(for: date)
        guard let sevenDaysBack = calendar.date(byAdding: .day, value: -7, to: candidateDay) else { return false }
        let earlierActivities = priorActivities.filter { $0.startedAt < candidateDay }
        guard !earlierActivities.isEmpty else { return false }
        return !earlierActivities.contains {
            let started = $0.startedAt
            return started >= sevenDaysBack && started < candidateDay
        }
    }

    private func hasFourWeekRhythm(_ date: Date, priorActivities: [SavedActivity]) -> Bool {
        guard let currentWeek = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        let activeWeekStarts = Set(priorActivities.compactMap {
            calendar.dateInterval(of: .weekOfYear, for: $0.startedAt)?.start
        }).union([currentWeek.start])

        return (0..<4).allSatisfy { offset in
            guard let requiredWeek = calendar.date(byAdding: .weekOfYear, value: -offset, to: currentWeek.start) else {
                return false
            }
            return activeWeekStarts.contains(requiredWeek)
        }
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
        defaults.set(data, forKey: awardsStorageKey)
    }

    private var awardsStorageKey: String {
        currentUserID.map { "recognition_store_awards_v2_\($0)" } ?? legacyAwardsKey
    }

    private func cachedAwards(for userID: String) -> [RecognitionAward] {
        Self.decode(
            [RecognitionAward].self,
            from: defaults.data(forKey: "recognition_store_awards_v2_\(userID)")
        ) ?? []
    }

    private func migrateLegacyAwardsIfNeeded() {
        guard let currentUserID, !defaults.bool(forKey: legacyMigrationKey) else { return }
        let scopedKey = "recognition_store_awards_v2_\(currentUserID)"
        if defaults.data(forKey: scopedKey) == nil,
           let legacyData = defaults.data(forKey: legacyAwardsKey) {
            defaults.set(legacyData, forKey: scopedKey)
        }
        defaults.set(true, forKey: legacyMigrationKey)
    }

    private func scheduleSync() {
        guard currentUserID != nil else { return }
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private nonisolated static func syncErrorCategory(_ error: Error) -> String {
        if case let APIError.http(statusCode, _, _) = error { return "http_\(statusCode)" }
        if error is DecodingError { return "decoding" }
        if let urlError = error as? URLError {
            return urlError.code == .notConnectedToInternet ? "offline" : "network"
        }
        return "unknown"
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    static func definition(for badgeID: RecognitionBadgeID) -> RecognitionDefinition {
        switch badgeID {
        case .firstStep:
            return RecognitionDefinition(
                id: badgeID,
                family: .showedUp,
                title: String(localized: "recognition.badge.first_step.title", defaultValue: "First Step"),
                symbolName: "figure.walk.motion",
                shareEligible: false,
                priority: 70
            )
        case .backInMotion:
            return RecognitionDefinition(
                id: badgeID,
                family: .showedUp,
                title: String(localized: "recognition.badge.back_in_motion.title", defaultValue: "Back In Motion"),
                symbolName: "arrow.clockwise.heart",
                shareEligible: true,
                priority: 100
            )
        case .weeklyFocusComplete:
            return RecognitionDefinition(
                id: badgeID,
                family: .momentum,
                title: String(localized: "recognition.badge.weekly_focus_complete.title", defaultValue: "Weekly Focus Complete"),
                symbolName: "target",
                shareEligible: true,
                priority: 90
            )
        case .fourWeekRhythm:
            return RecognitionDefinition(
                id: badgeID,
                family: .momentum,
                title: String(localized: "recognition.badge.four_week_rhythm.title", defaultValue: "Four-Week Rhythm"),
                symbolName: "calendar.badge.checkmark",
                shareEligible: false,
                priority: 85
            )
        case .first5K:
            return RecognitionDefinition(
                id: badgeID,
                family: .momentum,
                title: String(localized: "recognition.badge.first_5k.title", defaultValue: "First 5K"),
                symbolName: "5.circle.fill",
                shareEligible: true,
                priority: 82
            )
        case .first10K:
            return RecognitionDefinition(
                id: badgeID,
                family: .momentum,
                title: String(localized: "recognition.badge.first_10k.title", defaultValue: "First 10K"),
                symbolName: "10.circle.fill",
                shareEligible: true,
                priority: 84
            )
        case .firstHalfMarathon:
            return RecognitionDefinition(
                id: badgeID,
                family: .momentum,
                title: String(localized: "recognition.badge.first_half_marathon.title", defaultValue: "First Half Marathon"),
                symbolName: "medal.fill",
                shareEligible: true,
                priority: 92
            )
        case .firstMarathon:
            return RecognitionDefinition(
                id: badgeID,
                family: .momentum,
                title: String(localized: "recognition.badge.first_marathon.title", defaultValue: "First Marathon"),
                symbolName: "trophy.fill",
                shareEligible: true,
                priority: 95
            )
        }
    }

    static func guideLine(for badgeID: RecognitionBadgeID) -> String {
        switch badgeID {
        case .firstStep:
            return String(
                localized: "recognition.badge.first_step.detail",
                defaultValue: "You turned the first session into something real."
            )
        case .backInMotion:
            return String(
                localized: "recognition.badge.back_in_motion.detail",
                defaultValue: "You came back before it felt perfect. That's real momentum."
            )
        case .weeklyFocusComplete:
            return String(
                localized: "recognition.badge.weekly_focus_complete.detail",
                defaultValue: "You followed through on the week you were trying to build."
            )
        case .fourWeekRhythm:
            return String(
                localized: "recognition.badge.four_week_rhythm.detail",
                defaultValue: "You showed up across four straight weeks. That is a rhythm you can build on."
            )
        case .first5K:
            return String(
                localized: "recognition.badge.first_5k.detail",
                defaultValue: "Five kilometers in one activity. You have a real distance marker now."
            )
        case .first10K:
            return String(
                localized: "recognition.badge.first_10k.detail",
                defaultValue: "Ten kilometers changes what the next finish line can look like."
            )
        case .firstHalfMarathon:
            return String(
                localized: "recognition.badge.first_half_marathon.detail",
                defaultValue: "You carried the effort through 21.1 kilometers. That belongs in your history."
            )
        case .firstMarathon:
            return String(
                localized: "recognition.badge.first_marathon.detail",
                defaultValue: "42.2 kilometers, start to finish. You earned a milestone that lasts."
            )
        }
    }
}

private struct ActivityCandidate {
    let activityType: ActivityType
    let startedAt: Date
    let distanceM: Double
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

struct RecognitionAwardRow: View {
    let award: RecognitionAward
    let preview: RecognitionPreview

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RecognitionOrb(preview: preview, size: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(preview.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(earnedDate)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(preview.guideLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var earnedDate: String {
        let formattedDate = award.earnedAt.formatted(date: .abbreviated, time: .omitted)
        return String.localizedStringWithFormat(
            String(localized: "recognition.earned_on.format", defaultValue: "Earned %@"),
            formattedDate
        )
    }
}

struct RecognitionEmptyState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles")
                .font(.headline.weight(.semibold))
                .foregroundStyle(.orange)
                .frame(width: 46, height: 46)
                .background(Color.orange.opacity(0.12), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(String(
                    localized: "recognition.empty.title",
                    defaultValue: "Your first milestone is ahead"
                ))
                .font(.subheadline.weight(.semibold))

                Text(String(
                    localized: "recognition.empty.detail",
                    defaultValue: "Save activities and meaningful firsts, distance, consistency, and comebacks will appear here."
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct RecognitionHistoryView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var recognitionStore: RecognitionStore

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                Text(String(
                    localized: "recognition.history.intro",
                    defaultValue: "The moments here mark meaningful beginnings, distance, consistency, and comebacks."
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)

                if recognitionStore.awards.isEmpty {
                    OutboundCard {
                        RecognitionEmptyState()
                    }
                } else {
                    ForEach(earnedFamilies, id: \.self) { family in
                        OutboundCard {
                            VStack(alignment: .leading, spacing: OutboundSpacing.standard) {
                                Text(family.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                ForEach(Array(awards(for: family).enumerated()), id: \.element.id) { index, award in
                                    if index > 0 {
                                        Divider()
                                    }
                                    RecognitionAwardRow(
                                        award: award,
                                        preview: recognitionStore.preview(for: award.badgeID)
                                    )
                                }
                            }
                        }
                    }
                }
            }
            .padding(OutboundSpacing.screen)
        }
        .background(OutboundPalette.background)
        .navigationTitle(String(localized: "recognition.title", defaultValue: "Milestones"))
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("me_recognition_history"),
            ]))
        }
    }

    private var earnedFamilies: [RecognitionFamily] {
        RecognitionFamily.allCases.filter { !awards(for: $0).isEmpty }
    }

    private func awards(for family: RecognitionFamily) -> [RecognitionAward] {
        recognitionStore.awards.filter { RecognitionStore.definition(for: $0.badgeID).family == family }
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
                    Text(String(localized: "recognition.hero.eyebrow", defaultValue: "Milestone reached"))
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.orange)
                }

                Spacer()
            }

            Text(preview.guideLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if secondaryCount > 0 {
                Text(String(
                    localized: "recognition.hero.more",
                    defaultValue: "More milestones are ready when you save."
                ))
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
