import SwiftUI
import AVFoundation
import CoreLocation

// Full-screen camera with an always-available shutter, a right-edge utility
// rail, and a bottom session card that carries live workout status plus coach
// motivation while the session is active.
struct CameraHUDView: View {
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var coach: VirtualCoach
    @ObservedObject var musicStore: MusicStore
    let capturedPhotoCount: Int
    let lastCapturedPhoto: UIImage?
    @Binding var activePage: SessionPage
    let onStart: () -> Void
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

    private let coordinateSpaceName = "CameraHUDCoordinateSpace"

    private var displayPhoto: UIImage? { lastCapturedPhoto ?? optimisticCapturedPhoto }

    private var displayPhotoCount: Int {
        if capturedPhotoCount > 0 { return capturedPhotoCount }
        return optimisticCapturedPhoto == nil ? 0 : 1
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                CameraPreviewLayer(session: camera.session)
                    .ignoresSafeArea()

                if showFlash {
                    Color.white.opacity(0.6)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }

                if camera.authorizationStatus == .denied || camera.authorizationStatus == .restricted {
                    cameraPermissionMessage
                }

                VStack(spacing: 12) {
                    Spacer()

                    SessionStatusCard(
                        state: recorder.state,
                        elapsedText: recorder.elapsedSeconds.formatted(),
                        paceLabel: recorder.state == .paused ? "Avg. pace" : "Pace",
                        paceText: sessionPaceText,
                        distanceText: String(format: "%.2f", recorder.distanceMeters / 1000),
                        coachMessage: coachMessage,
                        musicPlayback: musicStore.playback.hasActiveQueue ? musicStore.playback : nil,
                        showsMusicDisabledState: musicStore.hasDeveloperTokenError,
                        musicErrorMessage: musicStore.hasDeveloperTokenError ? nil : musicStore.lastErrorMessage,
                        onTogglePlayback: {
                            Task { await musicStore.togglePlayback() }
                        },
                        onSkipTrack: {
                            Task { await musicStore.skipToNext() }
                        },
                        onStart: onStart,
                        onPause: pauseActivity,
                        onResume: resumeActivity,
                        onFinish: onFinish
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 18)
                }

                VStack {
                    Spacer()

                    HStack {
                        Spacer()

                        rightControlRail
                    }
                    .padding(.trailing, 16)
                    .padding(.bottom, railBottomPadding)
                }

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

    private var coachMessage: String? {
        guard recorder.state != .idle, !coach.lastNudge.isEmpty else { return nil }
        return coach.lastNudge
    }

    private var rightControlRail: some View {
        VStack(spacing: 14) {
            CapturedPhotoStackView(
                image: displayPhoto,
                count: displayPhotoCount,
                isConfirming: showCaptureSuccess
            )
            .readFrame(in: coordinateSpaceName, key: PhotoStackFramePreferenceKey.self)

            Button { activePage = .map } label: {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel("Show Map")

            ShutterButton {
                capturePhoto()
            }
            .readFrame(in: coordinateSpaceName, key: ShutterFramePreferenceKey.self)
        }
    }

    private var railBottomPadding: CGFloat {
        recorder.state == .paused ? 230 : 184
    }

    private var sessionPaceText: String {
        switch recorder.state {
        case .idle:
            return "--"
        case .active:
            return recorder.currentPace?.paceString ?? "--"
        case .paused:
            guard recorder.distanceMeters > 0 else { return "--" }
            return (Double(recorder.elapsedSeconds) / (recorder.distanceMeters / 1000)).paceString
        }
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
                    coordinate: recorder.locationManager.location?.coordinate,
                    captureContext: recorder.photoCaptureContext
                )
                onCapture(image, meta)
            }
        }
    }

    private func pauseActivity() {
        recorder.pause()
    }

    private func resumeActivity() {
        recorder.resume()
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
            ? CGPoint(x: size.width - 44, y: fallbackY)
            : CGPoint(x: shutterFrame.midX, y: shutterFrame.midY)
        let end = photoStackFrame.isEmpty
            ? CGPoint(x: max(size.width - 58, 58), y: max(size.height - 310, 72))
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

struct ShutterButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.white)
                    .frame(width: 64, height: 64)
                Circle()
                    .stroke(.white.opacity(0.4), lineWidth: 4)
                    .frame(width: 74, height: 74)
            }
        }
        .accessibilityLabel("Capture Photo")
    }
}

struct SessionStatusCard: View {
    let state: RecordingState
    let elapsedText: String
    let paceLabel: String
    let paceText: String
    let distanceText: String
    let coachMessage: String?
    let musicPlayback: MusicPlaybackSnapshot?
    let showsMusicDisabledState: Bool
    let musicErrorMessage: String?
    let onTogglePlayback: () -> Void
    let onSkipTrack: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(headerText)
                .font(headerFont)
                .multilineTextAlignment(headerAlignment)
                .lineLimit(state == .idle ? 1 : 3)
                .frame(maxWidth: .infinity, alignment: headerFrameAlignment)
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(statusColor)
                .foregroundStyle(statusTextColor)

