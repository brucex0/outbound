import Combine
import Network
import SwiftUI

@MainActor
final class ConnectivityStore: ObservableObject {
    @Published private(set) var isOffline = false
    @Published private(set) var recentlyReconnected = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.plainstride.connectivity")
    private var hasReceivedInitialPath = false
    private var reconnectTask: Task<Void, Never>?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor [weak self, isOffline] in
                guard let self else { return }
                let wasOffline = self.isOffline
                self.isOffline = isOffline
                if self.hasReceivedInitialPath, wasOffline, !isOffline {
                    self.recentlyReconnected = true
                    self.reconnectTask?.cancel()
                    self.reconnectTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(for: .seconds(4))
                        guard !Task.isCancelled else { return }
                        self?.recentlyReconnected = false
                    }
                }
                self.hasReceivedInitialPath = true
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
        reconnectTask?.cancel()
        monitor.cancel()
    }
}

struct GlobalConnectivityBanner: View {
    @EnvironmentObject private var connectivityStore: ConnectivityStore
    @EnvironmentObject private var activityStore: ActivityStore

    var body: some View {
        if let presentation {
            Label(presentation.message, systemImage: presentation.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(presentation.foreground)
                .padding(.horizontal, 14)
                .frame(minHeight: 36)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay {
                    Capsule().strokeBorder(presentation.foreground.opacity(0.22), lineWidth: 0.8)
                }
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel(presentation.accessibilityLabel)
        }
    }

    private var presentation: ConnectivityBannerPresentation? {
        if connectivityStore.isOffline {
            return ConnectivityBannerPresentation(
                message: "Offline · changes saved on this device",
                systemImage: "icloud.slash.fill",
                foreground: .orange,
                accessibilityLabel: "Offline. Changes are saved on this device and will sync later."
            )
        }

        if activityStore.isSyncing {
            let count = activityStore.pendingActivityCount
            return ConnectivityBannerPresentation(
                message: count == 0 ? "Back online · checking sync" : "Back online · syncing \(count) item\(count == 1 ? "" : "s")",
                systemImage: "arrow.triangle.2.circlepath.icloud.fill",
                foreground: .blue,
                accessibilityLabel: "Back online. Syncing saved changes."
            )
        }

        if AuthStore.currentUserId != nil, activityStore.failedActivityCount > 0 {
            return ConnectivityBannerPresentation(
                message: "Some items still need to sync",
                systemImage: "exclamationmark.icloud.fill",
                foreground: .orange,
                accessibilityLabel: "Some saved items still need to sync. Plainstride will retry automatically."
            )
        }

        if connectivityStore.recentlyReconnected {
            return ConnectivityBannerPresentation(
                message: "Back online · synced",
                systemImage: "checkmark.icloud.fill",
                foreground: .green,
                accessibilityLabel: "Back online. Saved changes are synced."
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
