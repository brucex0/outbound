import Foundation
import Network
import XCTest

/// Stateful, loopback-only HTTP fixture. App stores and mutation handlers use
/// the normal network path; only authentication and unrelated setup are seeded.
final class GroupImprovementsFixture: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "GroupImprovementsFixture")
    private let lock = NSLock()
    private let viewer: String
    private var requests: [(String, [String: Any])] = []
    private var approvalRequired = true
    private var joinPolicy = "open"
    private var reviewIDs = ["approve-request", "deny-request"]
    private var invitationStatus = "pending"
    private var eventBody: [String: Any]?
    private var rejectFirstActivity = true

    init(viewer: String = "owner") throws {
        self.viewer = viewer
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(IPv4Address("127.0.0.1")!), port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() throws -> String {
        let ready = XCTestExpectation(description: "Group fixture ready")
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.fulfill() }
            if case .failed = state { ready.fulfill() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { connection.cancel(); return }
            connection.start(queue: self.queue)
            self.receive(connection, buffered: Data())
        }
        listener.start(queue: queue)
        guard XCTWaiter.wait(for: [ready], timeout: 5) == .completed, let port = listener.port else { throw FixtureError.unavailable }
        return "http://127.0.0.1:\(port.rawValue)"
    }

    func stop() { listener.cancel() }

    func bodies(_ path: String) -> [[String: Any]] {
        lock.lock(); defer { lock.unlock() }
        return requests.filter { $0.0 == path }.map(\.1)
    }

    private func receive(_ connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] bytes, _, complete, error in
            guard let self else { connection.cancel(); return }
            var data = buffered
            if let bytes { data.append(bytes) }
            guard let boundary = data.range(of: Data("\r\n\r\n".utf8)),
                  let headers = String(data: data[..<boundary.lowerBound], encoding: .utf8) else {
                if complete || error != nil { connection.cancel() } else { self.receive(connection, buffered: data) }
                return
            }
            let contentLength = headers.components(separatedBy: "\r\n").first(where: { $0.lowercased().hasPrefix("content-length:") }).flatMap { Int($0.split(separator: ":", maxSplits: 1).last!.trimmingCharacters(in: .whitespaces)) } ?? 0
            guard data.count >= boundary.upperBound + contentLength else {
                if complete || error != nil { connection.cancel() } else { self.receive(connection, buffered: data) }
                return
            }
            let firstLine = headers.components(separatedBy: "\r\n")[0].split(separator: " ")
            guard firstLine.count >= 2 else { connection.cancel(); return }
            let target = String(firstLine[1])
            let path = target.components(separatedBy: "?")[0]
            let method = String(firstLine[0])
            let bodyData = data[boundary.upperBound..<(boundary.upperBound + contentLength)]
            let body = (try? JSONSerialization.jsonObject(with: bodyData)) as? [String: Any] ?? [:]
            self.lock.lock()
            self.requests.append(("\(method) \(target)", body))
            let (status, payload) = self.respond(method: method, path: path, target: target, body: body)
            self.lock.unlock()
            let json = try! JSONSerialization.data(withJSONObject: payload)
            var response = Data("HTTP/1.1 \(status) \(status < 400 ? "OK" : "Rejected")\r\nContent-Type: application/json\r\nContent-Length: \(json.count)\r\nConnection: close\r\n\r\n".utf8)
            response.append(json)
            connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    private func respond(method: String, path: String, target: String, body: [String: Any]) -> (Int, [String: Any]) {
        if path == "/social/groups/invitations/inbox" {
            return (200, ["invitations": viewer == "invitee" && ["pending", "awaiting_approval"].contains(invitationStatus) ? [invitation()] : []])
        }
        if path == "/social/groups/invitations/fixture-invitation/accept" {
            invitationStatus = "awaiting_approval"
            return (200, group())
        }
        if path == "/social/groups/invitations/fixture-invitation/decline" {
            invitationStatus = "declined"
            return (200, ["status": "declined"])
        }
        if path == "/social/groups" {
            let discovered = target.contains("scope=discover")
            return (200, ["groups": viewer == "invitee" || discovered ? [] : [group()], "policy": ["memberLimit": 500], "nextCursor": NSNull()])
        }
        if path == "/social/groups/ui-test-group" {
            if method == "PATCH" {
                approvalRequired = body["memberInviteApprovalRequired"] as? Bool ?? approvalRequired
                joinPolicy = body["joinPolicy"] as? String ?? joinPolicy
            }
            return (200, group())
        }
        if path.hasPrefix("/social/groups/ui-test-group/join-requests/") {
            let parts = path.split(separator: "/")
            reviewIDs.removeAll { $0 == String(parts[parts.count - 2]) }
            return (200, ["group": group(), "status": parts.last == "approve" ? "approved" : "denied"])
        }
        if path == "/social/groups/ui-test-group/invitations" {
            return (201, ["group": group(), "invitations": [["id": "sent-invite", "recipientUserId": "fixture-target", "status": "sent"]]])
        }
        if path == "/social/activity-events", method == "POST" {
            if rejectFirstActivity { rejectFirstActivity = false; return (422, ["error": "synthetic_retryable_failure"]) }
            eventBody = body
            return (201, event())
        }
        if path == "/social/activity-events/fixture-event" {
            if method == "PATCH" { eventBody = body }
            return (200, event())
        }
        if path == "/social/activity-events/fixture-event/cancel" { return (200, event(cancelled: true)) }
        if path == "/social/home" || path == "/social/together" {
            return (200, ["upcomingRuns": [], "pastEvents": [], "groups": [], "posts": [], "nextFeedCursor": NSNull()])
        }
        if path == "/social/connections" {
            return (200, ["connections": [["id": "fixture-connection", "person": person("fixture-target", "Fixture Connection"), "status": "accepted", "direction": "outgoing"]], "nextCursor": NSNull()])
        }
        if path == "/social/notifications" { return (200, ["notifications": []]) }
        if path == "/social/blocks" { return (200, ["blocks": []]) }
        if path == "/recognition" { return (200, ["awards": []]) }
        return (404, ["error": "synthetic_fixture_unavailable"])
    }

    private func person(_ id: String, _ name: String) -> [String: Any] {
        ["id": id, "username": id, "displayName": name, "avatarUrl": NSNull()]
    }

    private func timestamp(_ offset: Double = 0) -> String {
        ISO8601DateFormatter().string(from: Date().addingTimeInterval(offset))
    }

    private func invitation() -> [String: Any] {
        ["id": "fixture-invitation", "groupId": "ui-test-group", "group": ["id": "ui-test-group", "name": "Golden Gate Community"], "sender": person("fixture-member", "Fixture Inviter"), "status": invitationStatus, "approvalRequired": true, "createdAt": timestamp(-60), "expiresAt": timestamp(86_400)]
    }

    private func group() -> [String: Any] {
        var payload: [String: Any] = [
            "id": "ui-test-group", "name": "Golden Gate Community", "lifecycle": "active",
            "owner": person("fixture-owner", "Fixture Owner"), "trustPolicy": "community", "groupType": "community",
            "visibility": "public", "joinPolicy": joinPolicy, "memberInviteApprovalRequired": approvalRequired,
            "memberCount": 2, "memberLimit": 500, "timeZone": "America/Los_Angeles", "resetWeekday": 1,
            "loadedDetailPayload": true, "canInvite": viewer != "invitee",
            "capabilities": ["weeklyTheme": false, "workoutContributions": false, "presetCheers": false, "notices": false, "scheduledActivities": true],
        ]
        if viewer == "invitee" {
            payload["invitationPreview"] = true
            payload["pendingInvitation"] = invitation()
            return payload
        }
        payload["role"] = viewer
        payload["membershipRole"] = viewer
        payload["members"] = [["id": "fixture-membership", "user": person("fixture-owner", "Fixture Owner"), "role": "owner", "isCurrentUser": viewer == "owner", "contributedCount": 0]]
        payload["pendingRequestCount"] = viewer == "owner" ? reviewIDs.count : 0
        payload["joinRequests"] = viewer == "owner" ? reviewIDs.map { ["id": $0, "requester": person($0, "Applicant \($0)"), "inviter": person("fixture-member", "Fixture Inviter"), "createdAt": timestamp(-30)] } : []
        if eventBody != nil { payload["upcomingActivities"] = [event()] }
        return payload
    }

    private func event(cancelled: Bool = false) -> [String: Any] {
        let body = eventBody ?? [:]
        let start = body["startsAt"] as? String ?? timestamp(86_400)
        return ["id": "fixture-event", "title": body["title"] ?? "Weekly fixture activity", "activityType": "running", "startsAt": start, "endsAt": timestamp(90_000), "locationName": NSNull(), "paceNote": NSNull(), "group": ["id": "ui-test-group", "name": "Golden Gate Community"], "creator": person("fixture-owner", "Fixture Owner"), "groups": [], "attendeeCount": 1, "currentUserGoing": true, "canParticipate": !cancelled, "compatibility": NSNull(), "status": cancelled ? "cancelled" : "scheduled", "currentUserRole": "owner", "participationMode": "hybrid", "seriesId": "fixture-series", "recurrence": body["recurrence"] ?? ["timeZone": "America/Los_Angeles", "intervalWeeks": 1, "weekdays": [6]], "participants": []]
    }

    private enum FixtureError: Error { case unavailable }
}
