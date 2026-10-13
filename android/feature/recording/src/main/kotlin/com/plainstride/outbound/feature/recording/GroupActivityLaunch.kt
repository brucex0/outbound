package com.plainstride.outbound.feature.recording

import com.plainstride.outbound.feature.social.SocialEvent
import java.time.Duration
import java.time.Instant

fun SocialEvent.recordingLaunch(): RecordingLaunchConfiguration {
    val duration = endsAt?.let { end -> runCatching { Duration.between(Instant.parse(startsAt), Instant.parse(end)).seconds.coerceAtLeast(60) }.onFailure { android.util.Log.w("PlainstrideGroups", "event_duration_parse type=${it.javaClass.simpleName}") }.getOrNull() }
    return RecordingLaunchConfiguration(
        activityKind = when(activityType?.lowercase()) { "walking" -> ActivityKind.WALKING; "hiking" -> ActivityKind.HIKING; "cycling" -> ActivityKind.CYCLING; "swimming" -> ActivityKind.SWIMMING; else -> ActivityKind.RUNNING },
        title = name, entrySource = "group_event", activityEventId = id, startImmediately = true,
        goal = duration?.let { RecordingGoal(RecordingGoalType.TIME, targetDurationSeconds = it) } ?: RecordingGoal(),
    )
}
