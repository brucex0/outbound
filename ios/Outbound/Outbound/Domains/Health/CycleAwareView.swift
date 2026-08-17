import SwiftUI

struct CycleAwareView: View {
    @EnvironmentObject private var store: CycleAwareStore
    @State private var bleeding = false
    @State private var energy = 3
    @State private var discomfort = 1

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "cycle.setting.enabled", defaultValue: "Use cycle-aware guidance"), isOn: $store.isEnabled)
            } footer: {
                Text(String(localized: "cycle.privacy.detail", defaultValue: "Optional and private. Plainstride stores these entries only on this device and sends only a generic training signal when adaptation is requested."))
            }
            if store.isEnabled {
                Section(String(localized: "cycle.checkin.title", defaultValue: "How are you today?")) {
                    Toggle(String(localized: "cycle.checkin.period_today", defaultValue: "Period today"), isOn: $bleeding)
                    Stepper(String(localized: "Energy: \(energy) of 5"), value: $energy, in: 1...5)
                    Stepper(String(localized: "Discomfort: \(discomfort) of 5"), value: $discomfort, in: 1...5)
                    Button(String(localized: "cycle.checkin.save", defaultValue: "Save private check-in")) { store.log(bleeding: bleeding, energy: energy, discomfort: discomfort) }
                }
                Section(String(localized: "cycle.training_impact.title", defaultValue: "Training impact")) {
                    Label(store.currentSignal.title, systemImage: "sparkles")
                    Text(String(localized: "cycle.training_impact.detail", defaultValue: "You always choose whether to use a gentler option or keep the planned workout."))
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !store.logs.isEmpty {
                    Section {
                        Button(String(localized: "cycle.data.delete", defaultValue: "Delete cycle data"), role: .destructive) { store.clear() }
                    }
                }
            }
        }
        .navigationTitle(String(localized: "cycle.title", defaultValue: "Cycle-aware guidance"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
