import SwiftUI

struct CheerInvitationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var liveShareStore: LiveShareStore
    @EnvironmentObject private var safetyContactStore: SafetyContactStore
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var selectedIDs: Set<String> = []

    private var connections: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "accepted" }.sorted(by: SocialConnectionDTO.previewOrder)
    }

    private var trustedConnections: [SocialConnectionDTO] {
        connections.filter { safetyContactStore.isTrusted($0.person.id) }
    }

    private var otherConnections: [SocialConnectionDTO] {
        connections.filter { !safetyContactStore.isTrusted($0.person.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Trusted contacts") {
                    if !socialStore.hasLoadedConnections {
                        ProgressView("Loading your people…")
                    } else if trustedConnections.isEmpty {
                        ContentUnavailableView(
                            "No trusted contacts",
                            systemImage: "person.badge.shield.checkmark",
                            description: Text("Choose trusted contacts in Settings to keep them at the top and selected automatically.")
                        )
                        NavigationLink("Set up trusted contacts") { SafetyContactsSettingsView() }
                    } else {
                        ForEach(trustedConnections) { connectionRow($0) }
                    }
                }

                if !otherConnections.isEmpty {
                    Section("Other connections") {
                        ForEach(otherConnections) { connectionRow($0) }
                    }
                }

                Section {
                    Text("They’ll see your precise location, pace, distance, and heart rate for this activity, and can send short voice cheers in the app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Cheer me on")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        liveShareStore.setSelectedConnections(connections.filter { selectedIDs.contains($0.person.id) })
                        Task { await analyticsManager?.track(.init(.liveCheerInvitationConfigured, properties: [.participantCountBucket: .string(ProductAnalyticsBucket.count(selectedIDs.count))])) }
                        dismiss()
                    }
                }
            }
            .task {
                selectedIDs = Set(liveShareStore.selectedConnections.map(\.person.id))
                if !socialStore.hasLoadedConnections { await socialStore.refreshConnections() }
                if selectedIDs.isEmpty {
                    selectedIDs = Set(trustedConnections.map(\.person.id))
                }
            }
            .onChange(of: safetyContactStore.trustedConnectionIDs) { oldIDs, newIDs in
                selectedIDs.formUnion(newIDs.subtracting(oldIDs))
            }
        }
    }

    private func connectionRow(_ connection: SocialConnectionDTO) -> some View {
        Button {
            if selectedIDs.contains(connection.person.id) { selectedIDs.remove(connection.person.id) }
            else { selectedIDs.insert(connection.person.id) }
        } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(connection.person.displayName).foregroundStyle(.primary)
                    Text("@\(connection.person.username)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: selectedIDs.contains(connection.person.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selectedIDs.contains(connection.person.id) ? .orange : .secondary)
            }
        }
    }
}
