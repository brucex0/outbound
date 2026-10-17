import SwiftUI

struct WatchWorkoutView: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @State private var selectedActivity: PlainstrideWorkoutActivity = .running
    @State private var isIndoor = false
    @State private var showsSettings = false
    @State private var confirmsFinish = false
    @AppStorage("watch.miles") private var miles = false
    @AppStorage("watch.showPace") private var showPace = true
    @AppStorage("watch.showHeart") private var showHeart = true

    var body: some View {
        Group {
            if workout.isWorkoutInProgress || workout.lifecycle == .finished || workout.lifecycle == .failed {
                workoutSurface
            } else {
                activityPicker
            }
        }
        .sheet(isPresented: $showsSettings) { WatchRunningSettingsView() }
        .confirmationDialog(String(localized: "watch.finish.confirm", defaultValue: "Finish workout?"), isPresented: $confirmsFinish) {
            Button(String(localized: "watch.finish", defaultValue: "Finish"), role: .destructive) { workout.finish() }
        }
        .task { await workout.retryPendingRoutes() }
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

                Button(String(localized: "watch.settings", defaultValue: "Running settings")) { showsSettings = true }
            }
        }
        .navigationTitle(String(localized: "watch.app.title", defaultValue: "Plainstride"))
    }

    private var workoutSurface: some View {
        TabView {
            ScrollView {
                VStack(spacing: 8) {
                    Text(statusText).font(.caption).foregroundStyle(statusColor)
                    Text(durationText).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                    metric(distanceText, miles
                        ? String(localized: "watch.mi", defaultValue: "mi")
                        : String(localized: "watch.km", defaultValue: "km"))
                    if let energy = workout.metrics?.activeEnergyKilocalories {
                        metric(String(Int(energy.rounded())), String(localized: "watch.calories", defaultValue: "Active kcal"))
                    }
                    if workout.routePermissionDenied {
                        Text(String(localized: "watch.route.permission", defaultValue: "Route unavailable. Allow Location in Settings."))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if WatchRunningSettings.goalValue > 0, !workout.goalReached {
                        ProgressView(value: goalProgress)
                            .accessibilityLabel(String(localized: "watch.goal", defaultValue: "Goal"))
                    }
                    if workout.goalReached {
                        Label(String(localized: "watch.goal.reached", defaultValue: "Goal reached"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                    if workout.lifecycle == .active || workout.lifecycle == .paused {
                        HStack {
                            Button { workout.lifecycle == .paused ? workout.resume() : workout.pause() } label: {
                                Image(systemName: workout.lifecycle == .paused ? "play.fill" : "pause.fill").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel(workout.lifecycle == .paused
                                ? String(localized: "watch.resume", defaultValue: "Resume")
                                : String(localized: "watch.pause", defaultValue: "Pause"))
                            Button(role: .destructive) { confirmsFinish = true } label: {
                                Image(systemName: "stop.fill").frame(minWidth: 44, minHeight: 44)
                            }
                            .accessibilityLabel(String(localized: "watch.finish", defaultValue: "Finish"))
                        }
                        if workout.lifecycle == .active {
                            Button(String(localized: "watch.lap", defaultValue: "Lap")) { workout.markLap() }
                        }
                    } else if workout.lifecycle == .finished || workout.lifecycle == .failed {
                        Button(String(localized: "watch.done", defaultValue: "Done")) { workout.dismissResult() }
                    }
                }
            }
            if showPace {
                ScrollView {
                    VStack(spacing: 12) {
                        metric(paceText(workout.currentPaceSecondsPerKilometer), String(localized: "watch.pace.current", defaultValue: "Current pace"))
                        metric(paceText(averagePace), String(localized: "watch.pace.average", defaultValue: "Average pace"))
                        metric(paceText(workout.lapPaceSecondsPerKilometer), String(localized: "watch.pace.lap", defaultValue: "Lap pace"))
                        ForEach(workout.laps.suffix(5)) { lap in
                            let number = (workout.laps.firstIndex { $0.id == lap.id } ?? 0) + 1
                            Text(String(format: String(localized: "watch.lap.pace.format", defaultValue: "Lap %d · %@"), number, paceText(lap.pace)))
                                .font(.caption).monospacedDigit()
                        }
                    }
                }
            }
            if showHeart {
                ScrollView {
                    VStack(spacing: 10) {
                        metric(workout.metrics?.currentBPM.map(String.init) ?? "—", String(localized: "watch.bpm", defaultValue: "BPM"))
                        metric(zoneText, String(localized: "watch.effort", defaultValue: "Effort"))
                        if let zone = workout.metrics?.currentZone {
                            Text(String(format: String(localized: "watch.zone.format", defaultValue: "Zone %d"), zone))
                        }
                        HStack {
                            metric(workout.metrics?.averageBPM.map(String.init) ?? "—", String(localized: "watch.average", defaultValue: "Average"))
                            metric(workout.metrics?.maximumBPM.map(String.init) ?? "—", String(localized: "watch.maximum", defaultValue: "Maximum"))
                        }
                        ForEach(workout.metrics?.timeInZones ?? [], id: \.zone) { zone in
                            Text(String(format: String(localized: "watch.zone.duration", defaultValue: "Zone %d · %d min"), zone.zone, Int(zone.seconds / 60)))
                                .font(.caption)
                        }
                    }
                }
            }
        }
        .tabViewStyle(.page)
    }

    private var goalProgress: Double {
        let value = WatchRunningSettings.goalIsTime ? (workout.metrics?.elapsedTime ?? 0) : (workout.metrics?.distanceMeters ?? 0)
        return min(1, max(0, value / WatchRunningSettings.goalValue))
    }

    private var distanceText: String {
        guard let distance = workout.metrics?.distanceMeters else { return "—" }
        return String(format: "%.2f", distance / (miles ? 1609.344 : 1000))
    }
    private var averagePace: Double? {
        guard let metrics = workout.metrics, let distance = metrics.distanceMeters, distance > 10 else { return nil }
        return metrics.elapsedTime * 1000 / distance
    }
    private func paceText(_ secondsPerKilometer: Double?) -> String {
        guard let pace = secondsPerKilometer, pace.isFinite, pace > 0 else { return "—" }
        let seconds = Int((pace * (miles ? 1.609344 : 1)).rounded())
        let unit = miles ? String(localized: "watch.pace.mi", defaultValue: "/mi") : String(localized: "watch.pace.km", defaultValue: "/km")
        return String(format: "%d:%02d", seconds / 60, seconds % 60) + unit
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
