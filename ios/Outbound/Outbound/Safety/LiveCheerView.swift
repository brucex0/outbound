import AVFoundation
import Combine
import MapKit
import SwiftUI

@MainActor
final class LiveCheerStore: NSObject, ObservableObject, @preconcurrency AVAudioRecorderDelegate {
    @Published var sessions: [InvitedLiveShareDTO] = []
    @Published var session: InvitedLiveShareDTO?
    @Published var isRecording = false
    @Published var statusMessage: String?
    private var recorder: AVAudioRecorder?
    private var recordingStartedAt: Date?
    private let api = APIClient.shared

    func refreshSessions() async { sessions = (try? await api.fetchInvitedLiveShares().sessions) ?? sessions }
    func refresh(id: String) async { if let value = try? await api.fetchInvitedLiveShare(id: id) { session = value } }

    func beginRecording() {
        guard !isRecording else { return }
        AVAudioApplication.requestRecordPermission { [weak self] allowed in
            Task { @MainActor in
                guard let self else { return }
                guard allowed else { self.statusMessage = String(localized: "cheer.microphone.required", defaultValue: "Microphone access is needed to send a voice cheer."); return }
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
                } catch { self.statusMessage = String(localized: "cheer.record.failed", defaultValue: "Couldn’t start recording.") }
            }
        }
    }

    func finishAndSend() {
        guard let recorder, let session, isRecording else { return }
        recorder.stop(); isRecording = false
        let durationMs = min(15_000, max(250, Int(Date().timeIntervalSince(recordingStartedAt ?? Date()) * 1_000)))
        guard let audio = try? Data(contentsOf: recorder.url) else { return }
        try? FileManager.default.removeItem(at: recorder.url)
        self.recorder = nil
        Task {
            do { _ = try await api.sendVoiceCheer(shareID: session.id, audio: audio, durationMs: durationMs); statusMessage = String(localized: "cheer.sent", defaultValue: "Voice cheer sent") }
            catch { statusMessage = String(localized: "cheer.send.failed", defaultValue: "Couldn’t send your cheer.") }
        }
    }
}

struct LiveCheerView: View {
    let sessionID: String
    @StateObject private var store = LiveCheerStore()
    @Environment(\.analyticsManager) private var analyticsManager

    var body: some View {
        Group {
            if let session = store.session {
                VStack(spacing: 16) {
                    if !session.routePreview.isEmpty {
                        Map {
                            MapPolyline(coordinates: session.routePreview.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) })
                                .stroke(.orange, lineWidth: 5)
                            if let point = session.lastLocation { Marker(session.runner.displayName, coordinate: .init(latitude: point.latitude, longitude: point.longitude)) }
                        }
                        .frame(maxHeight: .infinity)
                    }
                    HStack {
                        metric(String(format: "%.2f km", session.distanceM / 1000), "Distance")
                        metric(session.currentPaceSecsPerKm.map(Self.pace) ?? "—", "Pace")
                        metric(session.heartRate.map { "\($0)" } ?? "—", "Heart rate")
                    }
                    Text(session.status == "active" ? "\(session.runner.displayName) is moving" : "This activity has ended")
                        .font(.headline)
                    if session.status == "active" {
                        Image(systemName: store.isRecording ? "waveform.circle.fill" : "mic.circle.fill")
                            .font(.system(size: 70)).foregroundStyle(store.isRecording ? .red : .orange)
                            .onLongPressGesture(minimumDuration: 0.15, maximumDistance: 80, pressing: { pressing in
                                if pressing { store.beginRecording() } else if store.isRecording { store.finishAndSend() }
                            }, perform: {})
                        Text(store.isRecording ? "Release to send" : "Hold to cheer")
                    }
                    if let message = store.statusMessage { Text(message).font(.caption).foregroundStyle(.secondary) }
                }
                .padding()
                .navigationTitle("Cheer \(session.runner.displayName) on")
            } else { ProgressView() }
        }
        .task {
            await analyticsManager?.track(.init(.liveCheerFollowerOpened, properties: [.entrySource: .string("social")]))
            while !Task.isCancelled {
                await store.refresh(id: sessionID)
                try? await Task.sleep(for: .seconds(5))
            }
        }
        .onChange(of: store.statusMessage) { _, message in
            guard let message else { return }
            Task { await analyticsManager?.track(.init(.liveVoiceCheerSent, properties: [.result: .string(message == String(localized: "cheer.sent", defaultValue: "Voice cheer sent") ? "success" : "failure")])) }
        }
    }

    private func metric(_ value: String, _ label: LocalizedStringKey) -> some View { VStack { Text(value).font(.headline); Text(label).font(.caption).foregroundStyle(.secondary) }.frame(maxWidth: .infinity) }
    private static func pace(_ seconds: Double) -> String { "\(Int(seconds) / 60):\(String(format: "%02d", Int(seconds) % 60))/km" }
}
