import SwiftUI
import AVFoundation

// Full-screen camera with transparent running stats overlay.
// The camera stays live throughout the activity — tap shutter to capture a
// photo tagged with current pace, HR, distance and GPS coords.
struct CameraHUDView: View {
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var coach: VirtualCoach
    let onCapture: (UIImage, PhotoMetadata) -> Void

    @StateObject private var camera = CameraController()
    @State private var lastCaptured: UIImage?
    @State private var showFlash = false

    var body: some View {
        ZStack {
            // Live camera feed — full screen
            CameraPreviewLayer(session: camera.session)
                .ignoresSafeArea()

            // Flash effect on capture
            if showFlash {
                Color.white.opacity(0.6).ignoresSafeArea()
                    .transition(.opacity)
            }

            VStack {
                // Top HUD — elapsed time + distance
                HStack {
                    StatPill(icon: "timer", value: recorder.elapsedSeconds.formatted())
                    Spacer()
                    StatPill(icon: "figure.run", value: String(format: "%.2f km", recorder.distanceMeters / 1000))
                }
                .padding(.horizontal, 20)
                .padding(.top, 60)

                Spacer()

                // Bottom HUD — pace + shutter
                HStack(alignment: .center) {
                    if let pace = recorder.currentPace {
                        StatPill(icon: "speedometer", value: pace.paceString)
                    }
                    Spacer()
                    ShutterButton {
                        capturePhoto()
                    }
                    Spacer()
                    if let hr = recorder.heartRate {
                        StatPill(icon: "heart.fill", value: "\(hr) bpm")
                            .foregroundStyle(.red)
                    } else {
                        Color.clear.frame(width: 80)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 40)
            }

            // Coach nudge banner
            if !coach.lastNudge.isEmpty {
                VStack {
                    Spacer()
                    Text(coach.lastNudge)
                        .font(.caption)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .padding()
                        .padding(.bottom, 110)
                }
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private func capturePhoto() {
        camera.capturePhoto { image in
            guard let image else { return }
            withAnimation(.easeOut(duration: 0.1)) { showFlash = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                withAnimation { showFlash = false }
            }
            let meta = PhotoMetadata(
                takenAt: Date(),
                paceAtShot: recorder.currentPace,
                hrAtShot: recorder.heartRate,
                distAtShot: recorder.distanceMeters,
                coordinate: recorder.locationManager.location?.coordinate
            )
            onCapture(image, meta)
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String

    var body: some View {
        Label(value, systemImage: icon)
            .font(.system(.caption, design: .rounded, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
            .foregroundStyle(.white)
    }
}

struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().fill(.white).frame(width: 70, height: 70)
                Circle().stroke(.white.opacity(0.4), lineWidth: 4).frame(width: 80, height: 80)
            }
        }
    }
}

struct PhotoMetadata {
    let takenAt: Date
    let paceAtShot: Double?
    let hrAtShot: Int?
    let distAtShot: Double
    let coordinate: (any Any)?
}

extension Double {
    var paceString: String {
        let m = Int(self) / 60
        let s = Int(self) % 60
        return String(format: "%d:%02d /km", m, s)
    }
}

extension Int {
    func formatted() -> String {
        let h = self / 3600
        let m = (self % 3600) / 60
        let s = self % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
