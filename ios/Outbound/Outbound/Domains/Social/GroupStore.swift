import Combine
import Foundation

@MainActor
final class GroupContributionCenter: ObservableObject {
    static let shared = GroupContributionCenter()
    @Published private(set) var latest: GroupContributionReceipt?

    func publish(_ contributions: [GroupContributionDTO]) {
        guard let primary = contributions.first else { return }
        latest = GroupContributionReceipt(primary: primary, additionalGroupCount: max(0, contributions.count - 1))
    }
}

@MainActor
final class GroupStore: ObservableObject {
    @Published private(set) var groups: [GroupDTO] = []
    @Published private(set) var invitations: [GroupInvitationDTO] = []
    @Published private(set) var memberLimit = 6
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var toastMessage: String?
    @Published private(set) var lastConfirmedContribution: GroupContributionDTO?

    private let api: APIClient
    private let defaults: UserDefaults
    private let cachePrefix = "group_store_v1_account_"
    private var activeUserID: String?
    private var authGeneration = 0
    private var contributionObserver: AnyCancellable?

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        contributionObserver = GroupContributionCenter.shared.$latest
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

    var pendingCompletion: GroupDTO? { groups.first(where: { $0.completionPresentationPending }) }

    func activate(userID: String?) {
        guard activeUserID != userID else { return }
        if let activeUserID { defaults.removeObject(forKey: cacheKey(activeUserID)) }
        authGeneration += 1
        activeUserID = userID
        groups = []
        invitations = []
        memberLimit = 6
        errorMessage = nil
        toastMessage = nil
        lastConfirmedContribution = nil
        if isUITestSeedData, userID != nil {
            let fixture = Self.uiTestGroup
            groups = [fixture]
            return
        }
        guard let userID,
              let cached = decode(GroupListResponseDTO.self, from: defaults.data(forKey: cacheKey(userID))) else { return }
        memberLimit = cached.policy.memberLimit
        groups = ordered(cached.groups)
    }

    func refresh() async {
        if isUITestSeedData {
            let fixture = Self.uiTestGroup
            groups = [fixture]
            errorMessage = nil
            return
        }
        guard let userID = activeUserID else { return }
        let generation = authGeneration
        isLoading = true
        defer { if generation == authGeneration { isLoading = false } }
        do {
            let response = try await api.fetchGroups()
            guard generation == authGeneration, activeUserID == userID else { return }
            memberLimit = response.policy.memberLimit
            groups = ordered(response.groups)
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
            let response = try await api.fetchGroupInvitations()
            guard generation == authGeneration else { return }
            invitations = response.invitations
            errorMessage = nil
        } catch {
            guard generation == authGeneration else { return }
            errorMessage = String(localized: "group.error.invitations", defaultValue: "Group invitations could not be refreshed.")
        }
    }

    func refreshGroup(id: String) async {
        if isUITestSeedData { upsert(Self.uiTestGroup); errorMessage = nil; return }
        let generation = authGeneration
        guard activeUserID != nil else { return }
        do {
            let group = try await api.fetchGroup(id: id)
            guard generation == authGeneration else { return }
            upsert(group)
        } catch {
            guard generation == authGeneration else { return }
            errorMessage = String(localized: "group.error.operation", defaultValue: "That Group update didn’t go through. Try again.")
        }
    }

    func create(template: String = "motivation", name: String?, description: String? = nil, city: String? = nil, activityInterests: [String] = [], memberUserIDs: [String]) async -> GroupDTO? {
        do {
            let appleWeekday = Calendar.current.firstWeekday
            let isoWeekday = ((appleWeekday + 5) % 7) + 1
            let group = try await api.createGroup(.init(template: template, name: name?.nilIfBlank, description: description?.nilIfBlank, city: city?.nilIfBlank, activityInterests: activityInterests, memberUserIds: memberUserIDs, timeZone: TimeZone.current.identifier, resetWeekday: isoWeekday))
            upsert(group)
            toastMessage = String(localized: "group.toast.created", defaultValue: "Group created. Invitations sent.")
            return group
        } catch { return fail(error) }
    }

