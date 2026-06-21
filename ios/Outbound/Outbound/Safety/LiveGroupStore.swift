import Combine
import CoreLocation
import Foundation

struct LiveGroupSession: Identifiable, Hashable {
    let id: String
    let creatorUserId: String
    let currentUserId: String
    let title: String?
    let sport: String?
    let startedAt: Date
    let expiresAt: Date
    var endedAt: Date?
    var status: String
    var inviteToken: String?
    var inviteURL: URL?

    var isActive: Bool {
        endedAt == nil && status == "active" && expiresAt > Date()
    }

    var isCreatedByCurrentUser: Bool {
        creatorUserId == currentUserId
    }
}

struct LiveGroupParticipant: Identifiable, Hashable {
    let id: String
    let userId: String
    let displayName: String
    let status: String
    let joinedAt: Date
    let leftAt: Date?
    let lastLocationAt: Date?
    let coordinate: CLLocationCoordinate2D?
    let distanceM: Double?
    let paceSecondsPerKM: Double?

    var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = parts.map { String($0) }.joined().uppercased()
        return value.isEmpty ? "?" : value
    }

    var isVisibleOnMap: Bool {
        guard coordinate != nil else { return false }
        if status == "active" || status == "stale" { return true }
        guard let lastLocationAt else { return false }
        return Date().timeIntervalSince(lastLocationAt) < 5 * 60
    }

    var isFresh: Bool {
        status == "active"
    }

    static func == (lhs: LiveGroupParticipant, rhs: LiveGroupParticipant) -> Bool {
        lhs.id == rhs.id
            && lhs.userId == rhs.userId
            && lhs.displayName == rhs.displayName
            && lhs.status == rhs.status
            && lhs.joinedAt == rhs.joinedAt
            && lhs.leftAt == rhs.leftAt
            && lhs.lastLocationAt == rhs.lastLocationAt
            && lhs.coordinate?.latitude == rhs.coordinate?.latitude
            && lhs.coordinate?.longitude == rhs.coordinate?.longitude
            && lhs.distanceM == rhs.distanceM
            && lhs.paceSecondsPerKM == rhs.paceSecondsPerKM
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(userId)
        hasher.combine(displayName)
        hasher.combine(status)
        hasher.combine(joinedAt)
        hasher.combine(leftAt)
        hasher.combine(lastLocationAt)
        hasher.combine(coordinate?.latitude)
        hasher.combine(coordinate?.longitude)
        hasher.combine(distanceM)
        hasher.combine(paceSecondsPerKM)
    }
}

struct LiveGroupStartPresentation: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let message: String

    var activityItems: [Any] {
        [message, url]
    }
}

@MainActor
final class LiveGroupStore: ObservableObject {
    @Published private(set) var activeSession: LiveGroupSession?
    @Published private(set) var participants: [LiveGroupParticipant] = []
    @Published private(set) var lastErrorMessage: String?
    @Published private(set) var isCreating = false
    @Published private(set) var isJoining = false
    @Published private(set) var isUpdating = false

    private let api: APIClient
    private var lastSentAt: Date?
    private var lastSentDistanceM: Double?
    private var updateTask: Task<Void, Never>?
    private var pollingTask: Task<Void, Never>?

    init(api: APIClient? = nil) {
        self.api = api ?? APIClient.shared
    }

    var isSharing: Bool {
        activeSession?.isActive == true
    }

    var visibleParticipants: [LiveGroupParticipant] {
        participants.filter { $0.isVisibleOnMap }
    }

    var statusSummary: String {
        guard let session = activeSession else { return "Off" }
        let count = visibleParticipants.count
        guard session.isActive else { return "Ended" }
        return count == 0 ? "Waiting" : "\(count) live"
    }

    func createGroup(intent: SessionIntent?) async -> LiveGroupStartPresentation? {
        guard activeSession == nil else {
            if let inviteURL = activeSession?.inviteURL {
                return LiveGroupStartPresentation(
                    url: inviteURL,
                    message: shareMessage(url: inviteURL, intent: intent)
                )
            }
            return nil
        }

        isCreating = true
        lastErrorMessage = nil
        defer { isCreating = false }

        do {
            let response = try await api.createLiveGroupRun(
                LiveGroupCreateRequest(
                    title: intent?.title ?? "Outbound group run",
                    sport: intent?.sport.rawValue,
                    expiresInSeconds: 4 * 60 * 60
                )
            )
            apply(response)
            startPolling()
            guard let inviteURL = response.inviteURL else { return nil }
            return LiveGroupStartPresentation(
                url: inviteURL,
                message: shareMessage(url: inviteURL, intent: intent)
            )
        } catch {
            lastErrorMessage = "Group sharing unavailable: \(error.localizedDescription)"
            activeSession = nil
            participants = []
            return nil
        }
    }

    func joinGroup(invite: String) async {
        let trimmed = invite.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        isJoining = true
        lastErrorMessage = nil
        defer { isJoining = false }

        do {
            let response = try await api.joinLiveGroupRun(LiveGroupJoinRequest(invite: trimmed))
            apply(response)
            startPolling()
        } catch {
            lastErrorMessage = "Could not join group: \(error.localizedDescription)"
        }
    }

