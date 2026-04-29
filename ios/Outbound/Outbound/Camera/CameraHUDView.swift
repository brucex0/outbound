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
    let lastCapturedPhoto: UIImage?
    @Binding var activePage: SessionPage
    let onFinish: () -> Void
    let onCapture: (UIImage, PhotoMetadata) -> Void

    @StateObject private var camera = CameraController()
    @State private var showFlash = false
    @State private var optimisticCapturedPhoto: UIImage?
    @State private var showCaptureSuccess = false
    @State private var captureSuccessID = 0
    @State private var flyingCapturedPhoto: UIImage?
    @State private var captureFlightProgress: CGFloat = 1
    @State private var captureFlightID = 0
    @State private var shutterFrame: CGRect = .zero
    @State private var photoStackFrame: CGRect = .zero
    private let statColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 2)
    private let coordinateSpaceName = "CameraHUDCoordinateSpace"
    private var displayPhoto: UIImage? { lastCapturedPhoto ?? optimisticCapturedPhoto }
    private var displayPhotoCount: Int {
        if capturedPhotoCount > 0 { return capturedPhotoCount }
        return optimisticCapturedPhoto == nil ? 0 : 1
    }

    var body: some View {
        GeometryReader { geometry in
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

                if let flyingCapturedPhoto {
                    CaptureFlightThumbnail(
                        image: flyingCapturedPhoto,
                        progress: captureFlightProgress
                    )
                    .position(captureFlightPosition(in: geometry.size))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .coordinateSpace(name: coordinateSpaceName)
        }
        .onPreferenceChange(ShutterFramePreferenceKey.self) { shutterFrame = $0 }
        .onPreferenceChange(PhotoStackFramePreferenceKey.self) { photoStackFrame = $0 }
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

            if recorder.state == .paused {
                pausedPill
            }

            activityStatsRow

            HStack(alignment: .center) {
                Button {
                    onFinish()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(.red))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel("Finish")

                Button(action: togglePauseResume) {
                    Image(systemName: recorder.state == .paused ? "play.fill" : "pause.fill")
                        .font(.title3.weight(.semibold))
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(.white.opacity(0.2)))
                        .foregroundStyle(.white)
                }
                .accessibilityLabel(recorder.state == .paused ? "Resume" : "Pause")

                Spacer()

                ShutterButton {
                    capturePhoto()
                }
                .disabled(recorder.state == .paused)
                .opacity(recorder.state == .paused ? 0.55 : 1)
                .readFrame(in: coordinateSpaceName, key: ShutterFramePreferenceKey.self)

                Spacer()

                Button { activePage = .map } label: {
                    Image(systemName: "map.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 58, height: 58)
                        .background(Circle().fill(.white.opacity(0.2)))
                }
                .accessibilityLabel("Show Map")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 16)
        .padding(.bottom, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.black.opacity(0.52))
        .accessibilityIdentifier("CameraDataOverlay")
    }

    private var pausedPill: some View {
        Label("Paused", systemImage: "pause.circle.fill")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(.yellow.opacity(0.22)))
            .foregroundStyle(.yellow)
    }

    private var activityStatsRow: some View {
        ZStack(alignment: .topTrailing) {
            LazyVGrid(columns: statColumns, alignment: .leading, spacing: 10) {
                CameraStatTile(icon: "timer", label: "Time", value: recorder.elapsedSeconds.formatted())
                CameraStatTile(icon: "figure.run", label: "Distance", value: String(format: "%.2f km", recorder.distanceMeters / 1000))
                CameraStatTile(icon: "speedometer", label: "Pace", value: recorder.currentPace?.paceString ?? "-- /km")
                CameraStatTile(icon: "heart.fill", label: "Heart Rate", value: recorder.heartRate.map { "\($0) bpm" } ?? "-- bpm")
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            CapturedPhotoStackView(
                image: displayPhoto,
                count: displayPhotoCount,
                isConfirming: showCaptureSuccess
            )
            .readFrame(in: coordinateSpaceName, key: PhotoStackFramePreferenceKey.self)
        }
        .frame(maxWidth: .infinity, minHeight: 98, alignment: .topLeading)
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
                optimisticCapturedPhoto = image
                startCaptureFlight(with: image)

                withAnimation(.easeOut(duration: 0.1)) { showFlash = true }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    withAnimation { showFlash = false }
                }

                withAnimation(.spring(response: 0.28, dampingFraction: 0.58)) {
                    captureSuccessID += 1
                    showCaptureSuccess = true
                }
                let successID = captureSuccessID
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.85) {
                    guard successID == captureSuccessID else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        showCaptureSuccess = false
                    }
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

    private func togglePauseResume() {
        switch recorder.state {
        case .active:
            recorder.pause()
        case .paused:
            recorder.resume()
        case .idle:
            break
        }
    }

    private func startCaptureFlight(with image: UIImage) {
        captureFlightID += 1
        let flightID = captureFlightID
        captureFlightProgress = 0
        flyingCapturedPhoto = image

        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.55, dampingFraction: 0.82)) {
                captureFlightProgress = 1
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
            guard flightID == captureFlightID else { return }
            flyingCapturedPhoto = nil
            captureFlightProgress = 1
        }
    }

    private func captureFlightPosition(in size: CGSize) -> CGPoint {
        let fallbackY = max(size.height - 62, 72)
        let start = shutterFrame.isEmpty
            ? CGPoint(x: size.width / 2, y: fallbackY)
            : CGPoint(x: shutterFrame.midX, y: shutterFrame.midY)
        let end = photoStackFrame.isEmpty
            ? CGPoint(x: max(size.width - 54, 58), y: max(size.height - 190, 72))
            : CGPoint(x: photoStackFrame.midX, y: photoStackFrame.midY)
        return CGPoint(
            x: start.x + (end.x - start.x) * captureFlightProgress,
            y: start.y + (end.y - start.y) * captureFlightProgress
        )
    }
}

