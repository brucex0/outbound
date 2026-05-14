import SwiftUI

enum SessionPage: String {
    case camera
    case map
}

struct RecordView: View {
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var coachStore: CoachStore
    @EnvironmentObject var coachCatalog: CoachCatalogStore
    @EnvironmentObject var assistantStore: AssistantStore
    @EnvironmentObject var checkInStore: DailyCheckInStore
    @EnvironmentObject var goalStore: GoalStore
    @EnvironmentObject var musicStore: MusicStore
    @EnvironmentObject var recognitionStore: RecognitionStore
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var coach = VirtualCoach()
    @StateObject private var liveActivityManager = SessionLiveActivityManager()
    @AppStorage("preferred_session_page_v1") private var preferredSessionPageRawValue = SessionPage.camera.rawValue
    @State private var showCamera = false
    @State private var activePage: SessionPage = .camera
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @State private var pendingActivity: PendingFinishedActivity?
    @State private var plannedIntent: SessionIntent?
    @State private var activeIntent: SessionIntent?
    @State private var isAssistantPresented = false
    @State private var selectedGoalMode: SessionGoalMode = .freestyle
    @State private var customDistanceText = ""
    @State private var customTimeText = ""
    @State private var customGoalKind: CustomGoalKind?
    @State private var isCustomGoalAlertPresented = false

    let isVisible: Bool
    private let onCloseRequest: ((Bool) -> Void)?
    private let onSessionStateChange: ((ActivitySessionPortalState) -> Void)?
    private let onElapsedTimeChange: ((Int) -> Void)?

    init(
        initialIntent: SessionIntent? = nil,
        isVisible: Bool = true,
        onCloseRequest: ((Bool) -> Void)? = nil,
        onSessionStateChange: ((ActivitySessionPortalState) -> Void)? = nil,
        onElapsedTimeChange: ((Int) -> Void)? = nil
    ) {
        _plannedIntent = State(initialValue: initialIntent ?? .freestyleRun)
        self.isVisible = isVisible
        self.onCloseRequest = onCloseRequest
        self.onSessionStateChange = onSessionStateChange
        self.onElapsedTimeChange = onElapsedTimeChange
        let loc = LocationManager()
        _recorder = StateObject(wrappedValue: ActivityRecorder(locationManager: loc))
    }

