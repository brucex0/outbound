import Combine
import Foundation

struct LiveShareSession: Identifiable, Hashable {
    let id: String
    let startedAt: Date
    let expiresAt: Date
    var lastLocationAt: Date?
    var endedAt: Date?
    var status: String

    var isActive: Bool {
        endedAt == nil && status == "active" && expiresAt > Date()
    }
}

@MainActor
final class LiveShareStore: ObservableObject {
    @Published private(set) var activeSession: LiveShareSession?
    @Published var isArmedForNextActivity = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isStarting = false
    @Published private(set) var isUpdating = false
    @Published var selectedConnections: [SocialConnectionDTO] = []

    private let api: APIClient
    private var lastSentAt: Date?
    private var lastSentDistanceM: Double?
    private var updateTask: Task<Void, Never>?
    private var lastCheerFetchAt: Date?

    init(api: APIClient? = nil) {
        self.api = api ?? APIClient.shared
    }

    var isSharing: Bool {
        activeSession?.isActive == true
    }

    var invitationLabel: String {
        switch selectedConnections.count {
        case 0: return String(localized: "record.cheer.invite", defaultValue: "Invite someone to cheer me on")
        case 1: return String(format: String(localized: "record.cheer.invite.named", defaultValue: "Invite %@ to cheer me on"), selectedConnections[0].person.displayName)
        default: return String(format: String(localized: "record.cheer.invite.count", defaultValue: "Invite %lld people to cheer me on"), selectedConnections.count)
        }
    }

    func armForNextActivity(_ isArmed: Bool) {
        isArmedForNextActivity = isArmed
        if !isArmed {
            lastErrorMessage = nil
        }
    }

    func beginIfArmed(intent: SessionIntent?) async {
        guard isArmedForNextActivity, activeSession == nil else { return }

        isStarting = true
        lastErrorMessage = nil
        defer { isStarting = false }

        do {
            let response = try await api.createLiveShare(
                LiveShareCreateRequest(
                    recipientUserIds: selectedConnections.map(\.person.id),
                    sport: intent?.sport.rawValue,
                    title: intent?.title,
                    expiresInSeconds: 4 * 60 * 60
                )
            )
            activeSession = LiveShareSession(
                id: response.id,
                startedAt: response.startedAt,
                expiresAt: response.expiresAt,
                lastLocationAt: nil,
                endedAt: nil,
                status: response.status
            )
            isArmedForNextActivity = false
            lastSentAt = nil
            lastSentDistanceM = nil
        } catch {
            lastErrorMessage = "Live sharing unavailable: \(error.localizedDescription)"
            isArmedForNextActivity = false
            activeSession = nil
        }
    }

    func ingest(_ snapshot: ActiveSessionSnapshot) {
        guard let session = activeSession, session.isActive, snapshot.isActive else { return }
        guard let location = snapshot.location else { return }
        guard shouldSend(snapshot: snapshot) else { return }

        lastSentAt = snapshot.recordedAt
        lastSentDistanceM = snapshot.distanceMeters
        updateTask?.cancel()
        updateTask = Task { [api] in
            do {
                let response = try await api.updateLiveShareLocation(
                    shareID: session.id,
                    request: LiveShareLocationUpdateRequest(
                        recordedAt: snapshot.recordedAt,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        altitudeM: location.altitudeMeters.isFinite ? location.altitudeMeters : nil,
                        accuracyM: location.horizontalAccuracyMeters.isFinite ? location.horizontalAccuracyMeters : nil,
                        elapsedSeconds: snapshot.elapsedSeconds,
                        distanceM: snapshot.distanceMeters,
                        currentPaceSecsPerKm: snapshot.currentPaceSecsPerKm,
                        heartRate: snapshot.heartRate
                    )
                )
                await MainActor.run {
                    apply(response)
                    lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    lastErrorMessage = "Live sharing signal is stale."
                }
            }
        }
    }

    func end(now: Date = Date()) {
        updateTask?.cancel()
        updateTask = nil

        guard let session = activeSession else {
            isArmedForNextActivity = false
            return
        }
        activeSession?.endedAt = now
        activeSession?.status = "ended"
        activeSession = nil
        isArmedForNextActivity = false
        lastSentAt = nil
        lastSentDistanceM = nil
        lastCheerFetchAt = nil

        Task { [api] in
            _ = try? await api.endLiveShare(shareID: session.id)
        }
    }

    func takePendingVoiceCheers(now: Date = Date()) async -> [Data] {
        guard let session = activeSession, session.isActive else { return [] }
        if let lastCheerFetchAt, now.timeIntervalSince(lastCheerFetchAt) < 4 { return [] }
        lastCheerFetchAt = now
        do {
            return try await api.fetchVoiceCheers(shareID: session.id).cheers.compactMap(\.audioData)
        } catch {
            return []
        }
    }

    private func shouldSend(snapshot: ActiveSessionSnapshot) -> Bool {
        guard let lastSentAt, let lastSentDistanceM else { return true }
        let timeDelta = snapshot.recordedAt.timeIntervalSince(lastSentAt)
        let distanceDelta = abs(snapshot.distanceMeters - lastSentDistanceM)
        return timeDelta >= 10 || distanceDelta >= 25
    }

    private func apply(_ response: LiveShareStatusResponse) {
        guard var session = activeSession, session.id == response.id else { return }
        session.status = response.status
        session.endedAt = response.endedAt
        session.lastLocationAt = response.lastLocationAt
        activeSession = session
    }

    func setSelectedConnections(_ connections: [SocialConnectionDTO]) {
        selectedConnections = connections
        armForNextActivity(!connections.isEmpty)
    }
}
