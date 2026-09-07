import SwiftUI
import AVFoundation
import CoreLocation
import UIKit

// Full-screen camera with an always-available shutter, a right-edge utility
// rail, and a bottom session card that carries live workout status plus guide
// motivation while the session is active.
struct CameraHUDView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    @EnvironmentObject var measurementPreferences: MeasurementPreferences
    @EnvironmentObject var liveShareStore: LiveShareStore
    @EnvironmentObject var liveGroupStore: LiveGroupStore
    @EnvironmentObject var onboardingStore: OnboardingStore
    @ObservedObject var recorder: ActivityRecorder
    @ObservedObject var guide: VirtualGuide
    @ObservedObject var musicStore: MusicStore
    let intent: SessionIntent?
    let capturedPhotoCount: Int
    let lastCapturedPhoto: UIImage?
    @Binding var activePage: SessionPage
    @Binding var isWorkoutPanelExpanded: Bool
    let onStart: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void
    let onCaptureStateChange: (Bool) -> Void
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
    @State private var isCapturingPhoto = false

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

                SessionStatusCard(
                        state: recorder.state,
                        isExpanded: $isWorkoutPanelExpanded,
                        expandedHeight: geometry.size.height,
                        intent: intent,
                        elapsedText: recorder.elapsedSeconds.formatted(),
                        elapsedSeconds: recorder.elapsedSeconds,
                        paceLabel: recorder.state == .paused
                            ? String(localized: "session.metric.average_pace", defaultValue: "Avg. pace")
                            : String(localized: "session.metric.pace", defaultValue: "Pace"),
                        paceText: sessionPaceText,
                        distanceText: measurementPreferences.unitSystem.distanceValueString(meters: recorder.distanceMeters),
                        distanceMeters: recorder.distanceMeters,
                        energyKilocalories: estimatedEnergyKilocalories,
                        walkingStepCount: recorder.walkingStepCount,
                        distanceLabel: measurementPreferences.unitSystem.distanceLabel,
                        elevationText: measurementPreferences.unitSystem.elevationValueString(meters: recorder.elevationGainMeters),
                        elevationLabel: measurementPreferences.unitSystem.elevationLabel,
                        heartRateText: recorder.heartRate.map { "\($0)" } ?? "--",
                        guideMessage: guideMessage,
                        musicPlayback: musicStore.playback.hasActiveQueue ? musicStore.playback : nil,
                        showsMusicDisabledState: musicStore.hasDeveloperTokenError,
                        musicErrorMessage: musicStore.hasDeveloperTokenError ? nil : musicStore.lastErrorMessage,
                        onTogglePlayback: {
                            trackMusicControl(musicStore.playback.isPlaying ? "pause" : "resume")
                            Task { await musicStore.togglePlayback() }
                        },
                        onSkipTrack: {
                            trackMusicControl("skip")
                            Task { await musicStore.skipToNext() }
                        },
                        onStart: onStart,
                        onPause: pauseActivity,
                        onResume: onResume,
                        onFinish: onFinish,
                        isFinishEnabled: !isCapturingPhoto
                    )
                    .background {
                        GeometryReader { proxy in
                            Color.clear.preference(
                                key: SessionStatusCardHeightPreferenceKey.self,
                                value: isWorkoutPanelExpanded ? 0 : proxy.size.height
                            )
                        }
                    }
                    .padding(.horizontal, isWorkoutPanelExpanded ? 0 : 16)
                    .padding(.bottom, isWorkoutPanelExpanded ? 0 : 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)

                if !isWorkoutPanelExpanded {
                    VStack {
                        Spacer()

                        HStack {
                            Spacer()

                            rightControlRail
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, railBottomPadding)
                    }
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
            if height > 0 {
                statusCardHeight = height
            }
        }
        .onAppear { camera.start() }
        .onDisappear { camera.stop() }
    }

    private var guideMessage: String? {
        guard recorder.state != .idle, !guide.lastNudge.isEmpty else { return nil }
        return guide.lastNudge
    }

    private var estimatedEnergyKilocalories: Double? {
        WorkoutCalorieEstimator.liveEnergyKilocalories(
            activityType: intent?.resolvedActivityType ?? .running,
            distanceMeters: recorder.distanceMeters,
            durationSeconds: recorder.elapsedSeconds,
            elevationGainMeters: recorder.elevationGainMeters,
            weightKilograms: onboardingStore.latestWeightKilograms
        )
    }

    private var rightControlRail: some View {
        VStack(spacing: 14) {
            if liveShareStore.isSharing {
                Button {
                    liveShareStore.end()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.orange))
                }
                .accessibilityLabel(String(localized: "camera.live_share.stop", defaultValue: "Stop live sharing"))
            }

            if liveGroupStore.isSharing {
                Button {
                    liveGroupStore.stopFromManagementControl()
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.blue))
                }
                .accessibilityLabel(String(localized: "camera.group_share.leave", defaultValue: "Leave group sharing"))
            }

            CapturedPhotoStackView(
                image: displayPhoto,
                count: displayPhotoCount,
                isConfirming: showCaptureSuccess
            )
            .readFrame(in: coordinateSpaceName, key: PhotoStackFramePreferenceKey.self)

            Button { camera.flipCamera() } label: {
                Image(systemName: "camera.rotate")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel(String(localized: "camera.action.flip", defaultValue: "Flip Camera"))

            Button { activePage = .map } label: {
                Image(systemName: "map.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 56, height: 56)
                    .background(Circle().fill(.black.opacity(0.42)))
            }
            .accessibilityLabel(String(localized: "camera.action.show_map", defaultValue: "Show Map"))

            ShutterButton {
                capturePhoto()
            }
            .disabled(isCapturingPhoto)
            .opacity(isCapturingPhoto ? 0.6 : 1)
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
            Text(String(localized: "camera.permission.off.title", defaultValue: "Camera access is off"))
                .font(.headline)
            Text(String(localized: "camera.permission.off.detail", defaultValue: "Enable Camera for Plainstride in Settings to record with the live preview."))
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
        guard !isCapturingPhoto else { return }
        isCapturingPhoto = true
        onCaptureStateChange(true)
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-OutboundUseSampleCameraPhoto") {
            handleCapturedPhoto(UITestSampleCameraPhoto.make(index: capturedPhotoCount + 1))
            finishPhotoCapture()
            return
        }
        #endif

        camera.capturePhoto { image in
            DispatchQueue.main.async {
                if let image {
                    handleCapturedPhoto(image)
                }
                finishPhotoCapture()
            }
        }
    }

    private func finishPhotoCapture() {
        isCapturingPhoto = false
        onCaptureStateChange(false)
    }

    private func handleCapturedPhoto(_ image: UIImage) {
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

    private func pauseActivity() {
        recorder.pause()
    }

    private func trackMusicControl(_ control: String) {
        guard let analyticsManager else { return }
        Task {
            await analyticsManager.track(.init(.musicControlUsed, properties: [.control: .string(control)]))
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
        .accessibilityIdentifier("CapturedPhotoStack")
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

#if DEBUG
private enum UITestSampleCameraPhoto {
    static func make(index: Int) -> UIImage {
        let size = CGSize(width: 900, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)

        return renderer.image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: size.height * 0.58, width: size.width, height: size.height * 0.42))

            UIColor.white.withAlphaComponent(0.95).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 96, y: 124, width: 220, height: 220))

            let text = "Plainstride\nPhoto \(index)"
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 84, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph
            ]
            let textRect = CGRect(x: 80, y: 430, width: size.width - 160, height: 240)
            text.draw(in: textRect, withAttributes: attributes)
        }
    }
}
#endif

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
        .accessibilityLabel(String(localized: "camera.action.capture_photo", defaultValue: "Capture Photo"))
    }
}

