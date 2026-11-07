import SwiftUI

struct GroupMembershipSettingsView: View {
    @EnvironmentObject private var groupStore: GroupStore
    @Environment(\.analyticsManager) private var analyticsManager
    let group: GroupDTO
    @State private var joinPolicy: String
    @State private var approvalRequired: Bool
    @State private var savedJoinPolicy: String
    @State private var savedApprovalRequired: Bool
    @State private var saving = false
    @State private var reviewing: Set<String> = []

    init(group: GroupDTO) {
        self.group = group
        _joinPolicy = State(initialValue: group.joinPolicy)
        _approvalRequired = State(initialValue: group.memberInviteApprovalRequired)
        _savedJoinPolicy = State(initialValue: group.joinPolicy)
        _savedApprovalRequired = State(initialValue: group.memberInviteApprovalRequired)
    }

    private var current: GroupDTO { groupStore.groups.first(where: { $0.id == group.id }) ?? group }
    private var dirty: Bool { joinPolicy != savedJoinPolicy || approvalRequired != savedApprovalRequired }

    var body: some View {
        Form {
            if current.role == "owner" {
                Section {
                    if current.trustPolicy == "community" {
                        Picker(String(localized: "Who can join", table: "GroupMembership"), selection: $joinPolicy) {
                            Text(String(localized: "Anyone can join", table: "GroupMembership")).tag("open")
                            Text(String(localized: "Approval required", table: "GroupMembership")).tag("request")
                            Text(String(localized: "Invitation only", table: "GroupMembership")).tag("invite_only")
                        }
                        .accessibilityIdentifier("group.membership.join_policy")
                    }
                    Toggle(String(localized: "Approve member invitations", table: "GroupMembership"), isOn: $approvalRequired)
                        .accessibilityIdentifier("group.membership.approval_required")
                    Text(String(localized: "Members can invite their connections. When approval is required, invitees must accept before an owner or admin reviews their membership. Invitations from owners and admins are pre-approved.", table: "GroupMembership"))
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
        let policy = joinPolicy, required = approvalRequired
        Task { @MainActor in
            let updated = await groupStore.updateMembershipPolicy(group: current, joinPolicy: policy, approvalRequired: required)
            if updated != nil {
                savedJoinPolicy = policy
                savedApprovalRequired = required
            }
            await analyticsManager?.track(.init(.groupMembershipPolicyChanged, properties: [.sourceType: .string(policy), .selectionType: .string(required ? "approval_required" : "direct"), .result: .string(updated == nil ? "failure" : "success")]))
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
