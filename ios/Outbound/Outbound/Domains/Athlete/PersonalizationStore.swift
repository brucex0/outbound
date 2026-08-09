import Combine
import Foundation

@MainActor
final class PersonalizationStore: ObservableObject {
    @Published private(set) var snapshot: PersonalizationSnapshotDTO
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private let api: APIClient
    private let defaults: UserDefaults
    private let cacheKey = "personalization_snapshot_v1"
    private let readinessQueueKey = "personalization_readiness_queue_v1"
    private let feedbackQueueKey = "personalization_feedback_queue_v1"

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        snapshot = Self.decode(PersonalizationSnapshotDTO.self, from: defaults.data(forKey: cacheKey)) ?? .preview
    }

    func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            snapshot = try await api.fetchPersonalizationSnapshot()
            persistSnapshot()
            lastError = nil
            await flushPending()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func completeProfile(_ request: RunnerProfileRequestDTO) async {
        do {
            let response = try await api.updateRunnerProfile(request)
            apply(response)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func submitReadiness(_ choice: ReadinessChoice, workoutID: String, note: String? = nil) async {
        let request = ReadinessCheckInRequestDTO(
            idempotencyKey: UUID().uuidString,
            workoutId: workoutID,
            recordedAt: Date(),
            choice: choice,
            note: note
        )
        do {
            apply(try await api.submitPersonalizationReadiness(request))
        } catch {
            enqueue(request, key: readinessQueueKey)
            lastError = "Saved offline. Outbound will sync this check-in later."
        }
    }

    func submitFeedback(
        effort: RunEffort,
        continuationCapacity: ContinuationCapacity?,
        workoutID: String,
        activityID: String?
    ) async {
        let request = WorkoutFeedbackRequestDTO(
            idempotencyKey: UUID().uuidString,
            workoutId: workoutID,
            activityId: activityID,
            recordedAt: Date(),
            effort: effort,
            continuationCapacity: continuationCapacity,
            note: nil
        )
        do {
            apply(try await api.submitWorkoutFeedback(request))
        } catch {
            enqueue(request, key: feedbackQueueKey)
            lastError = "Saved offline. Outbound will learn from this run after syncing."
        }
    }

    func decideAdjustment(accept: Bool) async {
        guard let adjustment = snapshot.pendingAdjustment else { return }
        do {
            _ = try await api.decidePersonalizationAdjustment(id: adjustment.id, accept: accept)
            snapshot = PersonalizationSnapshotDTO(
                contractVersion: snapshot.contractVersion,
                modelVersion: snapshot.modelVersion,
                generatedAt: Date(),
                calibration: snapshot.calibration,
                calibrationWorkouts: snapshot.calibrationWorkouts,
                insights: snapshot.insights,
                pendingAdjustment: nil
            )
            persistSnapshot()
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func flushPending() async {
        var readiness = queued(ReadinessCheckInRequestDTO.self, key: readinessQueueKey)
        while let request = readiness.first {
            do {
                apply(try await api.submitPersonalizationReadiness(request))
                readiness.removeFirst()
                persistQueue(readiness, key: readinessQueueKey)
            } catch { break }
        }

        var feedback = queued(WorkoutFeedbackRequestDTO.self, key: feedbackQueueKey)
        while let request = feedback.first {
            do {
                apply(try await api.submitWorkoutFeedback(request))
                feedback.removeFirst()
                persistQueue(feedback, key: feedbackQueueKey)
            } catch { break }
        }
    }

    private func apply(_ response: PersonalizationMutationResponseDTO) {
        snapshot = response.personalization
        if let adjustment = response.adjustment {
            snapshot = PersonalizationSnapshotDTO(
                contractVersion: snapshot.contractVersion,
                modelVersion: snapshot.modelVersion,
                generatedAt: snapshot.generatedAt,
                calibration: snapshot.calibration,
                calibrationWorkouts: snapshot.calibrationWorkouts,
                insights: snapshot.insights,
                pendingAdjustment: adjustment
            )
        }
        persistSnapshot()
        lastError = nil
    }

    private func enqueue<T: Codable>(_ value: T, key: String) {
        var values = queued(T.self, key: key)
        values.append(value)
        persistQueue(values, key: key)
    }

    private func queued<T: Codable>(_ type: T.Type, key: String) -> [T] {
        Self.decode([T].self, from: defaults.data(forKey: key)) ?? []
    }

    private func persistQueue<T: Codable>(_ values: [T], key: String) {
        defaults.set(try? Self.encoder.encode(values), forKey: key)
    }

    private func persistSnapshot() {
        defaults.set(try? Self.encoder.encode(snapshot), forKey: cacheKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