struct SessionStatusCard: View {
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @EnvironmentObject private var connectivityStore: ConnectivityStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.outboundTheme) private var theme

    let state: RecordingState
    @Binding var isExpanded: Bool
    let expandedHeight: CGFloat
    let intent: SessionIntent?
    let elapsedText: String
    let elapsedSeconds: Int
    let paceLabel: String
    let paceText: String
    let distanceText: String
    let distanceMeters: Double
    let energyKilocalories: Double?
    let walkingStepCount: Int?
    let distanceLabel: String
    let elevationText: String
    let elevationLabel: String
    let heartRateText: String
    let guideMessage: String?
    let musicPlayback: MusicPlaybackSnapshot?
    let showsMusicDisabledState: Bool
    let musicErrorMessage: String?
    let onTogglePlayback: () -> Void
    let onSkipTrack: () -> Void
    let onStart: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onFinish: () -> Void
    let isFinishEnabled: Bool
    @State private var panelDragHeight: CGFloat?

    private let collapsedHeight: CGFloat = 92

    var body: some View {
        let panelHeight = resolvedPanelHeight
        let expansionProgress = panelExpansionProgress(for: panelHeight)

        VStack(spacing: 0) {
            panelGrabber

            if expansionProgress > 0.08 {
                expandedDashboard
                    .opacity(expansionProgress)
                    .allowsHitTesting(isExpanded && panelDragHeight == nil)
            } else {
                compactRow
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        setExpanded(true)
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: panelHeight, alignment: .top)
        .background(OutboundPalette.surface)
        .clipShape(
            UnevenRoundedRectangle(
                topLeadingRadius: 20 * (1 - expansionProgress),
                topTrailingRadius: 20 * (1 - expansionProgress)
            )
        )
        .overlay {
            UnevenRoundedRectangle(
                topLeadingRadius: 20 * (1 - expansionProgress),
                topTrailingRadius: 20 * (1 - expansionProgress)
            )
            .strokeBorder(theme.accentColor.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: theme.glowColor.opacity(0.55), radius: 18, y: -6)
        .animation(panelAnimation, value: isExpanded)
        .accessibilityIdentifier("CameraDataOverlay")
    }

    private var panelGrabber: some View {
        VStack(spacing: 3) {
            Capsule()
                .fill(Color.secondary.opacity(0.38))
                .frame(width: 42, height: 5)

            Image(systemName: isExpanded ? "chevron.down" : "chevron.up")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .contentShape(Rectangle())
        .padding(.top, isExpanded ? 48 : 0)
        .onTapGesture {
            setExpanded(!isExpanded)
        }
        .gesture(panelDragGesture)
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isExpanded
            ? String(localized: "session.panel.collapse.accessibility", defaultValue: "Collapse workout dashboard")
            : String(localized: "session.panel.expand.accessibility", defaultValue: "Expand workout dashboard"))
        .accessibilityAction {
            setExpanded(!isExpanded)
        }
    }

    private var panelDragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .global)
            .onChanged { value in
                let baseHeight = isExpanded ? maximumPanelHeight : collapsedHeight
                let proposedHeight = baseHeight - value.translation.height
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    panelDragHeight = min(max(proposedHeight, collapsedHeight), maximumPanelHeight)
                }
            }
            .onEnded { value in
                let baseHeight = isExpanded ? maximumPanelHeight : collapsedHeight
                let projectedHeight = min(
                    max(baseHeight - value.predictedEndTranslation.height, collapsedHeight),
                    maximumPanelHeight
                )
                let midpoint = collapsedHeight + ((maximumPanelHeight - collapsedHeight) * 0.5)
                let shouldExpand = projectedHeight >= midpoint
                withAnimation(panelAnimation) {
                    panelDragHeight = shouldExpand ? maximumPanelHeight : collapsedHeight
                } completion: {
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        isExpanded = shouldExpand
                        panelDragHeight = nil
                    }
                }
            }
    }

    private var maximumPanelHeight: CGFloat {
        max(expandedHeight, collapsedHeight)
    }

    private var resolvedPanelHeight: CGFloat {
        panelDragHeight ?? (isExpanded ? maximumPanelHeight : collapsedHeight)
    }

    private func panelExpansionProgress(for height: CGFloat) -> CGFloat {
        let range = maximumPanelHeight - collapsedHeight
        guard range > 0 else { return isExpanded ? 1 : 0 }
        return min(max((height - collapsedHeight) / range, 0), 1)
    }

    private var panelAnimation: Animation {
        reduceMotion ? .easeOut(duration: 0.16) : .snappy(duration: 0.3)
    }

    private func setExpanded(_ expanded: Bool) {
        guard expanded != isExpanded else { return }
        isExpanded = expanded
    }

    private var expandedDashboard: some View {
        VStack(spacing: 0) {
            topRow
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .contentShape(Rectangle())
                .onTapGesture {
                    setExpanded(false)
                }

            if connectivityStore.isOffline {
                OfflineStatusBanner()
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            ScrollView {
                VStack(spacing: 18) {
                    heroMetric

                    LazyVGrid(
                        columns: Array(
                            repeating: GridItem(.flexible(), spacing: 10),
                            count: dynamicTypeSize.isAccessibilitySize ? 2 : 3
                        ),
                        spacing: 10
                    ) {
                        ExpandedSessionMetric(
                            value: displayedElapsedText,
                            label: String(localized: "summary.stats.time", defaultValue: "Time")
                        )
                        ExpandedSessionMetric(
                            value: displayedDistanceText,
                            label: String(localized: "summary.stats.distance", defaultValue: "Distance")
                        )
                        ExpandedSessionMetric(value: paceText, label: paceLabel)
                        ExpandedSessionMetric(value: movementDetailValue, label: movementDetailLabel)
                        ExpandedSessionMetric(
                            value: heartRateText,
                            label: String(localized: "session.metric.heart_rate", defaultValue: "Heart rate")
                        )
                    }

                    extraCountdownStrip

                    if let guideMessage, state != .idle {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(theme.accentColor)
                                .frame(width: 32, height: 32)
                                .background(theme.accentColor.opacity(0.12), in: Circle())

                            VStack(alignment: .leading, spacing: 3) {
                                Text(String(localized: "session.dashboard.coach", defaultValue: "Live coach"))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(guideMessage)
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)

            expandedControls
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .background(OutboundPalette.surface)
        }
    }

    private var heroMetric: some View {
        VStack(spacing: 8) {
            Text(heroMetricValue)
                .font(.system(size: 54, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.55)

            Text(heroMetricLabel)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.secondary)

            if let progress = heroProgress {
                ProgressView(value: progress)
                    .tint(theme.accentColor)
                    .frame(maxWidth: 260)
                    .accessibilityLabel(heroMetricLabel)
                    .accessibilityValue(Text("\(Int((progress * 100).rounded()))%"))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var heroMetricValue: String {
        switch displayIntent.activityGoal {
        case .timeSeconds:
            displayedElapsedText
        case .calories:
            displayedDistanceText
        case .distanceMeters, .freestyle:
            displayedDistanceText
        }
    }

    private var heroMetricLabel: String {
        switch displayIntent.activityGoal {
        case .timeSeconds:
            String(localized: "record.goal.time", defaultValue: "Time")
        case .calories:
            String(localized: "record.goal.calories", defaultValue: "Calories")
        case .distanceMeters, .freestyle:
            String(localized: "record.goal.distance", defaultValue: "Distance")
        }
    }

    private var heroProgress: Double? {
        switch displayIntent.activityGoal {
        case .freestyle:
            return nil
        case .distanceMeters(let target):
            guard target > 0 else { return nil }
            return min(max(distanceMeters / target, 0), 1)
        case .timeSeconds(let target):
            guard target > 0 else { return nil }
            return min(max(Double(elapsedSeconds) / Double(target), 0), 1)
        case .calories(let target):
            guard target > 0 else { return nil }
            return min(max((energyKilocalories ?? 0) / Double(target), 0), 1)
        }
    }

    private var expandedControls: some View {
        HStack(spacing: 12) {
            Button(action: expandedPrimaryAction) {
                Label(expandedPrimaryTitle, systemImage: expandedPrimarySymbol)
                    .font(.headline.weight(.bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .foregroundStyle(.white)
                    .background(theme.actionColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(expandedPrimaryAccessibilityLabel)

            if state == .paused {
                Button(action: onFinish) {
                    Label(String(localized: "session.action.finish", defaultValue: "Finish"), systemImage: "stop.fill")
                        .font(.headline.weight(.bold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 62)
                        .foregroundStyle(.white)
                        .background(theme.secondaryColor, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!isFinishEnabled)
                .opacity(isFinishEnabled ? 1 : 0.55)
                .accessibilityLabel(String(localized: "session.action.finish.accessibility", defaultValue: "Finish activity"))
            }
        }
    }

    private var expandedPrimaryTitle: String {
        switch state {
        case .idle: String(localized: "session.action.start", defaultValue: "Start")
        case .active: String(localized: "session.action.pause", defaultValue: "Pause")
        case .paused: String(localized: "session.action.resume", defaultValue: "Resume")
        }
    }

    private var expandedPrimarySymbol: String {
        switch state {
        case .idle: "record.circle.fill"
        case .active: "pause.fill"
        case .paused: "play.fill"
        }
    }

    private var expandedPrimaryAccessibilityLabel: String {
        switch state {
        case .idle: String(localized: "session.action.start.accessibility", defaultValue: "Start activity")
        case .active: String(localized: "session.action.pause.accessibility", defaultValue: "Pause activity")
        case .paused: String(localized: "session.action.resume.accessibility", defaultValue: "Resume activity")
        }
    }

    private func expandedPrimaryAction() {
        switch state {
        case .idle: onStart()
        case .active: onPause()
        case .paused: onResume()
        }
    }

    private var compactRow: some View {
        HStack(spacing: 10) {
            if connectivityStore.isOffline {
                Image(systemName: "icloud.slash.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.orange)
                    .accessibilityLabel(String(localized: "session.offline.accessibility", defaultValue: "Offline. Activity saved on this device and will sync later."))
            }

            SessionMetricColumn(value: displayedElapsedText, label: nil)
                .frame(maxWidth: .infinity)

            primaryControl(size: 46)
                .fixedSize()

            if state == .paused {
                compactFinishControl
                    .fixedSize()
            }

            SessionMetricColumn(value: displayedDistanceText, label: nil)
                .frame(maxWidth: .infinity)
        }
        .frame(height: 50)
    }

    private var compactFinishControl: some View {
        Button(action: onFinish) {
            Image(systemName: "stop.fill")
                .font(.callout.weight(.bold))
        }
        .disabled(!isFinishEnabled)
        .opacity(isFinishEnabled ? 1 : 0.55)
        .buttonStyle(SessionIconButtonStyle(background: theme.actionColor, foreground: .white, size: 40))
        .accessibilityLabel(String(localized: "session.action.finish.accessibility", defaultValue: "Finish activity"))
    }

    private var topRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.primary)
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

            musicMenu
        }
        .frame(minHeight: 34)
    }

    private var movementDetailValue: String {
        guard intent?.sport == .walk else { return elevationText }
        return walkingStepCount?.formatted() ?? "--"
    }

    private var movementDetailLabel: String {
        intent?.sport == .walk
            ? String(localized: "activity.metric.steps", defaultValue: "Steps")
            : elevationLabel
    }

    @ViewBuilder
    private var extraCountdownStrip: some View {
        if currentStepProgress != nil || secondaryRouteName != nil {
            HStack(spacing: 8) {
                if let stepProgress = currentStepProgress {
                    SessionStepCountdown(
                        progressText: String(
                            localized: "session.step.progress",
                            defaultValue: "\(stepProgress.index + 1) of \(stepProgress.count)"
                        ),
                        title: stepProgress.step.label,
                        remainingText: stepRemainingText(stepProgress),
                        tint: theme.accentColor
                    )
                }

                if let routeName = secondaryRouteName {
                    SessionMiniCountdown(symbolName: "map.fill", text: routeName, tint: theme.accentColor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func primaryControl(size: CGFloat = 58) -> some View {
        switch state {
        case .idle:
            Button(action: onStart) {
                Image(systemName: "record.circle.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(SessionIconButtonStyle(background: theme.actionColor, foreground: .white, size: size))
            .accessibilityLabel(String(localized: "session.action.start.accessibility", defaultValue: "Start activity"))
        case .active:
            Button(action: onPause) {
                Image(systemName: "pause.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(SessionIconButtonStyle(background: theme.actionColor, foreground: .white, size: size))
            .accessibilityLabel(String(localized: "session.action.pause.accessibility", defaultValue: "Pause activity"))
        case .paused:
            Button(action: onResume) {
                Image(systemName: "play.fill")
                    .font(.title3.weight(.bold))
            }
            .buttonStyle(SessionIconButtonStyle(background: theme.actionColor, foreground: .white, size: size))
            .accessibilityLabel(String(localized: "session.action.resume.accessibility", defaultValue: "Resume activity"))
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
                    Label(String(localized: "session.music.skip_track", defaultValue: "Skip track"), systemImage: "forward.fill")
                }
            } label: {
                musicIcon(isPlaying: musicPlayback.isPlaying, symbolName: "music.note")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "Music controls, \(musicPlayback.title)"))
            .accessibilityIdentifier("MusicPlaybackRow")
        } else if showsMusicDisabledState {
            musicIcon(isPlaying: false, symbolName: "music.note.slash")
                .accessibilityLabel(String(localized: "session.music.unavailable", defaultValue: "Music unavailable"))
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
        switch state {
        case .idle:
            return String(localized: "session.status.ready", defaultValue: "Ready")
        case .active:
            return String(localized: "session.status.in_progress", defaultValue: "In progress")
        case .paused:
            return String(localized: "session.status.paused", defaultValue: "Paused")
        }
    }

    private var displayIntent: SessionIntent {
        intent ?? .freestyleRun
    }

    private var activityTitle: String {
        if displayIntent.preparedRoute != nil,
           !displayIntent.activityGoal.isFreestyle {
            return displayIntent.activityGoal.title(for: displayIntent.sport)
        }
        return displayIntent.title
    }

    private var secondaryRouteName: String? {
        guard let routeName = displayIntent.routeName,
              !routeName.isEmpty,
              routeName != activityTitle
        else { return nil }
        return routeName
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
        if let targetCalories = displayIntent.resolvedTargetCalories, targetCalories > 0 {
            let currentCalories = Int((energyKilocalories ?? 0).rounded())
            return "\(currentCalories)/\(targetCalories)kcal"
        }
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

    private func stepRemainingText(
        _ stepProgress: (index: Int, count: Int, step: SessionIntentStep, progress: Double)
    ) -> String {
        let elapsedBeforeStep = displayIntent.workoutSteps
            .prefix(stepProgress.index)
            .reduce(0) { $0 + max(0, $1.durationSeconds) }
        let elapsedInStep = max(0, elapsedSeconds - elapsedBeforeStep)
        let remaining = max(0, stepProgress.step.durationSeconds - elapsedInStep)
        return remaining.formatted()
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
        case .idle: return theme.accentColor
        case .active: return theme.accentColor
        case .paused: return theme.secondaryColor
        }
    }
}

struct OfflineStatusBanner: View {
    var compact = false

    var body: some View {
        Label(String(localized: "session.offline.label", defaultValue: "Offline · activity saved on this device"), systemImage: "icloud.slash.fill")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: compact ? .leading : .center)
            .padding(.horizontal, compact ? 0 : 12)
            .padding(.vertical, compact ? 0 : 9)
            .background(compact ? Color.clear : Color.orange.opacity(0.1))
            .clipShape(Capsule())
            .accessibilityLabel(String(localized: "session.offline.accessibility", defaultValue: "Offline. Activity saved on this device and will sync later."))
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
                .foregroundStyle(.primary)
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

private struct ExpandedSessionMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: 72)
        .padding(.horizontal, 6)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

private struct SessionStepCountdown: View {
    let progressText: String
    let title: String
    let remainingText: String
    let tint: Color

    var body: some View {
        HStack(spacing: 8) {
            Text(progressText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(tint.opacity(0.12), in: Capsule())

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Spacer(minLength: 4)

            Label(remainingText, systemImage: "clock")
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct SessionMiniCountdown: View {
    let symbolName: String
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbolName)
                .font(.caption2.weight(.bold))
                .foregroundStyle(tint)

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
