import Combine
import OSLog
import RevenueCat

@MainActor
final class RevenueCatSubscriptionStore: NSObject, ObservableObject, PurchasesDelegate {
    static let shared = RevenueCatSubscriptionStore()
    static let proEntitlementID = "plainstride_pro"

    @Published private(set) var isReady = false
    @Published private(set) var customerInfo: CustomerInfo?

    var hasProEntitlement: Bool {
        customerInfo?.entitlements[Self.proEntitlementID]?.isActive == true
    }

    private let logger = Logger(subsystem: "plainstride.outbound", category: "RevenueCat")
    private var configuredUserID: String?

    func activate(userID: String?) {
        guard let userID, !userID.isEmpty, let apiKey else {
            isReady = false
            customerInfo = nil
            return
        }

        if !Purchases.isConfigured {
            #if DEBUG
            Purchases.logLevel = .debug
            #endif
            Purchases.configure(withAPIKey: apiKey, appUserID: userID)
            Purchases.shared.delegate = self
            configuredUserID = userID
            isReady = true
            Task { await refreshCustomerInfo() }
            return
        }

        guard configuredUserID != userID else {
            isReady = true
            Task { await refreshCustomerInfo() }
            return
        }

        isReady = false
        customerInfo = nil
        Purchases.shared.logIn(userID) { [weak self] customerInfo, _, error in
            Task { @MainActor in
                guard let self else { return }
                if let error {
                    self.logger.warning("RevenueCat identity switch failed: \(String(describing: type(of: error)), privacy: .public)")
                    return
                }
                self.configuredUserID = userID
                self.customerInfo = customerInfo
                self.isReady = true
            }
        }
    }

    func refreshCustomerInfo() async {
        guard isReady else { return }
        do {
            customerInfo = try await Purchases.shared.customerInfo()
        } catch {
            logger.warning("RevenueCat customer info refresh failed: \(String(describing: type(of: error)), privacy: .public)")
        }
    }

    func adopt(_ customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
    }

    nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor [weak self] in
            self?.customerInfo = customerInfo
        }
    }

    private var apiKey: String? {
        let value = (Bundle.main.object(forInfoDictionaryKey: "RevenueCatPublicSDKKey") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}
