import SwiftUI

struct GroupActivityAttribution: Codable, Sendable, Equatable {
    struct Participant: Codable, Sendable, Equatable {
        let person: TogetherPersonDTO
        let attendanceMode: String?
    }
    let id: String?
    let title: String?
    let groupName: String?
    let participants: [Participant]
}

struct GroupActivityAttributionView: View {
    var eventID: String? = nil
    let activityType: String
    var attribution: GroupActivityAttribution? = nil
    @EnvironmentObject private var appNavigationStore: AppNavigationStore
    @EnvironmentObject private var authStore: AuthStore
    @State private var navigationFailed = false
    @State private var resolved: GroupActivityAttribution?

    private var context: GroupActivityAttribution? { resolved ?? attribution }
    private var companionText: String? {
        guard let context, !context.participants.isEmpty else { return nil }
        let people = context.participants
        var names = people.prefix(2).map(\.person.displayName).joined(separator: ", ")
        if people.count > 2 { names += " +\(people.count - 2)" }
        if people.contains(where: { $0.attendanceMode != "in_person" }) {
            return String(format: String(localized: "group.activity.joined_with", table: "GroupActivity"), names)
        }
        let key: String.LocalizationValue = switch activityType {
        case "running", "trail_running": "group.activity.ran_with"
        case "walking": "group.activity.walked_with"
        case "hiking": "group.activity.hiked_with"
        case "cycling": "group.activity.rode_with"
        case "swimming": "group.activity.swam_with"
        default: "group.activity.worked_out_with"
        }
        return String(format: String(localized: key, table: "GroupActivity"), names)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(context?.groupName.map { String(format: String(localized: "group.activity.named", table: "GroupActivity"), $0) }
                     ?? String(localized: "group.activity.label", table: "GroupActivity"))
            } icon: { Image(systemName: "person.2.fill") }
            .font(.caption.weight(.semibold))
            if let title = context?.title { Text(title).font(.caption) }
            if let companionText { Text(companionText).font(.caption).foregroundStyle(.secondary) }
        }
        .foregroundStyle(OutboundPalette.companion)
        .accessibilityAddTraits(context?.id != nil || eventID != nil ? .isButton : [])
        .overlay(alignment: .bottom) {
            if navigationFailed {
                Text(String(localized: "group.activity.open_error", table: "GroupActivity"))
                    .font(.caption).padding(10)
                    .background(.regularMaterial, in: Capsule())
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard let id = context?.id ?? eventID else { return }
            Task {
                do {
                    let detail = try await APIClient.shared.fetchActivityEvent(id: id)
                    let event = ActivityEventDTO(id: detail.id, title: detail.title, activityType: detail.activityType,
                        startsAt: detail.startsAt, endsAt: detail.endsAt, locationName: detail.locationName,
                        latitude: detail.latitude, longitude: detail.longitude, paceNote: detail.paceNote,
                        group: detail.group, creator: detail.creator, groups: detail.groups,
                        compatibility: detail.compatibility, canParticipate: detail.canParticipate,
                        currentUserGoing: detail.currentUserGoing, status: detail.status)
                    appNavigationStore.openSharedDestination(.plannedActivity(event, entrySource: "activity_detail"))
                } catch {
                    if Task.isCancelled { return }
                    ActivityDiagnosticLog.error(.persistence, "Group activity navigation failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                    navigationFailed = true
                    do { try await Task.sleep(for: .seconds(3)) } catch { return }
                    navigationFailed = false
                }
            }
        }
        .task(id: eventID) {
            guard let eventID else { return }
            do {
                let detail = try await APIClient.shared.fetchActivityEvent(id: eventID)
                resolved = GroupActivityAttribution(id: detail.id, title: detail.title, groupName: detail.group?.name,
                    participants: (detail.participants ?? []).filter { $0.startedAt != nil && $0.person.id != authStore.user?.id }.map {
                        .init(person: $0.person, attendanceMode: $0.attendanceMode)
                    })
            } catch {
                if Task.isCancelled { return }
                ActivityDiagnosticLog.error(.persistence, "Group activity attribution fetch failed error=\(ActivityDiagnosticLog.errorCategory(error))")
            }
        }
    }
}

struct GroupActivityPresenceView: View {
    @Environment(\.analyticsManager) private var analyticsManager
    let eventID: String
    var title: String? = nil
    @State private var participants: [ActivityEventParticipantDTO] = []
    @State private var isExpanded = false
    @State private var hasTrackedPresence = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(participants) { participant in
                        HStack {
                            SocialAvatar(name: participant.person.displayName, avatarURL: participant.person.avatarUrl)
                            Text(participant.person.displayName)
                            Spacer()
                            Text(status(participant)).foregroundStyle(.secondary)
                        }.font(.caption)
                    }
                }
            }
            .frame(maxHeight: 180)
        } label: {
            VStack(alignment: .leading, spacing: 3) {
                Label(title ?? String(localized: "group.activity.label", table: "GroupActivity"), systemImage: "person.2.fill")
                    .font(.subheadline.weight(.semibold))
                Text(String(format: String(localized: "group.activity.counts", table: "GroupActivity"),
                            participants.filter { $0.status == "going" }.count, participants.filter { $0.startedAt != nil }.count,
                            participants.filter { $0.outcome == "completed" || $0.outcome == "no_recording" }.count))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .task(id: eventID) {
            while !Task.isCancelled {
                do {
                    let detail = try await APIClient.shared.fetchActivityEvent(id: eventID)
                    participants = detail.participants ?? []
                    if !hasTrackedPresence {
                        hasTrackedPresence = true
                        await analyticsManager?.track(.init(.groupActivityPresenceViewed, properties: [
                            .participantCountBucket: .string(ProductAnalyticsBucket.count(participants.count))
                        ]))
                    }
                } catch {
                    if Task.isCancelled || (error as NSError).code == NSURLErrorCancelled { return }
                    ActivityDiagnosticLog.error(.persistence, "Group activity presence fetch failed error=\(ActivityDiagnosticLog.errorCategory(error)) code=\((error as NSError).code)")
                }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }

    private func status(_ participant: ActivityEventParticipantDTO) -> String {
        if participant.outcome == "completed" || participant.outcome == "no_recording" {
            return String(localized: "group.activity.finished", table: "GroupActivity")
        }
        if participant.isRecording == true { return String(localized: "group.activity.recording", table: "GroupActivity") }
        return participant.startedAt != nil
            ? String(localized: "group.activity.started", table: "GroupActivity")
            : String(localized: "group.activity.not_started", table: "GroupActivity")
    }
}
