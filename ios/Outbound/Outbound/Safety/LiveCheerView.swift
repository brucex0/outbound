import AVFoundation
import Ably
import Combine
import MapKit
import SwiftUI

@MainActor
final class LiveCheerStore: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published var sessions: [InvitedLiveShareDTO] = []
    @Published var session: InvitedLiveShareDTO?
    @Published var isLoadingSession: Bool
    @Published var sessionLoadFailed = false
    @Published var isRecording = false
    @Published fileprivate var statusMessage: CheerFeedback?
    @Published var latestCheer: VoiceCheerReceiptDTO?
    private var recorder: AVAudioRecorder?
    private var recordingStartedAt: Date?
    private let usesFixture: Bool
    private let api = APIClient.shared
    private var realtime: AblySessionTransport?
    private var realtimeSessionID: String?

    init(initialSession: InvitedLiveShareDTO? = nil) {
        session = initialSession
        isLoadingSession = initialSession == nil
        latestCheer = initialSession?.latestCheer
        usesFixture = initialSession != nil
        super.init()
    }

    func refreshSessions() async { sessions = (try? await api.fetchInvitedLiveShares().sessions) ?? sessions }
    func refresh(id: String) async {
        guard !usesFixture else { return }
        if session == nil {
            isLoadingSession = true
            sessionLoadFailed = false
        }
        defer { isLoadingSession = false }
        do {
            let value = try await api.fetchInvitedLiveShare(id: id)
            session = value
            latestCheer = value.latestCheer
            sessionLoadFailed = false
            if value.status == "active" { connectRealtime(id: id) }
        } catch {
            if session == nil { sessionLoadFailed = true }
        }
    }

    func stopRealtime() {
        realtime?.close()
        realtime = nil
        realtimeSessionID = nil
    }

    private func connectRealtime(id: String) {
        guard !usesFixture, realtimeSessionID != id else { return }
        realtime?.close()
        realtimeSessionID = id
        realtime = AblySessionTransport(kind: "live_share", sessionID: id, api: api) { [weak self] message in
            guard message.name == "location" || message.name == "cheer.available" else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if message.name == "location", var value = self.session,
                   let payload = message.data as? [String: Any],
                   let latitude = (payload["latitude"] as? NSNumber)?.doubleValue,
                   let longitude = (payload["longitude"] as? NSNumber)?.doubleValue {
                    let recordedAt = (payload["recordedAt"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
                    let courseDegrees = (payload["courseDegrees"] as? NSNumber)?.doubleValue
                    value.lastLocation = LiveSharePointDTO(
                        recordedAt: recordedAt,
                        latitude: latitude,
                        longitude: longitude,
                        courseDegrees: courseDegrees
                    )
                    value.lastLocationAt = recordedAt
                    value.elapsedSeconds = (payload["elapsedSeconds"] as? NSNumber)?.intValue ?? value.elapsedSeconds
                    value.distanceM = (payload["distanceM"] as? NSNumber)?.doubleValue ?? value.distanceM
                    value.currentPaceSecsPerKm = (payload["currentPaceSecsPerKm"] as? NSNumber)?.doubleValue
                    value.heartRate = (payload["heartRate"] as? NSNumber)?.intValue
                    self.session = value
                } else {
                    await self.refresh(id: id)
                }
            }
        }
    }

    func beginRecording() {
        guard !isRecording else { return }
        statusMessage = nil
        AVAudioApplication.requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else {
                    self.statusMessage = CheerFeedback(message: String(localized: "cheer.microphone.required", defaultValue: "Microphone access is needed to send a voice Cheer."), isSuccess: false)
                    return
                }
                do {
                    let audioSession = AVAudioSession.sharedInstance()
                    try audioSession.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker, .allowBluetoothHFP])
                    try audioSession.setActive(true)
                    let url = FileManager.default.temporaryDirectory.appendingPathComponent("plainstride-cheer-\(UUID().uuidString).m4a")
                    let recorder = try AVAudioRecorder(url: url, settings: [AVFormatIDKey: Int(kAudioFormatMPEG4AAC), AVSampleRateKey: 22_050, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000])
                    recorder.delegate = self
                    recorder.record(forDuration: 15)
                    self.recorder = recorder
                    self.recordingStartedAt = Date()
                    self.isRecording = true
                } catch {
                    self.statusMessage = CheerFeedback(message: String(localized: "cheer.record.failed", defaultValue: "Couldn’t start recording."), isSuccess: false)
                }
            }
        }
    }

    func finishAndSend() {
        guard let recorder, let session, isRecording else { return }
        recorder.stop(); isRecording = false
        let durationMs = min(15_000, max(250, Int(Date().timeIntervalSince(recordingStartedAt ?? Date()) * 1_000)))
        guard let audio = try? Data(contentsOf: recorder.url) else {
            try? FileManager.default.removeItem(at: recorder.url)
            self.recorder = nil
            statusMessage = CheerFeedback(message: String(localized: "cheer.audio.failed", defaultValue: "Couldn’t prepare your Cheer to send."), isSuccess: false)
            return
        }
        try? FileManager.default.removeItem(at: recorder.url)
        self.recorder = nil
        Task {
            do {
                latestCheer = try await api.sendVoiceCheer(shareID: session.id, audio: audio, durationMs: durationMs)
                statusMessage = CheerFeedback(message: String(localized: "cheer.sent", defaultValue: "Voice Cheer sent"), isSuccess: true, tracksSendResult: true)
            }
            catch {
                statusMessage = CheerFeedback(message: String(localized: "cheer.send.failed", defaultValue: "Couldn’t send your Cheer."), isSuccess: false, tracksSendResult: true)
            }
        }
    }
}

