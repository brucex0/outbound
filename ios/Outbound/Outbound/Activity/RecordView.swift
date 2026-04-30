import SwiftUI

enum SessionPage { case camera, map }

struct RecordView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var coachStore: CoachStore
    @EnvironmentObject var coachCatalog: CoachCatalogStore
    @EnvironmentObject var checkInStore: DailyCheckInStore
    @Binding private var plannedIntent: SessionIntent?
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var coach = VirtualCoach()
    @State private var showCamera = false
    @State private var activePage: SessionPage = .camera
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @State private var pendingActivity: PendingFinishedActivity?
    @State private var activeIntent: SessionIntent?

    init(plannedIntent: Binding<SessionIntent?> = .constant(nil)) {
        _plannedIntent = plannedIntent
        let loc = LocationManager()
        _recorder = StateObject(wrappedValue: ActivityRecorder(locationManager: loc))
    }

    var body: some View {
        ZStack {
            if showCamera {
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
                readyView
            }
        }
        .toolbar(showCamera ? .hidden : .visible, for: .tabBar)
        .onReceive(recorder.$liveSnapshot) { snapshot in
            coach.ingest(snapshot)
        }
        .fullScreenCover(item: $pendingActivity) { activity in
            PostRunSummaryView(
                summary: activity.summary,
                photos: activity.photos,
                lastNudge: coach.lastNudge,
                reflection: activity.reflection,
                onSave: { saveRoute in savePendingActivity(activity, saveRoute: saveRoute) },
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
            intent: activeIntent
        )
        pendingActivity = PendingFinishedActivity(
            summary: summary,
            photos: capturedPhotos,
            reflection: reflection
        )
    }

    private func savePendingActivity(_ activity: PendingFinishedActivity, saveRoute: Bool) {
        _ = try? activityStore.save(
            summary: activity.summary,
            photos: activity.photos,
            lastNudge: coach.lastNudge,
            saveRoute: saveRoute
        )
        clearPending()
    }

    private func discardPendingActivity() {
        clearPending()
    }

    private func clearPending() {
        pendingActivity = nil
        capturedPhotos = []
        activeIntent = nil
        plannedIntent = nil
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()

            if let plannedIntent {
                VStack(spacing: 20) {
                    VStack(spacing: 8) {
                        Text(plannedIntent.title)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .multilineTextAlignment(.center)
                        Text(plannedIntent.detail)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Coach \(coachCatalog.selectedPersona.template.displayName) says:")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text("“\(plannedIntent.coachLine)”")
                            .font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                }
            } else {
                VStack(spacing: 8) {
                    Text(recorder.elapsedSeconds.formatted())
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    HStack(spacing: 40) {
                        StatBlock(
                            label: "Distance",
                            value: String(format: "%.2f km", recorder.distanceMeters / 1000)
                        )
                        if let pace = recorder.currentPace {
                            StatBlock(label: "Pace", value: pace.paceString)
                        }
                    }
                }

                if !coach.lastNudge.isEmpty {
                    Text(coach.lastNudge)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }
            }

            Spacer()

            VStack(spacing: 12) {
                Button(action: startRecording) {
                    Label(plannedIntent?.startLabel ?? "Start Run", systemImage: "record.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(Capsule().fill(.orange))
                        .foregroundStyle(.white)
                }

                if plannedIntent != nil {
                    Button("Change activity") {
                        plannedIntent = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .padding()
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
