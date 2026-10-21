package com.plainstride.outbound.core.model.activity

import com.plainstride.outbound.core.model.CoachingPaceTarget
import java.time.Instant
import java.time.temporal.ChronoUnit

/** In-memory reference only; never written back as a server profile. */
fun localCoachingReference(activities: List<SavedActivity>, now: Instant = Instant.now()): Double? {
    val cutoff = now.minus(30, ChronoUnit.DAYS)
    val paces = activities.asSequence().filter {
        it.type == ActivityType.running && it.deletedAt == null &&
            it.durationSecs >= 300 && it.distanceM.isFinite() && it.distanceM >= 500
    }.mapNotNull { activity ->
        // Malformed imported timestamps cannot establish recent running history.
        val started = runCatching { Instant.parse(activity.startedAt) }.getOrNull() ?: return@mapNotNull null
        if (started < cutoff || started > now) return@mapNotNull null
        val pace = activity.averagePaceSecsPerKm
            ?: (activity.durationSecs * 1000.0 / activity.distanceM)
        pace.takeIf { it.isFinite() && it in 60.0..3600.0 }?.let { started to it }
    }.sortedByDescending { it.first }.take(10).map { it.second }.sorted().toList()
    if (paces.isEmpty()) return null
    return (paces[(paces.size - 1) / 2] + paces[paces.size / 2]) / 2
}

fun CoachingPaceTarget.resolveTarget(athleteReferencePace: Double?): Double? {
    val pace = when (reference) {
        "absolute" -> targetSecondsPerKilometer
        "athlete_reference" -> athleteReferencePace?.plus(athleteReferenceOffsetSeconds)
        else -> null
    }
    return pace?.takeIf { it.isFinite() && it in 60.0..3600.0 }
}