fileprivate struct CheerFeedback: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isSuccess: Bool
    var tracksSendResult = false
}

struct LiveCheerView: View {
    let sessionID: String
    let entrySource: String
    @StateObject private var store: LiveCheerStore
    @State private var toast: CheerFeedback?
    @Environment(\.analyticsManager) private var analyticsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var measurementPreferences: MeasurementPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.outboundTheme) private var theme
    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var isFollowingRunner = true
    @State private var didTrackRunnerMarkerExposure = false

    init(sessionID: String, entrySource: String = "social", initialSession: InvitedLiveShareDTO? = nil) {
        self.sessionID = sessionID
        self.entrySource = entrySource
        _store = StateObject(wrappedValue: LiveCheerStore(initialSession: initialSession))
    }

    var body: some View {
        Group {
            if let session = store.session {
                VStack(spacing: 16) {
                    LiveSessionMapCanvas(
                        position: $mapPosition,
                        isFollowingLocation: $isFollowingRunner,
                        location: liveMapLocation(for: session),
                        routeSegments: [session.routePreview.map {
                            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
                        }],
                        activityType: ActivityType(rawValue: session.sport) ?? .running,
                        tint: theme.accentColor,
                        isMoving: session.status == "active",
                        reduceMotion: reduceMotion,
                        followsLocation: isFollowingRunner
                    ) {}
                    .frame(maxHeight: .infinity)
                    .overlay(alignment: .topTrailing) {
                        Button {
                            guard let location = liveMapLocation(for: session) else { return }
                            isFollowingRunner = true
                            withAnimation(.easeInOut(duration: 0.6)) {
                                mapPosition = .camera(LiveSessionMapCamera.camera(for: location))
                            }
                        } label: {
                            Image(systemName: "location.fill")
                                .font(.title3)
                                .foregroundStyle(.white)
                                .frame(width: 48, height: 48)
                                .background(Circle().fill(.black.opacity(0.42)))
                        }
                        .accessibilityLabel(String(localized: "map.action.recenter", defaultValue: "Recenter Map"))
                        .padding(16)
                    }
                    .onChange(of: session.lastLocationAt, initial: true) { _, _ in
                        guard store.session?.lastLocation != nil else { return }
                        guard !didTrackRunnerMarkerExposure else { return }
                        didTrackRunnerMarkerExposure = true
                        Task {
                            await analyticsManager?.track(.init(.featureExposed, properties: [
                                .feature: .string("live_cheer_runner_avatar")
                            ]))
                        }
                    }
                    HStack {
                        metric(
                            measurementPreferences.unitSystem.distanceString(meters: session.distanceM),
                            String(localized: "social.distance", defaultValue: "Distance")
                        )
                        metric(
                            Self.elapsedTime(session.elapsedSeconds),
                            String(localized: "social.time", defaultValue: "Time")
                        )
                        metric(
                            paceValue(for: session),
                            paceLabel(for: session)
                        )
                        metric(
                            session.heartRate.map { "\($0)" } ?? "—",
                            String(localized: "session.metric.heart_rate", defaultValue: "Heart rate")
                        )
                    }
                    Text(
                        session.status == "active"
                            ? String(format: String(localized: "cheer.runner.moving", defaultValue: "%@ is moving"), session.runner.displayName)
                            : String(localized: "cheer.activity.ended", defaultValue: "This activity has ended")
                    )
                        .font(.headline)
                    if session.status == "active" && session.voiceCheerEnabled {
                        Image(systemName: store.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 70)).foregroundStyle(store.isRecording ? .red : .orange)
                            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 80, pressing: { pressing in
                                if pressing { store.beginRecording() } else if store.isRecording { store.finishAndSend() }
                            }, perform: {})
                        Text(
                            store.isRecording
                                ? String(localized: "cheer.release_to_send", defaultValue: "Release to send")
                                : String(localized: "cheer.hold_to_record", defaultValue: "Hold to cheer")
                        )
                    } else if session.status == "active" {
                        Label(String(localized: "rewards.voice_cheer_locked", table: "Rewards"), systemImage: "lock.fill")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if let receipt = store.latestCheer {
                        VoiceCheerDeliveryStatus(receipt: receipt)
                    }
                }
                .padding()
                .navigationTitle(
                    String(
                        format: String(localized: "cheer.navigation.title", defaultValue: "Cheer %@ on"),
                        session.runner.displayName
                    )
                )
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(String(localized: "common.close", defaultValue: "Close"))
                    }
                }
            } else if store.isLoadingSession {
                ProgressView()
            } else if store.sessionLoadFailed {
                ContentUnavailableView {
                    Label(
                        String(localized: "cheer.session.unavailable.title", defaultValue: "Live activity unavailable"),
                        systemImage: "location.slash"
                    )
                } description: {
                    Text(String(localized: "cheer.session.unavailable.message", defaultValue: "This activity isn’t available right now. Check your connection or try again."))
                } actions: {
                    Button(String(localized: "cheer.session.unavailable.retry", defaultValue: "Try again")) {
                        Task { await store.refresh(id: sessionID) }
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            await store.refresh(id: sessionID)
            await analyticsManager?.track(.init(.liveCheerFollowerOpened, properties: [
                .entrySource: .string(entrySource),
                .selectionType: .string(store.session?.status == "active" ? "current_pace" : "average_pace")
            ]))
        }
        .onDisappear { store.stopRealtime() }
        .onChange(of: store.statusMessage) { _, feedback in
            guard let feedback else { return }
            toast = feedback
            if feedback.tracksSendResult {
                Task { await analyticsManager?.track(.init(.liveVoiceCheerSent, properties: [.result: .string(feedback.isSuccess ? "success" : "failure")])) }
            }
        }
        .overlay(alignment: .bottom) {
            if let toast {
                CheerToastView(feedback: toast)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: toast)
        .task(id: toast?.id) {
            guard let toastID = toast?.id else { return }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
            guard toast?.id == toastID else { return }
            withAnimation(.snappy) { toast = nil }
        }
    }

    private func liveMapLocation(for session: InvitedLiveShareDTO) -> LiveSessionMapLocation? {
        guard let point = session.lastLocation else { return nil }
        return LiveSessionMapLocation(
            coordinate: CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude),
            course: point.courseDegrees,
            updatedAt: point.recordedAt
        )
    }

    private func metric(_ value: String, _ label: String) -> some View { VStack { Text(value).font(.headline); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }

    private func paceValue(for session: InvitedLiveShareDTO) -> String {
        let secondsPerKilometer: Double?
        if session.status == "active" {
            secondsPerKilometer = session.currentPaceSecsPerKm
        } else if session.distanceM > 0 {
            secondsPerKilometer = Double(session.elapsedSeconds) / (session.distanceM / 1_000)
        } else {
            secondsPerKilometer = nil
        }
        return secondsPerKilometer?.paceString(for: measurementPreferences.unitSystem) ?? "—"
    }

    private func paceLabel(for session: InvitedLiveShareDTO) -> String {
        session.status == "active"
            ? String(localized: "session.metric.pace", defaultValue: "Pace")
            : String(localized: "session.metric.average_pace", defaultValue: "Avg. pace")
    }

    private static func elapsedTime(_ seconds: Int) -> String {
        let hours = seconds / 3_600
        let minutes = (seconds % 3_600) / 60
        let remainingSeconds = seconds % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
            : String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

private struct CheerToastView: View {
    let feedback: CheerFeedback

    var body: some View {
        Label(feedback.message, systemImage: feedback.isSuccess ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(feedback.isSuccess ? Color.green : Color.red, in: Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .accessibilityAddTraits(.isStaticText)
    }
}

#if DEBUG
struct DebugLiveCheerFollowerHarness: View {
    var body: some View {
        NavigationStack {
            LiveCheerView(
                sessionID: Self.session.id,
                entrySource: "debug_screenshot",
                initialSession: Self.session
            )
        }
        .preferredColorScheme(.light)
        .environmentObject(MeasurementPreferences())
    }

    private static let session = InvitedLiveShareDTO(
        id: "debug-live-cheer-follower",
        status: "active",
        runner: LiveShareRunnerDTO(
            id: "debug-runner",
            displayName: "Sage Runner",
            username: "sage-runner",
            avatarUrl: nil
        ),
        sport: "running",
        title: "Golden Gate recovery run",
        voiceCheerEnabled: true,
        startedAt: Date(timeIntervalSince1970: 1_788_500_000),
        expiresAt: Date(timeIntervalSince1970: 1_788_507_200),
        endedAt: nil,
        lastLocationAt: Date(timeIntervalSince1970: 1_788_501_718),
        lastLocation: point(37.7696, -122.4863, offset: 1_718),
        routePreview: [
            point(37.7702, -122.4548, offset: 0),
            point(37.7699, -122.4631, offset: 280),
            point(37.7695, -122.4718, offset: 560),
            point(37.7698, -122.4794, offset: 840),
            point(37.7696, -122.4863, offset: 1_120),
            point(37.7700, -122.4948, offset: 1_400),
            point(37.7705, -122.5023, offset: 1_718),
        ],
        elapsedSeconds: 1_718,
        distanceM: 4_730,
        currentPaceSecsPerKm: 362,
        heartRate: 148,
        latestCheer: nil
    )

    private static func point(_ latitude: Double, _ longitude: Double, offset: TimeInterval) -> LiveSharePointDTO {
        LiveSharePointDTO(
            recordedAt: Date(timeIntervalSince1970: 1_788_500_000 + offset),
            latitude: latitude,
            longitude: longitude
        )
    }
}
#endif

private struct VoiceCheerDeliveryStatus: View {
    let receipt: VoiceCheerReceiptDTO

    var body: some View {
        Label(statusText, systemImage: statusSymbol)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(statusColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(statusColor.opacity(0.12), in: Capsule())
            .accessibilityLabel(statusText)
    }

    private var statusText: String {
        if receipt.acknowledgedAt != nil {
            return String(localized: "cheer.status.acknowledged", defaultValue: "❤️ Heard you")
        }
        if receipt.playedAt != nil {
            return String(localized: "cheer.status.heard", defaultValue: "Heard")
        }
        if receipt.deliveredAt != nil {
            return String(localized: "cheer.status.delivered", defaultValue: "Delivered")
        }
        return String(localized: "cheer.status.sent", defaultValue: "Sent")
    }

    private var statusSymbol: String {
        if receipt.acknowledgedAt != nil { return "heart.fill" }
        if receipt.playedAt != nil { return "speaker.wave.2.fill" }
        if receipt.deliveredAt != nil { return "iphone.radiowaves.left.and.right" }
        return "paperplane.fill"
    }

    private var statusColor: Color {
        receipt.acknowledgedAt != nil ? .pink : .orange
    }
}
