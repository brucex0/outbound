import SwiftUI
import AVFoundation
import CoreLocation

// Full-screen camera with an always-available shutter, a right-edge utility
// rail, and a bottom session card that carries live workout status plus coach
// motivation while the session is active.
struct CameraHUDView: View {
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var coach: VirtualCoach
    @ObservedObject var musicStore: MusicStore
    let intent: SessionIntent?
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
    @State private var statusCardHeight: CGFloat = 132

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
                        intent: intent,
                        elapsedText: recorder.elapsedSeconds.formatted(),
                        elapsedSeconds: recorder.elapsedSeconds,
                        paceLabel: recorder.state == .paused ? "Avg. pace" : "Pace",
                        paceText: sessionPaceText,
                        distanceText: measurementPreferences.unitSystem.distanceValueString(meters: recorder.distanceMeters),
                        distanceMeters: recorder.distanceMeters,
                        distanceLabel: measurementPreferences.unitSystem.distanceLabel,
                        elevationText: measurementPreferences.unitSystem.elevationValueString(meters: recorder.elevationGainMeters),
                        elevationLabel: measurementPreferences.unitSystem.elevationLabel,
                        heartRateText: recorder.heartRate.map { "\($0)" } ?? "--",
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
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SessionStatusCardHeightPreferenceKey.self,
                                value: proxy.size.height
                            )
                        }
                    }
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
        .onPreferenceChange(SessionStatusCardHeightPreferenceKey.self) { height in
            statusCardHeight = height
        }
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
        max(statusCardHeight + 38, 150)
    }

    private var sessionPaceText: String {
        switch recorder.state {
        case .idle:
            return "--"
        case .active:
            return recorder.currentPace?.paceString(for: measurementPreferences.unitSystem) ?? "--"
        case .paused:
            guard recorder.distanceMeters > 0 else { return "--" }
            return (Double(recorder.elapsedSeconds) / (recorder.distanceMeters / 1000)).paceString(for: measurementPreferences.unitSystem)
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

struct SessionStatusCardHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
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
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences

    let state: RecordingState
    let intent: SessionIntent?
    let elapsedText: String
    let elapsedSeconds: Int
    let paceLabel: String
    let paceText: String
    let distanceText: String
    let distanceMeters: Double
    let distanceLabel: String
    let elevationText: String
    let elevationLabel: String
    let heartRateText: String
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
        VStack(spacing: 10) {
            topRow
            extraCountdownStrip
            controlMetricsLayout
        }
        .padding(12)
        .background(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Color.black.opacity(0.06), lineWidth: 0.8)
        }
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
        .accessibilityIdentifier("CameraDataOverlay")
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.black)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityLabel(activityTitle)

                Text(headerText)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .accessibilityLabel(headerText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if state == .paused {
                Button(action: onFinish) {
                    Label("Finish", systemImage: "flag.checkered")
                }
                .buttonStyle(SessionMiniCapsuleButtonStyle(background: .black, foreground: .white))
            }

            musicMenu
        }
        .frame(minHeight: 34)
    }

    private var controlMetricsLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .center, spacing: 8) {
                VStack(spacing: 8) {
                    SessionMetricColumn(value: displayedElapsedText, label: nil)
                    SessionMetricColumn(value: displayedDistanceText, label: nil)
                }
                .frame(maxWidth: .infinity)

                primaryControl
                    .fixedSize()

                VStack(spacing: 8) {
                    SessionMetricColumn(value: paceText, label: paceLabel)
                    HStack(spacing: 8) {
                        SessionMetricColumn(value: elevationText, label: elevationLabel)
                        SessionMetricColumn(value: heartRateText, label: "HR")
                    }
                }
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                HStack(spacing: 8) {
                    SessionMetricColumn(value: displayedElapsedText, label: nil)
                    SessionMetricColumn(value: displayedDistanceText, label: nil)
                    SessionMetricColumn(value: paceText, label: paceLabel)
                }

                HStack(spacing: 10) {
                    SessionMetricColumn(value: elevationText, label: elevationLabel)
                    primaryControl
                    SessionMetricColumn(value: heartRateText, label: "HR")
                }
            }
        }
    }

    @ViewBuilder
    private var extraCountdownStrip: some View {
        if currentStepProgress != nil || displayIntent.routeName?.isEmpty == false {
            HStack(spacing: 8) {
                if let stepProgress = currentStepProgress {
                    SessionMiniCountdown(
                        symbolName: "list.bullet",
                        text: stepCountdownText(stepProgress)
                    )
                }

                if let routeName = displayIntent.routeName, !routeName.isEmpty {
                    SessionMiniCountdown(symbolName: "map.fill", text: routeName)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var primaryControl: some View {
        switch state {
        case .idle:
            Button(action: onStart) {
                Image(systemName: "record.circle.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(SessionIconButtonStyle(background: .orange, foreground: .white, size: 58))
            .accessibilityLabel("Start activity")
        case .active:
            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(SessionIconButtonStyle(background: .orange, foreground: .white, size: 58))
            .accessibilityLabel("Pause activity")
        case .paused:
            Button(action: onResume) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(SessionIconButtonStyle(background: .orange, foreground: .white, size: 58))
            .accessibilityLabel("Resume activity")
        }
    }

    @ViewBuilder
    private var musicMenu: some View {
        if let musicPlayback {
            Menu {
                Button(action: onTogglePlayback) {
                    Label(musicPlayback.isPlaying ? "Pause music" : "Play music",
                          systemImage: musicPlayback.isPlaying ? "pause.fill" : "play.fill")
                }
                Button(action: onSkipTrack) {
                    Label("Skip track", systemImage: "forward.fill")
                }
            } label: {
                musicIcon(isPlaying: musicPlayback.isPlaying, symbolName: "music.note")
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Music controls, \(musicPlayback.title)")
            .accessibilityIdentifier("MusicPlaybackRow")
        } else if showsMusicDisabledState {
            musicIcon(isPlaying: false, symbolName: "music.note.slash")
                .accessibilityLabel("Music unavailable")
        } else if let musicErrorMessage, !musicErrorMessage.isEmpty {
            musicIcon(isPlaying: false, symbolName: "exclamationmark.triangle.fill")
                .accessibilityLabel(musicErrorMessage)
        }
    }

    private func musicIcon(isPlaying: Bool, symbolName: String) -> some View {
        ZStack {
            if isPlaying {
                MusicWaveView(isAnimating: true)
            } else {
                Image(systemName: symbolName)
                    .font(.caption.weight(.bold))
            }
        }
        .foregroundStyle(symbolName == "exclamationmark.triangle.fill" ? Color.orange : Color.secondary)
        .frame(width: 34, height: 34)
        .background(Color(.systemGroupedBackground), in: Circle())
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

    private var displayIntent: SessionIntent {
        intent ?? .freestyleRun
    }

    private var activityTitle: String {
        displayIntent.title
    }

    private var displayedElapsedText: String {
        guard let targetDurationSeconds = displayIntent.resolvedTargetDurationSeconds,
              targetDurationSeconds > 0
        else {
            return elapsedText
        }

        return "\(elapsedText)/\(compactDurationText(seconds: targetDurationSeconds))"
    }

    private var displayedDistanceText: String {
        guard let targetDistanceMeters = displayIntent.resolvedTargetDistanceMeters,
              targetDistanceMeters > 0
        else {
            return measurementPreferences.unitSystem.distanceString(meters: distanceMeters)
                .replacingOccurrences(of: " ", with: "")
        }

        return compactDistanceProgressText(targetMeters: targetDistanceMeters)
    }

    private var currentStepProgress: (index: Int, count: Int, step: SessionIntentStep, progress: Double)? {
        let steps = displayIntent.workoutSteps.filter { $0.durationSeconds > 0 }
        guard !steps.isEmpty else { return nil }

        var remainingElapsed = elapsedSeconds
        for (index, step) in steps.enumerated() {
            if remainingElapsed < step.durationSeconds {
                return (
                    index,
                    steps.count,
                    step,
                    Double(max(0, remainingElapsed)) / Double(step.durationSeconds)
                )
            }
            remainingElapsed -= step.durationSeconds
        }

        guard let finalStep = steps.last else { return nil }
        return (steps.count - 1, steps.count, finalStep, 1)
    }

    private func stepCountdownText(
        _ stepProgress: (index: Int, count: Int, step: SessionIntentStep, progress: Double)
    ) -> String {
        let elapsedBeforeStep = displayIntent.workoutSteps
            .prefix(stepProgress.index)
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        let elapsedInStep = max(0, elapsedSeconds - elapsedBeforeStep)
        let remaining = max(0, stepProgress.step.durationSeconds - elapsedInStep)
        return "\(stepProgress.index + 1)/\(stepProgress.count) \(stepProgress.step.label) \(remaining.formatted())"
    }

    private func compactDistanceProgressText(targetMeters: Double) -> String {
        let unitSystem = measurementPreferences.unitSystem
        let currentValue = unitSystem.distanceValue(meters: distanceMeters)
        let targetValue = unitSystem.distanceValue(meters: targetMeters)
        let currentText = compactDecimal(currentValue, fractionDigits: currentValue < 1 ? 2 : 1)
        let targetText = compactDecimal(targetValue, fractionDigits: targetValue.rounded() == targetValue ? 0 : 1)
        return "\(currentText)/\(targetText)\(unitSystem.distanceUnit)"
    }

    private func compactDurationText(seconds: Int) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        }

        if seconds < 3600 {
            let minutes = seconds / 60
            let remainder = seconds % 60
            return remainder == 0 ? "\(minutes)min" : "\(minutes):\(String(format: "%02d", remainder))"
        }

        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        return minutes == 0 ? "\(hours)h" : "\(hours)h\(minutes)m"
    }

    private func compactDecimal(_ value: Double, fractionDigits: Int) -> String {
        let formatted = String(format: "%.\(fractionDigits)f", value)
        return formatted
            .replacingOccurrences(of: #"(\.\d*?)0+$"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"\.$"#, with: "", options: .regularExpression)
    }

    private var statusColor: Color {
        switch state {
        case .idle: return .orange
        case .active: return .orange
        case .paused: return Color(red: 0.95, green: 0.78, blue: 0.26)
        }
    }
}

private struct SessionMetricColumn: View {
    let value: String
    let label: String?

    var body: some View {
        VStack(spacing: label == nil ? 0 : 6) {
            Text(value)
                .font(.system(size: value.contains("/") ? 16 : 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.black)
                .lineLimit(1)
                .minimumScaleFactor(0.65)

            if let label {
                Text(label)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(minWidth: value.contains("/") ? 70 : 54, maxWidth: .infinity, minHeight: label == nil ? 28 : nil)
    }
}

private struct SessionMiniCountdown: View {
    let symbolName: String
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)

            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.horizontal, 8)
        .frame(height: 24)
        .background(Color(.systemGroupedBackground), in: Capsule())
    }
}

private struct SessionIconButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color
    let size: CGFloat

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: size, height: size)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1), in: Circle())
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct SessionMiniCapsuleButtonStyle: ButtonStyle {
    let background: Color
    let foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(background.opacity(configuration.isPressed ? 0.82 : 1), in: Capsule())
            .foregroundStyle(foreground)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
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
