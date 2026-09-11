import RevenueCat
import RevenueCatUI
import SwiftUI

struct PlusView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var subscriptionStore: RevenueCatSubscriptionStore
    @State private var status: RewardsStatusDTO?
    @State private var isWorking = false
    @State private var message: String?
    @State private var showPaywall = false
    @State private var showCustomerCenter = false

    let entrySource: String

    init(entrySource: String = "settings") {
        self.entrySource = entrySource
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 10) {
                    Image(systemName: "figure.run.circle.fill")
                        .font(.system(size: 52))
                        .foregroundStyle(.orange)
                    Text(text("rewards.plus"))
                        .font(.title2.bold())
                    Text(text("rewards.plus_tagline"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section {
                capability("ai_planning_dynamic", title: text("rewards.ai_planning"), detail: text("rewards.ai_planning_detail"))
                capability("live_coach_dynamic", title: text("rewards.live_coach"), detail: text("rewards.live_coach_detail"))
                capability("live_cheer_voice", title: text("rewards.voice_cheers"), detail: text("rewards.voice_cheers_detail"))
            } footer: {
                Text(text("rewards.free_fallback"))
            }

            Section {
                if subscriptionStore.isReady {
                    Button {
                        if subscriptionStore.hasProEntitlement {
                            showCustomerCenter = true
                            track(.subscriptionCustomerCenterOpened)
                        } else {
                            showPaywall = true
                            track(.subscriptionPaywallOpened)
                        }
                    } label: {
                        Text(text(subscriptionStore.hasProEntitlement
                            ? "rewards.manage_subscription"
                            : "rewards.view_subscription"))
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(isWorking)
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                }
            } footer: {
                Text(text(subscriptionStore.hasProEntitlement
                    ? "rewards.plus_active_detail"
                    : "rewards.plus_options_detail"))
            }
        }
        .navigationTitle(text("rewards.plus"))
        .task { await refresh() }
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
        .sheet(isPresented: $showPaywall) {
            PaywallView(displayCloseButton: true)
                .onPurchaseCompleted { customerInfo in
                    subscriptionStore.adopt(customerInfo)
                    showPaywall = false
                    Task { await reconcileSubscription(source: "purchase") }
                }
                .onRestoreCompleted { customerInfo in
                    subscriptionStore.adopt(customerInfo)
                    showPaywall = false
                    Task { await reconcileSubscription(source: "restore") }
                }
        }
        .sheet(isPresented: $showCustomerCenter, onDismiss: {
            Task { await reconcileSubscription(source: "customer_center") }
        }) {
            CustomerCenterView()
        }
    }

    private func capability(_ id: String, title: String, detail: String) -> some View {
        let entitlement = status?.entitlements.first { $0.capability == id }
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: entitlement?.allowed == true ? "checkmark.circle.fill" : "sparkles")
                .foregroundStyle(entitlement?.allowed == true ? .green : .orange)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() async {
        status = try? await APIClient.shared.fetchRewardsStatus()
        await subscriptionStore.refreshCustomerInfo()
    }

    private func reconcileSubscription(source: String) async {
        isWorking = true
        defer { isWorking = false }
        do {
            _ = try await APIClient.shared.reconcileSubscription()
            await subscriptionStore.refreshCustomerInfo()
            await analyticsManager?.track(.init(.subscriptionReconciled, properties: [
                .sourceType: .string(source),
                .result: .string("success")
            ]))
            show(text("rewards.subscription_synced"))
            await refresh()
        } catch {
            await analyticsManager?.track(.init(.subscriptionReconciled, properties: [
                .sourceType: .string(source),
                .result: .string("failure")
            ]))
            show(text("rewards.subscription_sync_failed"))
        }
    }

    private func track(_ event: ProductEventName) {
        Task {
            await analyticsManager?.track(.init(event, properties: [
                .entrySource: .string(entrySource)
            ]))
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
