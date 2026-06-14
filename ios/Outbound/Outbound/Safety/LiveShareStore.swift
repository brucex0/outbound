import Combine
import Foundation

struct LiveShareSession: Identifiable, Hashable {
    let id: String
    let token: String
    let shareURL: URL
    let startedAt: Date
    let expiresAt: Date
    var lastLocationAt: Date?
    var endedAt: Date?
    var status: String

    var isActive: Bool {
        endedAt == nil && status == "active" && expiresAt > Date()
    }
}

struct LiveShareStartPresentation: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let message: String
    let recipientName: String?
    let deliveries: [LiveShareDeliveryResult]

    var activityItems: [Any] {
        [message, url]
    }
}

@MainActor
final class LiveShareStore: ObservableObject {
    @Published private(set) var activeSession: LiveShareSession?
    @Published var isArmedForNextActivity = false
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isStarting = false
    @Published private(set) var isUpdating = false

    private let api: APIClient
    private var lastSentAt: Date?
    private var lastSentDistanceM: Double?
    private var updateTask: Task<Void, Never>?

    init(api: APIClient? = nil) {
        self.api = api ?? APIClient.shared
    }

    var isSharing: Bool {
        activeSession?.isActive == true
    }

    var shareURL: URL? {
        activeSession?.shareURL
    }

    func armForNextActivity(_ isArmed: Bool) {
        isArmedForNextActivity = isArmed
        if !isArmed {
            lastErrorMessage = nil
        }
    }

    func beginIfArmed(intent: SessionIntent?, contact: SafetyContact?) async -> LiveShareStartPresentation? {
        guard isArmedForNextActivity, activeSession == nil else { return nil }

        isStarting = true
        lastErrorMessage = nil
        defer { isStarting = false }

        do {
            let deliveryTargets = contact.map {
                [
                    LiveShareDeliveryTarget(
                        channel: $0.deliveryChannel.rawValue,
                        label: $0.name,
                        address: $0.deliveryAddress.isEmpty ? nil : $0.deliveryAddress
                    )
                ]
            }
            let response = try await api.createLiveShare(
                LiveShareCreateRequest(
                    recipientLabel: contact?.name,
                    deliveryTargets: deliveryTargets,
                    sport: intent?.sport.rawValue,
                    title: intent?.title,
                    expiresInSeconds: 4 * 60 * 60
                )
            )
            activeSession = LiveShareSession(
                id: response.id,
                token: response.token,
                shareURL: response.shareURL,
                startedAt: response.startedAt,
                expiresAt: response.expiresAt,
                lastLocationAt: nil,
                endedAt: nil,
                status: response.status
            )
            isArmedForNextActivity = false
            lastSentAt = nil
            lastSentDistanceM = nil
            return LiveShareStartPresentation(
                url: response.shareURL,
                message: shareMessage(url: response.shareURL, intent: intent, contact: contact),
                recipientName: contact?.name,
                deliveries: response.deliveries ?? []
            )
        } catch {
            lastErrorMessage = "Live sharing unavailable: \(error.localizedDescription)"
            isArmedForNextActivity = false
            activeSession = nil
            return nil
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
                        distanceM: snapshot.distanceMeters
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

        Task { [api] in
            _ = try? await api.endLiveShare(shareID: session.id)
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

    private func shareMessage(url: URL, intent: SessionIntent?, contact: SafetyContact?) -> String {
        let sport = intent?.sport.rawValue ?? "run"
        if let contact {
            return "Hi \(contact.name), follow my live \(sport) on Outbound: \(url.absoluteString)"
        }
        return "Follow my live \(sport) on Outbound: \(url.absoluteString)"
    }
}
