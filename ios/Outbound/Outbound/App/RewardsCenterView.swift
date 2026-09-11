import SwiftUI

struct RewardsCenterView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var status: RewardsStatusDTO?
    @State private var invitationCode = ""
    @State private var entitlementCode = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Form {
            plusSection
            inviteSection
            redeemSection
        }
        .navigationTitle(text("rewards.title"))
        .task {
            await analyticsManager?.track(.init(.rewardsCenterOpened))
            await refresh()
        }
        .overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 12)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
    }

    private var plusSection: some View {
        Section {
            capability("ai_planning_dynamic", title: text("rewards.ai_planning"), detail: text("rewards.ai_planning_detail"))
            capability("live_coach_dynamic", title: text("rewards.live_coach"), detail: text("rewards.live_coach_detail"))
            capability("live_cheer_voice", title: text("rewards.voice_cheers"), detail: text("rewards.voice_cheers_detail"))
        } header: {
            Text(text("rewards.plus"))
        } footer: {
            Text(text("rewards.free_fallback"))
        }
    }

    private var inviteSection: some View {
        Section {
            if let referral = status?.referral {
                LabeledContent(text("rewards.your_code"), value: referral.code)
                    .textSelection(.enabled)
                Button {
                    let message = text("rewards.share_message")
                    let invitation = "\(message)\n\n\(referral.shareURL.absoluteString)"
                    Task {
                        await SystemSharePresenter.present(activityItems: [invitation])
                    }
                    Task {
                        await analyticsManager?.track(.init(.referralCodeShared, properties: [
                            .sourceType: .string("rewards_center")
                        ]))
                    }
                } label: {
                    Label(text("rewards.share_invitation"), systemImage: "square.and.arrow.up")
                }
                LabeledContent(text("rewards.qualified_invites"), value: "\(referral.qualifiedCount)")
                if referral.pendingCount > 0 {
                    LabeledContent(text("rewards.pending_invites"), value: "\(referral.pendingCount)")
                }
            } else {
                ProgressView()
            }
        } header: {
            Text(text("rewards.invite"))
        } footer: {
            Text(text("rewards.invite_detail"))
        }
    }

    private var redeemSection: some View {
        Section {
            if status?.referral.claimStatus == nil {
                TextField(text("rewards.invitation_placeholder"), text: $invitationCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Button(text("rewards.claim_invitation")) { Task { await redeem(invitation: true) } }
                    .disabled(isWorking || invitationCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            TextField(text("rewards.entitlement_placeholder"), text: $entitlementCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button(text("rewards.redeem_reward")) { Task { await redeem(invitation: false) } }
                .disabled(isWorking || entitlementCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } header: {
            Text(text("rewards.redeem"))
        } footer: {
            Text(text("rewards.redeem_detail"))
        }
    }

    @ViewBuilder
    private func capability(_ id: String, title: String, detail: String) -> some View {
        let entitlement = status?.entitlements.first { $0.capability == id }
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: entitlement?.allowed == true ? "checkmark.circle.fill" : "lock.circle")
                .foregroundStyle(entitlement?.allowed == true ? .green : .secondary)
        }
    }

    private func refresh() async {
        do { status = try await APIClient.shared.fetchRewardsStatus() }
        catch { show(text("rewards.load_failed")) }
    }

    private func redeem(invitation: Bool) async {
        isWorking = true
        defer { isWorking = false }
        do {
            if invitation {
                _ = try await APIClient.shared.claimInvitationCode(invitationCode)
                invitationCode = ""
            } else {
                _ = try await APIClient.shared.redeemEntitlementCode(entitlementCode)
                entitlementCode = ""
            }
            await analyticsManager?.track(.init(.rewardCodeRedeemed, properties: [
                .sourceType: .string(invitation ? "referral" : "contribution"),
                .result: .string("success")
            ]))
            show(text("rewards.redeemed"))
            await refresh()
        } catch {
            await analyticsManager?.track(.init(.rewardCodeRedeemed, properties: [
                .sourceType: .string(invitation ? "referral" : "contribution"),
                .result: .string("failure")
            ]))
            show(text("rewards.redeem_failed"))
        }
    }

    private func show(_ value: String) {
        withAnimation { message = value }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if message == value { withAnimation { message = nil } }
        }
    }

    private func text(_ key: String.LocalizationValue) -> String {
        String(localized: key, table: "Rewards")
    }
}
