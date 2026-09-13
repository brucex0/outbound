import SwiftUI

struct RewardsCenterView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var status: RewardsStatusDTO?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let status {
                    if rewardEntitlements(in: status).isEmpty && status.bankedRewardDays == 0 {
                        Text(text("rewards.no_active_rewards"))
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(rewardEntitlements(in: status)) { entitlement in
                            rewardRow(entitlement)
                        }
                        if status.bankedRewardDays > 0 {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar.badge.clock")
                                    .foregroundStyle(.orange)
                                    .frame(width: 24)
                                Text(String.localizedStringWithFormat(
                                    text("rewards.banked_days_format"),
                                    status.bankedRewardDays
                                ))
                            }
                        }
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } header: {
                Text(text("rewards.current_rewards"))
            } footer: {
                Text(text("rewards.current_rewards_detail"))
            }

            Section {
                NavigationLink {
                    RewardRedemptionView()
                } label: {
                    Label(text("rewards.redeem"), systemImage: "ticket")
                }
            } footer: {
                Text(text("rewards.redeem_detail"))
            }
        }
        .navigationTitle(text("rewards.title"))
        .task {
            await analyticsManager?.track(.init(.rewardsCenterOpened))
            await refresh()
        }
        .overlay(alignment: .bottom) {
            if let message {
                ToastMessage(message: message)
            }
        }
    }

    private func rewardEntitlements(in status: RewardsStatusDTO) -> [CapabilityEntitlementDTO] {
        status.entitlements.filter { entitlement in
            entitlement.allowed && entitlement.sources.contains { $0 != "revenuecat" }
        }
    }

    private func rewardRow(_ entitlement: CapabilityEntitlementDTO) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(capabilityTitle(entitlement.capability))
                Text(capabilityDetail(entitlement.capability))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func capabilityTitle(_ capability: String) -> String {
        switch capability {
        case "ai_planning_dynamic": text("rewards.ai_planning")
        case "live_coach_dynamic": text("rewards.live_coach")
        case "live_cheer_voice": text("rewards.voice_cheers")
        default: text("rewards.plus")
        }
    }

    private func capabilityDetail(_ capability: String) -> String {
        switch capability {
        case "ai_planning_dynamic": text("rewards.ai_planning_detail")
        case "live_coach_dynamic": text("rewards.live_coach_detail")
        case "live_cheer_voice": text("rewards.voice_cheers_detail")
        default: text("rewards.current_rewards_detail")
        }
    }

    private func refresh() async {
        do { status = try await APIClient.shared.fetchRewardsStatus() }
        catch { show(text("rewards.load_failed")) }
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

struct InvitationCodeView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var status: RewardsStatusDTO?
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                if let status {
                    let referral = status.referral
                    LabeledContent(text("rewards.your_code"), value: referral.code)
                        .textSelection(.enabled)
                    Button {
                        share(referral)
                    } label: {
                        Label(text("rewards.share_invitation"), systemImage: "square.and.arrow.up")
                    }
                    LabeledContent(
                        status.referralProgram.foundingMember
                            ? text("rewards.activated_runners")
                            : text("rewards.qualified_invites"),
                        value: "\(referral.qualifiedCount)"
                    )
                    if referral.pendingCount > 0 {
                        LabeledContent(text("rewards.pending_invites"), value: "\(referral.pendingCount)")
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                if let status {
                    Text(invitationDetail(status.referralProgram))
                }
            }
        }
        .navigationTitle(text("rewards.my_invitation_code"))
        .task { await refresh() }
        .overlay(alignment: .bottom) {
            if let message {
                ToastMessage(message: message)
            }
        }
    }

    private func share(_ referral: RewardsReferralDTO) {
        guard let program = status?.referralProgram else { return }
        let invitation = "\(shareMessage(program))\n\n\(referral.shareURL.absoluteString)"
        Task {
            await SystemSharePresenter.present(activityItems: [invitation])
            await analyticsManager?.track(.init(.referralCodeShared, properties: [
                .sourceType: .string("me_invitation_code"),
                .selectionType: .string(program.foundingMember ? "founding" : "reward_eligible")
            ]))
        }
    }

    private func invitationDetail(_ program: ReferralProgramDTO) -> String {
        let qualifyingMinutes = program.qualifyingActivitySeconds / 60
        if program.inviterRewardEligible {
            return String.localizedStringWithFormat(
                text("rewards.invite_detail_format"),
                program.inviteeRewardDays,
                program.inviterRewardDays,
                qualifyingMinutes
            )
        }
        return String.localizedStringWithFormat(
            text("rewards.invite_detail_founding_format"),
            program.inviteeRewardDays,
            program.claimWindowDays
        )
    }

    private func shareMessage(_ program: ReferralProgramDTO) -> String {
        let key: String.LocalizationValue = program.inviterRewardEligible
            ? "rewards.share_message_format"
            : "rewards.share_message_founding_format"
        return String.localizedStringWithFormat(text(key), program.inviteeRewardDays)
    }

    private func refresh() async {
        do { status = try await APIClient.shared.fetchRewardsStatus() }
        catch { show(text("rewards.load_failed")) }
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

private struct RewardRedemptionView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var status: RewardsStatusDTO?
    @State private var invitationCode = ""
    @State private var entitlementCode = ""
    @State private var isWorking = false
    @State private var message: String?

    var body: some View {
        Form {
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
            } footer: {
                Text(text("rewards.redeem_detail"))
            }
        }
        .navigationTitle(text("rewards.redeem"))
        .task { await refresh() }
        .overlay(alignment: .bottom) {
            if let message {
                ToastMessage(message: message)
            }
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

private struct ToastMessage: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, 12)
            .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
