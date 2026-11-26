import Combine
import CoreLocation
import Foundation

/// Foreground consumers share fixes, not ownership of a recording's GPS delivery.
@MainActor final class ForegroundLocationSource: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Policy {
        let maximumAge: TimeInterval
        let maximumAccuracy: CLLocationAccuracy
        static let planner = Policy(maximumAge: 60, maximumAccuracy: 100)
        static let activityPreview = Policy(maximumAge: 15, maximumAccuracy: 80)

        func accepts(_ fix: CLLocation, at now: Date = Date()) -> Bool {
            let age = now.timeIntervalSince(fix.timestamp)
            return CLLocationCoordinate2DIsValid(fix.coordinate)
                && fix.coordinate.latitude.isFinite && fix.coordinate.longitude.isFinite
                && fix.horizontalAccuracy.isFinite && fix.horizontalAccuracy >= 0
                && fix.horizontalAccuracy <= maximumAccuracy
                && age.isFinite && age > -5 && age < maximumAge
        }
    }
    static let shared = ForegroundLocationSource()
    @Published private(set) var latestLocation: CLLocation?
    private let manager: CLLocationManager
    private struct Request {
        let policy: Policy
        let continuation: CheckedContinuation<CLLocation, Error>
        let timeout: Task<Void, Never>
    }
    private var requests: [UUID: Request] = [:]

    init(manager: CLLocationManager = CLLocationManager()) {
        self.manager = manager
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
    }
    private var authorized: Bool {
        [.authorizedAlways, .authorizedWhenInUse].contains(manager.authorizationStatus)
    }
    func cachedLocation(policy: Policy) -> CLLocation? {
        refreshAuthorization()
        guard authorized, let latestLocation, policy.accepts(latestLocation) else { return nil }
        return latestLocation
    }
    func refreshAuthorization() {
        guard !authorized else { return }
        latestLocation = nil
        if manager.authorizationStatus != .notDetermined {
            finishAll(.failure(CLError(.denied)))
        }
    }
    /// Receives physical foreground delivery and accepted fixes from the recording wrapper.
    func publish(_ fix: CLLocation) {
        refreshAuthorization()
        guard authorized, Policy.planner.accepts(fix) else { return }
        if latestLocation.map({ fix.timestamp > $0.timestamp }) ?? true { latestLocation = fix }
        guard let latestLocation else { return }
        let satisfied = requests.compactMap { $0.value.policy.accepts(latestLocation) ? $0.key : nil }
        for id in satisfied { finish(id, .success(latestLocation)) }
    }
    func locate(id: UUID, policy: Policy, reuseCached: Bool = true) async throws -> CLLocation {
        try Task.checkCancellation()
        if reuseCached, let fix = cachedLocation(policy: policy) { return fix }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                guard !Task.isCancelled else { pending.resume(throwing: CancellationError()); return }
                let timeout = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(15)) }
                    catch { return } // Expected when this request finishes or is cancelled.
                    guard !Task.isCancelled else { return }
                    self?.finish(id, .failure(CLError(.locationUnknown)))
                }
                requests[id] = Request(policy: policy, continuation: pending, timeout: timeout)
                authorizeAndRequest()
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }
    func cancel(id: UUID) { finish(id, .failure(CancellationError())) }
    private func authorizeAndRequest() {
        guard !requests.isEmpty else { return }
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse: manager.requestLocation()
        default: refreshAuthorization()
        }
    }
    private func finish(_ id: UUID, _ result: Result<CLLocation, Error>) {
        guard let request = requests.removeValue(forKey: id) else { return }
        request.timeout.cancel()
        request.continuation.resume(with: result)
        if requests.isEmpty { manager.stopUpdatingLocation() }
    }
    private func finishAll(_ result: Result<CLLocation, Error>) {
        for id in Array(requests.keys) { finish(id, result) }
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refreshAuthorization()
        authorizeAndRequest()
    }
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // Resolve pending requests with the newest valid batch fix; late old fixes cannot move the cache backwards.
        for fix in locations.sorted(by: { $0.timestamp > $1.timestamp }) { publish(fix) }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // Preserve the planner's existing fail-fast CoreLocation error semantics.
        let code = (error as NSError).code
        ActivityDiagnosticLog.error(.lifecycle, "foreground_location_request_failed code=\(code)")
        finishAll(.failure(error))
    }
}
