import Combine
import Foundation

@MainActor
final class PersonalizationStore: ObservableObject {
    @Published private(set) var snapshot: PersonalizationSnapshotDTO = .preview
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastError: String?

    private var accountContext = ActivityAccountBoundary.current
    private let api: APIClient
    private let defaults: UserDefaults
    private var cacheKey: String { "personalization_snapshot_v1.\(accountContext.owner)" }
    private var cacheLocaleKey: String { "personalization_snapshot_locale_v1.\(accountContext.owner)" }
    private var profileQueueKey: String { "personalization_profile_queue_v1.\(accountContext.owner)" }
    private var readinessQueueKey: String { "personalization_readiness_queue_v1.\(accountContext.owner)" }
    private var feedbackQueueKey: String { "personalization_feedback_queue_v1.\(accountContext.owner)" }

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        let cacheMatchesLocale = defaults.string(forKey: cacheLocaleKey) == AppLanguage.currentIdentifier
        snapshot = cacheMatchesLocale
            ? Self.decode(PersonalizationSnapshotDTO.self, from: defaults.data(forKey: cacheKey)) ?? .preview
            : .preview
    }

    func activateAccount() {
        accountContext = ActivityAccountBoundary.current
        isRefreshing = false
        lastError = nil
        snapshot = defaults.string(forKey: cacheLocaleKey) == AppLanguage.currentIdentifier
            ? Self.decode(PersonalizationSnapshotDTO.self, from: defaults.data(forKey: cacheKey)) ?? .preview : .preview
    }

    func refresh() async {
        let context = accountContext
        return await ActivityAccountBoundary.$operation.withValue(context) {
            guard context == ActivityAccountBoundary.current else { return }
            guard !isRefreshing, accountContext == ActivityAccountBoundary.current else { return }
            isRefreshing = true
            defer { if accountContext == ActivityAccountBoundary.context { isRefreshing = false } }
            do {
                let value = try await api.fetchPersonalizationSnapshot()
                try ActivityAccountBoundary.validate()
                snapshot = value
                persistSnapshot()
                lastError = nil
                await flushPending()
            } catch is CancellationError { return }
            catch {
                guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
                ActivityDiagnosticLog.error(.sync, "Personalization refresh failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                lastError = error.localizedDescription
            }

        }
    }

    func completeProfile(_ request: RunnerProfileRequestDTO) async {
        let context = accountContext
        return await ActivityAccountBoundary.$operation.withValue(context) {
            guard context == ActivityAccountBoundary.current else { return }
            do {
                let response = try await api.updateRunnerProfile(request)
                apply(response)
                persistQueue([RunnerProfileRequestDTO](), key: profileQueueKey)
            } catch is CancellationError { return }
            catch {
                guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
                ActivityDiagnosticLog.error(.sync, "Personalization completeProfile failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                persistQueue([request], key: profileQueueKey)
                lastError = error.localizedDescription
            }

        }
    }

    func submitReadiness(_ choice: ReadinessChoice, workoutID: String, note: String? = nil) async {
        let context = accountContext
        return await ActivityAccountBoundary.$operation.withValue(context) {
            guard context == ActivityAccountBoundary.current else { return }
            let request = ReadinessCheckInRequestDTO(
                idempotencyKey: UUID().uuidString,
                workoutId: workoutID,
                recordedAt: Date(),
                choice: choice,
                note: note
            )
            do {
                apply(try await api.submitPersonalizationReadiness(request))
            } catch is CancellationError { return }
            catch {
                guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
                ActivityDiagnosticLog.error(.sync, "Personalization submitReadiness failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                enqueue(request, key: readinessQueueKey)
                lastError = "Saved offline. Plainstride will sync this check-in later."
            }

        }
    }

    func submitFeedback(
        effort: RunEffort,
        continuationCapacity: ContinuationCapacity?,
        workoutID: String,
        activityID: String?
    ) async {
        let context = accountContext
        return await ActivityAccountBoundary.$operation.withValue(context) {
            guard context == ActivityAccountBoundary.current else { return }
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
            } catch is CancellationError { return }
            catch {
                guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
                ActivityDiagnosticLog.error(.sync, "Personalization submitFeedback failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                enqueue(request, key: feedbackQueueKey)
                lastError = "Saved offline. Plainstride will learn from this run after syncing."
            }

        }
    }

    func decideAdjustment(accept: Bool) async {
        let context = accountContext
        return await ActivityAccountBoundary.$operation.withValue(context) {
            guard context == ActivityAccountBoundary.current else { return }
            guard let adjustment = snapshot.pendingAdjustment else { return }
            do {
                _ = try await api.decidePersonalizationAdjustment(id: adjustment.id, accept: accept)
                try ActivityAccountBoundary.validate()
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
            } catch is CancellationError { return }
            catch {
                guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
                ActivityDiagnosticLog.error(.sync, "Personalization decideAdjustment failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                lastError = error.localizedDescription
            }

        }
    }

    func flushPending() async {
        let context = accountContext
        return await ActivityAccountBoundary.$operation.withValue(context) {
            guard context == ActivityAccountBoundary.current else { return }
            var profiles = queued(RunnerProfileRequestDTO.self, key: profileQueueKey)
            while let request = profiles.first {
                do {
                    apply(try await api.updateRunnerProfile(request))
                    profiles.removeFirst()
                    persistQueue(profiles, key: profileQueueKey)
                } catch is CancellationError { return }
                catch {
                    ActivityDiagnosticLog.error(.sync, "Personalization queue flush failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                    break
                }
            }

            var readiness = queued(ReadinessCheckInRequestDTO.self, key: readinessQueueKey)
            while let request = readiness.first {
                do {
                    apply(try await api.submitPersonalizationReadiness(request))
                    readiness.removeFirst()
                    persistQueue(readiness, key: readinessQueueKey)
                } catch is CancellationError { return }
                catch {
                    ActivityDiagnosticLog.error(.sync, "Personalization queue flush failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                    break
                }
            }

            var feedback = queued(WorkoutFeedbackRequestDTO.self, key: feedbackQueueKey)
            while let request = feedback.first {
                do {
                    apply(try await api.submitWorkoutFeedback(request))
                    feedback.removeFirst()
                    persistQueue(feedback, key: feedbackQueueKey)
                } catch is CancellationError { return }
                catch {
                    ActivityDiagnosticLog.error(.sync, "Personalization queue flush failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                    break
                }
            }

        }
    }

    private func apply(_ response: PersonalizationMutationResponseDTO) {
        guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
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
        guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
        defaults.set(try? Self.encoder.encode(values), forKey: key)
    }

    private func persistSnapshot() {
        guard ActivityAccountBoundary.context == ActivityAccountBoundary.current else { return }
        defaults.set(try? Self.encoder.encode(snapshot), forKey: cacheKey)
        defaults.set(AppLanguage.currentIdentifier, forKey: cacheLocaleKey)
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