    func ingest(_ snapshot: ActiveSessionSnapshot) {
        guard let session = activeSession, session.isActive, snapshot.isActive else { return }
        guard let location = snapshot.location else { return }
        guard shouldSend(snapshot: snapshot) else { return }

        lastSentAt = snapshot.recordedAt
        lastSentDistanceM = snapshot.distanceMeters
        isUpdating = true
        updateTask?.cancel()
        updateTask = Task { [api] in
            do {
                let response = try await api.updateLiveGroupLocation(
                    sessionID: session.id,
                    request: LiveGroupLocationUpdateRequest(
                        recordedAt: snapshot.recordedAt,
                        latitude: location.latitude,
                        longitude: location.longitude,
                        altitudeM: location.altitudeMeters.isFinite ? location.altitudeMeters : nil,
                        accuracyM: location.horizontalAccuracyMeters.isFinite ? location.horizontalAccuracyMeters : nil,
                        elapsedSeconds: snapshot.elapsedSeconds,
                        distanceM: snapshot.distanceMeters,
                        paceSecondsPerKM: snapshot.currentPaceSecsPerKm
                    )
                )
                await MainActor.run {
                    apply(response)
                    isUpdating = false
                    lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    isUpdating = false
                    lastErrorMessage = "Group signal is stale."
                }
            }
        }
    }

    func finishActivity() {
        guard let session = activeSession else { return }
        if session.isCreatedByCurrentUser {
            end()
        } else {
            leave()
        }
    }

    func leave() {
        guard let sessionID = activeSession?.id else { return }
        stopLocalState(markEnded: true)
        Task { [api] in
            _ = try? await api.leaveLiveGroupRun(sessionID: sessionID)
        }
    }

    func end() {
        guard let sessionID = activeSession?.id else { return }
        stopLocalState(markEnded: true)
        Task { [api] in
            _ = try? await api.endLiveGroupRun(sessionID: sessionID)
        }
    }

    private func startPolling() {
        pollingTask?.cancel()
        guard let sessionID = activeSession?.id else { return }
        pollingTask = Task { [api] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 12_000_000_000)
                    let response = try await api.fetchLiveGroupRun(sessionID: sessionID)
                    await MainActor.run {
                        apply(response)
                        lastErrorMessage = nil
                    }
                } catch is CancellationError {
                    return
                } catch {
                    await MainActor.run {
                        lastErrorMessage = "Group locations are stale."
                    }
                }
            }
        }
    }

    private func stopLocalState(markEnded: Bool) {
        updateTask?.cancel()
        pollingTask?.cancel()
        updateTask = nil
        pollingTask = nil

        let sessionID = activeSession?.id
        if markEnded, var session = activeSession {
            session.status = "ended"
            session.endedAt = Date()
            activeSession = session
        }
        activeSession = nil
        participants = []
        lastSentAt = nil
        lastSentDistanceM = nil
        isUpdating = false

        if sessionID == nil {
            lastErrorMessage = nil
        }
    }

    private func shouldSend(snapshot: ActiveSessionSnapshot) -> Bool {
        guard let lastSentAt, let lastSentDistanceM else { return true }
        let timeDelta = snapshot.recordedAt.timeIntervalSince(lastSentAt)
        let distanceDelta = abs(snapshot.distanceMeters - lastSentDistanceM)
        return timeDelta >= 10 || distanceDelta >= 25
    }

    private func apply(_ response: LiveGroupSessionResponse) {
        activeSession = LiveGroupSession(
            id: response.id,
            creatorUserId: response.creatorUserId,
            currentUserId: response.currentUserId,
            title: response.title,
            sport: response.sport,
            startedAt: response.startedAt,
            expiresAt: response.expiresAt,
            endedAt: response.endedAt,
            status: response.status,
            inviteToken: response.inviteToken ?? activeSession?.inviteToken,
            inviteURL: response.inviteURL ?? activeSession?.inviteURL
        )
        participants = response.participants
            .filter { $0.userId != response.currentUserId }
            .map(Self.participant)
            .filter { $0.isVisibleOnMap || $0.status == "active" || $0.status == "stale" }
        if activeSession?.isActive == false {
            pollingTask?.cancel()
        }
    }

    private static func participant(_ response: LiveGroupParticipantResponse) -> LiveGroupParticipant {
        let coordinate = response.lastLocation.map {
            CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
        }
        return LiveGroupParticipant(
            id: response.id,
            userId: response.userId,
            displayName: response.displayName,
            status: response.status,
            joinedAt: response.joinedAt,
            leftAt: response.leftAt,
            lastLocationAt: response.lastLocationAt,
            coordinate: coordinate,
            distanceM: response.lastActivitySnapshot?.distanceM,
            paceSecondsPerKM: response.lastActivitySnapshot?.paceSecondsPerKM
        )
    }

    private func shareMessage(url: URL, intent: SessionIntent?) -> String {
        let sport = intent?.sport.rawValue ?? "run"
        return "Join my Outbound group \(sport): \(url.absoluteString)"
    }
}
