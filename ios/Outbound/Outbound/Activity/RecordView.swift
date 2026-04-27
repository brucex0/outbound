import SwiftUI

struct RecordView: View {
    @EnvironmentObject var coachStore: CoachStore
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var coach = VirtualCoach()
    @State private var showCamera = false
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []
    @State private var pendingActivity: PendingFinishedActivity?
    @State private var statusMessage: String?

    init() {
        let loc = LocationManager()
        _recorder = StateObject(wrappedValue: ActivityRecorder(locationManager: loc))
    }

    var body: some View {
        ZStack {
            if showCamera {
                CameraHUDView(
                    recorder: recorder,
                    coach: coach,
                    capturedPhotoCount: capturedPhotos.count,
                    onFinish: finishRecording
                ) { image, meta in
                    capturedPhotos.append((image, meta))
                }
            } else {
                statsView
            }
        }
        .onReceive(recorder.$liveSnapshot) { snapshot in
            coach.ingest(snapshot)
        }
        .sheet(item: $pendingActivity) { activity in
            FinishActivitySheet(
                activity: activity,
                onSave: { savePendingActivity(activity) },
                onDiscard: discardPendingActivity
            )
            .interactiveDismissDisabled()
        }
    }

    private var statsView: some View {
        VStack(spacing: 24) {
            Text(recorder.elapsedSeconds.formatted())
                .font(.system(size: 64, weight: .bold, design: .rounded))

            HStack(spacing: 40) {
                StatBlock(label: "Distance", value: String(format: "%.2f km", recorder.distanceMeters / 1000))
                if let pace = recorder.currentPace {
                    StatBlock(label: "Pace", value: pace.paceString)
                }
            }

            if let nudge = coach.lastNudge.isEmpty ? nil : coach.lastNudge {
                Text(nudge)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }

            if let statusMessage {
                Text(statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            Spacer()

            Button {
                startRecording()
            } label: {
                Label("Start", systemImage: "record.circle.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Capsule().fill(.orange))
                    .foregroundStyle(.white)
            }
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func startRecording() {
        capturedPhotos = []
        pendingActivity = nil
        statusMessage = nil
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
        do {
            let saved = try LocalActivityStore.save(summary: activity.summary, photos: activity.photos)
            statusMessage = "Saved locally: \(saved.durationSecs.formatted()) | \(String(format: "%.2f km", saved.distanceM / 1000))"
            clearPendingActivity()
        } catch {
            statusMessage = "Could not save activity: \(error.localizedDescription)"
        }
    }

    private func discardPendingActivity() {
        statusMessage = "Activity discarded."
        clearPendingActivity()
    }

    private func clearPendingActivity() {
        pendingActivity = nil
        capturedPhotos = []
    }
}

private struct PendingFinishedActivity: Identifiable {
    let id = UUID()
    let summary: ActivitySummary
    let photos: [(UIImage, PhotoMetadata)]
}

private struct FinishActivitySheet: View {
    let activity: PendingFinishedActivity
    let onSave: () -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Finish Activity")
                    .font(.title2.bold())
                Text("Save this run locally or discard it.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 24) {
                StatBlock(label: "Time", value: activity.summary.durationSecs.formatted())
                StatBlock(label: "Distance", value: String(format: "%.2f km", activity.summary.distanceM / 1000))
                StatBlock(label: "Photos", value: "\(activity.photos.count)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 12) {
                Button {
                    onSave()
                } label: {
                    Label("Save Activity", systemImage: "square.and.arrow.down.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)

                Button(role: .destructive) {
                    onDiscard()
                } label: {
                    Label("Discard", systemImage: "trash.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .presentationDetents([.height(330)])
        .presentationDragIndicator(.visible)
    }
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
