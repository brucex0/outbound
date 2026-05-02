import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var coachStore: CoachStore
    @EnvironmentObject var coachCatalog: CoachCatalogStore
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var goalStore: GoalStore
    @EnvironmentObject var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject var healthImportStore: HealthImportStore
    @EnvironmentObject var musicStore: MusicStore

    let onStartSuggestion: (SuggestedSession) -> Void

    private let sectionPreviewLimit = 3

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    MotivationDashboardView(
                        showRecentActivity: false,
                        onStartSuggestion: onStartSuggestion
                    )
                    accountCard
                    coachCard
                    highlightsSection
                    myActivitiesSection
                }
                .padding()
            }
            .navigationTitle("Me")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                            .environmentObject(authStore)
                            .environmentObject(healthAuthorizationStore)
                            .environmentObject(healthImportStore)
                            .environmentObject(musicStore)
                    } label: {
                        Image(systemName: "gearshape.fill")
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .navigationDestination(for: SavedActivity.self) { activity in
                ActivityDetailView(activity: activity)
                    .environmentObject(activityStore)
            }
        }
    }

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Account")
                    .font(.title3.bold())
                Spacer()
                Image(systemName: authStore.user == nil ? "person.crop.circle.badge.exclamationmark" : "checkmark.shield.fill")
                    .font(.title2)
                    .foregroundStyle(authStore.user == nil ? .orange : .green)
            }

            Text(authStore.currentLoginLabel ?? "Signed in")
                .font(.headline)

            Text(accountDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(authStore.backendDescription)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding()
        .background(.blue.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var accountDetail: String {
        if authStore.user == nil {
            return "This account is stored locally on this device until Firebase-backed login is configured."
        }

        return "Your activity and coach data can now be associated with this authenticated account."
    }

    // MARK: - Coach card
    private var coachCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Coach")
                    .font(.title3.bold())
                Spacer()
                if coachStore.isSyncing {
                    ProgressView()
                } else {
                    NavigationLink {
                        CoachSelectionView()
                            .environmentObject(coachCatalog)
                    } label: {
                        Label("Change", systemImage: "slider.horizontal.3")
                            .font(.subheadline.bold())
                    }
                }
            }

            CoachTemplateSummaryView(persona: coachCatalog.selectedPersona)

            if let profile = coachStore.profile {
                HStack(spacing: 20) {
                    StatBlock(label: "Weekly",
                              value: "\(String(format: "%.0f", profile.athlete.weeklyVolumeKm)) km")
                    StatBlock(label: "Level",
                              value: profile.athlete.fitnessLevel.capitalized)
                    StatBlock(label: "Consistency",
                              value: "\(Int(profile.memorySnapshot.consistencyScore * 100))%")
                }
                .padding(.top, 4)
            }
        }
        .padding()
        .background(.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var highlightsSection: some View {
        HStack(spacing: 12) {
            ProfileMetricCard(
                label: "Activities",
                value: "\(activityStore.activities.count)",
                systemImage: "figure.run"
            )
            ProfileMetricCard(
                label: "Photos",
                value: "\(totalPhotoCount)",
                systemImage: "camera"
            )
            ProfileMetricCard(
                label: "This Week",
                value: String(format: "%.1f km", weeklyDistanceKm),
                systemImage: "calendar"
            )
        }
    }

    private var myActivitiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("My Activities")
                    .font(.title3.bold())
                Spacer()
                if activityStore.activities.count > sectionPreviewLimit {
                    NavigationLink("See All") {
                        ActivityHistoryView()
                            .environmentObject(activityStore)
                    }
                    .font(.caption.weight(.semibold))
                }
            }

            if activityStore.activities.isEmpty {
                emptyActivitiesPlaceholder
            } else {
                ForEach(Array(activityStore.activities.prefix(sectionPreviewLimit))) { activity in
                    NavigationLink(value: activity) {
                        ActivityCard(activity: activity, activityStore: activityStore)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var emptyActivitiesPlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.run.circle")
                .font(.system(size: 44))
                .foregroundStyle(.orange.opacity(0.6))
            Text("No activities yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var weeklyDistanceKm: Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        return activityStore.activities
            .filter { $0.startedAt >= startOfWeek }
            .reduce(0) { $0 + $1.distanceM } / 1000
    }

    private var totalPhotoCount: Int {
        activityStore.activities.reduce(0) { $0 + $1.photos.count }
    }
}

private struct SettingsView: View {
    @EnvironmentObject var authStore: AuthStore
    @EnvironmentObject var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject var healthImportStore: HealthImportStore
    @EnvironmentObject var musicStore: MusicStore

    var body: some View {
        List {
            Section("Account") {
                if let label = authStore.currentLoginLabel {
                    LabeledContent("Signed in as", value: label)
                } else {
                    LabeledContent("Account", value: "Signed in")
                }

                Text(authStore.backendDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Integrations") {
                AppleHealthSettingsCard()
                    .environmentObject(healthAuthorizationStore)
                    .environmentObject(healthImportStore)
                    .listRowInsets(EdgeInsets())

                AppleMusicSettingsCard()
                    .environmentObject(musicStore)
                    .listRowInsets(EdgeInsets())
            }

            Section("App") {
                LabeledContent("Version", value: "Prototype")
            }

            Section {
                Button("Sign Out", role: .destructive) {
                    authStore.signOut()
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct AssistantView: View {
    @EnvironmentObject private var assistantStore: AssistantStore
    @EnvironmentObject private var coachCatalog: CoachCatalogStore
    @EnvironmentObject private var activityStore: ActivityStore
    @EnvironmentObject private var goalStore: GoalStore

    let screenName: String
    let isRecordingActive: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    contextHeader
                    suggestionsSection
                    conversationSection
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .safeAreaInset(edge: .bottom) {
                composer
                    .background(.thinMaterial)
            }
            .task {
                assistantStore.ensureSeedMessage(context: assistantContext)
            }
            .onChange(of: assistantStore.messages.count) { _, _ in
                guard let lastID = assistantStore.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.22)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button("Reset") {
                assistantStore.reset(context: assistantContext)
            }
            .font(.subheadline.weight(.semibold))
        }
    }

    private var contextHeader: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: coachCatalog.selectedPersona.face.symbolName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(personaAccentColor)
                .frame(width: 30, height: 30)
                .background(personaAccentColor.opacity(0.12), in: Circle())

            VStack(alignment: .leading, spacing: 4) {
                Text("Ask for a plan, a quick explanation, or help getting unstuck.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(contextLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Try")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            ForEach(compactSuggestions) { suggestion in
                Button {
                    Task {
                        await assistantStore.sendSuggestion(suggestion, context: assistantContext)
                    }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: suggestion.capability.symbolName)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(personaAccentColor)
                        Text(suggestion.title)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(assistantStore.messages) { message in
                AssistantBubble(
                    message: message,
                    accentColor: personaAccentColor
                )
                .id(message.id)
            }

            if assistantStore.isResponding {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Thinking...")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 2)
            }
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 12) {
            TextField("Ask for help", text: $assistantStore.draft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...4)

            Button {
                Task {
                    await assistantStore.sendCurrentDraft(context: assistantContext)
                }
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 30))
            }
            .disabled(assistantStore.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || assistantStore.isResponding)
        }
        .padding(.horizontal)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    private var assistantContext: AssistantContext {
        AssistantContext(
            coachName: coachCatalog.selectedPersona.template.displayName,
            activityCount: activityStore.activities.count,
            weeklyDistanceKilometers: weeklyDistanceKilometers,
            currentGoalSummary: goalStore.progress?.summaryLine,
            currentScreen: screenName,
            isRecordingActive: isRecordingActive
        )
    }

    private var compactSuggestions: [AssistantSuggestion] {
        [
            assistantStore.suggestions.first { $0.capability == .plan },
            assistantStore.suggestions.first { $0.capability == .navigate },
            assistantStore.suggestions.first { $0.capability == .support },
            assistantStore.suggestions.first { $0.capability == .brainstorm }
        ]
        .compactMap { $0 }
    }

    private var contextLine: String {
        if let summary = goalStore.progress?.summaryLine, !summary.isEmpty {
            return summary
        }
        if activityStore.activities.isEmpty {
            return "No saved activity yet."
        }
        return "\(activityStore.activities.count) saved activit\(activityStore.activities.count == 1 ? "y" : "ies") this season."
    }

    private var weeklyDistanceKilometers: Double {
        let calendar = Calendar.current
        let startOfWeek = calendar.dateInterval(of: .weekOfYear, for: Date())?.start ?? .distantPast
        return activityStore.activities
            .filter { $0.startedAt >= startOfWeek }
            .reduce(0) { $0 + $1.distanceM } / 1000
    }

    private var personaAccentColor: Color {
        switch coachCatalog.selectedPersona.face.colorName {
        case "orange": .orange
        case "pink": .pink
        case "green": .green
        case "blue": .blue
        case "cyan": .cyan
        case "yellow": .yellow
        case "red": .red
        case "gray": .gray
        default: .orange
        }
    }
}

private struct AssistantBubble: View {
    let message: AssistantMessage
    let accentColor: Color

    var body: some View {
        HStack {
            if message.author == .assistant {
                bubble
                Spacer(minLength: 42)
            } else {
                Spacer(minLength: 42)
                bubble
            }
        }
    }

    private var bubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let capability = message.capability, message.author == .assistant {
                Label(capability.title, systemImage: capability.symbolName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(accentColor)
            }

            Text(message.text)
                .font(.subheadline)
                .foregroundStyle(message.author == .assistant ? Color.primary : Color.white)
        }
        .padding(14)
        .background(message.author == .assistant ? Color(.secondarySystemBackground) : accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AppleHealthSettingsCard: View {
    @EnvironmentObject var healthAuthorizationStore: HealthAuthorizationStore
    @EnvironmentObject var healthImportStore: HealthImportStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Health")
                        .font(.title3.bold())
                    Text(healthAuthorizationStore.snapshot.statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if healthAuthorizationStore.isRefreshing || healthAuthorizationStore.isRequestingAccess {
                    ProgressView()
                } else {
                    Image(systemName: "heart.text.square.fill")
                        .font(.title2)
                        .foregroundStyle(.red)
                }
            }

            Text(healthAuthorizationStore.snapshot.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !healthAuthorizationStore.snapshot.readDataTypeTitles.isEmpty {
                Text(healthAuthorizationStore.snapshot.readDataTypeTitles.joined(separator: " • "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let lastErrorMessage = healthAuthorizationStore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            recentHealthWorkouts

            if healthAuthorizationStore.snapshot.isHealthDataAvailable {
                Button {
                    Task {
                        await healthAuthorizationStore.requestAuthorization()
                        await healthImportStore.refreshRecentWorkouts()
                    }
                } label: {
                    HStack {
                        Text(healthAuthorizationStore.actionLabel)
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(healthAuthorizationStore.isRequestingAccess)
            }
        }
        .padding()
        .background(.red.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var recentHealthWorkouts: some View {
        if healthImportStore.isLoading {
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading recent workouts...")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else if let lastErrorMessage = healthImportStore.lastErrorMessage {
            Text(lastErrorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if !healthImportStore.recentWorkouts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent Health Workouts")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(healthImportStore.recentWorkouts) { workout in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(workout.activityName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(workout.startedAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(workout.summaryLine)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(workout.sourceName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

private struct AppleMusicSettingsCard: View {
    @EnvironmentObject var musicStore: MusicStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apple Music")
                        .font(.title3.bold())
                    Text(musicStore.snapshot.statusTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if musicStore.isRefreshing || musicStore.isLoadingQuickPicks {
                    ProgressView()
                } else if musicStore.hasDeveloperTokenError {
                    Image(systemName: "music.note.slash")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                } else {
                    Image(systemName: "music.note.house.fill")
                        .font(.title2)
                        .foregroundStyle(.orange)
                }
            }

            Text(musicStore.snapshot.statusDetail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(musicStore.musicSummaryLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let lastErrorMessage = musicStore.lastErrorMessage, !musicStore.hasDeveloperTokenError {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let troubleshootingLine = musicStore.troubleshootingLine {
                Text(troubleshootingLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task {
                    await musicStore.performPrimaryAction()
                }
            } label: {
                HStack {
                    Text(musicStore.primaryActionTitle)
                        .font(.subheadline.bold())
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(!musicStore.isPrimaryActionEnabled)
        }
        .padding()
        .background(.orange.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct ProfileMetricCard: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.orange)
            Text(value)
                .font(.title3.bold().monospacedDigit())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ActivityCard: View {
    let activity: SavedActivity
    let activityStore: ActivityStore

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 5) {
                Text(activity.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(activity.startedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    Label(String(format: "%.2f km", activity.distanceM / 1000),
                          systemImage: "figure.run")
                    Label(activity.durationSecs.formatted(), systemImage: "timer")
                    if let pace = activity.avgPace {
                        Label(pace.paceString, systemImage: "speedometer")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let photo = activity.photos.first, let url = activityStore.imageURL(for: photo) {
            LocalImageView(url: url) {
                Color.orange.opacity(0.25)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.15))
                .frame(width: 56, height: 56)
                .overlay {
                    Image(systemName: "figure.run").foregroundStyle(.orange)
                }
        }
    }
}
