import SwiftUI

enum SessionPage: String {
    case camera
    case map
}

struct RecordView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
    @State private var countdownStep: ActivityStartCountdownStep?
    @State private var countdownTask: Task<Void, Never>?
    @State private var didApplySmartGoalDefault = false

    let isVisible: Bool
    private let shouldApplySmartGoalDefault: Bool
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
        self.shouldApplySmartGoalDefault = initialIntent == nil
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
        .overlay {
            if let countdownStep {
                ActivityStartCountdownOverlay(step: countdownStep, reduceMotion: reduceMotion)
                    .transition(.opacity)
            }
        }
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
        .onDisappear {
            cancelStartCountdown(returnToSetup: recorder.state == .idle)
        }
        .overlay(alignment: .topLeading) {
            if isVisible, let onCloseRequest {
                Button {
                    if isCountingDown {
                        cancelStartCountdown(returnToSetup: true)
                    } else {
                        onCloseRequest(recorder.state != .idle || pendingActivity != nil)
                    }
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
        guard recorder.state == .idle, !isCountingDown else { return }
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
        showCamera = true
        beginStartCountdown()
    }

    private func beginStartCountdown() {
        countdownTask?.cancel()
        countdownTask = Task { @MainActor in
            for step in ActivityStartCountdownStep.sequence {
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: reduceMotion ? 0.12 : 0.22)) {
                    countdownStep = step
                }
                announceCountdownStep(step)

                do {
                    try await Task.sleep(nanoseconds: step.durationNanoseconds)
                } catch {
                    return
                }
            }

            guard !Task.isCancelled else { return }
            completeStartCountdown()
        }
    }

    private func announceCountdownStep(_ step: ActivityStartCountdownStep) {
        coach.announceStartCountdown(step.spokenText)
        #if os(iOS)
        UIAccessibility.post(notification: .announcement, argument: step.accessibilityText)
        switch step {
        case .go:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        case .three, .two, .one:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        #endif
    }

    private func completeStartCountdown() {
        guard recorder.state == .idle else {
            countdownStep = nil
            countdownTask = nil
            return
        }

        countdownStep = nil
        countdownTask = nil
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
    }

    private func cancelStartCountdown(returnToSetup: Bool) {
        guard isCountingDown else { return }
        countdownTask?.cancel()
        countdownTask = nil
        countdownStep = nil
        coach.deactivate()
        activeIntent = nil
        if returnToSetup {
            showCamera = false
        }
    }

    private var isCountingDown: Bool {
        countdownStep != nil || countdownTask != nil
    }

    private func finishRecording() {
        cancelStartCountdown(returnToSetup: true)
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
        cancelStartCountdown(returnToSetup: true)
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
            VStack(spacing: 20) {
                Spacer(minLength: 92)
                confirmationView(for: plannedIntent ?? .freestyleRun)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 36)
        }
        .onAppear(perform: applySmartGoalDefaultIfNeeded)
    }

    private func confirmationView(for intent: SessionIntent) -> some View {
        VStack(spacing: 20) {
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

            VStack(alignment: .leading, spacing: 14) {
                Text("Coach \(coachCatalog.selectedPersona.template.displayName) says:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("“\(intent.coachLine)”")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))

            musicSetupCard

            VStack(spacing: 14) {
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
        VStack(alignment: .leading, spacing: 16) {
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
                GoalPresetFlow(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(distanceGoalPresets) { preset in
                        goalPresetButton(title: preset.title, isSelected: isSelectedDistancePreset(preset.meters)) {
                            applyGoal(.distanceMeters(preset.meters))
                        }
                    }
                    goalPresetButton(title: "Custom", isSelected: isCustomDistanceSelected) { presentCustomGoal(.distance) }
                }
            case .time:
                GoalPresetFlow(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(timeGoalPresets) { preset in
                        goalPresetButton(title: preset.title, isSelected: isSelectedTimePreset(preset.seconds)) {
                            applyGoal(.timeSeconds(preset.seconds))
                        }
                    }
                    goalPresetButton(title: "Custom", isSelected: isCustomTimeSelected) { presentCustomGoal(.time) }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
        .onAppear {
            selectedGoalMode = SessionGoalMode(goal: intent.activityGoal)
        }
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
                .lineLimit(1)
                .minimumScaleFactor(0.82)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }
            .padding(.horizontal, isSelected ? 18 : 20)
            .frame(height: 40)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(isSelected ? Color.orange : Color(.tertiarySystemBackground), in: Capsule())
            .fixedSize(horizontal: true, vertical: false)
        }
        .buttonStyle(.plain)
    }

    private var currentActivityGoal: ActivityGoal {
        (plannedIntent ?? .freestyleRun).activityGoal
    }

    private var distanceGoalPresets: [DistanceGoalPreset] {
        DistanceGoalPreset.recommended(from: activityStore.activities)
    }

    private var timeGoalPresets: [TimeGoalPreset] {
        TimeGoalPreset.recommended(from: activityStore.activities)
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
        return !distanceGoalPresets.contains { isSelectedDistancePreset($0.meters) }
    }

    private var isCustomTimeSelected: Bool {
        guard case .timeSeconds = currentActivityGoal else { return false }
        return !timeGoalPresets.contains { isSelectedTimePreset($0.seconds) }
    }

    private func applyGoal(_ goal: ActivityGoal) {
        let currentIntent = plannedIntent ?? .freestyleRun
        plannedIntent = currentIntent.replacingGoal(goal, unitSystem: measurementPreferences.unitSystem)
        selectedGoalMode = SessionGoalMode(goal: goal)
    }

    private func applySmartGoalDefaultIfNeeded() {
        guard shouldApplySmartGoalDefault, !didApplySmartGoalDefault else { return }
        didApplySmartGoalDefault = true
        guard currentActivityGoal.isFreestyle,
              let preferredGoal = SmartGoalPreference.preferredFrequentCustomGoal(from: activityStore.activities) else {
            return
        }
        applyGoal(preferredGoal)
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
        VStack(alignment: .leading, spacing: 12) {
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
                    HStack(spacing: 10) {
                        Text(musicStore.primaryActionTitle)
                            .font(.subheadline.bold())
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(musicStore.isPrimaryActionEnabled ? Color.orange : Color.secondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                }
                .buttonStyle(.plain)
                .disabled(!musicStore.isPrimaryActionEnabled)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: startSetupCardCornerRadius, style: .continuous))
    }

    private var startSetupCardCornerRadius: CGFloat { 20 }
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

private enum ActivityStartCountdownStep: CaseIterable, Equatable {
    case three
    case two
    case one
    case go

    static let sequence: [ActivityStartCountdownStep] = [.three, .two, .one, .go]

    var displayText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return "Go"
        }
    }

    var spokenText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return "Go"
        }
    }

    var accessibilityText: String {
        switch self {
        case .three:
            return "3"
        case .two:
            return "2"
        case .one:
            return "1"
        case .go:
            return "Go"
        }
    }

    var durationNanoseconds: UInt64 {
        switch self {
        case .three, .two, .one:
            return 1_000_000_000
        case .go:
            return 420_000_000
        }
    }

    var progress: CGFloat {
        guard let index = Self.sequence.firstIndex(of: self) else { return 0 }
        return CGFloat(index + 1) / CGFloat(Self.sequence.count)
    }
}

