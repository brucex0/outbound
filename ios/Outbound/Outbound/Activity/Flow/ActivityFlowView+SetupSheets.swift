import SwiftUI
import PhotosUI
import CoreLocation
import MapKit

extension ActivityFlowView {
    func confirmationView(for intent: SessionIntent) -> some View {
        VStack(spacing: 14) {
            VStack(spacing: 8) {
                Text(intent.title)
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.86)
                Text(intent.detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 48)

            VStack(alignment: .leading) {
                Text(intent.guideLine)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))

            VStack(spacing: 14) {
                voiceGuideCard

                if intent.workoutSteps.isEmpty {
                    sessionGoalCard(for: intent)
                } else {
                    plannedWorkoutCard(for: intent)
                }

                routeSetupCard

                Button {
                    model.setup.setupSheet = .more
                } label: {
                    Label(String(localized: "record.setup.more_options", defaultValue: "More options"), systemImage: "ellipsis.circle")
                        .font(.subheadline.weight(.semibold))
                }

                Button(intent.workoutSteps.isEmpty ? "Change activity" : "Choose a different activity") {
                    host.onCloseRequest?(false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }

        }
    }

    var voiceGuideCard: some View {
        Toggle(isOn: Binding(
            get: { model.voiceGuideSpeechEnabled },
            set: { model.isVoiceGuideEnabled = $0 }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Label(String(localized: "record.voice_guide.title", defaultValue: "Voice Guide"), systemImage: "waveform.circle")
                    .font(.subheadline.weight(.semibold))
                Text(model.isVoiceGuideExplicitlyUnavailable
                    ? String(
                        localized: "record.voice_guide.unavailable.message",
                        defaultValue: "Voice Guide audio is temporarily unavailable."
                    )
                    : String(localized: "record.voice_guide.detail", defaultValue: "Hear countdowns, progress updates, and live coaching."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(model.isVoiceGuideExplicitlyUnavailable)
        .tint(.orange)
        .padding(16)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
        .onChange(of: model.isVoiceGuideEnabled) { _, isEnabled in
            model.guide.setSpeechEnabled(model.voiceGuideSpeechEnabled)
            model.track(.init(.activityConfigurationChanged, properties: [
                .changeType: .string("voice_guide"),
                .selectionType: .string(isEnabled ? "enabled" : "disabled")
            ]))
            guard isEnabled else { return }
            Task { await model.dependencies.guideCatalog.refreshServerCatalog() }
        }
    }

    @ViewBuilder
    func setupSheetView(_ sheet: ActivitySetupSheet) -> some View {
        NavigationStack {
            Group {
                switch sheet {
                case .goal:
                    goalValueEditor.padding(20)
                case .music:
                    ScrollView { musicSetupChoices.padding() }
                case .more:
                    moreSetupSheet
                case .groupRun:
                    groupRunSetupSheet
                }
            }
            .navigationTitle(sheet.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if sheet != .goal {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: "common.done", defaultValue: "Done")) { model.setup.setupSheet = nil }
                    }
                }
            }
        }
    }

    var musicSetupChoices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                model.dependencies.musicStore.disableMusic()
                model.track(.init(.musicQuickPickSelected, properties: [.selectionType: .string("no_music")]))
            } label: {
                setupChoiceRow(
                    title: String(localized: "record.music.none", defaultValue: "No music"),
                    detail: String(localized: "record.music.none.detail", defaultValue: "Start without a soundtrack"),
                    systemImage: "music.note.slash",
                    isSelected: model.dependencies.musicStore.isMusicDisabled
                )
            }
            .buttonStyle(.plain)

            Divider().padding(.vertical, 4)

            if model.dependencies.musicStore.hasDeveloperTokenError {
                Label(String(localized: "session.music.unavailable", defaultValue: "Music unavailable"), systemImage: "music.note.slash")
                    .foregroundStyle(.secondary)
            } else if let lastErrorMessage = model.dependencies.musicStore.lastErrorMessage {
                Text(lastErrorMessage).font(.caption).foregroundStyle(.orange)
            }
            if let troubleshootingLine = model.dependencies.musicStore.troubleshootingLine {
                Text(troubleshootingLine).font(.caption).foregroundStyle(.secondary)
            }
            if model.dependencies.musicStore.canShowQuickPicks, !model.dependencies.musicStore.quickPicks.isEmpty {
                Text(String(localized: "record.music.suggested", defaultValue: "Suggested for this workout"))
                    .font(.headline)
                ForEach(model.dependencies.musicStore.quickPicks) { quickPick in
                    Button {
                        model.dependencies.musicStore.selectQuickPick(quickPick)
                        model.track(.init(.musicQuickPickSelected, properties: [.selectionType: .string("quick_pick")]))
                    } label: {
                        setupChoiceRow(title: quickPick.title, detail: quickPick.subtitle, systemImage: quickPick.symbolName, isSelected: model.dependencies.musicStore.selectedQuickPickID == quickPick.id)
                    }
                    .buttonStyle(.plain)
                }

                Divider().padding(.vertical, 4)
                Text(String(localized: "record.music.choose", defaultValue: "Choose your music"))
                    .font(.headline)
                Picker(String(localized: "record.music.category", defaultValue: "Music category"), selection: binding(\.setup.musicSearchCategory)) {
                    Text(String(localized: "record.music.songs", defaultValue: "Songs")).tag(MusicSearchCategory.songs)
                    Text(String(localized: "record.music.albums", defaultValue: "Albums")).tag(MusicSearchCategory.albums)
                    Text(String(localized: "record.music.playlists", defaultValue: "Playlists")).tag(MusicSearchCategory.playlists)
                }
                .pickerStyle(.segmented)
                .onChange(of: model.setup.musicSearchCategory) { _, category in
                    guard model.dependencies.musicStore.searchResults(for: category).isEmpty,
                          !model.dependencies.musicStore.isSearching(category)
                    else { return }
                    model.setup.searchMusic()
                }
                HStack {
                    TextField(String(localized: "record.music.search", defaultValue: "Search Apple Music"), text: binding(\.setup.musicSearchText))
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { model.setup.searchMusic() }
                    Button { model.setup.searchMusic() } label: {
                        if model.dependencies.musicStore.isSearching { ProgressView() } else { Image(systemName: "magnifyingglass") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.setup.musicSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.dependencies.musicStore.isSearching)
                    .accessibilityLabel(String(localized: "record.music.search.action", defaultValue: "Search music"))
                }
                musicPlaybackOptions
                ForEach(model.dependencies.musicStore.searchResults(for: model.setup.musicSearchCategory)) { item in
                    Button { model.dependencies.musicStore.toggleCustomSelection(item) } label: {
                        setupChoiceRow(
                            title: item.title,
                            detail: item.subtitle,
                            systemImage: model.setup.musicSearchSymbol(for: item.category),
                            isSelected: model.dependencies.musicStore.selectedCustomItems.contains(item)
                        )
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    if !model.dependencies.musicStore.isConnected { model.track(.init(.musicAuthorizationRequested)) }
                    Task { await model.dependencies.musicStore.performPrimaryAction() }
                } label: {
                    setupChoiceRow(title: model.dependencies.musicStore.primaryActionTitle, detail: model.dependencies.musicStore.musicSummaryLine, systemImage: "music.note.list", isSelected: model.setup.musicIsConfigured)
                }
                .buttonStyle(.plain)
                .disabled(!model.dependencies.musicStore.isPrimaryActionEnabled)
            }
        }
    }

    var moreSetupSheet: some View {
        List {
#if DEBUG
            Section(String(localized: "run.simulation.testing.section", defaultValue: "Testing")) {
                Toggle(isOn: Binding(
                    get: { model.isRunSimulationEnabled },
                    set: { model.configureHarvestRunSimulation(enabled: $0) }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Label(
                            String(localized: "run.simulation.setup.title", defaultValue: "Simulated Harvest Run"),
                            systemImage: "figure.run.circle"
                        )
                        Text(String(
                            localized: "run.simulation.setup.detail",
                            defaultValue: "Use the Redmond route with adjustable speed and time. No GPS movement is required."
                        ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
                .tint(.orange)
                .disabled(model.recorder.state != .idle)
            }
#endif
            Section(String(localized: "model.guide.challenge.section.title", defaultValue: "Optional live challenge")) {
                ForEach(LiveGuidanceChallenge.allCases) { challenge in
                    Button {
                        model.setup.selectedGuidanceChallenge = challenge
                        model.track(.init(.liveGuidanceChallengeSelected, properties: [
                            .selectionType: .string(challenge.rawValue)
                        ]))
                    } label: {
                        setupChoiceRow(
                            title: challenge.displayName,
                            detail: challenge.detail,
                            systemImage: challenge == .off ? "minus.circle" : "bolt.fill",
                            isSelected: model.setup.selectedGuidanceChallenge == challenge
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            Section(String(localized: "record.group.title", defaultValue: "Group run")) {
                VStack(alignment: .leading, spacing: 12) { liveGroupSetup }
                    .padding(.vertical, 6)
            }
            Section(String(localized: "record.environment.title", defaultValue: "Indoor / Outdoor")) {
                Button { model.setup.isIndoorSession = false } label: {
                    setupChoiceRow(title: String(localized: "record.environment.outdoor", defaultValue: "Outdoor"), detail: "", systemImage: "sun.max.fill", isSelected: !model.setup.isIndoorSession)
                }
                Button { model.setup.isIndoorSession = true } label: {
                    setupChoiceRow(title: String(localized: "record.environment.indoor", defaultValue: "Indoor"), detail: "", systemImage: "figure.run.treadmill", isSelected: model.setup.isIndoorSession)
                }
            }
        }
    }

    func setupChoiceRow(title: String, detail: String, systemImage: String, isSelected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage).foregroundStyle(.orange).frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(.primary)
                if !detail.isEmpty { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
            if isSelected { Image(systemName: "checkmark.circle.fill").foregroundStyle(.orange) }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    var musicPlaybackOptions: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(String(localized: "record.music.playback", defaultValue: "Playback"))
                    .font(.subheadline.weight(.semibold))
                Text(model.setup.musicSelectionSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
            }
            HStack(spacing: 8) {
                Toggle(isOn: binding(\.dependencies.musicStore.repeatsQueue)) {
                    Label(String(localized: "record.music.repeat.short", defaultValue: "Repeat"), systemImage: "repeat")
                }
                .accessibilityLabel(String(localized: "record.music.repeat", defaultValue: "Repeat during workout"))
                Toggle(isOn: binding(\.dependencies.musicStore.shufflesQueue)) {
                    Label(String(localized: "record.music.shuffle.short", defaultValue: "Shuffle"), systemImage: "shuffle")
                }
                .accessibilityLabel(String(localized: "record.music.shuffle", defaultValue: "Shuffle songs"))
            }
            .toggleStyle(.button)
            .buttonStyle(.bordered)
            .tint(.orange)
            .font(.caption.weight(.semibold))
        }
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .disabled(!model.setup.musicIsConfigured)
    }

    @ViewBuilder
    var musicSetupCard: some View {
        DisclosureGroup(isExpanded: binding(\.setup.isMusicSetupExpanded)) {
            VStack(alignment: .leading, spacing: 12) {

                if model.dependencies.musicStore.hasDeveloperTokenError {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.slash")
                        .foregroundStyle(.secondary)
                    Text(String(localized: "session.music.unavailable", defaultValue: "Music unavailable"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                } else if let lastErrorMessage = model.dependencies.musicStore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

                if let troubleshootingLine = model.dependencies.musicStore.troubleshootingLine {
                Text(troubleshootingLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

                if model.dependencies.musicStore.canShowQuickPicks, !model.dependencies.musicStore.quickPicks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(model.dependencies.musicStore.quickPicks) { quickPick in
                        Button {
                            model.dependencies.musicStore.selectQuickPick(quickPick)
                            model.track(.init(.musicQuickPickSelected, properties: [.selectionType: .string("quick_pick")]))
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: quickPick.symbolName)
                                    .foregroundStyle(.orange)
                                    .frame(width: 22)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(quickPick.title)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(quickPick.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: model.dependencies.musicStore.selectedQuickPickID == quickPick.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(model.dependencies.musicStore.selectedQuickPickID == quickPick.id ? Color.orange : Color.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(String(localized: "Select \(quickPick.title)"))
                    }
                }
                } else {
                Button {
                    if !model.dependencies.musicStore.isConnected { model.track(.init(.musicAuthorizationRequested)) }
                    Task { await model.dependencies.musicStore.performPrimaryAction() }
                } label: {
                    HStack(spacing: 10) {
                        Text(model.dependencies.musicStore.primaryActionTitle)
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(model.dependencies.musicStore.isPrimaryActionEnabled ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(.plain)
                .disabled(!model.dependencies.musicStore.isPrimaryActionEnabled)
                }
            }
            .padding(.top, 12)
        } label: {
            compactSetupLabel(title: "Music", value: model.dependencies.musicStore.musicSummaryLine, systemImage: "music.note.list")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: model.startSetupCardCornerRadius, style: .continuous))
    }

    func compactSetupLabel(title: String, value: String, systemImage: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage).foregroundStyle(.orange).frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
                Text(value).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
        }
        .contentShape(Rectangle())
    }
}
