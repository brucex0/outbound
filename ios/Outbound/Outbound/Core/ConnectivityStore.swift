import Combine
import Network
import SwiftUI

@MainActor
final class ConnectivityStore: ObservableObject {
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.plainstride.connectivity")

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OutboundDebugActivityRepository") { return }
        #endif
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor [weak self, isOffline] in
                self?.isOffline = isOffline
            }
        }
        monitor.start(queue: queue)
    }

    #if DEBUG
    func setRepositoryFixtureOffline(_ offline: Bool) {
        guard ProcessInfo.processInfo.arguments.contains("-OutboundDebugActivityRepository") else { return }
        isOffline = offline
    }
    #endif

    deinit {
        monitor.cancel()
    }
}

struct GlobalConnectivityBanner: View {
    @EnvironmentObject private var connectivityStore: ConnectivityStore
    @EnvironmentObject private var activityStore: ActivityStore

    var body: some View {
        if let presentation {
            HStack(spacing: OutboundSpacing.compact) {
                Label(presentation.message, systemImage: presentation.systemImage)
                    .accessibilityLabel(presentation.accessibilityLabel)
                if !connectivityStore.isOffline, activityStore.failedActivityCount > 0 {
                    Button { activityStore.retrySynchronization() } label: {
                        Image(systemName: "arrow.clockwise")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel(String(localized: "activity.sync.retry", defaultValue: "Retry saved activity sync"))
                }
            }
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(presentation.foreground.opacity(0.22), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .accessibilityElement(children: .contain)
        }
    }

    private var presentation: ConnectivityBannerPresentation? {
        if connectivityStore.isOffline {
            return ConnectivityBannerPresentation(
                message: String(localized: "activity.sync.offline", defaultValue: "Offline · changes saved on this device"),
                systemImage: "icloud.slash.fill",
                foreground: .orange,
                accessibilityLabel: String(localized: "activity.sync.offline.accessibility", defaultValue: "Offline. Changes are saved on this device and will sync later.")
            )
        }

        if AuthStore.currentUserId != nil, activityStore.failedActivityCount > 0 {
            return ConnectivityBannerPresentation(
                message: activityStore.repositoryProjection.blockedActivityIDs.isEmpty
                    ? String(localized: "activity.sync.pending", defaultValue: "Some items still need to sync")
                    : String(localized: "activity.sync.conflict", defaultValue: "Saved activity sync needs attention"),
                systemImage: "exclamationmark.icloud.fill",
                foreground: .orange,
                accessibilityLabel: activityStore.repositoryProjection.blockedActivityIDs.isEmpty
                    ? String(localized: "activity.sync.pending.accessibility", defaultValue: "Some saved items still need to sync. Plainstride will retry automatically.")
                    : String(localized: "activity.sync.conflict.accessibility", defaultValue: "Your activity is saved on this device. Refresh and retry its plan synchronization.")
            )
        }

        return nil
    }
}

private struct ConnectivityBannerPresentation {
    let message: String
    let systemImage: String
    let foreground: Color
    let accessibilityLabel: String
}