private struct ActivityStartCountdownOverlay: View {
    let step: ActivityStartCountdownStep
    let reduceMotion: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.black.opacity(0.42))
                .ignoresSafeArea()

            VStack(spacing: 20) {
                ZStack {
                    Circle()
                        .stroke(.white.opacity(0.2), lineWidth: 8)
                    Circle()
                        .trim(from: 0, to: step.progress)
                        .stroke(
                            Color.orange,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(step.displayText)
                        .font(.system(size: step == .go ? 76 : 118, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.72)
                        .lineLimit(1)
                        .contentTransition(reduceMotion ? .identity : .numericText())
                        .id(step)
                        .transition(reduceMotion ? .opacity : .scale(scale: 0.86).combined(with: .opacity))
                }
                .frame(width: 188, height: 188)
                .shadow(color: .black.opacity(0.26), radius: 20, y: 8)

                Text("Outbound")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
            }
            .padding(.horizontal, 28)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.accessibilityText)
        }
        .allowsHitTesting(true)
        .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.24), value: step)
    }
}

private struct GoalPresetFlow: Layout {
    let horizontalSpacing: CGFloat
    let verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = arrangedRows(in: maxWidth, subviews: subviews)
        let width = rows.reduce(0) { max($0, $1.width) }
        let height = rows.enumerated().reduce(CGFloat.zero) { total, item in
            total + item.element.height + (item.offset == 0 ? 0 : verticalSpacing)
        }
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = bounds.origin
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let wouldOverflow = origin.x > bounds.minX && origin.x + size.width > bounds.maxX
            if wouldOverflow {
                origin.x = bounds.minX
                origin.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(
                at: CGPoint(x: origin.x, y: origin.y),
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            origin.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }

    private func arrangedRows(in maxWidth: CGFloat, subviews: Subviews) -> [(width: CGFloat, height: CGFloat)] {
        var rows: [(width: CGFloat, height: CGFloat)] = []
        var rowWidth: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let spacing = rowWidth == 0 ? 0 : horizontalSpacing
            let wouldOverflow = rowWidth > 0 && rowWidth + spacing + size.width > maxWidth
            if wouldOverflow {
                rows.append((rowWidth, rowHeight))
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += spacing + size.width
                rowHeight = max(rowHeight, size.height)
            }
        }

        if rowWidth > 0 {
            rows.append((rowWidth, rowHeight))
        }

        return rows
    }
}

