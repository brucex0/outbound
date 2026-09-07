import SwiftUI

struct CheerInvitationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: TogetherStore
    @EnvironmentObject private var liveShareStore: LiveShareStore
    @Environment(\.analyticsManager) private var analyticsManager
    @State private var selectedIDs: Set<String> = []

    private var connections: [SocialConnectionDTO] {
        socialStore.connections.filter { $0.status == "accepted" }.sorted(by: SocialConnectionDTO.previewOrder)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if !socialStore.hasLoadedConnections {
                        ProgressView("Loading your people…")
                    } else if connections.isEmpty {
                        ContentUnavailableView(
                            "Connect with someone first",
                            systemImage: "person.2",
                            description: Text("Only your accepted Plainstride connections can follow your live run and send voice cheers.")
                        )
                    } else {
                        ForEach(connections) { connection in
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
                                }
                            }
                        }
                    }
                } header: {
                    Text("Who should cheer you on?")
                } footer: {
                    Text("They’ll see your precise location, pace, distance, and heart rate for this activity, and can send short voice cheers in the app.")
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
            }
        }
    }
}
