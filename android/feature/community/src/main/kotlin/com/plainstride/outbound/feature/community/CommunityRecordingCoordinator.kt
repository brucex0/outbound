package com.plainstride.outbound.feature.community

import com.plainstride.outbound.feature.recording.ActivityKind
import com.plainstride.outbound.feature.recording.FollowedRouteConfiguration
import com.plainstride.outbound.feature.recording.RecordingLaunchConfiguration
import com.plainstride.outbound.feature.recording.RecordingRoutePoint

/** Keeps route-to-recording integration inside the route feature rather than the app shell. */
object CommunityRecordingCoordinator {
    fun launch(route: CommunityRoute, reverse: Boolean): RecordingLaunchConfiguration {
        val points = route.guidancePoints()
        return RecordingLaunchConfiguration(
            activityKind = when (route.activityType.lowercase()) {
                "walking" -> ActivityKind.WALKING
                "cycling" -> ActivityKind.CYCLING
                "hiking" -> ActivityKind.HIKING
                else -> ActivityKind.RUNNING
            },
            title = route.name,
            entrySource = "community_route",
            followedRoute = FollowedRouteConfiguration(
                id = route.id,
                name = route.name,
                shape = route.routeShape,
                distanceMeters = route.distanceM,
                elevationGainMeters = route.elevationGainM,
                reverse = reverse,
                points = points.map { RecordingRoutePoint(it.latitude, it.longitude, it.altitudeM) },
            ),
        )
    }
}
