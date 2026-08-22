import SwiftUI

struct StandaloneWorkout: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let durationLabel: String
    let systemImage: String
    let intent: SessionIntent
}

enum StandaloneWorkoutLibrary {
    static var workouts: [StandaloneWorkout] {
        [guided5K, guided10K, speedRun]
    }

    private static var guided5K: StandaloneWorkout {
        StandaloneWorkout(
            id: "standalone-guided-5k",
            title: String(localized: "Guided 5K"),
            subtitle: String(localized: "A steady 5K with distance cues and calm guidance."),
            durationLabel: String(localized: "5 km · Steady"),
            systemImage: "5.circle.fill",
            intent: SessionIntent(
                id: "standalone-guided-5k",
                sport: .run,
                title: String(localized: "Guided 5K"),
                detail: String(localized: "Run · 5 km · steady effort"),
                guideLine: String(localized: "Settle in early, stay smooth through the middle, and finish with control."),
                startLabel: String(localized: "Start Guided 5K"),
                targetDistanceMeters: 5_000
            )
        )
    }

    private static var guided10K: StandaloneWorkout {
        StandaloneWorkout(
            id: "standalone-guided-10k",
            title: String(localized: "Guided 10K"),
            subtitle: String(localized: "Patient pacing and progress cues across 10K."),
            durationLabel: String(localized: "10 km · Endurance"),
            systemImage: "10.circle.fill",
            intent: SessionIntent(
                id: "standalone-guided-10k",
                sport: .run,
                title: String(localized: "Guided 10K"),
                detail: String(localized: "Run · 10 km · aerobic effort"),
                guideLine: String(localized: "Keep the first half patient and let your rhythm carry you home."),
                startLabel: String(localized: "Start Guided 10K"),
                targetDistanceMeters: 10_000
            )
        )
    }

    private static var speedRun: StandaloneWorkout {
        let steps = [
            SessionIntentStep(
                id: "standalone-speed-warmup",
                label: String(localized: "Easy warmup"),
                durationSeconds: 8 * 60,
                detail: String(localized: "Relaxed conversational running")
            ),
            SessionIntentStep(
                id: "standalone-speed-fast-1",
                label: String(localized: "Fast repeat 1"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Quick and controlled")
            ),
            SessionIntentStep(
                id: "standalone-speed-recover-1",
                label: String(localized: "Easy recovery 1"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Jog or walk until settled")
            ),
            SessionIntentStep(
                id: "standalone-speed-fast-2",
                label: String(localized: "Fast repeat 2"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Match the first repeat")
            ),
            SessionIntentStep(
                id: "standalone-speed-recover-2",
                label: String(localized: "Easy recovery 2"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Let your breathing come down")
            ),
            SessionIntentStep(
                id: "standalone-speed-fast-3",
                label: String(localized: "Fast repeat 3"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Stay tall and relaxed")
            ),
            SessionIntentStep(
                id: "standalone-speed-recover-3",
                label: String(localized: "Easy recovery 3"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Easy jog")
            ),
            SessionIntentStep(
                id: "standalone-speed-fast-4",
                label: String(localized: "Fast repeat 4"),
                durationSeconds: 2 * 60,
                detail: String(localized: "Finish fast, not strained")
            ),
            SessionIntentStep(
                id: "standalone-speed-cooldown",
                label: String(localized: "Cooldown"),
                durationSeconds: 8 * 60,
                detail: String(localized: "Easy running or walking")
            )
        ]

        return StandaloneWorkout(
            id: "standalone-speed-run",
            title: String(localized: "Speed Run"),
            subtitle: String(localized: "Four controlled fast repeats with full guidance."),
            durationLabel: String(localized: "30 min · Intervals"),
            systemImage: "hare.fill",
            intent: SessionIntent(
                id: "standalone-speed-run",
                sport: .run,
                title: String(localized: "Speed Run"),
                detail: String(localized: "Run · 30 min · 4 fast repeats"),
                guideLine: String(localized: "Run each fast repeat with control and use every recovery."),
                startLabel: String(localized: "Start Speed Run"),
                targetDurationSeconds: 30 * 60,
                workoutSteps: steps
            )
        )
    }
}

struct StandaloneWorkoutPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.outboundTheme) private var theme
    let onSelect: (StandaloneWorkout) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: OutboundSpacing.standard) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Pick one workout and go. No training plan required.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ForEach(StandaloneWorkoutLibrary.workouts) { workout in
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
                                        Text(workout.title)
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                        Text(workout.durationLabel)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(theme.accentColor)
                                        Text(workout.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.leading)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "chevron.right")
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Opens this workout setup")
                    }
                }
                .padding(.horizontal, OutboundSpacing.screen)
                .padding(.vertical, OutboundSpacing.standard)
            }
            .background(OutboundPalette.background)
            .navigationTitle("Workouts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}