private struct SmartGoalPreference {
    let goal: ActivityGoal
    let count: Int
    let firstSeenOrder: Int

    static func preferredFrequentCustomGoal(from activities: [SavedActivity]) -> ActivityGoal? {
        [
            DistanceGoalPreset.preferredFrequentCustom(from: activities),
            TimeGoalPreset.preferredFrequentCustom(from: activities)
        ]
        .compactMap { $0 }
        .sorted { lhs, rhs in
            if lhs.count != rhs.count { return lhs.count > rhs.count }
            return lhs.firstSeenOrder < rhs.firstSeenOrder
        }
        .first?
        .goal
    }
}

private struct DistanceGoalPreset: Identifiable, Hashable {
    let title: String
    let meters: Double

    var id: Int {
        Self.normalizedDistanceKey(meters)
    }

    static func recommended(from activities: [SavedActivity]) -> [DistanceGoalPreset] {
        let stats = distanceStats(from: activities)
        var presets = defaultPresets

        if stats.totalDistanceGoalCount >= matureHistoryCount {
            let usedDefaults = defaultPresets.filter { stats.usageCounts[$0.id, default: 0] > 0 }
            presets = usedDefaults.isEmpty ? Array(defaultPresets.prefix(2)) : usedDefaults
        }

        for custom in frequentCustomPresets(from: stats) where !presets.contains(where: { $0.id == custom.id }) {
            presets.insert(custom, at: 0)
        }

        if presets.count < minimumPresetCount {
            for preset in defaultPresets where !presets.contains(where: { $0.id == preset.id }) {
                presets.append(preset)
                if presets.count == minimumPresetCount { break }
            }
        }

        return Array(presets.prefix(maximumPresetCount))
    }

    static func preferredFrequentCustom(from activities: [SavedActivity]) -> SmartGoalPreference? {
        let stats = distanceStats(from: activities)
        guard let candidate = frequentCustomPresets(from: stats).first else { return nil }
        return SmartGoalPreference(
            goal: .distanceMeters(candidate.meters),
            count: stats.usageCounts[candidate.id, default: 0],
            firstSeenOrder: stats.firstSeenOrder[candidate.id, default: Int.max]
        )
    }

    private static let defaultPresets: [DistanceGoalPreset] = [
        DistanceGoalPreset(title: "5K", meters: 5_000),
        DistanceGoalPreset(title: "10K", meters: 10_000),
        DistanceGoalPreset(title: "Half marathon", meters: 21_097.5),
        DistanceGoalPreset(title: "Marathon", meters: 42_195)
    ]

    private static let frequentCustomUseThreshold = 3
    private static let recentActivityLimit = 30
    private static let matureHistoryCount = 8
    private static let minimumPresetCount = 4
    private static let maximumPresetCount = 6
    private static let distanceBucketMeters = 100.0

    private struct DistanceStats {
        var usageCounts: [Int: Int]
        var firstSeenOrder: [Int: Int]
        var totalDistanceGoalCount: Int
    }

    private static func frequentCustomPresets(from stats: DistanceStats) -> [DistanceGoalPreset] {
        stats.usageCounts
            .filter { key, count in
                count >= frequentCustomUseThreshold && !defaultPresets.contains { $0.id == key }
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return stats.firstSeenOrder[lhs.key, default: Int.max] < stats.firstSeenOrder[rhs.key, default: Int.max]
            }
            .map { key, _ in
                let meters = Double(key) * distanceBucketMeters
                return DistanceGoalPreset(title: label(forMeters: meters), meters: meters)
            }
    }

    private static func distanceStats(from activities: [SavedActivity]) -> DistanceStats {
        var usageCounts: [Int: Int] = [:]
        var firstSeenOrder: [Int: Int] = [:]
        var totalDistanceGoalCount = 0

        for (index, activity) in activities.prefix(recentActivityLimit).enumerated() {
            guard let meters = activity.goal?.targetDistanceMeters, meters >= 1_000 else { continue }
            let key = normalizedDistanceKey(meters)
            usageCounts[key, default: 0] += 1
            firstSeenOrder[key] = min(firstSeenOrder[key, default: index], index)
            totalDistanceGoalCount += 1
        }

        return DistanceStats(
            usageCounts: usageCounts,
            firstSeenOrder: firstSeenOrder,
            totalDistanceGoalCount: totalDistanceGoalCount
        )
    }

    private static func normalizedDistanceKey(_ meters: Double) -> Int {
        Int((meters / distanceBucketMeters).rounded())
    }

