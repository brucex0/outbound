import SwiftUI

struct CreateFutureActivityView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: TogetherStore

    @State private var title = ""
    @State private var startsAt = Date().addingTimeInterval(86_400)
    @State private var locationName = ""
    @State private var note = ""
    @State private var created: SocialGroupRunDetailDTO?
    @State private var selectedConnectionIDs: Set<String> = []
    @State private var shareURL: URL?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    inviteStep(created)
                } else {
                    planStep
                }
            }
            .navigationTitle(created == nil ? "Plan a run" : "Invite friends")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task {
            if socialStore.connections.isEmpty {
                await socialStore.refreshConnections()
            }
        }
    }

    private var planStep: some View {
        Form {
            Section {
                TextField("Saturday easy run", text: $title)
                    .textInputAutocapitalization(.sentences)
            } header: {
                Text("Name")
            }

            Section("Date and time") {
                DatePicker("Starts", selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
            }

            Section {
                TextField("Golden Gate Park", text: $locationName)
            } header: {
                Text("Meet at")
            } footer: {
                Text("Friends can meet here or join from anywhere.")
            }

            Section("Pace / note") {
                TextField("Easy, conversational pace", text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text("Create and invite").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func inviteStep(_ activity: SocialGroupRunDetailDTO) -> some View {
        List {
            Section {
                FutureActivitySummaryContent(
                    title: activity.title,
                    startsAt: activity.startsAt,
                    locationName: activity.locationName,
                    note: activity.paceNote
                )
            }

            Section("Invite running friends") {
                ForEach(socialStore.connections.filter { $0.status == "accepted" }) { connection in
                    Button {
                        if selectedConnectionIDs.contains(connection.person.id) {
                            selectedConnectionIDs.remove(connection.person.id)
                        } else {
                            selectedConnectionIDs.insert(connection.person.id)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(name: connection.person.displayName, avatarURL: connection.person.avatarUrl)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.person.displayName).foregroundStyle(.primary)
                                Text("@\(connection.person.username)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: selectedConnectionIDs.contains(connection.person.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedConnectionIDs.contains(connection.person.id) ? OutboundPalette.companion : .secondary)
                        }
                    }
                }
            }

            Section {
                if let shareURL {
                    ShareLink(item: "Join \(activity.title) on Plainstride: \(shareURL.absoluteString)") {
                        Label("Share link", systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        Task { shareURL = await socialStore.invitationURL(forFutureActivity: activity.id) }
                    } label: {
                        Label("Prepare share link", systemImage: "link")
                    }
                }

                Button {
                    Task {
                        isSubmitting = true
                        if await socialStore.inviteConnections(Array(selectedConnectionIDs), toFutureActivity: activity.id) {
                            dismiss()
                        }
                        isSubmitting = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text("Send \(selectedConnectionIDs.count) invite\(selectedConnectionIDs.count == 1 ? "" : "s")").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSubmitting || selectedConnectionIDs.isEmpty)
            }
        }
    }

    private func create() async {
        isSubmitting = true
        defer { isSubmitting = false }
        created = await socialStore.createFutureActivity(CreateFutureActivityRequestDTO(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startsAt: startsAt,
            locationName: locationName.nilIfBlank,
            note: note.nilIfBlank
        ))
    }
}

struct FutureActivitySummaryContent: View {
    let title: String
    let startsAt: Date
    let locationName: String?
    let note: String?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Text(startsAt.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).textCase(.uppercase)
                Text(startsAt.formatted(.dateTime.day())).font(.title2).fontWeight(.semibold)
            }
            .frame(width: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text([startsAt.formatted(date: .omitted, time: .shortened), locationName].compactMap { $0 }.joined(separator: " · "))
                    .font(.subheadline).foregroundStyle(.secondary)
                if let note { Text(note).font(.subheadline).foregroundStyle(.secondary) }
                Text("Meet up or join from anywhere").font(.caption).foregroundStyle(OutboundPalette.companion)
            }
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