            VStack(spacing: 18) {
                HStack(spacing: 14) {
                    SessionMetricColumn(value: elapsedText, label: "Time")
                    SessionMetricColumn(value: paceText, label: paceLabel)
                    SessionMetricColumn(value: distanceText, label: "Distance (km)")
                }

                if let musicPlayback {
                    musicRow(for: musicPlayback)
                } else if showsMusicDisabledState {
                    disabledMusicRow
                } else if let musicErrorMessage, !musicErrorMessage.isEmpty {
                    musicErrorRow(message: musicErrorMessage)
                }

                controls
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)
            .padding(.bottom, 18)
            .background(.white)
        }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        .accessibilityIdentifier("CameraDataOverlay")
    }

    private func musicRow(for playback: MusicPlaybackSnapshot) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "music.note")
                    .foregroundStyle(.orange)

                MusicWaveView(isAnimating: playback.isPlaying)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(playback.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                Text(playback.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onTogglePlayback) {
                Image(systemName: playback.isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(playback.isPlaying ? "Pause music" : "Play music")

            Button(action: onSkipTrack) {
                Image(systemName: "forward.fill")
                    .frame(width: 34, height: 34)
                    .background(Color(.secondarySystemBackground), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Skip track")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("MusicPlaybackRow")
    }

    private var disabledMusicRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "music.note.slash")
                .foregroundStyle(.secondary)
            Text("Music unavailable")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Music unavailable")
    }

    private func musicErrorRow(message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }

    private struct MusicWaveView: View {
        let isAnimating: Bool

        private let barCount = 4

        var body: some View {
            TimelineView(.animation(minimumInterval: 0.18, paused: !isAnimating)) { context in
                HStack(alignment: .center, spacing: 3) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule(style: .continuous)
                            .fill(isAnimating ? Color.orange : Color.secondary.opacity(0.45))
                            .frame(width: 3, height: barHeight(for: index, date: context.date))
                    }
                }
                .frame(width: 24, height: 16, alignment: .center)
            }
            .accessibilityHidden(true)
        }

        private func barHeight(for index: Int, date: Date) -> CGFloat {
            guard isAnimating else { return [6, 10, 8, 5][index] }

            let time = date.timeIntervalSinceReferenceDate
            let phase = time * 5.4 + Double(index) * 0.8
            let normalized = (sin(phase) + 1) / 2
            return 5 + CGFloat(normalized) * 11
        }
    }

    @ViewBuilder
    private var controls: some View {
        switch state {
        case .idle:
            Button(action: onStart) {
                Text("Start")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SessionPrimaryButtonStyle(background: .orange, foreground: .white))
        case .active:
            Button(action: onPause) {
                Text("Pause")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SessionPrimaryButtonStyle(background: .orange, foreground: .white))
        case .paused:
            HStack(spacing: 12) {
                Button(action: onResume) {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SessionPrimaryButtonStyle(background: .orange, foreground: .white))

                Button(action: onFinish) {
                    Label("Finish", systemImage: "flag.checkered")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SessionPrimaryButtonStyle(background: .black, foreground: .white))
            }
        }
    }

    private var headerText: String {
        if let coachMessage, state != .idle {
            return coachMessage
        }

        switch state {
        case .idle:
            return "Ready"
        case .active:
            return "In progress"
        case .paused:
            return "Paused"
        }
    }

    private var headerFont: Font {
        state == .idle ? .headline.weight(.semibold) : .subheadline.weight(.semibold)
    }

    private var headerAlignment: TextAlignment {
        state == .idle ? .center : .leading
    }

    private var headerFrameAlignment: Alignment {
        state == .idle ? .center : .leading
    }

    private var statusColor: Color {
        switch state {
        case .idle: return Color.white.opacity(0.92)
        case .active: return .orange
        case .paused: return Color(red: 0.95, green: 0.78, blue: 0.26)
        }
    }

    private var statusTextColor: Color {
        switch state {
        case .idle: return .black
        case .active: return .white
        case .paused: return .black
        }
    }
}

private struct SessionMetricColumn: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct SessionPrimaryButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .padding(.vertical, 16)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

enum PhotoCaptureContext: String, Codable {
    case preActivity = "pre_activity"
    case active
    case paused
}

struct PhotoMetadata {
    let takenAt: Date
    let paceAtShot: Double?
    let hrAtShot: Int?
    let distAtShot: Double
    let coordinate: CLLocationCoordinate2D?
    let captureContext: PhotoCaptureContext
}
