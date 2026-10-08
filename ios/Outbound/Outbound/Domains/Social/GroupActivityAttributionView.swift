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
            return String(format: String(localized: "group.activity.joined_with"), names)
        }
        let key: String.LocalizationValue = switch activityType {
        case "running", "trail_running": "group.activity.ran_with"
        case "walking": "group.activity.walked_with"
        case "hiking": "group.activity.hiked_with"
        case "cycling": "group.activity.rode_with"
        case "swimming": "group.activity.swam_with"
        default: "group.activity.worked_out_with"
        }
        return String(format: String(localized: key), names)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(context?.groupName.map { String(format: String(localized: "group.activity.named"), $0) }
                     ?? String(localized: "group.activity.label"))
            } icon: { Image(systemName: "person.2.fill") }
            .font(.caption.weight(.semibold))
            if let title = context?.title { Text(title).font(.caption) }
            if let companionText { Text(companionText).font(.caption).foregroundStyle(.secondary) }
        }
        .foregroundStyle(OutboundPalette.companion)
        .accessibilityAddTraits(context?.id != nil || eventID != nil ? .isButton : [])
        .overlay(alignment: .bottom) {
            if navigationFailed {
                Text(String(localized: "group.activity.open_error"))
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
    let eventID: String
    @State private var participants: [ActivityEventParticipantDTO] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(format: String(localized: "group.activity.started_count"), participants.filter { $0.startedAt != nil }.count))
                .font(.subheadline.weight(.semibold))
            ForEach(participants.filter { $0.startedAt != nil }) { participant in
                HStack {
                    SocialAvatar(name: participant.person.displayName, avatarURL: participant.person.avatarUrl)
                    Text(participant.person.displayName)
                    Spacer()
                    Text(participant.outcome != nil ? String(localized: "group.activity.finished") : participant.isRecording == true ? String(localized: "group.activity.recording") : String(localized: "group.activity.started"))
                        .foregroundStyle(.secondary)
                }.font(.caption)
            }
        }
        .task(id: eventID) {
            while !Task.isCancelled {
                do {
                    let detail = try await APIClient.shared.fetchActivityEvent(id: eventID)
                    participants = detail.participants ?? []
                } catch {
                    if Task.isCancelled { return }
                    ActivityDiagnosticLog.error(.persistence, "Group activity presence fetch failed error=\(ActivityDiagnosticLog.errorCategory(error))")
                }
                do { try await Task.sleep(for: .seconds(15)) } catch { return }
            }
        }
    }
}