private struct ShutterFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private struct PhotoStackFramePreferenceKey: PreferenceKey {
    static var defaultValue: CGRect = .zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        value = nextValue()
    }
}

private extension View {
    func readFrame<Key: PreferenceKey>(in coordinateSpaceName: String, key: Key.Type) -> some View where Key.Value == CGRect {
        background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: key,
                    value: proxy.frame(in: .named(coordinateSpaceName))
                )
            }
        }
    }
}

struct CapturedPhotoStackView: View {
    let image: UIImage?
    let count: Int
    let isConfirming: Bool

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if count > 1 {
                Circle()
                    .fill(.white.opacity(0.22))
                    .frame(width: 72, height: 72)
                    .offset(x: -16, y: 16)

                Circle()
                    .fill(.white.opacity(0.36))
                    .frame(width: 76, height: 76)
                    .offset(x: -8, y: 8)
            }

            thumbnail
                .scaleEffect(isConfirming ? 1.08 : 1)
                .overlay(alignment: .center) {
                    if isConfirming && count > 0 {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .transition(.scale.combined(with: .opacity))
                    }
                }

            if count > 1 {
                Text("\(count)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(.orange))
                    .offset(x: 6, y: -6)
            }
        }
        .frame(width: 104, height: 98, alignment: .topTrailing)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: count)
        .animation(.spring(response: 0.28, dampingFraction: 0.72), value: image == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(photoStackAccessibilityLabel)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image, count > 0 {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 81, height: 81)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.85), lineWidth: 2)
                }
                .shadow(color: .black.opacity(0.35), radius: 8, y: 4)
        } else {
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 81, height: 81)
                .overlay {
                    Image(systemName: "photo.on.rectangle")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.75))
                }
                .overlay {
                    Circle()
                        .stroke(.white.opacity(0.34), lineWidth: 1)
                }
        }
    }

    private var photoStackAccessibilityLabel: String {
        guard count > 0 else { return "No photos captured" }
        return count == 1 ? "1 photo captured" : "\(count) photos captured"
    }
}

private struct CaptureFlightThumbnail: View {
    let image: UIImage
    let progress: CGFloat

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 2)
            }
            .shadow(color: .black.opacity(0.35), radius: 12, y: 5)
            .rotationEffect(.degrees(Double(1 - progress) * -4))
            .opacity(opacity)
    }

    private var size: CGFloat {
        120 - progress * 39
    }

    private var opacity: Double {
        guard progress > 0.82 else { return 1 }
        return max(0, Double((1 - progress) / 0.18))
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
