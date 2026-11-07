import SwiftUI

struct GroupMembershipSettingsView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.analyticsManager) private var analyticsManager
    let group: GroupDTO
    @State private var memberInvitesAllowed: Bool
    @State private var approvalRequired: Bool
    @State private var savedMemberInvitesAllowed: Bool
    @State private var savedApprovalRequired: Bool
    @State private var saving = false
    @State private var reviewing: Set<String> = []

    init(group: GroupDTO) {
        self.group = group
        let required = group.trustPolicy == "community" ? group.joinPolicy != "open" : group.memberInviteApprovalRequired
        _memberInvitesAllowed = State(initialValue: group.memberInvitesAllowed)
        _approvalRequired = State(initialValue: required)
        _savedMemberInvitesAllowed = State(initialValue: group.memberInvitesAllowed)
        _savedApprovalRequired = State(initialValue: required)
    }

    private var current: GroupDTO { groupStore.groups.first(where: { $0.id == group.id }) ?? group }
    private var dirty: Bool { memberInvitesAllowed != savedMemberInvitesAllowed || approvalRequired != savedApprovalRequired }

    var body: some View {
        Form {
            if current.role == "owner" {
                Section {
                    Toggle(String(localized: "Allow members to invite friends", table: "GroupMembership"), isOn: $memberInvitesAllowed)
                        .accessibilityIdentifier("group.membership.member_invites_allowed")
                    Toggle(String(localized: "Require approval to join", table: "GroupMembership"), isOn: $approvalRequired)
                        .accessibilityIdentifier("group.membership.approval_required")
                    Text(current.trustPolicy == "community"
                        ? String(localized: "Community Groups remain open to joining. Approval applies to discovery and member invitations; invitations from owners and admins are pre-approved.", table: "GroupMembership")
                        : String(localized: "Private Groups require an invitation. Approval applies to member invitations; owner and admin invitations are pre-approved.", table: "GroupMembership"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .disabled(saving || current.lifecycle == "archived")
            }
            Section {
                if current.joinRequests.isEmpty {
                    Text(String(localized: "No membership requests to review", table: "GroupMembership"))
                        .foregroundStyle(.secondary)
                }
                ForEach(current.joinRequests) { request in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(request.requester.displayName).font(.headline)
                        if let inviter = request.inviter {
                            Text(String(format: String(localized: "Invited by %@", table: "GroupMembership"), inviter.displayName))
                                .font(.subheadline).foregroundStyle(.secondary)
                        }
                        HStack {
                            Button(String(localized: "Approve", table: "GroupMembership")) { review(request, approve: true) }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("group.request.approve.\(request.id)")
                            Button(String(localized: "Decline", table: "GroupMembership"), role: .destructive) { review(request, approve: false) }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("group.request.deny.\(request.id)")
                            if reviewing.contains(request.id) { ProgressView() }
                        }
                        .disabled(reviewing.contains(request.id) || current.lifecycle == "archived")
                    }
                    .padding(.vertical, 4)
                }
                if current.pendingRequestCount > current.joinRequests.count {
                    Text(String(localized: "More requests will appear as you review this list.", table: "GroupMembership"))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } header: {
                Text(String(localized: "Membership requests", table: "GroupMembership"))
            }
        }
        .navigationTitle(String(localized: "Membership and invitations", table: "GroupMembership"))
        .toolbar {
            if current.role == "owner" {
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save", table: "GroupMembership")) { save() }
                        .disabled(!dirty || saving || current.lifecycle == "archived")
                        .accessibilityIdentifier("group.membership.save")
                }
            }
        }
        .interactiveDismissDisabled(dirty || saving)
        .refreshable { _ = await groupStore.refreshGroup(id: group.id) }
    }

    private func save() {
        saving = true
        let allowed = memberInvitesAllowed, required = approvalRequired
        let policy = current.trustPolicy == "community" ? (required ? "request" : "open") : "invite_only"
        Task { @MainActor in
            let updated = await groupStore.updateMembershipPolicy(group: current, joinPolicy: policy, approvalRequired: required, memberInvitesAllowed: allowed)
            if updated != nil {
                savedMemberInvitesAllowed = allowed
                savedApprovalRequired = required
            }
            await analyticsManager?.track(.init(.groupMembershipPolicyChanged, properties: [.sourceType: .string(policy), .selectionType: .string(required ? "approval_required" : "direct"), .changeType: .string(allowed ? "member_invites_on" : "member_invites_off"), .result: .string(updated == nil ? "failure" : "success")]))
            saving = false
        }
    }

    private func review(_ request: GroupJoinRequestDTO, approve: Bool) {
        guard reviewing.insert(request.id).inserted else { return }
        Task { @MainActor in
            let updated = await groupStore.reviewMembership(group: current, requestID: request.id, approve: approve)
            await analyticsManager?.track(.init(.groupMembershipRequestReviewed, properties: [.sourceType: .string(approve ? "approve" : "deny"), .result: .string(updated == nil ? "failure" : "success")]))
            reviewing.remove(request.id)
        }
    }
}
