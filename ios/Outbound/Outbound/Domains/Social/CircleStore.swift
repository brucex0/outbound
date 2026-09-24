import Combine
import Foundation

@MainActor
final class CircleContributionCenter: ObservableObject {
    static let shared = CircleContributionCenter()
    @Published private(set) var latest: CircleContributionReceipt?

    func publish(_ contributions: [CircleContributionDTO]) {
        guard let primary = contributions.first(where: \.primary) ?? contributions.first else { return }
        latest = CircleContributionReceipt(primary: primary, additionalCircleCount: max(0, contributions.count - 1))
    }
}

@MainActor
final class CircleStore: ObservableObject {
    @Published private(set) var circles: [CircleDTO] = []
    @Published private(set) var primaryCircleID: String?
    @Published private(set) var invitations: [CircleInvitationDTO] = []
    @Published private(set) var memberLimit = 6
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var toastMessage: String?
    @Published private(set) var lastConfirmedContribution: CircleContributionDTO?

    private let api: APIClient
    private let defaults: UserDefaults
    private let cachePrefix = "group_store_v1_account_"
    private var activeUserID: String?
    private var authGeneration = 0
    private var contributionObserver: AnyCancellable?

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        contributionObserver = CircleContributionCenter.shared.$latest
            .compactMap { $0 }
            .sink { [weak self] receipt in
                guard let self else { return }
                let contribution = receipt.primary
                lastConfirmedContribution = contribution
                if !contribution.completed {
                    toastMessage = contributionMessage(receipt)
                }
                Task { await self.refresh() }
            }
    }

    var primaryCircle: CircleDTO? {
        if let primaryCircleID, let selected = circles.first(where: { $0.id == primaryCircleID }) { return selected }
        return circles.first(where: \.eligibleForToday) ?? circles.first
    }

    var eligiblePrimaryCircle: CircleDTO? {
        guard let primaryCircle, primaryCircle.eligibleForToday else { return nil }
        return primaryCircle
    }

    var pendingCompletion: CircleDTO? { circles.first(where: { $0.completionPresentationPending }) }

    func activate(userID: String?) {
        guard activeUserID != userID else { return }
        if let activeUserID { defaults.removeObject(forKey: cacheKey(activeUserID)) }
        authGeneration += 1
        activeUserID = userID
        circles = []
        primaryCircleID = nil
        invitations = []
        memberLimit = 6
        errorMessage = nil
        toastMessage = nil
        lastConfirmedContribution = nil
        if isUITestSeedData, userID != nil {
            let fixture = Self.uiTestCircle
            circles = [fixture]
            primaryCircleID = fixture.id
            return
        }
        guard let userID,
              let cached = decode(CircleListResponseDTO.self, from: defaults.data(forKey: cacheKey(userID))) else { return }
        primaryCircleID = cached.primaryCircleId
        memberLimit = cached.policy.memberLimit
        circles = ordered(cached.circles, primaryID: cached.primaryCircleId)
    }

    func refresh() async {
        if isUITestSeedData {
            let fixture = Self.uiTestCircle
            circles = [fixture]
            primaryCircleID = fixture.id
            errorMessage = nil
            return
        }
        guard let userID = activeUserID else { return }
        let generation = authGeneration
        isLoading = true
        defer { if generation == authGeneration { isLoading = false } }
        do {
            let response = try await api.fetchCircles()
            guard generation == authGeneration, activeUserID == userID else { return }
            primaryCircleID = response.primaryCircleId ?? fallbackPrimaryID(in: response.circles)
            memberLimit = response.policy.memberLimit
            circles = ordered(response.circles, primaryID: primaryCircleID)
            persistCurrentState()
            errorMessage = nil
        } catch {
            guard generation == authGeneration else { return }
            errorMessage = String(localized: "group.error.offline", defaultValue: "Your Group is temporarily unavailable. Showing saved information.")
        }
    }

    func refreshInvitations() async {
        if isUITestSeedData { invitations = []; errorMessage = nil; return }
        let generation = authGeneration
        guard activeUserID != nil else { return }
        do {
            let response = try await api.fetchCircleInvitations()
            guard generation == authGeneration else { return }
            invitations = response.invitations
            errorMessage = nil
        } catch {
            guard generation == authGeneration else { return }
            errorMessage = String(localized: "group.error.invitations", defaultValue: "Group invitations could not be refreshed.")
        }
    }

    func refreshCircle(id: String) async {
        if isUITestSeedData { upsert(Self.uiTestCircle); errorMessage = nil; return }
        let generation = authGeneration
        guard activeUserID != nil else { return }
        do {
            let circle = try await api.fetchCircle(id: id)
            guard generation == authGeneration else { return }
            upsert(circle)
        } catch {
            guard generation == authGeneration else { return }
            errorMessage = String(localized: "group.error.operation", defaultValue: "That Group update didn’t go through. Try again.")
        }
    }

    func create(name: String?, memberUserIDs: [String]) async -> CircleDTO? {
        do {
            let appleWeekday = Calendar.current.firstWeekday
            let isoWeekday = ((appleWeekday + 5) % 7) + 1
            let circle = try await api.createCircle(.init(name: name?.nilIfBlank, memberUserIds: memberUserIDs, timeZone: TimeZone.current.identifier, resetWeekday: isoWeekday))
            upsert(circle)
            toastMessage = String(localized: "group.toast.created", defaultValue: "Group created. Invitations sent.")
            return circle
        } catch { return fail(error) }
    }

    func accept(_ invitation: CircleInvitationDTO) async -> Bool {
        do {
            let circle = try await api.acceptCircleInvitation(id: invitation.id)
            invitations.removeAll { $0.id == invitation.id }
            upsert(circle)
            toastMessage = String(localized: "group.toast.joined", defaultValue: "You joined the Group.")
            return true
        } catch { _ = fail(error); return false }
    }

    func decline(_ invitation: CircleInvitationDTO) async -> Bool {
        do {
            _ = try await api.declineCircleInvitation(id: invitation.id)
            invitations.removeAll { $0.id == invitation.id }
            toastMessage = String(localized: "circle.toast.declined", defaultValue: "Invitation declined.")
            return true
        } catch { _ = fail(error); return false }
    }

    func updateName(circle: CircleDTO, name: String) async -> CircleDTO? {
        await mutate(success: String(localized: "group.toast.saved", defaultValue: "Group updated.")) { try await api.updateCircleName(id: circle.id, name: name) }
    }

    func updateFocus(circle: CircleDTO, themeKey: String, customTitle: String?, customNote: String?, apply: String = "now") async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.focus_saved", defaultValue: "Weekly theme updated.")) {
            try await api.updateCircleFocus(
                id: circle.id,
                request: .init(
                    mode: "theme",
                    sharedTarget: nil,
                    themeKey: themeKey,
                    customThemeTitle: customTitle,
                    customThemeNote: customNote,
                    apply: apply
                )
            )
        }
    }

    func updateCommitment(circle: CircleDTO, targetCount: Int?, skipped: Bool, clear: Bool = false) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.commitment_saved", defaultValue: "Your weekly commitment is updated.")) { try await api.updateCircleCommitment(id: circle.id, request: .init(targetCount: targetCount, skipped: skipped, clear: clear)) }
    }

    func sendCheer(circle: CircleDTO, member: CircleMemberDTO, presetType: String) async -> Bool {
        do {
            let response = try await api.sendCircleCheer(id: circle.id, request: .init(recipientUserId: member.user.id, presetType: presetType))
            upsert(response.circle)
            toastMessage = String(localized: "circle.toast.cheer_sent", defaultValue: "Cheer sent.")
            return true
        } catch { _ = fail(error); return false }
    }

    func removeCheer(_ cheer: CircleCheerDTO, from circle: CircleDTO) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.cheer_removed", defaultValue: "Cheer removed.")) { try await api.removeCircleCheer(id: circle.id, cheerID: cheer.id).circle }
    }

    func invite(_ userIDs: [String], to circle: CircleDTO) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.invitations_sent", defaultValue: "Invitations sent.")) { try await api.inviteToCircle(id: circle.id, request: .init(recipientUserIds: userIDs, idempotencyKey: UUID().uuidString)) }
    }

    func cancel(_ invitation: CircleInvitationDTO, in circle: CircleDTO) async -> CircleDTO? {
        do {
            let response = try await api.cancelCircleInvitation(circleID: circle.id, invitationID: invitation.id)
            let updated = response.circle
            toastMessage = String(localized: "circle.toast.invitation_cancelled", defaultValue: "Invitation cancelled.")
            upsert(updated)
            return updated
        } catch { return fail(error) }
    }

    func selectPrimary(_ circle: CircleDTO) async -> Bool {
        do {
            let response = try await api.selectPrimaryCircle(id: circle.id)
            primaryCircleID = response.primaryCircleId
            if let canonicalCircle = response.circle { upsert(canonicalCircle) }
            circles = ordered(circles, primaryID: primaryCircleID)
            persistCurrentState()
            toastMessage = String(localized: "circle.toast.primary", defaultValue: "Primary Circle updated.")
            return true
        } catch { _ = fail(error); return false }
    }

    func setMuted(_ circle: CircleDTO, muted: Bool) async -> Bool {
        do {
            let refreshed = try await api.setCircleNotifications(id: circle.id, muted: muted)
            upsert(refreshed)
            toastMessage = muted ? String(localized: "circle.toast.muted", defaultValue: "Circle notifications muted.") : String(localized: "circle.toast.unmuted", defaultValue: "Circle notifications turned on.")
            return true
        } catch { _ = fail(error); return false }
    }

    func updateCalendar(circle: CircleDTO, resetWeekday: Int, timeZone: String, apply: String) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.calendar_saved", defaultValue: "Circle week updated.")) { try await api.updateCircleCalendar(id: circle.id, request: .init(resetWeekday: resetWeekday, timeZone: timeZone, apply: apply)) }
    }

    func leave(_ circle: CircleDTO) async -> Bool {
        do {
            _ = try await api.leaveCircle(id: circle.id)
            remove(circle)
            toastMessage = String(localized: "circle.toast.left", defaultValue: "You left the Circle.")
            return true
        } catch { _ = fail(error); return false }
    }

    func removeMember(_ member: CircleMemberDTO, from circle: CircleDTO) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.member_removed", defaultValue: "Member removed.")) { try await api.removeCircleMember(id: circle.id, memberUserID: member.user.id) }
    }

    func transferOwnership(of circle: CircleDTO, to member: CircleMemberDTO) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.owner_transferred", defaultValue: "Ownership transferred.")) { try await api.transferCircleOwnership(id: circle.id, recipientUserID: member.user.id) }
    }

    func archive(_ circle: CircleDTO) async -> Bool {
        do {
            let archived = try await api.archiveCircle(id: circle.id)
            upsert(archived)
            if primaryCircleID == circle.id { primaryCircleID = fallbackPrimaryID(in: circles) }
            circles = ordered(circles, primaryID: primaryCircleID)
            persistCurrentState()
            toastMessage = String(localized: "circle.toast.archived", defaultValue: "Circle archived.")
            return true
        } catch { _ = fail(error); return false }
    }

    func reactivate(_ circle: CircleDTO) async -> CircleDTO? {
        await mutate(success: String(localized: "circle.toast.reactivated", defaultValue: "Circle reactivated.")) { try await api.reactivateCircle(id: circle.id) }
    }

    func presentCompletionIfNeeded(for circle: CircleDTO) async -> Bool {
        guard circle.completionPresentationPending else { return false }
        do {
            let presented = try await api.presentCircleWeek(circleID: circle.id, weekID: circle.week.id).presented
            if presented { await refresh() }
            return presented
        } catch { return false }
    }

    func clearToast() { toastMessage = nil }

    private func mutate(success: String, operation: () async throws -> CircleDTO) async -> CircleDTO? {
        do {
            let circle = try await operation()
            upsert(circle)
            toastMessage = success
            return circle
        } catch { return fail(error) }
    }

    private func fail(_ error: Error) -> CircleDTO? {
        errorMessage = String(localized: "circle.error.operation", defaultValue: "That Circle update didn’t go through. Try again.")
        return nil
    }

    private func upsert(_ circle: CircleDTO) {
        if let index = circles.firstIndex(where: { $0.id == circle.id }) { circles[index] = circle } else { circles.append(circle) }
        if primaryCircleID == nil, circle.eligibleForToday { primaryCircleID = circle.id }
        circles = ordered(circles, primaryID: primaryCircleID)
        persistCurrentState()
        errorMessage = nil
    }

    private func remove(_ circle: CircleDTO) {
        circles.removeAll { $0.id == circle.id }
        if primaryCircleID == circle.id { primaryCircleID = fallbackPrimaryID(in: circles) }
        persistCurrentState()
    }

    private func ordered(_ circles: [CircleDTO], primaryID: String?) -> [CircleDTO] {
        circles.sorted {
            if $0.id == primaryID { return true }
            if $1.id == primaryID { return false }
            if $0.lifecycle != $1.lifecycle { return $0.lifecycle != "archived" }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private func fallbackPrimaryID(in circles: [CircleDTO]) -> String? { circles.first(where: \.eligibleForToday)?.id }

    private var isUITestSeedData: Bool {
        ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
    }

    private static var uiTestCircle: CircleDTO {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let sage = CirclePersonDTO(id: "ui-test-sage", displayName: "Sage Runner", avatarUrl: nil)
        let avery = CirclePersonDTO(id: "ui-test-avery", displayName: "Avery Runner", avatarUrl: nil)
        return CircleDTO(
            id: "ui-test-weekend-crew", name: "Weekend Crew", lifecycle: "active", role: "owner",
            owner: sage, resetWeekday: 1, timeZone: "America/Los_Angeles", memberLimit: 6,
            memberCount: 2, eligibleForToday: true,
            members: [
                CircleMemberDTO(id: "ui-test-circle-sage", user: sage, role: "owner", isCurrentUser: true, commitment: .init(targetCount: 3, skipped: false), contributedCount: 1, recentActivity: .init(type: "running", title: "Golden Gate recovery run", startedAt: now.addingTimeInterval(-86_400), durationSecs: 1_740, distanceM: 4_600, elevationM: 38, avgPace: 378, avgHeartRate: 138, energyKilocalories: 315)),
                CircleMemberDTO(id: "ui-test-circle-avery", user: avery, role: "member", isCurrentUser: false, commitment: .init(targetCount: 4, skipped: false), contributedCount: 2, recentActivity: .init(type: "running", title: "Easy neighborhood run", startedAt: now.addingTimeInterval(-172_800), durationSecs: 1_920, distanceM: 5_100, elevationM: 42, avgPace: 376, avgHeartRate: 144, energyKilocalories: 510)),
            ],
            upcomingFocus: .init(mode: "theme", focusConfigured: true, sharedTarget: nil, themeKey: "build_consistency", themeTitle: nil, themeNote: nil),
            week: .init(id: "ui-test-circle-week", startsAt: start, endsAt: start.addingTimeInterval(7 * 86_400), focusMode: "theme", focusConfigured: true, sharedTarget: nil, themeKey: "build_consistency", themeTitle: nil, themeNote: nil, state: "open", contributedCount: 3, targetCount: nil),
            currentUserMuted: false, completionPresentationPending: false,
            cheers: [.init(id: "ui-test-cheer", senderUserId: sage.id, recipientUserId: avery.id, presetType: "encouragement", createdAt: now.addingTimeInterval(-3_600))],
            invitations: [],
            upcomingActivities: [
                .init(
                    id: "ui-test-circle-activity",
                    title: "Saturday morning run",
                    startsAt: now.addingTimeInterval(86_400),
                    endsAt: now.addingTimeInterval(90_000),
                    locationName: "Golden Gate Park",
                    paceNote: "Easy and conversational",
                    status: "scheduled",
                    creator: sage,
                    attendeeCount: 2,
                    currentUserGoing: true,
                    currentUserRole: "owner"
                ),
            ],
            recentMoments: [.init(id: "ui-test-moment", type: "cheer", createdAt: now.addingTimeInterval(-3_600), title: "encouragement")],
            history: []
        )
    }

    private func contributionMessage(_ receipt: CircleContributionReceipt) -> String {
        let contribution = receipt.primary
        let primaryMessage: String
        if let target = contribution.targetCount {
            primaryMessage = String(localized: "circle.contribution.confirmed_progress", defaultValue: "You moved your Circle forward. \(contribution.contributedCount) of \(target) activities complete this week.")
        } else {
            primaryMessage = String(localized: "circle.contribution.confirmed", defaultValue: "You moved your Circle forward.")
        }
        guard receipt.additionalCircleCount > 0 else { return primaryMessage }
        let additional = String(localized: "circle.contribution.additional", defaultValue: "It also counted for \(receipt.additionalCircleCount) other Circles.")
        return "\(primaryMessage) \(additional)"
    }

    private func persistCurrentState() {
        guard let activeUserID else { return }
        defaults.set(try? encode(CircleListResponseDTO(circles: circles, primaryCircleId: primaryCircleID, policy: .init(memberLimit: memberLimit))), forKey: cacheKey(activeUserID))
    }

    private func cacheKey(_ userID: String) -> String { cachePrefix + userID }
    private func encode<T: Encodable>(_ value: T) throws -> Data { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(value) }
    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? { guard let data else { return nil }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try? decoder.decode(type, from: data) }
}

private extension String {
    var nilIfBlank: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
}
