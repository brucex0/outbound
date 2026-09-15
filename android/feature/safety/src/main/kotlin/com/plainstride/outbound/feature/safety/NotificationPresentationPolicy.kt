package com.plainstride.outbound.feature.safety

enum class NotificationCenterSection(val analyticsValue: String) {
    NEEDS_YOU("needs_you"),
    UPDATES("updates"),
    CHEERS_AND_MILESTONES("cheers_milestones"),
}

enum class NotificationCategory(val analyticsValue: String) {
    ACTIONABLE("actionable"),
    UPDATE("update"),
    SUPPORT("support"),
}

data class NotificationPresentation(
    val section: NotificationCenterSection,
    val category: NotificationCategory,
    val destination: NotificationDestination,
    val urgencyRank: Int = 1,
    val aggregateKey: String? = null,
)

data class NotificationCenterItem(
    val primary: InboxNotification,
    val notifications: List<InboxNotification>,
    val presentation: NotificationPresentation,
) {
    val id: String = primary.id
    val unread: Boolean = notifications.any { it.readAt == null }
    val additionalCount: Int = (notifications.size - 1).coerceAtLeast(0)
}

/**
 * One bounded policy for durable inbox classification, ordering, aggregation, routing, and attention.
 * Unknown future types intentionally remain visible in Updates and open the generic inbox destination.
 */
object NotificationPresentationPolicy {
    fun presentationFor(type: String, objectId: String?): NotificationPresentation {
        val id = objectId?.takeIf(String::isNotBlank)
        return when (type) {
            "liveCheerInvitation" -> NotificationPresentation(
                NotificationCenterSection.NEEDS_YOU,
                NotificationCategory.ACTIONABLE,
                id?.let(NotificationDestination::Live) ?: NotificationDestination.Inbox,
                urgencyRank = 0,
            )
            "connectionRequest" -> NotificationPresentation(
                NotificationCenterSection.NEEDS_YOU,
                NotificationCategory.ACTIONABLE,
                NotificationDestination.Connections,
            )
            "runInvitation", "circleInvitation" -> NotificationPresentation(
                NotificationCenterSection.NEEDS_YOU,
                NotificationCategory.ACTIONABLE,
                id?.let(NotificationDestination::Invitation) ?: NotificationDestination.Inbox,
            )
            "groupRunInvitation" -> NotificationPresentation(
                NotificationCenterSection.NEEDS_YOU,
                NotificationCategory.ACTIONABLE,
                id?.let(NotificationDestination::Group) ?: NotificationDestination.Inbox,
            )

            "connectionAccepted" -> update(NotificationDestination.Connections)
            "comment" -> update(id?.let(NotificationDestination::Post) ?: NotificationDestination.Inbox)
            "invitationAccepted", "activityEventJoined" ->
                update(id?.let(NotificationDestination::Event) ?: NotificationDestination.Inbox)
            "circleInvitationAccepted", "circleOwnershipTransferred" ->
                update(id?.let(NotificationDestination::Circle) ?: NotificationDestination.Inbox)
            "activity" -> update(id?.let(NotificationDestination::Activity) ?: NotificationDestination.Inbox)
            "groupRunStarted", "groupRunUpdated" ->
                update(id?.let(NotificationDestination::Group) ?: NotificationDestination.Inbox)
            "liveShare", "liveShareStarted", "liveShareUpdated" ->
                update(id?.let(NotificationDestination::Live) ?: NotificationDestination.Inbox)

            "cheer" -> support(
                id?.let(NotificationDestination::Post) ?: NotificationDestination.Inbox,
                id?.let { "cheer:$it" },
            )
            "circleCheer" -> support(
                id?.let(NotificationDestination::Circle) ?: NotificationDestination.Inbox,
                id?.let { "circleCheer:$it" },
            )
            "circleWeeklyGoalCompleted" -> support(
                id?.let(NotificationDestination::Circle) ?: NotificationDestination.Inbox,
            )

            // Includes any future backend category: visible, non-actionable, and generically routable.
            else -> update(NotificationDestination.Inbox)
        }
    }

    fun items(notifications: List<InboxNotification>): List<NotificationCenterItem> {
        val sorted = notifications.sortedWith(
            compareBy<InboxNotification> { presentationFor(it.type, it.objectId).section.ordinal }
                .thenBy { presentationFor(it.type, it.objectId).urgencyRank }
                .thenByDescending { it.createdAt },
        )
        val grouped = linkedMapOf<String, MutableList<InboxNotification>>()
        sorted.forEach { notification ->
            val presentation = presentationFor(notification.type, notification.objectId)
            val key = presentation.aggregateKey ?: "notification:${notification.id}"
            grouped.getOrPut(key) { mutableListOf() }.add(notification)
        }
        return grouped.values.map { groupedNotifications ->
            val primary = groupedNotifications.first()
            NotificationCenterItem(primary, groupedNotifications, presentationFor(primary.type, primary.objectId))
        }
    }

    fun actionableAttentionCount(notifications: List<InboxNotification>): Int =
        notifications.count { presentationFor(it.type, it.objectId).section == NotificationCenterSection.NEEDS_YOU }

    fun deepLinkDestination(type: String, objectId: String?): String = when (presentationFor(type, objectId).destination) {
        NotificationDestination.Connections -> "connections"
        is NotificationDestination.Activity -> "activity"
        is NotificationDestination.Post -> "post"
        is NotificationDestination.Event -> "event"
        is NotificationDestination.Invitation -> "invitation"
        is NotificationDestination.Circle -> "circle"
        is NotificationDestination.Group -> "group"
        is NotificationDestination.Live -> "live"
        NotificationDestination.Inbox -> "inbox"
    }

    private fun update(destination: NotificationDestination) = NotificationPresentation(
        NotificationCenterSection.UPDATES,
        NotificationCategory.UPDATE,
        destination,
    )

    private fun support(destination: NotificationDestination, aggregateKey: String? = null) =
        NotificationPresentation(
            NotificationCenterSection.CHEERS_AND_MILESTONES,
            NotificationCategory.SUPPORT,
            destination,
            aggregateKey = aggregateKey,
        )
}

fun routeNotification(type: String, objectId: String?): NotificationDestination =
    NotificationPresentationPolicy.presentationFor(type, objectId).destination
