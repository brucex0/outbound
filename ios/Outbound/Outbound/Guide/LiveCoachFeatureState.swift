import Combine
import Foundation

@MainActor
final class LiveCoachFeatureState: ObservableObject {
    static let shared = LiveCoachFeatureState()

    @Published private(set) var configuration: LiveCoachConfigDTO?
    @Published private(set) var catalog: LiveCoachCatalogDTO?
    @Published private(set) var isRefreshing = false

    private init() {}

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let configRequest = try? APIClient.shared.fetchLiveCoachConfig()
        async let catalogRequest = try? APIClient.shared.fetchLiveCoachCatalog(locale: AppLanguage.currentIdentifier)
        if let config = await configRequest, config.contractVersion == 1 {
            configuration = config
        }
        if let catalog = await catalogRequest, catalog.contractVersion == 1 {
            self.catalog = catalog
            if let audioPack = catalog.audioPack {
                await GuideAudioPackStore.shared.refresh(
                    from: audioPack.manifestUrl,
                    expectedCatalogVersion: audioPack.manifestVersion
                )
            }
        }
    }
}
