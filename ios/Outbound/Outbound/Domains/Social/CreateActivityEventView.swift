import SwiftUI

struct CreateActivityEventView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var socialStore: TogetherStore

    @State private var title = ""
    @State private var startsAt = Date().addingTimeInterval(86_400)
    @State private var durationMinutes = 0
    @State private var locationName = ""
    @State private var note = ""
    @State private var created: ActivityEventDetailDTO?
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
            .navigationTitle(created == nil ? String(localized: "Plan a run") : String(localized: "Invite friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
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
                TextField(String(localized: "social.event.title.placeholder", defaultValue: "Saturday easy run"), text: $title)
                    .textInputAutocapitalization(.sentences)
            } header: {
                Text(String(localized: "social.event.run_name", defaultValue: "Run name"))
            }

            Section(String(localized: "social.event.date_time", defaultValue: "Date and time")) {
                DatePicker(String(localized: "social.event.starts", defaultValue: "Starts"), selection: $startsAt, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                Picker(String(localized: "social.event.duration", defaultValue: "Duration (optional)"), selection: $durationMinutes) {
                    Text("Default · 1 hr").tag(0)
                    Text("30 min").tag(30)
                    Text("45 min").tag(45)
                    Text("1 hr").tag(60)
                    Text("1 hr 30 min").tag(90)
                    Text("2 hr").tag(120)
                    Text("3 hr").tag(180)
                    Text("4 hr").tag(240)
                }
            }

            Section {
                TextField(String(localized: "social.event.location.placeholder", defaultValue: "Golden Gate Park"), text: $locationName)
            } header: {
                Text(String(localized: "social.event.meet_at", defaultValue: "Meet at"))
            } footer: {
                Text(String(localized: "social.event.location.detail", defaultValue: "Friends can meet here or join from anywhere."))
            }

            Section(String(localized: "social.event.pace_note", defaultValue: "Pace / note")) {
                TextField(String(localized: "social.event.note.placeholder", defaultValue: "Easy, conversational pace"), text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Label(String(localized: "social.event.flexible_location", defaultValue: "Meet up or join from anywhere"), systemImage: "person.2.wave.2")
                    .font(.headline)
                Text(String(localized: "social.event.location.detail", defaultValue: "Friends can meet here or join from anywhere."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await create() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text(String(localized: "social.event.create_and_invite", defaultValue: "Create and invite")).fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func inviteStep(_ activity: ActivityEventDetailDTO) -> some View {
        List {
            Section {
                ActivityEventSummaryContent(
                    title: activity.title,
                    startsAt: activity.startsAt,
                    locationName: activity.locationName,
                    note: activity.paceNote
                )
            }

            Section(String(localized: "social.event.invite_friends", defaultValue: "Invite running friends")) {
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
                    ShareLink(item: String(localized: "Join \(activity.title) on Plainstride: \(shareURL.absoluteString)")) {
                        Label(String(localized: "social.event.share_link", defaultValue: "Share link"), systemImage: "square.and.arrow.up")
                    }
                } else {
                    Button {
                        Task { shareURL = await socialStore.invitationURL(forActivityEvent: activity.id) }
                    } label: {
                        Label(String(localized: "social.event.create_share_link", defaultValue: "Create share link"), systemImage: "link")
                    }
                }

                Button {
                    Task {
                        isSubmitting = true
                        if await socialStore.inviteConnections(Array(selectedConnectionIDs), toActivityEvent: activity.id) {
                            dismiss()
                        }
                        isSubmitting = false
                    }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text(String(localized: "social.event.send_invitations", defaultValue: "Send invitations")).fontWeight(.semibold) }
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
        created = await socialStore.createActivityEvent(CreateActivityEventRequestDTO(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startsAt: startsAt,
            locationName: locationName.nilIfBlank,
            note: note.nilIfBlank,
            durationMinutes: durationMinutes == 0 ? ActivityEventTiming.defaultDurationMinutes : durationMinutes
        ))
    }
}

struct ActivityEventSummaryContent: View {
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
                Label(String(localized: "social.event.flexible_location", defaultValue: "Meet up or join from anywhere"), systemImage: "person.2.wave.2")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(OutboundPalette.companion)
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
