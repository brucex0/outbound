import SwiftUI

enum SessionPage { case camera, map }

struct RecordView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var coachStore: CoachStore
    @EnvironmentObject var coachCatalog: CoachCatalogStore
    @EnvironmentObject var checkInStore: DailyCheckInStore
    @EnvironmentObject var goalStore: GoalStore
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var coach = VirtualCoach()
    @State private var showCamera = false
    @State private var activePage: SessionPage = .camera
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @State private var pendingActivity: PendingFinishedActivity?
    @State private var plannedIntent: SessionIntent?
    @State private var activeIntent: SessionIntent?
    @State private var hasAttemptedAutoStart = false

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
        _plannedIntent = State(initialValue: initialIntent)
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
        }
        .onReceive(recorder.$state) { state in
            onSessionStateChange?(ActivitySessionPortalState(recordingState: state))
        }
        .onReceive(recorder.$elapsedSeconds) { elapsedSeconds in
            onElapsedTimeChange?(elapsedSeconds)
        }
        .onAppear {
            guard plannedIntent == nil, !hasAttemptedAutoStart else { return }
            hasAttemptedAutoStart = true
            startRecording()
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
        .fullScreenCover(item: $pendingActivity) { activity in
            PostRunSummaryView(
                summary: activity.summary,
                photos: activity.photos,
                lastNudge: coach.lastNudge,
                reflection: activity.reflection,
                onSave: { savePendingActivity(activity) },
                onDiscard: discardPendingActivity
            )
        }
    }

    private func startRecording() {
        guard recorder.state == .idle else { return }
        capturedPhotos = []
        pendingActivity = nil
        activePage = .camera
        activeIntent = plannedIntent
        recorder.locationManager.requestPermission()
        coach.activate(
            with: coachStore.profile,
            persona: coachCatalog.selectedPersona,
            sessionIntent: activeIntent
        )
        recorder.start()
        showCamera = true
    }

    private func finishRecording() {
        let summary = recorder.finish()
        coach.deactivate()
        showCamera = false
        activePage = .camera
        let reflection = DailyMotivationEngine.finishReflection(
            summary: summary,
            priorActivities: activityStore.activities,
            readiness: checkInStore.readiness,
            intent: activeIntent,
            goalProgress: goalStore.previewProgress(with: summary, activities: activityStore.activities)
        )
        pendingActivity = PendingFinishedActivity(
            summary: summary,
            photos: capturedPhotos,
            reflection: reflection
        )
    }

    private func savePendingActivity(_ activity: PendingFinishedActivity) {
        _ = try? activityStore.save(
            summary: activity.summary,
            photos: activity.photos,
            lastNudge: coach.lastNudge
        )
        goalStore.refresh(
            activities: activityStore.activities,
            phase: DailyMotivationEngine.phase(for: activityStore.activities)
        )
        clearPending()
        onCloseRequest?(false)
    }

    private func discardPendingActivity() {
        clearPending()
        onCloseRequest?(false)
    }

    private func clearPending() {
        pendingActivity = nil
        capturedPhotos = []
        activeIntent = nil
        plannedIntent = nil
    }

    private var readyView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 72)
                if let plannedIntent {
                    confirmationView(for: plannedIntent)
                } else {
                    autoStartView
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private var autoStartView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.orange)
            Text("Opening activity…")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 240)
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

            VStack(spacing: 12) {
                Button(action: startRecording) {
                    Label(intent.startLabel, systemImage: "record.circle.fill")
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
}

private struct PendingFinishedActivity: Identifiable {
    let id = UUID()
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
    let reflection: FinishReflection
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
