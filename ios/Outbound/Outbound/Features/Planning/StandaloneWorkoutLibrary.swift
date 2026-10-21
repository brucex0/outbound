import Combine
import SwiftUI

struct StandaloneWorkout: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let subtitle: String
    let durationLabel: String
    let systemImage: String
    let sport: SportType
    let detail: String
    let guideLine: String
    let startLabel: String
    let targetDistanceMeters: Double?
    let targetDurationSeconds: Int?
    let steps: [SessionIntentStep]
    let coachingTarget: SessionCoachingTarget?
    let guideInstructions: GuideInstructions
    var catalogVersion: Int?

    struct GuideInstructions: Hashable, Codable {
        let objective: String
        let beforeStart: [String]
        let segments: [SessionWorkoutCue]
        let finish: [String]
        let stopConditions: [String]
    }

    var intent: SessionIntent {
        SessionIntent(
            id: id, sport: sport, title: title, detail: detail,
            guideLine: guideLine, startLabel: startLabel,
            targetDistanceMeters: targetDistanceMeters,
            targetDurationSeconds: targetDurationSeconds,
            allowsCalorieGoal: sport == .run
                && (coachingTarget.map { [SessionCoachingPhase.easy, .recovery].contains($0.phase) } ?? false),
            workoutSteps: steps,
            coachingTarget: coachingTarget,
            workoutReference: SessionWorkoutReference(
                source: "standalone_catalog",
                id: id,
                version: catalogVersion
            ),
            workoutCues: guideInstructions.segments
        )
    }

    // Only catalog-authored prose is localized. IDs, triggers, targets and versions
    // remain untouched, and the persisted response stays in its original language.
    func withCatalogVersion(_ version: Int) -> StandaloneWorkout {
        func text(_ value: String) -> String {
            NSLocalizedString(value, tableName: "CuratedWorkouts", bundle: .main, value: value, comment: "Curated workout copy")
        }
        return StandaloneWorkout(
            id: id, title: text(title), subtitle: text(subtitle),
            durationLabel: text(durationLabel), systemImage: systemImage, sport: sport,
            detail: text(detail), guideLine: text(guideLine), startLabel: text(startLabel),
            targetDistanceMeters: targetDistanceMeters, targetDurationSeconds: targetDurationSeconds,
            steps: steps.map {
                SessionIntentStep(
                    id: $0.id, label: text($0.label), durationSeconds: $0.durationSeconds,
                    detail: $0.detail.map(text), coachingTarget: $0.coachingTarget,
                    transitionInstruction: $0.transitionInstruction.map(text),
                    transitionLeadSeconds: $0.transitionLeadSeconds,
                    transitionCountdown: $0.transitionCountdown
                )
            },
            coachingTarget: coachingTarget,
            guideInstructions: GuideInstructions(
                objective: text(guideInstructions.objective),
                beforeStart: guideInstructions.beforeStart.map(text),
                segments: guideInstructions.segments.map {
                    SessionWorkoutCue(
                        id: $0.id, trigger: $0.trigger,
                        effort: .init(rpeMin: $0.effort.rpeMin, rpeMax: $0.effort.rpeMax, feel: text($0.effort.feel)),
                        instruction: text($0.instruction), cue: text($0.cue), fallback: text($0.fallback)
                    )
                },
                finish: guideInstructions.finish.map(text),
                stopConditions: guideInstructions.stopConditions.map(text)
            ),
            catalogVersion: version
        )
    }
}

struct StandaloneWorkoutCatalogResponse: Codable {
    let version: Int
    let workouts: [StandaloneWorkout]
}

@MainActor
final class StandaloneWorkoutStore: ObservableObject {
    @Published private(set) var workouts: [StandaloneWorkout] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let api: APIClient
    private let defaults: UserDefaults
    private let cacheKey = "standalone_workout_catalog_v1"

    init(api: APIClient? = nil, defaults: UserDefaults = .standard) {
        self.api = api ?? .shared
        self.defaults = defaults
        if let data = defaults.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(StandaloneWorkoutCatalogResponse.self, from: data) {
            workouts = cached.workouts.map { $0.withCatalogVersion(cached.version) }
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.fetchStandaloneWorkouts()
            workouts = response.workouts.map { $0.withCatalogVersion(response.version) }
            if let data = try? JSONEncoder().encode(response) {
                defaults.set(data, forKey: cacheKey)
            }
        } catch {
            if workouts.isEmpty {
                errorMessage = String(localized: "Workouts couldn’t be loaded. Check your connection and try again.")
            }
        }
    }
}

struct StandaloneWorkoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.outboundTheme) private var theme
    @StateObject private var store = StandaloneWorkoutStore()
    let sport: SportType
    let onSelect: (StandaloneWorkout) -> Void

    private var workouts: [StandaloneWorkout] {
        store.workouts.filter { $0.sport == sport }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    Label(sport.displayName, systemImage: sport.systemImage)
                        .font(.headline)
                        .foregroundStyle(theme.accentColor)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Pick one workout and go. No training plan required.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if store.workouts.isEmpty, store.isLoading {
                        ProgressView("Loading workouts…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, OutboundSpacing.section)
                    } else if let errorMessage = store.errorMessage, store.workouts.isEmpty {
                        ContentUnavailableView {
                            Label("Workouts unavailable", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try Again") { Task { await store.refresh() } }
                        }
                    } else if workouts.isEmpty {
                        ContentUnavailableView {
                            Label("No curated workouts", systemImage: "sparkles.rectangle.stack")
                        } description: {
                            Text("Try another activity type.")
                        }
                    } else {
                        ForEach(workouts) { workout in
                            workoutButton(workout)
                        }
                    }
                }
                .padding(.horizontal, OutboundSpacing.screen)
                .padding(.vertical, OutboundSpacing.standard)
            }
            .background(OutboundPalette.background)
            .navigationTitle(String(localized: "library.workouts", defaultValue: "Workouts"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await store.refresh() }
    }

    private func workoutButton(_ workout: StandaloneWorkout) -> some View {
        Button {
            onSelect(workout)
        } label: {
            OutboundCard {
                HStack(spacing: OutboundSpacing.standard) {
                    Image(systemName: workout.systemImage)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(theme.accentColor)
                        .frame(width: 42, height: 42)
                        .background(theme.accentColor.opacity(0.12), in: Circle())
                    VStack(alignment: .leading, spacing: 4) {
                        Text(workout.title).font(.headline).foregroundStyle(.primary)
                        Text(workout.durationLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accentColor)
                        Text(workout.subtitle)
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.bold)).foregroundStyle(.tertiary)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens this workout setup")
    }
}
