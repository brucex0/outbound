import Combine
import Network
import SwiftUI

@MainActor
final class ConnectivityStore: ObservableObject {
    @Published private(set) var isOffline = false

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.plainstride.connectivity")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let isOffline = path.status != .satisfied
            Task { @MainActor [weak self, isOffline] in
                self?.isOffline = isOffline
            }
        }
        monitor.start(queue: queue)
    }

    deinit {
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

        if AuthStore.currentUserId != nil, activityStore.failedActivityCount > 0 {
            return ConnectivityBannerPresentation(
                message: "Some items still need to sync",
                systemImage: "exclamationmark.icloud.fill",
                foreground: .orange,
                accessibilityLabel: "Some saved items still need to sync. Plainstride will retry automatically."
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
