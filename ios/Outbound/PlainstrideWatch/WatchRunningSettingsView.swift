import SwiftUI

struct WatchRunningSettingsView: View {
    @AppStorage("watch.miles") private var miles = false
    @AppStorage("watch.autoSplits") private var autoSplits = true
    @AppStorage("watch.zoneAlerts") private var zoneAlerts = false
    @AppStorage("watch.showPace") private var showPace = true
    @AppStorage("watch.showHeart") private var showHeart = true
    @AppStorage("watch.goalIsTime") private var goalIsTime = false
    @AppStorage("watch.goalValue") private var goalValue = 0.0
    @AppStorage("watch.paceTarget") private var paceTarget = 0.0

    var body: some View {
        NavigationStack {
            Form {
                Toggle(String(localized: "watch.units.miles", defaultValue: "Use miles"), isOn: $miles)
                Toggle(String(localized: "watch.splits.auto", defaultValue: "Automatic splits"), isOn: $autoSplits)
                Toggle(String(localized: "watch.alerts.zone", defaultValue: "Zone change alerts"), isOn: $zoneAlerts)
                Toggle(String(localized: "watch.page.pace", defaultValue: "Pace page"), isOn: $showPace)
                Toggle(String(localized: "watch.page.heart", defaultValue: "Heart rate page"), isOn: $showHeart)
                Section(String(localized: "watch.goal", defaultValue: "Goal")) {
                    Toggle(String(localized: "watch.goal.time", defaultValue: "Time goal"), isOn: $goalIsTime)
                        .onChange(of: goalIsTime) { _, _ in goalValue = 0 }
                    Stepper(value: $goalValue, in: 0...maxGoal, step: goalStep) {
                        if goalValue == 0 {
                            Text(String(localized: "watch.goal.open", defaultValue: "Open goal"))
                        } else {
                            Text(goalIsTime
                                ? String(format: String(localized: "watch.goal.minutes", defaultValue: "%d min"), Int(goalValue / 60))
                                : String(format: String(localized: "watch.goal.distance", defaultValue: "%.1f %@"), goalValue / (miles ? 1609.344 : 1000), miles ? String(localized: "watch.mi", defaultValue: "mi") : String(localized: "watch.km", defaultValue: "km")))
                        }
                    }
                }
                Section(String(localized: "watch.pace.target", defaultValue: "Target pace")) {
                    Toggle(String(localized: "watch.pace.alerts", defaultValue: "Pace alerts"), isOn: Binding(
                        get: { paceTarget > 0 }, set: { paceTarget = $0 ? 360 : 0 }))
                    if paceTarget > 0 {
                        Stepper(value: $paceTarget, in: 120...900, step: 15) {
                            let seconds = Int((paceTarget * (miles ? 1.609344 : 1)).rounded())
                            Text(String(format: "%d:%02d", seconds / 60, seconds % 60) + (miles
                                ? String(localized: "watch.pace.mi", defaultValue: "/mi")
                                : String(localized: "watch.pace.km", defaultValue: "/km")))
                        }
                    }
                    Text(String(localized: "watch.pace.alert.help", defaultValue: "Vibrates when pace is more than 30 sec/km from your target. Pace uses a 15-second rolling window."))
                }
            }
            .navigationTitle(String(localized: "watch.settings", defaultValue: "Running settings"))
        }
    }
    private var goalStep: Double { goalIsTime ? 300 : (miles ? 1609.344 : 1000) }
    private var maxGoal: Double { goalIsTime ? 86400 : 200000 }
}
