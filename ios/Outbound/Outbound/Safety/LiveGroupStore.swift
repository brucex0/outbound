import Combine
import CoreLocation
import Foundation
import Ably

struct LiveGroupSession: Identifiable, Hashable {
    let id: String
    let activityEventId: String?
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

    var isLinkedToActivityEvent: Bool {
        activityEventId != nil
    }

    var displayTitle: String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Group run" : trimmed
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
    let isCurrentUser: Bool

    var initials: String {
        let parts = displayName
            .split(separator: " ")
            .prefix(2)
            .compactMap { $0.first }
        let value = parts.map { String($0) }.joined().uppercased()
        return value.isEmpty ? "?" : value
    }

    var isVisibleOnMap: Bool {
        guard !isCurrentUser else { return false }
        guard coordinate != nil else { return false }
        if status == "left" { return false }
        if status == "active" || status == "stale" { return true }
        guard let lastLocationAt else { return false }
        return Date().timeIntervalSince(lastLocationAt) < 5 * 60
    }

    var isFresh: Bool {
        status == "active"
    }

    var statusLabel: String {
        if isCurrentUser, status == "active" { return "You - sharing" }
        switch status {
        case "active":
            return lastLocationAt == nil ? "Joined - waiting for location" : "Live"
        case "stale":
            return "Last seen"
        case "left":
            return "Left"
        case "finished":
            return "Finished"
        default:
            return status.capitalized
        }
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
            && lhs.isCurrentUser == rhs.isCurrentUser
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
        hasher.combine(isCurrentUser)
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
    private var realtime: AblySessionTransport?
    private var realtimeSessionID: String?
    private var lastCheckpointAt: Date?
#if DEBUG
    private var isDebugTestGroupRun = false
#endif

    init(api: APIClient? = nil) {
        self.api = api ?? APIClient.shared
    }

    var isSharing: Bool {
        activeSession?.isActive == true
    }

    var visibleParticipants: [LiveGroupParticipant] {
        participants.filter { $0.isVisibleOnMap }
    }

    var activeParticipantCount: Int {
        participants.filter { $0.status == "active" || $0.status == "stale" }.count
    }

    var statusSummary: String {
        guard let session = activeSession else { return "Off" }
        guard session.isActive else { return "Ended" }
        let count = max(activeParticipantCount, 1)
        return count == 1 ? "1 runner" : "\(count) runners"
    }

    var displayTitle: String {
        activeSession?.displayTitle ?? "Group run"
    }

    func invitePresentation(intent: SessionIntent?) -> LiveGroupStartPresentation? {
        guard let session = activeSession, let inviteURL = session.inviteURL else { return nil }
        return LiveGroupStartPresentation(
            url: inviteURL,
            message: shareMessage(url: inviteURL, intent: intent, title: session.displayTitle)
        )
    }

    func createGroup(intent: SessionIntent?) async -> LiveGroupStartPresentation? {
        guard activeSession == nil else {
            if let inviteURL = activeSession?.inviteURL {
                return LiveGroupStartPresentation(
                    url: inviteURL,
                    message: shareMessage(url: inviteURL, intent: intent, title: activeSession?.displayTitle)
                )
            }
            return nil
        }

#if DEBUG
        isDebugTestGroupRun = false
#endif
        isCreating = true
        lastErrorMessage = nil
        defer { isCreating = false }

        do {
            let response = try await api.createLiveGroupRun(
                LiveGroupCreateRequest(
                    title: intent?.title ?? "Plainstride group run",
                    sport: intent?.sport.rawValue,
                    expiresInSeconds: 4 * 60 * 60
                )
            )
            apply(response)
            connectRealtime(sessionID: response.id)
            guard let inviteURL = response.inviteURL else { return nil }
            return LiveGroupStartPresentation(
                url: inviteURL,
                message: shareMessage(url: inviteURL, intent: intent, title: response.title)
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

#if DEBUG
        if isDebugTestGroupRun {
            isDebugTestGroupRun = false
            stopLocalState(markEnded: true)
        }
#endif
        isJoining = true
        lastErrorMessage = nil
        defer { isJoining = false }

        do {
            let response = try await api.joinLiveGroupRun(LiveGroupJoinRequest(invite: trimmed))
            apply(response)
            connectRealtime(sessionID: response.id)
        } catch {
            lastErrorMessage = "Could not join group: \(error.localizedDescription)"
        }
    }

    func joinActivityEvent(_ activityEventID: String) async {
        guard activeSession == nil else { return }
        isJoining = true
        lastErrorMessage = nil
        defer { isJoining = false }

        do {
            let response = try await api.joinLiveGroupRun(activityEventID: activityEventID)
            apply(response)
            connectRealtime(sessionID: response.id)
        } catch {
            ActivityDiagnosticLog.error(.persistence, "Event live map join failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            lastErrorMessage = String(localized: "group.activity.live_error")
        }
    }

    func ingest(_ snapshot: ActiveSessionSnapshot) {
        guard let session = activeSession, session.isActive, snapshot.isActive else { return }
        guard let location = snapshot.location else { return }
#if DEBUG
        if isDebugTestGroupRun {
            participants = Self.debugParticipants(
                centeredAt: CLLocationCoordinate2D(latitude: location.latitude, longitude: location.longitude),
                timestamp: snapshot.recordedAt,
                distanceMeters: snapshot.distanceMeters,
                includesRemoteAttendee: session.isLinkedToActivityEvent
            )
            return
        }
#endif
        guard shouldSend(snapshot: snapshot) else { return }

        lastSentAt = snapshot.recordedAt
        lastSentDistanceM = snapshot.distanceMeters
        realtime?.publishLocation([
            "recordedAt": ISO8601DateFormatter().string(from: snapshot.recordedAt),
            "latitude": location.latitude,
            "longitude": location.longitude,
            "altitudeM": location.altitudeMeters.isFinite ? location.altitudeMeters : NSNull(),
            "accuracyM": location.horizontalAccuracyMeters.isFinite ? location.horizontalAccuracyMeters : NSNull(),
            "elapsedSeconds": snapshot.elapsedSeconds,
            "distanceM": snapshot.distanceMeters,
            "paceSecondsPerKM": snapshot.currentPaceSecsPerKm as Any? ?? NSNull(),
        ])
        guard lastCheckpointAt.map({ snapshot.recordedAt.timeIntervalSince($0) >= 60 }) ?? true else { return }
        lastCheckpointAt = snapshot.recordedAt
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
        guard let sessionID = activeSession?.id else { return }
#if DEBUG
        if isDebugTestGroupRun {
            isDebugTestGroupRun = false
            stopLocalState(markEnded: true)
            return
        }
#endif
        updateTask?.cancel()
        updateTask = nil
        lastSentAt = nil
        lastSentDistanceM = nil
        isUpdating = false

        Task { [api] in
            do {
                let response = try await api.finishLiveGroupRunParticipation(sessionID: sessionID)
                await MainActor.run {
                    apply(response)
                    if activeSession?.isActive == true {
                        if response.participants.first(where: { $0.userId == response.currentUserId })?.status == "active" {
                            connectRealtime(sessionID: sessionID)
                        } else {
                            realtime?.close()
                            realtime = nil
                            realtimeSessionID = nil
                        }
                    } else {
                        realtime?.close()
                        realtime = nil
                    }
                    lastErrorMessage = nil
                }
            } catch {
                await MainActor.run {
                    lastErrorMessage = "Could not finish group participation."
                }
            }
        }
    }

    func stopFromManagementControl() {
        guard let session = activeSession else { return }
        if session.isCreatedByCurrentUser && !session.isLinkedToActivityEvent {
            end()
        } else {
            leave()
        }
    }

    func leave() {
        guard let sessionID = activeSession?.id else { return }
#if DEBUG
        if isDebugTestGroupRun {
            isDebugTestGroupRun = false
            stopLocalState(markEnded: true)
            return
        }
#endif
        stopLocalState(markEnded: true)
        Task { [api] in
            _ = try? await api.leaveLiveGroupRun(sessionID: sessionID)
        }
    }

    func end() {
        guard let sessionID = activeSession?.id else { return }
#if DEBUG
        if isDebugTestGroupRun {
            isDebugTestGroupRun = false
            stopLocalState(markEnded: true)
            return
        }
#endif
        stopLocalState(markEnded: true)
        Task { [api] in
            _ = try? await api.endLiveGroupRun(sessionID: sessionID)
        }
    }

    private func connectRealtime(sessionID: String) {
        guard realtimeSessionID != sessionID else { return }
        realtime?.close()
        realtimeSessionID = sessionID
        lastCheckpointAt = nil
        lastSentAt = nil
        lastSentDistanceM = nil
        realtime = AblySessionTransport(kind: "group_run", sessionID: sessionID, api: api) { [weak self] message in
            guard message.name == "location" || message.name == "participant.changed" else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if message.name == "location", let senderID = message.clientId, let payload = message.data as? [String: Any] {
                    self.applyRealtimeLocation(senderID: senderID, payload: payload)
                } else if let response = try? await self.api.fetchLiveGroupRun(sessionID: sessionID) {
                    self.apply(response)
                }
            }
        }
    }

    private func applyRealtimeLocation(senderID: String, payload: [String: Any]) {
        guard let index = participants.firstIndex(where: { $0.userId == senderID }),
              let latitude = (payload["latitude"] as? NSNumber)?.doubleValue,
              let longitude = (payload["longitude"] as? NSNumber)?.doubleValue else { return }
        let old = participants[index]
        let recordedAt = (payload["recordedAt"] as? String).flatMap(ISO8601DateFormatter().date(from:)) ?? Date()
        participants[index] = LiveGroupParticipant(
            id: old.id, userId: old.userId, displayName: old.displayName, status: "active",
            joinedAt: old.joinedAt, leftAt: nil,
            lastLocationAt: recordedAt,
            coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            distanceM: (payload["distanceM"] as? NSNumber)?.doubleValue,
            paceSecondsPerKM: (payload["paceSecondsPerKM"] as? NSNumber)?.doubleValue,
            isCurrentUser: old.isCurrentUser
        )
        lastErrorMessage = nil
    }

    private func stopLocalState(markEnded: Bool) {
        updateTask?.cancel()
        pollingTask?.cancel()
        realtime?.close()
        realtime = nil
        realtimeSessionID = nil
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

#if DEBUG
    func startDebugTestGroupRun(
        intent: SessionIntent?,
        center: CLLocationCoordinate2D?,
        activityEventID: String? = nil
    ) {
        updateTask?.cancel()
        pollingTask?.cancel()
        updateTask = nil
        pollingTask = nil
        lastSentAt = nil
        lastSentDistanceM = nil
        isUpdating = false
        lastErrorMessage = nil

        let now = Date()
        let origin = center ?? CLLocationCoordinate2D(latitude: 37.7699, longitude: -122.4862)
        let sessionID = "debug-test-group-run"
        let currentUserID = "debug-current-runner"
        isDebugTestGroupRun = true
        activeSession = LiveGroupSession(
            id: sessionID,
            activityEventId: activityEventID,
            creatorUserId: currentUserID,
            currentUserId: currentUserID,
            title: "Test group run",
            sport: intent?.sport.rawValue ?? "running",
            startedAt: now,
            expiresAt: now.addingTimeInterval(4 * 60 * 60),
            endedAt: nil,
            status: "active",
            inviteToken: nil,
            inviteURL: nil
        )
        participants = Self.debugParticipants(
            centeredAt: origin,
            timestamp: now,
            distanceMeters: 0,
            includesRemoteAttendee: activityEventID != nil
        )
    }

    private static func debugParticipants(
        centeredAt center: CLLocationCoordinate2D,
        timestamp: Date,
        distanceMeters: Double,
        includesRemoteAttendee: Bool
    ) -> [LiveGroupParticipant] {
        var runners: [(String, String, Double, Double, Double)] = [
            ("debug-runner-1", "Maya Chen", 42, 24, 430),
            ("debug-runner-2", "Jordan Lee", -28, -36, 456),
            ("debug-runner-3", "Alex Rivera", 8, 68, 415),
        ]
        if includesRemoteAttendee {
            runners.append(("debug-runner-remote", "Remote attendee", 0, 15_000, 448))
        }
        return runners.map { id, name, northMeters, eastMeters, pace in
            let coordinate = CLLocationCoordinate2D(
                latitude: center.latitude + northMeters / 111_000,
                longitude: center.longitude + eastMeters / (111_000 * max(cos(center.latitude * .pi / 180), 0.2))
            )
            return LiveGroupParticipant(
                id: id,
                userId: id,
                displayName: name,
                status: "active",
                joinedAt: timestamp,
                leftAt: nil,
                lastLocationAt: timestamp,
                coordinate: coordinate,
                distanceM: max(0, distanceMeters + northMeters),
                paceSecondsPerKM: pace,
                isCurrentUser: false
            )
        }
    }
#endif

    private func shouldSend(snapshot: ActiveSessionSnapshot) -> Bool {
        guard let lastSentAt, let lastSentDistanceM else { return true }
        let timeDelta = snapshot.recordedAt.timeIntervalSince(lastSentAt)
        let distanceDelta = abs(snapshot.distanceMeters - lastSentDistanceM)
        return timeDelta >= 10 || distanceDelta >= 25
    }

    private func apply(_ response: LiveGroupSessionResponse) {
        activeSession = LiveGroupSession(
            id: response.id,
            activityEventId: response.activityEventId,
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
            .map { Self.participant($0, currentUserID: response.currentUserId) }
            .filter { $0.isCurrentUser || $0.isVisibleOnMap || $0.status == "active" || $0.status == "stale" }
        if activeSession?.isActive == false {
            pollingTask?.cancel()
        }
    }

    private static func participant(
        _ response: LiveGroupParticipantResponse,
        currentUserID: String
    ) -> LiveGroupParticipant {
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
            paceSecondsPerKM: response.lastActivitySnapshot?.paceSecondsPerKM,
            isCurrentUser: response.userId == currentUserID
        )
    }

    private func shareMessage(url: URL, intent: SessionIntent?, title: String?) -> String {
        let sport = intent?.sport.rawValue ?? "run"
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let name, !name.isEmpty {
            return "Join \(name) on Plainstride: \(url.absoluteString)"
        }
        return "Join my Plainstride group \(sport): \(url.absoluteString)"
    }
}
