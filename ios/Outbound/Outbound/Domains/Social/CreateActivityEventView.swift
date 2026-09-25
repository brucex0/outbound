import CoreLocation
import MapKit
import SwiftUI

struct CreateActivityEventView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject private var socialStore: TogetherStore

    @StateObject private var locationSearch = ActivityEventLocationSearchModel()

    @State private var title = ""
    @State private var activityType = ActivityType.running.rawValue
    @State private var startsAt = Date().addingTimeInterval(86_400)
    @State private var durationMinutes = 0
    @State private var locationName = ""
    @State private var selectedLocationCoordinate: CLLocationCoordinate2D?
    @State private var selectedLocationName: String?
    @State private var isResolvingLocation = false
    @State private var locationResolveToken = 0
    @State private var showsMapPicker = false
    @State private var note = ""
    @State private var joinVirtually = true
    @State private var created: ActivityEventDetailDTO?
    @State private var selectedConnectionIDs: Set<String> = []
    @State private var shareURL: URL?
    @State private var isSubmitting = false
    @FocusState private var isLocationFieldFocused: Bool
    let sourceGroupID: String?
    let additionalInvitees: [GroupPersonDTO]
    let editingActivity: ActivityEventDetailDTO?
    let onCompleted: () -> Void

    init(sourceGroupID: String? = nil, preselectedConnectionIDs: Set<String> = [], additionalInvitees: [GroupPersonDTO] = [], editingActivity: ActivityEventDetailDTO? = nil, onCompleted: @escaping () -> Void = {}) {
        self.sourceGroupID = sourceGroupID
        self.additionalInvitees = additionalInvitees
        self.editingActivity = editingActivity
        self.onCompleted = onCompleted
        _title = State(initialValue: editingActivity?.title ?? "")
        _activityType = State(initialValue: editingActivity?.activityType ?? ActivityType.running.rawValue)
        _startsAt = State(initialValue: editingActivity?.startsAt ?? Date().addingTimeInterval(86_400))
        _durationMinutes = State(initialValue: editingActivity.flatMap { activity in
            activity.endsAt.map { max(15, Int($0.timeIntervalSince(activity.startsAt) / 60)) }
        } ?? 0)
        _locationName = State(initialValue: editingActivity?.locationName ?? "")
        _selectedLocationName = State(initialValue: editingActivity?.locationName)
        _selectedLocationCoordinate = State(initialValue: editingActivity?.meetupCoordinate)
        _note = State(initialValue: editingActivity?.paceNote ?? "")
        _joinVirtually = State(initialValue: editingActivity?.participationMode != "in_person")
        _selectedConnectionIDs = State(initialValue: preselectedConnectionIDs)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let created {
                    inviteStep(created)
                } else {
                    planStep
                }
            }
            .navigationTitle(created == nil ? (editingActivity == nil ? planningTitle : "Edit activity") : String(localized: "Invite friends"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "common.close", defaultValue: "Close")) { dismiss() }
                }
            }
        }
        .task {
            await analyticsManager?.track(.init(.featureExposed, properties: [
                .feature: .string("activity_event_location_picker"),
            ]))
            if socialStore.connections.isEmpty {
                await socialStore.refreshConnections()
            }
            await socialStore.loadRemainingConnections()
        }
        .sheet(isPresented: $showsMapPicker) {
            ActivityEventMapPicker(
                initialCoordinate: selectedLocationCoordinate,
                initialName: selectedLocationName
            ) { place in
                apply(place, source: "map")
            }
        }
    }

    private var planStep: some View {
        Form {
            Section {
                TextField(eventTitlePlaceholder, text: $title)
                    .textInputAutocapitalization(.sentences)
            } header: {
                Text(eventNameLabel)
            }

            Section(String(localized: "social.event.activity_type", defaultValue: "Activity")) {
                Picker(String(localized: "social.event.activity_type", defaultValue: "Activity"), selection: $activityType) {
                    ForEach(ActivityType.allCases, id: \.rawValue) { type in
                        Text(activityTypeTitle(type.rawValue)).tag(type.rawValue)
                    }
                }
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
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    TextField(
                        String(
                            localized: "social.event.location.placeholder",
                            defaultValue: "Search for a place or address"
                        ),
                        text: $locationName
                    )
                    .focused($isLocationFieldFocused)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
                    .onSubmit { isLocationFieldFocused = false }

                    if isResolvingLocation {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel(
                                String(
                                    localized: "social.event.location.search.resolving",
                                    defaultValue: "Selecting location"
                                )
                            )
                    }
                }

                if isLocationFieldFocused {
                    ForEach(locationSearch.completions, id: \.suggestionID) { completion in
                        Button {
                            Task { await select(completion) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundStyle(OutboundPalette.companion)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(completion.title)
                                        .foregroundStyle(.primary)
                                    if !completion.subtitle.isEmpty {
                                        Text(completion.subtitle)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolvingLocation)
                    }
                }

                Button {
                    isLocationFieldFocused = false
                    locationSearch.clear()
                    showsMapPicker = true
                } label: {
                    Label(
                        String(
                            localized: "social.event.location.choose_on_map",
                            defaultValue: "Choose on map"
                        ),
                        systemImage: "map"
                    )
                }
            } header: {
                Text(String(localized: "social.event.meet_at", defaultValue: "Meet at"))
            }

            Section(noteLabel) {
                TextField(notePlaceholder, text: $note, axis: .vertical)
                    .lineLimit(2...4)
            }

            Section {
                Toggle(isOn: $joinVirtually) {
                    Label("Join virtually", systemImage: "wifi")
                }
                Text("People can join without meeting at the listed location.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    Task { await submit() }
                } label: {
                    HStack {
                        Spacer()
                        if isSubmitting { ProgressView() } else { Text(editingActivity == nil ? String(localized: "social.event.create_and_invite", defaultValue: "Create and invite") : "Save changes").fontWeight(.semibold) }
                        Spacer()
                    }
                }
                .disabled(isSubmitting || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onChange(of: locationName) { _, query in
            guard isLocationFieldFocused else { return }
            selectedLocationCoordinate = nil
            selectedLocationName = nil
            locationSearch.update(query: query)
        }
        .onChange(of: isLocationFieldFocused) { _, isFocused in
            if isFocused {
                locationSearch.update(query: locationName)
            } else {
                locationSearch.clear()
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

            Section(inviteFriendsLabel) {
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
                ForEach(additionalInvitees.filter { person in
                    !socialStore.connections.contains { $0.status == "accepted" && $0.person.id == person.id }
                }) { person in
                    Button { toggleInvitee(person.id) } label: {
                        HStack(spacing: 12) {
                            SocialAvatar(name: person.displayName, avatarURL: person.avatarUrl)
                            Text(person.displayName).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: selectedConnectionIDs.contains(person.id) ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(selectedConnectionIDs.contains(person.id) ? OutboundPalette.companion : .secondary)
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
                            onCompleted()
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

    private func submit() async {
        if let editingActivity {
            await update(editingActivity)
        } else {
            await create()
        }
    }

    private func update(_ activity: ActivityEventDetailDTO) async {
        isSubmitting = true
        defer { isSubmitting = false }
        let request = UpdateActivityEventRequestDTO(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            startsAt: startsAt,
            locationName: locationName.locationNameForSubmission,
            latitude: selectedLocationCoordinate?.latitude,
            longitude: selectedLocationCoordinate?.longitude,
            note: note.nilIfBlank,
            durationMinutes: durationMinutes == 0 ? ActivityEventTiming.defaultDurationMinutes : durationMinutes,
            participationMode: joinVirtually ? "hybrid" : "in_person"
        )
        if await socialStore.updateActivityEvent(id: activity.id, request: request) != nil {
            onCompleted()
            dismiss()
        }
    }

    private func create() async {
        isSubmitting = true
        defer { isSubmitting = false }
        created = await socialStore.createActivityEvent(CreateActivityEventRequestDTO(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            activityType: activityType,
            startsAt: startsAt,
            locationName: locationName.locationNameForSubmission,
            latitude: selectedLocationCoordinate?.latitude,
            longitude: selectedLocationCoordinate?.longitude,
            note: note.nilIfBlank,
            durationMinutes: durationMinutes == 0 ? ActivityEventTiming.defaultDurationMinutes : durationMinutes,
            groupId: sourceGroupID,
            participationMode: joinVirtually ? "hybrid" : "in_person"
        ))
    }

    private var planningTitle: String {
        sourceGroupID == nil
            ? String(localized: "social.create.plan", defaultValue: "Plan an activity")
            : String(localized: "group.event.plan", defaultValue: "Plan an activity")
    }

    private func activityTypeTitle(_ rawValue: String) -> String {
        switch rawValue {
        case ActivityType.cycling.rawValue: return String(localized: "social.activity.cycling", defaultValue: "Cycling")
        case ActivityType.hiking.rawValue: return String(localized: "social.activity.hiking", defaultValue: "Hiking")
        case ActivityType.walking.rawValue: return String(localized: "social.activity.walking", defaultValue: "Walking")
        case ActivityType.swimming.rawValue: return String(localized: "social.activity.swimming", defaultValue: "Swimming")
        case ActivityType.strengthTraining.rawValue: return String(localized: "social.activity.strength", defaultValue: "Strength")
        case ActivityType.mobility.rawValue: return String(localized: "social.activity.mobility", defaultValue: "Mobility")
        default: return String(localized: "social.activity.running", defaultValue: "Running")
        }
    }

    private var eventNameLabel: String {
        sourceGroupID == nil
            ? String(localized: "social.event.run_name", defaultValue: "Run name")
            : String(localized: "group.event.name", defaultValue: "Activity name")
    }

    private var eventTitlePlaceholder: String {
        sourceGroupID == nil
            ? String(localized: "social.event.title.placeholder", defaultValue: "Saturday easy run")
            : String(localized: "group.event.title.placeholder", defaultValue: "Saturday morning workout")
    }

    private var noteLabel: String {
        sourceGroupID == nil
            ? String(localized: "social.event.pace_note", defaultValue: "Pace / note")
            : String(localized: "group.event.note", defaultValue: "Plan / note")
    }

    private var notePlaceholder: String {
        sourceGroupID == nil
            ? String(localized: "social.event.note.placeholder", defaultValue: "Easy, conversational pace")
            : String(localized: "group.event.note.placeholder", defaultValue: "Walk, ride, gym session—anything that feels good")
    }

    private var inviteFriendsLabel: String {
        sourceGroupID == nil
            ? String(localized: "social.event.invite_friends", defaultValue: "Invite running friends")
            : String(localized: "group.event.invite", defaultValue: "Invite your Group")
    }

    private func select(_ completion: MKLocalSearchCompletion) async {
        isResolvingLocation = true
        let resolveToken = locationResolveToken
        let place = await locationSearch.resolve(completion)
        guard resolveToken == locationResolveToken else { return }
        isResolvingLocation = false
        apply(place, source: "autocomplete")
    }

    private func toggleInvitee(_ id: String) {
        if selectedConnectionIDs.contains(id) { selectedConnectionIDs.remove(id) } else { selectedConnectionIDs.insert(id) }
    }

    private func apply(_ place: ActivityEventPlace, source: String) {
        isLocationFieldFocused = false
        locationSearch.clear()
        locationResolveToken += 1
        let boundedName = String(place.displayName.prefix(120))
        locationName = boundedName
        selectedLocationName = boundedName
        selectedLocationCoordinate = place.coordinate

        Task {
            await analyticsManager?.track(.init(.activityEventLocationSelected, properties: [
                .sourceType: .string(source),
            ]))
        }
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
                Image(systemName: "person.2.wave.2")
                    .accessibilityLabel(String(localized: "social.event.flexible_location", defaultValue: "Flexible attendance"))
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

    var locationNameForSubmission: String? {
        nilIfBlank.map { String($0.prefix(120)) }
    }
}
