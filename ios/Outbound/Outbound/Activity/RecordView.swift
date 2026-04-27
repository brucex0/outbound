import SwiftUI

enum SessionPage { case camera, map }

struct RecordView: View {
    @EnvironmentObject var activityStore: ActivityStore
    @EnvironmentObject var coachStore: CoachStore
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var coach = VirtualCoach()
    @State private var showCamera = false
    @State private var activePage: SessionPage = .camera
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @State private var pendingActivity: PendingFinishedActivity?

    init() {
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
                        activePage: $activePage,
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
                        activePage: $activePage,
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
                onSave: { savePendingActivity(activity) },
                onDiscard: discardPendingActivity
            )
        }
    }

    private var readyView: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text(recorder.elapsedSeconds.formatted())
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .monospacedDigit()

                HStack(spacing: 40) {
                    StatBlock(label: "Distance",
                              value: String(format: "%.2f km", recorder.distanceMeters / 1000))
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

            Spacer()

            Button(action: startRecording) {
                Label("Start Run", systemImage: "record.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(.orange))
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func startRecording() {
        capturedPhotos = []
        pendingActivity = nil
        activePage = .camera
        recorder.locationManager.requestPermission()
        coach.activate(with: coachStore.profile)
        recorder.start()
        showCamera = true
    }

    private func finishRecording() {
        let summary = recorder.finish()
        coach.deactivate()
        showCamera = false
        pendingActivity = PendingFinishedActivity(summary: summary, photos: capturedPhotos)
    }

    private func savePendingActivity(_ activity: PendingFinishedActivity) {
        try? activityStore.save(
            summary: activity.summary,
            photos: activity.photos,
            lastNudge: coach.lastNudge
        )
        clearPending()
    }

    private func discardPendingActivity() {
        clearPending()
    }

    private func clearPending() {
        pendingActivity = nil
        capturedPhotos = []
    }
}

private struct PendingFinishedActivity: Identifiable {
    let id = UUID()
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
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