    func accept(_ invitation: GroupInvitationDTO) async -> Bool {
        do {
            let group = try await api.acceptGroupInvitation(id: invitation.id)
            invitations.removeAll { $0.id == invitation.id }
            upsert(group)
            toastMessage = String(localized: "group.toast.joined", defaultValue: "You joined the Group.")
            return true
        } catch { _ = fail(error); return false }
    }

    func decline(_ invitation: GroupInvitationDTO) async -> Bool {
        do {
            _ = try await api.declineGroupInvitation(id: invitation.id)
            invitations.removeAll { $0.id == invitation.id }
            toastMessage = String(localized: "group.toast.declined", defaultValue: "Invitation declined.")
            return true
        } catch { _ = fail(error); return false }
    }

    func updateName(group: GroupDTO, name: String) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.saved", defaultValue: "Group updated.")) { try await api.updateGroupName(id: group.id, name: name) }
    }

    func updateFocus(group: GroupDTO, themeKey: String, customTitle: String?, customNote: String?, apply: String = "now") async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.focus_saved", defaultValue: "Weekly theme updated.")) {
            try await api.updateGroupFocus(
                id: group.id,
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

    func updateCommitment(group: GroupDTO, targetCount: Int?, skipped: Bool, clear: Bool = false) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.commitment_saved", defaultValue: "Your weekly commitment is updated.")) { try await api.updateGroupCommitment(id: group.id, request: .init(targetCount: targetCount, skipped: skipped, clear: clear)) }
    }

    func sendCheer(group: GroupDTO, member: GroupMemberDTO, presetType: String) async -> Bool {
        do {
            let response = try await api.sendGroupCheer(id: group.id, request: .init(recipientUserId: member.user.id, presetType: presetType))
            upsert(response.group)
            toastMessage = String(localized: "group.toast.cheer_sent", defaultValue: "Cheer sent.")
            return true
        } catch { _ = fail(error); return false }
    }

    func removeCheer(_ cheer: GroupCheerDTO, from group: GroupDTO) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.cheer_removed", defaultValue: "Cheer removed.")) { try await api.removeGroupCheer(id: group.id, cheerID: cheer.id).group }
    }

    func invite(_ userIDs: [String], to group: GroupDTO) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.invitations_sent", defaultValue: "Invitations sent.")) { try await api.inviteToGroup(id: group.id, request: .init(recipientUserIds: userIDs, idempotencyKey: UUID().uuidString)) }
    }

    func cancel(_ invitation: GroupInvitationDTO, in group: GroupDTO) async -> GroupDTO? {
        do {
            let response = try await api.cancelGroupInvitation(groupID: group.id, invitationID: invitation.id)
            let updated = response.group
            toastMessage = String(localized: "group.toast.invitation_cancelled", defaultValue: "Invitation cancelled.")
            upsert(updated)
            return updated
        } catch { return fail(error) }
    }

    func publishNotice(group: GroupDTO, title: String?, body: String, pinned: Bool) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.notice_published", defaultValue: "Notice published.")) {
            try await api.createGroupNotice(id: group.id, request: .init(title: title?.nilIfBlank, body: body, activityEventId: nil, pinned: pinned))
        }
    }

    func markNoticesRead(in group: GroupDTO) async -> GroupDTO? {
        do {
            let updated = try await api.markGroupNoticesRead(id: group.id)
            upsert(updated)
            return updated
        } catch { return fail(error) }
    }

    func createInviteLink(for group: GroupDTO) async -> URL? {
        do {
            let link = try await api.createGroupInviteLink(id: group.id)
            guard let url = link.url.flatMap(URL.init(string:)) else { return nil }
            toastMessage = String(localized: "group.toast.link_created", defaultValue: "Invite link created.")
            return url
        } catch { _ = fail(error); return nil }
    }

    func consumeInvite(token: String) async -> Bool {
        do {
            let group = try await api.consumeGroupInvite(token: token)
            upsert(group)
            toastMessage = String(localized: "group.toast.joined", defaultValue: "You joined the Group.")
            return true
        } catch { _ = fail(error); return false }
    }

    func setMuted(_ group: GroupDTO, muted: Bool) async -> Bool {
        do {
            let refreshed = try await api.setGroupNotifications(id: group.id, muted: muted)
            upsert(refreshed)
            toastMessage = muted ? String(localized: "group.toast.muted", defaultValue: "Group notifications muted.") : String(localized: "group.toast.unmuted", defaultValue: "Group notifications turned on.")
            return true
        } catch { _ = fail(error); return false }
    }

    func updateCalendar(group: GroupDTO, resetWeekday: Int, timeZone: String, apply: String) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.calendar_saved", defaultValue: "Group week updated.")) { try await api.updateGroupCalendar(id: group.id, request: .init(resetWeekday: resetWeekday, timeZone: timeZone, apply: apply)) }
    }

    func leave(_ group: GroupDTO) async -> Bool {
        do {
            _ = try await api.leaveGroup(id: group.id)
            remove(group)
            toastMessage = String(localized: "group.toast.left", defaultValue: "You left the Group.")
            return true
        } catch { _ = fail(error); return false }
    }

    func requestMembership(in group: GroupDTO) async -> Bool {
        do {
            _ = try await api.joinSocialGroup(id: group.id)
            await refreshGroup(id: group.id)
            toastMessage = String(localized: "group.toast.requested", defaultValue: "Join request sent.")
            return true
        } catch { _ = fail(error); return false }
    }

    func removeMember(_ member: GroupMemberDTO, from group: GroupDTO) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.member_removed", defaultValue: "Member removed.")) { try await api.removeGroupMember(id: group.id, memberUserID: member.user.id) }
    }

    func setRole(_ role: String, for member: GroupMemberDTO, in group: GroupDTO) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.role_saved", defaultValue: "Member role updated.")) { try await api.updateGroupMemberRole(id: group.id, memberUserID: member.user.id, role: role) }
    }

    func transferOwnership(of group: GroupDTO, to member: GroupMemberDTO) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.owner_transferred", defaultValue: "Ownership transferred.")) { try await api.transferGroupOwnership(id: group.id, recipientUserID: member.user.id) }
    }

    func archive(_ group: GroupDTO) async -> Bool {
        do {
            let archived = try await api.archiveGroup(id: group.id)
            upsert(archived)
            groups = ordered(groups)
            persistCurrentState()
            toastMessage = String(localized: "group.toast.archived", defaultValue: "Group archived.")
            return true
        } catch { _ = fail(error); return false }
    }

    func reactivate(_ group: GroupDTO) async -> GroupDTO? {
        await mutate(success: String(localized: "group.toast.reactivated", defaultValue: "Group reactivated.")) { try await api.reactivateGroup(id: group.id) }
    }

    func presentCompletionIfNeeded(for group: GroupDTO) async -> Bool {
        guard group.completionPresentationPending else { return false }
        do {
            let presented = try await api.presentGroupWeek(groupID: group.id, weekID: group.week.id).presented
            if presented { await refresh() }
            return presented
        } catch { return false }
    }

    func clearToast() { toastMessage = nil }

    private func mutate(success: String, operation: () async throws -> GroupDTO) async -> GroupDTO? {
        do {
            let group = try await operation()
            upsert(group)
            toastMessage = success
            return group
        } catch { return fail(error) }
    }

    private func fail(_ error: Error) -> GroupDTO? {
        errorMessage = String(localized: "group.error.operation", defaultValue: "That Group update didn’t go through. Try again.")
        return nil
    }

    private func upsert(_ group: GroupDTO) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) { groups[index] = group } else { groups.append(group) }
        groups = ordered(groups)
        persistCurrentState()
        errorMessage = nil
    }

    private func remove(_ group: GroupDTO) {
        groups.removeAll { $0.id == group.id }
        persistCurrentState()
    }

    private func ordered(_ groups: [GroupDTO]) -> [GroupDTO] {
        groups.sorted {
            if $0.lifecycle != $1.lifecycle { return $0.lifecycle != "archived" }
            return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private var isUITestSeedData: Bool {
        ProcessInfo.processInfo.arguments.contains("-OutboundUITestSeedData")
    }

    private static var uiTestGroup: GroupDTO {
        let now = Date()
        let start = Calendar.current.date(byAdding: .day, value: -2, to: now) ?? now
        let sage = GroupPersonDTO(id: "ui-test-sage", displayName: "Sage Runner", avatarUrl: nil)
        let avery = GroupPersonDTO(id: "ui-test-avery", displayName: "Avery Runner", avatarUrl: nil)
        return GroupDTO(
            id: "ui-test-weekend-crew", name: "Weekend Crew", lifecycle: "active", role: "owner",
            owner: sage, resetWeekday: 1, timeZone: "America/Los_Angeles", memberLimit: 6,
            memberCount: 2, eligibleForToday: true,
            members: [
                GroupMemberDTO(id: "ui-test-group-sage", user: sage, role: "owner", isCurrentUser: true, commitment: .init(targetCount: 3, skipped: false), contributedCount: 1, recentActivity: .init(type: "running", title: "Golden Gate recovery run", startedAt: now.addingTimeInterval(-86_400), durationSecs: 1_740, distanceM: 4_600, elevationM: 38, avgPace: 378, avgHeartRate: 138, energyKilocalories: 315)),
                GroupMemberDTO(id: "ui-test-group-avery", user: avery, role: "member", isCurrentUser: false, commitment: .init(targetCount: 4, skipped: false), contributedCount: 2, recentActivity: .init(type: "running", title: "Easy neighborhood run", startedAt: now.addingTimeInterval(-172_800), durationSecs: 1_920, distanceM: 5_100, elevationM: 42, avgPace: 376, avgHeartRate: 144, energyKilocalories: 510)),
            ],
            upcomingFocus: .init(mode: "theme", focusConfigured: true, sharedTarget: nil, themeKey: "build_consistency", themeTitle: nil, themeNote: nil),
            week: .init(id: "ui-test-group-week", startsAt: start, endsAt: start.addingTimeInterval(7 * 86_400), focusMode: "theme", focusConfigured: true, sharedTarget: nil, themeKey: "build_consistency", themeTitle: nil, themeNote: nil, state: "open", contributedCount: 3, targetCount: nil),
            currentUserMuted: false, completionPresentationPending: false,
            cheers: [.init(id: "ui-test-cheer", senderUserId: sage.id, recipientUserId: avery.id, presetType: "encouragement", createdAt: now.addingTimeInterval(-3_600))],
            invitations: [],
            upcomingActivities: [
                .init(
                    id: "ui-test-group-activity",
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

    private func contributionMessage(_ receipt: GroupContributionReceipt) -> String {
        let contribution = receipt.primary
        let primaryMessage: String
        if let target = contribution.targetCount {
            primaryMessage = String(localized: "group.contribution.confirmed_progress", defaultValue: "You moved your Group forward. \(contribution.contributedCount) of \(target) activities complete this week.")
        } else {
            primaryMessage = String(localized: "group.contribution.confirmed", defaultValue: "You moved your Group forward.")
        }
        guard receipt.additionalGroupCount > 0 else { return primaryMessage }
        let additional = String(localized: "group.contribution.additional", defaultValue: "It also counted for \(receipt.additionalGroupCount) other Groups.")
        return "\(primaryMessage) \(additional)"
    }

    private func persistCurrentState() {
        guard let activeUserID else { return }
        defaults.set(try? encode(GroupListResponseDTO(groups: groups, nextCursor: nil, policy: .init(memberLimit: memberLimit))), forKey: cacheKey(activeUserID))
    }

    private func cacheKey(_ userID: String) -> String { cachePrefix + userID }
    private func encode<T: Encodable>(_ value: T) throws -> Data { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return try encoder.encode(value) }
    private func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? { guard let data else { return nil }; let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return try? decoder.decode(type, from: data) }
}

private extension String {
    var nilIfBlank: String? { let value = trimmingCharacters(in: .whitespacesAndNewlines); return value.isEmpty ? nil : value }
}