    var body: some View {
        ZStack {
            if showCamera {
                if isVisible {
                    TabView(selection: $activePage) {
                        CameraHUDView(
                            recorder: recorder,
                            coach: coach,
                            musicStore: musicStore,
                            intent: activeIntent ?? plannedIntent,
                            capturedPhotoCount: capturedPhotos.count,
                            lastCapturedPhoto: capturedPhotos.last?.0,
                            activePage: $activePage,
                            onStart: startRecording,
                            onFinish: finishRecording
                        ) { image, meta in
                            capturedPhotos.append((image, meta))
                        }
                        .tag(SessionPage.camera)
                        .ignoresSafeArea()

                        LiveMapView(
                            recorder: recorder,
                            locationManager: recorder.locationManager,
                            coach: coach,
                            musicStore: musicStore,
                            intent: activeIntent ?? plannedIntent,
                            capturedPhotoCount: capturedPhotos.count,
                            lastCapturedPhoto: capturedPhotos.last?.0,
                            activePage: $activePage,
                            onStart: startRecording,
                            onFinish: finishRecording
                        )
                        .tag(SessionPage.map)
                        .ignoresSafeArea()
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                } else {
                    Color.clear
                        .ignoresSafeArea()
                }
            } else {
                readyView
            }
        }
        .background(Color(.systemBackground))
        .ignoresSafeArea()
        .toolbar(showCamera && isVisible ? .hidden : .visible, for: .tabBar)
        .onReceive(recorder.$liveSnapshot) { snapshot in
            coach.ingest(snapshot)
            liveActivityManager.update(
                snapshot: snapshot,
                state: recorder.state,
                intent: activeIntent ?? plannedIntent,
                unitSystem: measurementPreferences.unitSystem
            )
        }
        .onReceive(recorder.$state) { state in
            onSessionStateChange?(ActivitySessionPortalState(recordingState: state))
        }
        .onReceive(recorder.$elapsedSeconds) { elapsedSeconds in
            onElapsedTimeChange?(elapsedSeconds)
        }
        .task {
            await musicStore.refresh()
            await musicStore.loadQuickPicks()
            coach.speechEventHandler = { event in
                Task { await musicStore.handleCoachSpeechEvent(event) }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active, recorder.state == .active else { return }
            Task { await musicStore.retryPendingWorkoutPlaybackIfNeeded() }
        }
        .onChange(of: activePage) { _, newPage in
            guard showCamera else { return }
            preferredSessionPageRawValue = newPage.rawValue
        }
        .overlay(alignment: .topLeading) {
            if isVisible, let onCloseRequest {
                Button {
                    onCloseRequest(recorder.state != .idle || pendingActivity != nil)
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(showCamera ? .white : .primary)
                        .frame(width: 40, height: 40)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .padding(.top, showCamera ? 18 : 14)
                .padding(.leading, 16)
                .accessibilityLabel("Hide activity")
            }
        }
        .overlay(alignment: .topTrailing) {
            if isVisible {
                Button {
                    isAssistantPresented = true
                } label: {
                    Label("Assistant", systemImage: "sparkles")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(showCamera ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                .padding(.top, showCamera ? 18 : 14)
                .padding(.trailing, 16)
                .accessibilityLabel("Open assistant")
            }
        }
        .fullScreenCover(item: $pendingActivity) { activity in
            PostRunSummaryView(
                summary: activity.summary,
                photos: activity.photos,
                reflection: activity.reflection,
                recognitionPreviews: activity.recognitionPreviews,
                onSave: { selectedPhotos, reflection in savePendingActivity(activity, photos: selectedPhotos, reflection: reflection) },
                onDiscard: discardPendingActivity
            )
        }
        .sheet(isPresented: $isAssistantPresented) {
            AssistantView(
                screenName: showCamera ? "Live Recording" : "Record Setup",
                isRecordingActive: recorder.state == .active || recorder.state == .paused
            )
            .presentationDetents([.fraction(0.58), .large])
            .presentationDragIndicator(.visible)
        }
        .alert(customGoalAlertTitle, isPresented: $isCustomGoalAlertPresented) {
            if customGoalKind == .distance {
                TextField("Distance in km", text: $customDistanceText)
                    .keyboardType(.decimalPad)
            } else {
                TextField("Time in minutes", text: $customTimeText)
                    .keyboardType(.numberPad)
            }

            Button("Set") {
                applyCustomGoal()
            }

            Button("Cancel", role: .cancel) {
                customGoalKind = nil
            }
        } message: {
            Text(customGoalAlertMessage)
        }
    }

    private func startRecording() {
        guard recorder.state == .idle else { return }
        capturedPhotos = []
        pendingActivity = nil
        activePage = preferredSessionPage
        activeIntent = plannedIntent
        recorder.locationManager.requestPermission()
        coach.activate(
            with: coachStore.profile,
            persona: coachCatalog.selectedPersona,
            sessionIntent: activeIntent
        )
        recorder.start()
        liveActivityManager.update(
            snapshot: recorder.liveSnapshot,
            state: recorder.state,
            intent: activeIntent,
            unitSystem: measurementPreferences.unitSystem
        )
        Task {
            await musicStore.beginWorkoutPlaybackIfNeeded()
        }
        showCamera = true
    }

    private func finishRecording() {
        let summary = recorder.finish()
        liveActivityManager.end(using: recorder.liveSnapshot, unitSystem: measurementPreferences.unitSystem)
        coach.deactivate()
        musicStore.clearPendingWorkoutPlayback()
        showCamera = false
        let reflection = DailyMotivationEngine.finishReflection(
            summary: summary,
            priorActivities: activityStore.activities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: goalStore.previewProgress(with: summary, activities: activityStore.activities)
        )
        let recognitionPreviews = recognitionStore.previewPostRunRecognition(
            summary: summary,
            priorActivities: activityStore.activities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: goalStore.previewProgress(with: summary, activities: activityStore.activities),
            photoCount: capturedPhotos.count
        )
        pendingActivity = PendingFinishedActivity(
            summary: summary,
            photos: capturedPhotos,
            reflection: reflection,
            recognitionPreviews: recognitionPreviews
        )
    }

    private func savePendingActivity(_ activity: PendingFinishedActivity, photos: [(UIImage, PhotoMetadata)], reflection: FinishReflection) {
        let priorActivities = activityStore.activities
        let previewProgress = goalStore.previewProgress(with: activity.summary, activities: priorActivities)

        guard let savedActivity = try? activityStore.save(
            summary: activity.summary,
            photos: photos,
            reflection: reflection,
            goal: activeIntent?.activityGoal
        ) else {
            return
        }

        _ = recognitionStore.recordSavedActivity(
            savedActivity,
            priorActivities: priorActivities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: previewProgress
        )
        goalStore.refresh(
            activities: activityStore.activities,
            phase: DailyMotivationEngine.phase(for: activityStore.activities)
        )
        clearPending()
        onCloseRequest?(false)
    }

    private func discardPendingActivity() {
        liveActivityManager.end()
        clearPending()
        onCloseRequest?(false)
    }

    private func clearPending() {
        pendingActivity = nil
        capturedPhotos = []
        activeIntent = nil
        plannedIntent = nil
        selectedGoalMode = .freestyle
    }

    private var preferredSessionPage: SessionPage {
        SessionPage(rawValue: preferredSessionPageRawValue) ?? .camera
    }

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 72)
                confirmationView(for: plannedIntent ?? .freestyleRun)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func confirmationView(for intent: SessionIntent) -> some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Text(intent.title)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .multilineTextAlignment(.center)
                Text(intent.detail)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("Coach \(coachCatalog.selectedPersona.template.displayName) says:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("“\(intent.coachLine)”")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            musicSetupCard

            VStack(spacing: 12) {
                sessionGoalCard(for: intent)

                Button(action: startRecording) {
                    Label((plannedIntent ?? intent).startLabel, systemImage: "record.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(.orange))
                        .foregroundStyle(.white)
                }

                Button("Change activity") {
                    onCloseRequest?(false)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            }
        }
    }

    private func sessionGoalCard(for intent: SessionIntent) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Goal", systemImage: "flag")
                    .font(.headline)
                Spacer()
                Text(intent.activityGoal.label(unitSystem: measurementPreferences.unitSystem))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                goalModeButton(.freestyle)
                goalModeButton(.distance)
                goalModeButton(.time)
            }

            switch selectedGoalMode {
            case .freestyle:
                Text("No preset target. Tap Start and move by feel.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            case .distance:
                LazyVGrid(columns: goalPresetColumns, alignment: .leading, spacing: 8) {
                    goalPresetButton(title: "3K", isSelected: isSelectedDistancePreset(3_000)) { applyGoal(.distanceMeters(3_000)) }
                    goalPresetButton(title: "5K", isSelected: isSelectedDistancePreset(5_000)) { applyGoal(.distanceMeters(5_000)) }
                    goalPresetButton(title: "10K", isSelected: isSelectedDistancePreset(10_000)) { applyGoal(.distanceMeters(10_000)) }
                    goalPresetButton(title: "Custom", isSelected: isCustomDistanceSelected) { presentCustomGoal(.distance) }
                }
            case .time:
                LazyVGrid(columns: goalPresetColumns, alignment: .leading, spacing: 8) {
                    goalPresetButton(title: "20 min", isSelected: isSelectedTimePreset(20 * 60)) { applyGoal(.timeSeconds(20 * 60)) }
                    goalPresetButton(title: "30 min", isSelected: isSelectedTimePreset(30 * 60)) { applyGoal(.timeSeconds(30 * 60)) }
                    goalPresetButton(title: "45 min", isSelected: isSelectedTimePreset(45 * 60)) { applyGoal(.timeSeconds(45 * 60)) }
                    goalPresetButton(title: "Custom", isSelected: isCustomTimeSelected) { presentCustomGoal(.time) }
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear {
            selectedGoalMode = SessionGoalMode(goal: intent.activityGoal)
        }
    }

    private var goalPresetColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 76), spacing: 8)]
    }

    private func goalModeButton(_ mode: SessionGoalMode) -> some View {
        Button {
            selectedGoalMode = mode
            if mode == .freestyle {
                applyGoal(.freestyle)
            }
        } label: {
            Text(mode.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(selectedGoalMode == mode ? .white : .primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(
                    Capsule()
                        .fill(selectedGoalMode == mode ? Color.orange : Color(.tertiarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func goalPresetButton(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(isSelected ? .white : .primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var currentActivityGoal: ActivityGoal {
        (plannedIntent ?? .freestyleRun).activityGoal
    }

    private func isSelectedDistancePreset(_ meters: Double) -> Bool {
        guard case .distanceMeters(let selectedMeters) = currentActivityGoal else { return false }
        return abs(selectedMeters - meters) < 1
    }

    private func isSelectedTimePreset(_ seconds: Int) -> Bool {
        guard case .timeSeconds(let selectedSeconds) = currentActivityGoal else { return false }
        return selectedSeconds == seconds
    }

    private var isCustomDistanceSelected: Bool {
        guard case .distanceMeters = currentActivityGoal else { return false }
        return ![3_000, 5_000, 10_000].contains { isSelectedDistancePreset(Double($0)) }
    }

    private var isCustomTimeSelected: Bool {
        guard case .timeSeconds = currentActivityGoal else { return false }
        return ![20 * 60, 30 * 60, 45 * 60].contains { isSelectedTimePreset($0) }
    }

    private func applyGoal(_ goal: ActivityGoal) {
        let currentIntent = plannedIntent ?? .freestyleRun
        plannedIntent = currentIntent.replacingGoal(goal, unitSystem: measurementPreferences.unitSystem)
        selectedGoalMode = SessionGoalMode(goal: goal)
    }

    private func presentCustomGoal(_ kind: CustomGoalKind) {
        customGoalKind = kind
        switch kind {
        case .distance:
            customDistanceText = ""
        case .time:
            customTimeText = ""
        }
        isCustomGoalAlertPresented = true
    }

    private func applyCustomGoal() {
        switch customGoalKind {
        case .distance:
            let value = Double(customDistanceText.replacingOccurrences(of: ",", with: ".")) ?? 0
            guard value > 0 else { return }
            applyGoal(.distanceMeters(value * 1000))
        case .time:
            let minutes = Int(customTimeText) ?? 0
            guard minutes > 0 else { return }
            applyGoal(.timeSeconds(minutes * 60))
        case .none:
            return
        }
        customGoalKind = nil
    }

    private var customGoalAlertTitle: String {
        customGoalKind == .distance ? "Custom distance" : "Custom time"
    }

    private var customGoalAlertMessage: String {
        customGoalKind == .distance ? "Enter kilometers for this activity." : "Enter minutes for this activity."
    }

    @ViewBuilder
    private var musicSetupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Music", systemImage: "music.note.list")
                    .font(.headline)
                Spacer()
                if musicStore.isRefreshing || musicStore.isLoadingQuickPicks {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            Text(musicStore.musicSummaryLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if musicStore.hasDeveloperTokenError {
                HStack(spacing: 10) {
                    Image(systemName: "music.note.slash")
                        .foregroundStyle(.secondary)
                    Text("Music unavailable")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
            } else if let lastErrorMessage = musicStore.lastErrorMessage {
                Text(lastErrorMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            if let troubleshootingLine = musicStore.troubleshootingLine {
                Text(troubleshootingLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if musicStore.canShowQuickPicks, !musicStore.quickPicks.isEmpty {
                VStack(spacing: 10) {
                    ForEach(musicStore.quickPicks) { quickPick in
                        Button {
                            musicStore.selectQuickPick(quickPick)
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
                                Image(systemName: musicStore.selectedQuickPickID == quickPick.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(musicStore.selectedQuickPickID == quickPick.id ? Color.orange : Color.secondary)
                            }
                            .padding(.horizontal, 14)
                            .padding(.vertical, 12)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Select \(quickPick.title)")
                    }
                }
            } else {
                Button {
                    Task { await musicStore.performPrimaryAction() }
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
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}

private struct PendingFinishedActivity: Identifiable {
    let id = UUID()
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
    let recognitionPreviews: [RecognitionPreview]
}

struct StatBlock: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value).font(.title2.bold())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

private enum SessionGoalMode: Equatable {
    case freestyle
    case distance
    case time

    init(goal: ActivityGoal) {
        switch goal {
        case .freestyle:
            self = .freestyle
        case .distanceMeters:
            self = .distance
        case .timeSeconds:
            self = .time
        }
    }

    var title: String {
        switch self {
        case .freestyle:
            return "Freestyle"
        case .distance:
            return "Distance"
        case .time:
            return "Time"
        }
    }
}

private enum CustomGoalKind: Equatable {
    case distance
    case time
}
