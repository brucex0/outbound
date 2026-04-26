import SwiftUI

struct RecordView: View {
    @EnvironmentObject var coachStore: CoachStore
    @StateObject private var locationManager = LocationManager()
    @StateObject private var recorder: ActivityRecorder
    @StateObject private var coach = VirtualCoach()
    @State private var isRecording = false
    @State private var showCamera = false
    @State private var capturedPhotos: [(UIImage, PhotoMetadata)] = []

    init() {
        let loc = LocationManager()
        _recorder = StateObject(wrappedValue: ActivityRecorder(locationManager: loc))
    }

    var body: some View {
        ZStack {
            if showCamera {
                CameraHUDView(recorder: recorder, coach: coach) { image, meta in
                    capturedPhotos.append((image, meta))
                }
            } else {
                statsView
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .coachNudgeRequested)) { _ in
            coach.nudge(
                elapsedSecs: recorder.elapsedSeconds,
                distanceKm: recorder.distanceMeters / 1000,
                paceSecs: recorder.currentPace
            )
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

            Spacer()

            HStack(spacing: 20) {
                Button {
                    showCamera = true
                } label: {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .padding(16)
                        .background(Circle().fill(.secondary.opacity(0.2)))
                }

                Button {
                    if isRecording { stopRecording() } else { startRecording() }
                } label: {
                    Text(isRecording ? "Finish" : "Start")
                        .font(.headline)
                        .frame(width: 120, height: 56)
                        .background(Capsule().fill(isRecording ? .red : .orange))
                        .foregroundStyle(.white)
                }
            }
            .padding(.bottom, 40)
        }
        .padding()
    }

    private func startRecording() {
        isRecording = true
        recorder.start()
        if let profile = coachStore.profile {
            coach.activate(with: profile)
        }
    }

    private func stopRecording() {
        isRecording = false
        let summary = recorder.finish()
        coach.deactivate()
        // TODO: upload summary + photos to backend
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
