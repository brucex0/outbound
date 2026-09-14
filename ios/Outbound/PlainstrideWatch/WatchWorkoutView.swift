import SwiftUI

struct WatchWorkoutView: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @State private var selectedActivity: PlainstrideWorkoutActivity = .running
    @State private var isIndoor = false

    var body: some View {
        Group {
            if workout.isWorkoutInProgress || workout.lifecycle == .finished || workout.lifecycle == .failed {
                workoutSurface
            } else {
                activityPicker
            }
        }
    }

    private var activityPicker: some View {
        ScrollView {
            VStack(spacing: 10) {
                Picker(String(localized: "watch.activity", defaultValue: "Activity"), selection: $selectedActivity) {
                    ForEach(PlainstrideWorkoutActivity.allCases, id: \.self) { activity in
                        Label(activity.title, systemImage: activity.systemImage).tag(activity)
                    }
                }
                .pickerStyle(.navigationLink)

                Toggle(String(localized: "watch.indoor", defaultValue: "Indoor"), isOn: $isIndoor)

                Button {
                    workout.startFromWatch(activity: selectedActivity, isIndoor: isIndoor)
                } label: {
                    Label(String(localized: "watch.start", defaultValue: "Start"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityHint(String(localized: "watch.start.hint", defaultValue: "Starts one synchronized Plainstride workout"))
            }
        }
        .navigationTitle(String(localized: "watch.app.title", defaultValue: "Plainstride"))
    }

    private var workoutSurface: some View {
        ScrollView {
            VStack(spacing: 8) {
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(statusColor)
                    .accessibilityLabel(statusAccessibilityLabel)

                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    Text(durationText)
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .monospacedDigit()
                }

                HStack(spacing: 12) {
                    metric(workout.metrics?.currentBPM.map(String.init) ?? "—", String(localized: "watch.bpm", defaultValue: "BPM"))
                    metric(zoneText, String(localized: "watch.effort", defaultValue: "Effort"))
                    if let distance = workout.metrics?.distanceMeters {
                        metric(String(format: "%.2f", distance / 1_000), String(localized: "watch.km", defaultValue: "km"))
                    }
                }

                if workout.lifecycle == .finished || workout.lifecycle == .failed {
                    HStack(spacing: 12) {
                        metric(workout.metrics?.averageBPM.map(String.init) ?? "—", String(localized: "watch.average", defaultValue: "Average"))
                        metric(workout.metrics?.maximumBPM.map(String.init) ?? "—", String(localized: "watch.maximum", defaultValue: "Maximum"))
                    }

                    Button {
                        workout.dismissResult()
                    } label: {
                        Text(String(localized: "watch.done", defaultValue: "Done"))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                }

                if workout.lifecycle == .active || workout.lifecycle == .paused {
                    HStack {
                        Button {
                            workout.lifecycle == .paused ? workout.resume() : workout.pause()
                        } label: {
                            Image(systemName: workout.lifecycle == .paused ? "play.fill" : "pause.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .tint(.orange)
                        .accessibilityLabel(workout.lifecycle == .paused
                            ? String(localized: "watch.resume", defaultValue: "Resume")
                            : String(localized: "watch.pause", defaultValue: "Pause"))

                        Button(role: .destructive) { workout.finish() } label: {
                            Image(systemName: "stop.fill")
                                .frame(minWidth: 44, minHeight: 44)
                        }
                        .accessibilityLabel(String(localized: "watch.finish", defaultValue: "Finish"))
                    }
                }
            }
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(.headline).minimumScaleFactor(0.7)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var durationText: String {
        let total = Int(workout.metrics?.elapsedTime ?? 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    private var zoneText: String {
        guard let metrics = workout.metrics else {
            return String(localized: "watch.hr.waiting", defaultValue: "Waiting")
        }
        switch metrics.effort {
        case .easy: return String(localized: "watch.effort.easy", defaultValue: "Easy")
        case .moderate: return String(localized: "watch.effort.moderate", defaultValue: "Moderate")
        case .hard: return String(localized: "watch.effort.hard", defaultValue: "Hard")
        case .unavailable: return String(localized: "watch.hr.unavailable", defaultValue: "No signal")
        }
    }

    private var statusText: String {
        if workout.savedWorkoutSucceeded == true {
            return String(localized: "watch.saved", defaultValue: "Saved to Apple Health")
        }
        if workout.savedWorkoutSucceeded == false || workout.lifecycle == .failed {
            return String(localized: "watch.save_failed", defaultValue: "Workout could not be saved")
        }
        switch workout.connection {
        case .connected: return String(localized: "watch.connected", defaultValue: "iPhone connected")
        case .connecting: return String(localized: "watch.connecting", defaultValue: "Connecting to iPhone")
        case .disconnected: return String(localized: "watch.reconnecting", defaultValue: "iPhone disconnected — workout continues")
        case .unavailable: return String(localized: "watch.watch_only", defaultValue: "Recording on Apple Watch")
        }
    }

    private var statusAccessibilityLabel: String { statusText }
    private var statusColor: Color { workout.lifecycle == .failed ? .red : .secondary }
}

private extension PlainstrideWorkoutActivity {
    var title: String {
        switch self {
        case .running: String(localized: "watch.activity.run", defaultValue: "Run")
        case .walking: String(localized: "watch.activity.walk", defaultValue: "Walk")
        case .cycling: String(localized: "watch.activity.cycle", defaultValue: "Cycle")
        case .hiking: String(localized: "watch.activity.hike", defaultValue: "Hike")
        case .swimming: String(localized: "watch.activity.swim", defaultValue: "Swim")
        case .strength: String(localized: "watch.activity.strength", defaultValue: "Strength")
        case .mobility: String(localized: "watch.activity.mobility", defaultValue: "Mobility")
        }
    }

    var systemImage: String {
        switch self {
        case .running: "figure.run"
        case .walking: "figure.walk"
        case .cycling: "bicycle"
        case .hiking: "figure.hiking"
        case .swimming: "figure.pool.swim"
        case .strength: "dumbbell.fill"
        case .mobility: "figure.flexibility"
        }
    }
}