    private static func label(forMeters meters: Double) -> String {
        let kilometers = meters / 1000
        if abs(kilometers.rounded() - kilometers) < 0.05 {
            return "\(Int(kilometers.rounded()))K"
        }
        return String(format: "%.1fK", kilometers)
            .replacingOccurrences(of: #"\.0K$"#, with: "K", options: .regularExpression)
    }
}

private struct TimeGoalPreset: Identifiable, Hashable {
    let title: String
    let seconds: Int

    var id: Int {
        Self.normalizedTimeKey(seconds)
    }

    static func recommended(from activities: [SavedActivity]) -> [TimeGoalPreset] {
        let stats = timeStats(from: activities)
        var presets = defaultPresets

        if stats.totalTimeGoalCount >= matureHistoryCount {
            let usedDefaults = defaultPresets.filter { stats.usageCounts[$0.id, default: 0] > 0 }
            presets = usedDefaults.isEmpty ? Array(defaultPresets.prefix(3)) : usedDefaults
        }

        for custom in frequentCustomPresets(from: stats) where !presets.contains(where: { $0.id == custom.id }) {
            presets.insert(custom, at: 0)
        }

        if presets.count < minimumPresetCount {
            for preset in defaultPresets where !presets.contains(where: { $0.id == preset.id }) {
                presets.append(preset)
                if presets.count == minimumPresetCount { break }
            }
        }

        return Array(presets.prefix(maximumPresetCount))
    }

    static func preferredFrequentCustom(from activities: [SavedActivity]) -> SmartGoalPreference? {
        let stats = timeStats(from: activities)
        guard let candidate = frequentCustomPresets(from: stats).first else { return nil }
        return SmartGoalPreference(
            goal: .timeSeconds(candidate.seconds),
            count: stats.usageCounts[candidate.id, default: 0],
            firstSeenOrder: stats.firstSeenOrder[candidate.id, default: Int.max]
        )
    }

    private static let defaultPresets: [TimeGoalPreset] = [
        TimeGoalPreset(title: "20 min", seconds: 20 * 60),
        TimeGoalPreset(title: "30 min", seconds: 30 * 60),
        TimeGoalPreset(title: "45 min", seconds: 45 * 60),
        TimeGoalPreset(title: "1 hr", seconds: 60 * 60),
        TimeGoalPreset(title: "1.5 hr", seconds: 90 * 60)
    ]

    private static let frequentCustomUseThreshold = 3
    private static let recentActivityLimit = 30
    private static let matureHistoryCount = 8
    private static let minimumPresetCount = 4
    private static let maximumPresetCount = 6
    private static let timeBucketSeconds = 60

    private struct TimeStats {
        var usageCounts: [Int: Int]
        var firstSeenOrder: [Int: Int]
        var totalTimeGoalCount: Int
    }

    private static func frequentCustomPresets(from stats: TimeStats) -> [TimeGoalPreset] {
        stats.usageCounts
            .filter { key, count in
                count >= frequentCustomUseThreshold && !defaultPresets.contains { $0.id == key }
            }
            .sorted { lhs, rhs in
                if lhs.value != rhs.value { return lhs.value > rhs.value }
                return stats.firstSeenOrder[lhs.key, default: Int.max] < stats.firstSeenOrder[rhs.key, default: Int.max]
            }
            .map { key, _ in
                let seconds = key * timeBucketSeconds
                return TimeGoalPreset(title: label(forSeconds: seconds), seconds: seconds)
            }
    }

    private static func timeStats(from activities: [SavedActivity]) -> TimeStats {
        var usageCounts: [Int: Int] = [:]
        var firstSeenOrder: [Int: Int] = [:]
        var totalTimeGoalCount = 0

        for (index, activity) in activities.prefix(recentActivityLimit).enumerated() {
            guard let seconds = activity.goal?.targetDurationSeconds, seconds >= timeBucketSeconds else { continue }
            let key = normalizedTimeKey(seconds)
            usageCounts[key, default: 0] += 1
            firstSeenOrder[key] = min(firstSeenOrder[key, default: index], index)
            totalTimeGoalCount += 1
        }

        return TimeStats(
            usageCounts: usageCounts,
            firstSeenOrder: firstSeenOrder,
            totalTimeGoalCount: totalTimeGoalCount
        )
    }

    private static func normalizedTimeKey(_ seconds: Int) -> Int {
        Int((Double(seconds) / Double(timeBucketSeconds)).rounded())
    }

    private static func label(forSeconds seconds: Int) -> String {
        if seconds < 3600 {
            return "\(max(1, seconds / 60)) min"
        }

        let hours = Double(seconds) / 3600
        if abs(hours.rounded() - hours) < 0.01 {
            return "\(Int(hours.rounded())) hr"
        }
        return String(format: "%.1f hr", hours)
            .replacingOccurrences(of: #"\.0 hr$"#, with: " hr", options: .regularExpression)
    }
}
