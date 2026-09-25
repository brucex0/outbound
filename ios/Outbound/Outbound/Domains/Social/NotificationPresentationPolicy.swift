import Foundation

enum NotificationCenterTier: Int, CaseIterable, Identifiable, Sendable {
    case needsYou
    case updates
    case cheersAndMilestones

    var id: Self { self }

    var analyticsValue: String {
        switch self {
        case .needsYou: "needs_you"
        case .updates: "updates"
        case .cheersAndMilestones: "cheers_milestones"
        }
    }

    var localizedTitle: String {
        switch self {
        case .needsYou:
            String(localized: "safety.inbox.needs_you", defaultValue: "Needs you")
        case .updates:
            String(localized: "safety.inbox.updates", defaultValue: "Updates")
        case .cheersAndMilestones:
            String(localized: "safety.inbox.cheers_milestones", defaultValue: "Cheers & milestones")
        }
    }
}

enum NotificationCenterCategory: String, Sendable {
    case actionable
    case update
    case support
}

enum NotificationCenterDestination: Sendable, Equatable {
    case connections
    case post
    case runInvitation
    case activityEvent
    case groupInvitation
    case group
    case liveCheer
    case generic
}

struct NotificationPresentation: Sendable {
    let tier: NotificationCenterTier
    let category: NotificationCenterCategory
    let destination: NotificationCenterDestination
    let urgencyRank: Int
    let aggregationKey: String?
}

struct NotificationCenterPresentationItem: Identifiable, Sendable {
    let primary: SocialNotificationDTO
    let notifications: [SocialNotificationDTO]
    let presentation: NotificationPresentation

    var id: String { primary.id }
    var hasUnread: Bool { notifications.contains { $0.readAt == nil } }
    var additionalCount: Int { max(notifications.count - 1, 0) }
}

/// Central policy for durable inbox classification, ordering, aggregation, routing, and attention.
/// Unknown future types intentionally remain visible in Updates with a generic destination.
enum NotificationPresentationPolicy {
    /// Apple Health is a local-only, batched Needs you card and never enters the backend inbox.
    static let localAppleHealthImportType = "local_apple_health_import"
    /// Workout reminders remain OS-only and never enter Notification Center.
    static let localWorkoutReminderType = "local_workout_reminder"
    /// The backend caps a live share at eight hours. Notifications older than
    /// that cannot still represent an active live session, even if a stale
    /// backend record remains active.
    static let maximumLiveCheerDuration: TimeInterval = 8 * 60 * 60

    static func isCurrent(_ notification: SocialNotificationDTO, now: Date = Date()) -> Bool {
        guard notification.type == "liveCheerInvitation" else { return true }
        return notification.createdAt.addingTimeInterval(maximumLiveCheerDuration) > now
    }

    static func presentation(for type: String, objectID: String?) -> NotificationPresentation {
        switch type {
        case "liveCheerInvitation":
            actionable(.liveCheer, urgencyRank: 0)
        case "connectionRequest":
            actionable(.connections)
        case "runInvitation":
            actionable(.runInvitation)
        case "groupInvitation":
            actionable(.groupInvitation)
        case "groupJoinRequest":
            actionable(.group)
        case "groupRunInvitation":
            actionable(.generic)

        case "connectionAccepted":
            update(.connections)
        case "comment":
            update(.post)
        case "invitationAccepted", "activityEventJoined":
            update(.activityEvent)
        case "groupInvitationAccepted", "groupOwnershipTransferred", "groupJoinRequestApproved", "groupJoinRequestDenied":
            update(.group)
        case "activity", "groupRunStarted", "groupRunUpdated":
            update(.generic)
        case "liveShare", "liveShareStarted", "liveShareUpdated":
            update(.liveCheer)

        case "cheer":
            support(.post, aggregationKey: nonempty(objectID).map { "cheer:\($0)" })
        case "groupCheer":
            support(.group, aggregationKey: nonempty(objectID).map { "groupCheer:\($0)" })
        case "groupWeeklyGoalCompleted":
            support(.group)

        default:
            update(.generic)
        }
    }

    static func items(from notifications: [SocialNotificationDTO], now: Date = Date()) -> [NotificationCenterPresentationItem] {
        let sorted = notifications.filter { isCurrent($0, now: now) }.sorted { lhs, rhs in
            let left = presentation(for: lhs.type, objectID: lhs.objectId)
            let right = presentation(for: rhs.type, objectID: rhs.objectId)
            if left.tier.rawValue != right.tier.rawValue { return left.tier.rawValue < right.tier.rawValue }
            if left.urgencyRank != right.urgencyRank { return left.urgencyRank < right.urgencyRank }
            return lhs.createdAt > rhs.createdAt
        }

        var orderedKeys: [String] = []
        var grouped: [String: [SocialNotificationDTO]] = [:]
        for notification in sorted {
            let value = presentation(for: notification.type, objectID: notification.objectId)
            let key = value.aggregationKey ?? "notification:\(notification.id)"
            if grouped[key] == nil { orderedKeys.append(key) }
            grouped[key, default: []].append(notification)
        }

        return orderedKeys.compactMap { key in
            guard let notifications = grouped[key], let primary = notifications.first else { return nil }
            return NotificationCenterPresentationItem(
                primary: primary,
                notifications: notifications,
                presentation: presentation(for: primary.type, objectID: primary.objectId)
            )
        }
    }

    static func actionableAttentionCount(in notifications: [SocialNotificationDTO], now: Date = Date()) -> Int {
        notifications.count {
            isCurrent($0, now: now)
                && presentation(for: $0.type, objectID: $0.objectId).tier == .needsYou
        }
    }

    private static func actionable(
        _ destination: NotificationCenterDestination,
        urgencyRank: Int = 1
    ) -> NotificationPresentation {
        NotificationPresentation(
            tier: .needsYou,
            category: .actionable,
            destination: destination,
            urgencyRank: urgencyRank,
            aggregationKey: nil
        )
    }

    private static func update(_ destination: NotificationCenterDestination) -> NotificationPresentation {
        NotificationPresentation(
            tier: .updates,
            category: .update,
            destination: destination,
            urgencyRank: 1,
            aggregationKey: nil
        )
    }

    private static func support(
        _ destination: NotificationCenterDestination,
        aggregationKey: String? = nil
    ) -> NotificationPresentation {
        NotificationPresentation(
            tier: .cheersAndMilestones,
            category: .support,
            destination: destination,
            urgencyRank: 1,
            aggregationKey: aggregationKey
        )
    }

    private static func nonempty(_ value: String?) -> String? {
        value?.isEmpty == false ? value : nil
    }
}
