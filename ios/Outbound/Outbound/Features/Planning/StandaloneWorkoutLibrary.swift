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

    var intent: SessionIntent {
        SessionIntent(
            id: id, sport: sport, title: title, detail: detail,
            guideLine: guideLine, startLabel: startLabel,
            targetDistanceMeters: targetDistanceMeters,
            targetDurationSeconds: targetDurationSeconds,
            workoutSteps: steps,
            coachingTarget: coachingTarget
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
            workouts = cached.workouts
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.fetchStandaloneWorkouts()
            workouts = response.workouts
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
    let onSelect: (StandaloneWorkout) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
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
                    } else {
                        ForEach(store.workouts) { workout in
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
