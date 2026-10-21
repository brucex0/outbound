import CryptoKit
import Foundation

@MainActor
final class LiveCoachPreparationStore {
    static let shared = LiveCoachPreparationStore()
    var eventHandler: ((String, String) -> Void)?
    private var requestKey: String?
    private var selectedKey: String?
    private var prepared: LiveCoachPreparationDTO?
    private var preparationTask: Task<Void, Never>?
    private var generations: [String: Task<LiveCoachPreparationDTO?, Never>] = [:]

    private static func boundedStatus(_ value: String?) -> String {
        guard let value, ["pending", "generating", "ready", "fallback"].contains(value) else { return "failure" }
        return value
    }

    static func key(for request: CreateLiveCoachSessionRequest) -> String? {
        guard let userID = AuthStore.currentUserId else { return nil }
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            var object = try JSONSerialization.jsonObject(with: encoder.encode(request)) as? [String: Any] ?? [:]
            object.removeValue(forKey: "clientSessionId")
            object.removeValue(forKey: "preparationId")
            object["account"] = userID
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        } catch {
            ActivityDiagnosticLog.error(.lifecycle, "Coach preparation key failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            return nil
        }
    }

    func preparationID(for request: CreateLiveCoachSessionRequest) -> String? {
        guard requestKey == Self.key(for: request), let prepared, prepared.expiresAt > Date() else { return nil }
        return prepared.preparationId
    }

    func prepare(_ request: CreateLiveCoachSessionRequest, contextVersion: String) {
        guard let baseKey = Self.key(for: request) else { return }
        let key = baseKey + contextVersion
        if key == selectedKey, preparationTask != nil || prepared.map({ $0.expiresAt > Date() }) == true { return }
        preparationTask?.cancel()
        prepared = nil
        selectedKey = key
        requestKey = baseKey
        preparationTask = Task { [weak self] in
            defer { if self?.selectedKey == key { self?.preparationTask = nil } }
            do {
                try await Task.sleep(for: .milliseconds(400))
                let response = try await APIClient.shared.prepareLiveCoach(request)
                try Task.checkCancellation()
                guard self?.selectedKey == key, Self.key(for: request) == baseKey else { return }
                self?.prepared = response
                self?.eventHandler?("selection", Self.boundedStatus(response.status))
                if let result = await self?.generate(id: response.preparationId), self?.selectedKey == key {
                    self?.prepared = result
                }
            } catch is CancellationError {
                // Changing selection cancels the obsolete preparation request.
            } catch {
                if Task.isCancelled { return }
                if let apiError = error as? APIError, case let .http(_, _, code) = apiError, code == "not_eligible" {
                    // Safety/access may change after selection; fixed guidance is expected.
                    self?.eventHandler?("selection", "fallback")
                    return
                }
                ActivityDiagnosticLog.error(.lifecycle, "Coach preparation failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            }
        }
    }

    func generate(id: String) async -> LiveCoachPreparationDTO? {
        if let task = generations[id] { return await task.value }
        let task = Task<LiveCoachPreparationDTO?, Never> {
            do { return try await APIClient.shared.generateLiveCoachPreparation(id: id) }
            catch is CancellationError { return nil }
            catch {
                if Task.isCancelled { return nil }
                if let apiError = error as? APIError, case let .http(_, _, code) = apiError, code == "not_eligible" {
                    // Expired or newly ineligible preparations retain fixed guidance.
                    return nil
                }
                ActivityDiagnosticLog.error(.lifecycle, "Coach preparation generation failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                return nil
            }
        }
        generations[id] = task
        let result = await task.value
        eventHandler?("generation", Self.boundedStatus(result?.status))
        generations[id] = nil
        return result
    }
}
