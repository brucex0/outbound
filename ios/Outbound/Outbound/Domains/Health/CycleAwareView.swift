import SwiftUI

struct CycleAwareView: View {
    @EnvironmentObject private var store: CycleAwareStore
    @State private var bleeding = false
    @State private var energy = 3
    @State private var discomfort = 1

    var body: some View {
        Form {
            Section {
                Toggle("Use cycle-aware coaching", isOn: $store.isEnabled)
            } footer: {
                Text("Optional and private. Outbound stores these entries only on this device and sends only a generic training signal when adaptation is requested.")
            }
            if store.isEnabled {
                Section("How are you today?") {
                    Toggle("Period today", isOn: $bleeding)
                    Stepper("Energy: \(energy) of 5", value: $energy, in: 1...5)
                    Stepper("Discomfort: \(discomfort) of 5", value: $discomfort, in: 1...5)
                    Button("Save private check-in") { store.log(bleeding: bleeding, energy: energy, discomfort: discomfort) }
                }
                Section("Training impact") {
                    Label(store.currentSignal.title, systemImage: "sparkles")
                    Text("You always choose whether to use a gentler option or keep the planned workout.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if !store.logs.isEmpty {
                    Section {
                        Button("Delete cycle data", role: .destructive) { store.clear() }
                    }
                }
            }
        }
        .navigationTitle("Cycle-aware coaching")
        .navigationBarTitleDisplayMode(.inline)
    }
}
