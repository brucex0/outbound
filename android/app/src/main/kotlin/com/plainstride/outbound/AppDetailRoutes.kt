package com.plainstride.outbound

import android.net.Uri

/** A detail route identifies its content; it never names or creates a hosting tab/list. */
internal object AppDetailRoutes {
    const val Stretch = "stretch?source={source}"
    fun stretch(source: String = "standalone") = "stretch?source=${encode(source)}"
    const val Connections = "connections?source={source}&adding={adding}"
    const val Activity = "activity_detail/{id}?source={source}"
    const val Post = "social_activity_detail/{postId}"
    const val Event = "social_activity_event/{eventId}?source={source}"
    const val Profile = "social_profile/{personId}?source={source}"
    const val ConnectionProfile = "connection_profile/{code}"
    const val Group = "social_group/{groupId}?source={source}&invitation={invitation}"
    const val Invitation = "social_invitation/{id}"
    const val GroupInvite = "group_invite/{token}"
    const val Route = "route_detail/{routeId}"
    const val Safety = "safety_detail/{kind}/{id}?source={source}"
    const val Notification = "notification_detail/{id}"

    private fun encode(value: String) = Uri.encode(value)
    fun connections(source: String, adding: Boolean = false) = "connections?source=${encode(source)}&adding=$adding"
    fun activity(id: String, source: String) = "activity_detail/${encode(id)}?source=${encode(source)}"
    fun post(id: String) = "social_activity_detail/${encode(id)}"
    fun event(id: String, source: String) = "social_activity_event/${encode(id)}?source=${encode(source)}"
    fun profile(id: String, source: String = "social") = "social_profile/${encode(id)}?source=${encode(source)}"
    fun connectionProfile(code: String) = "connection_profile/${encode(code)}"
    fun group(id: String, source: String, invitation: String? = null) =
        "social_group/${encode(id)}?source=${encode(source)}&invitation=${encode(invitation.orEmpty())}"
    fun invitation(id: String) = "social_invitation/${encode(id)}"
    fun groupInvite(token: String) = "group_invite/${encode(token)}"
    fun route(id: String) = "route_detail/${encode(id)}"
    fun safety(kind: String, id: String, source: String) = "safety_detail/${encode(kind)}/${encode(id)}?source=${encode(source)}"
    fun notification(id: String) = "notification_detail/${encode(id)}"
}
