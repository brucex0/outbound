import SwiftUI
import AVFoundation
import CoreLocation

// Full-screen camera with transparent running stats overlay.
// The camera stays live throughout the activity — tap shutter to capture a
// photo tagged with current pace, HR, distance and GPS coords.
struct CameraHUDView: View {
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var coach: VirtualCoach
    let capturedPhotoCount: Int
    let onFinish: () -> Void
    let onCapture: (UIImage, PhotoMetadata) -> Void

    @StateObject private var camera = CameraController()
    @State private var showFlash = false
    private let statColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewLayer(session: camera.session)
                .ignoresSafeArea()

            if showFlash {
                Color.white.opacity(0.6).ignoresSafeArea()
                    .transition(.opacity)
            }

            if camera.authorizationStatus == .denied || camera.authorizationStatus == .restricted {
                cameraPermissionMessage
            }

            bottomDataOverlay
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var bottomDataOverlay: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !coach.lastNudge.isEmpty {
                Text(coach.lastNudge)
                    .font(.caption)
                    .foregroundStyle(.white)
                    .lineLimit(3)
            }

            LazyVGrid(columns: statColumns, alignment: .leading, spacing: 10) {
                CameraStatTile(icon: "timer", label: "Time", value: recorder.elapsedSeconds.formatted())
                CameraStatTile(icon: "figure.run", label: "Distance", value: String(format: "%.2f km", recorder.distanceMeters / 1000))
                CameraStatTile(icon: "speedometer", label: "Pace", value: recorder.currentPace?.paceString ?? "-- /km")
                CameraStatTile(icon: "heart.fill", label: "Heart Rate", value: recorder.heartRate.map { "\($0) bpm" } ?? "-- bpm")
            }

            HStack(alignment: .center) {
                Button {
                    onFinish()
                } label: {
                    Label("Finish", systemImage: "stop.fill")
                        .font(.headline)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(.red))
                        .foregroundStyle(.white)
                }

                Spacer()

                ShutterButton {
                    capturePhoto()
                }

                Spacer()

                Label("\(capturedPhotoCount)", systemImage: "photo.on.rectangle")
                    .font(.headline.monospacedDigit())
                    .frame(minWidth: 78, alignment: .trailing)
                    .foregroundStyle(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.52))
        .accessibilityIdentifier("CameraDataOverlay")
    }

    private var cameraPermissionMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text("Camera access is off")
                .font(.headline)
            Text("Enable Camera for Outbound in Settings to record with the live preview.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .padding()
        .foregroundStyle(.white)
        .background(.black.opacity(0.65))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func capturePhoto() {
        camera.capturePhoto { image in
            DispatchQueue.main.async {
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
}

struct CameraStatTile: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .frame(width: 16)
                .foregroundStyle(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.68))
                Text(value)
                    .font(.system(.callout, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
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
        .accessibilityLabel("Capture Photo")
    }
}

struct PhotoMetadata {
    let takenAt: Date
    let paceAtShot: Double?
    let hrAtShot: Int?
    let distAtShot: Double
    let coordinate: CLLocationCoordinate2D?
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
