package com.plainstride.outbound.feature.health

import java.nio.charset.StandardCharsets
import java.time.Duration
import java.time.Instant
import java.util.UUID
import javax.inject.Inject
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.data.ActivitySyncScheduler
import com.plainstride.outbound.core.data.RecordedActivityDraft
import com.plainstride.outbound.core.data.RecordedActivityFactory
import com.plainstride.outbound.core.data.RecordedTrackPointDraft
import com.plainstride.outbound.core.model.activity.ActivitySource
import com.plainstride.outbound.core.model.activity.ActivityType

/** Persists Health Connect sessions through the same local-first activity/outbox boundary as recordings. */
class HealthActivityImporter @Inject constructor(
    private val health: HealthConnectRepository,
    private val activities: ActivityRepository,
    private val sync: ActivitySyncScheduler,
) {
    suspend fun import(accountId: String, now: Instant = Instant.now()): HealthConnectResult<List<HealthActivity>> {
        val result = health.importOnboardingActivities(now)
        if (result !is HealthConnectResult.Success) return result
        result.value.forEach { activity ->
            val activityId = stableActivityId(activity.source)
            if (activities.activity(accountId, activityId) != null) return@forEach
            val heartRates = activity.heartRate.map { it.beatsPerMinute.toInt() }
            val saved = RecordedActivityFactory.create(
                RecordedActivityDraft(
                    sessionId = activityId,
                    accountId = accountId,
                    type = when (activity.type) {
                        HealthActivityType.RUN -> ActivityType.running
                        HealthActivityType.WALK -> ActivityType.walking
                        HealthActivityType.CYCLE -> ActivityType.cycling
                    },
                    title = activity.title.orEmpty().ifBlank { activity.source.packageName },
                    startedAtEpochMs = activity.startTime.toEpochMilli(),
                    endedAtEpochMs = activity.endTime.toEpochMilli(),
                    durationSecs = Duration.between(activity.startTime, activity.endTime).seconds.coerceAtLeast(0).coerceAtMost(Int.MAX_VALUE.toLong()).toInt(),
                    distanceM = activity.distanceMeters?.coerceAtLeast(0.0) ?: 0.0,
                    elevationGainM = elevationGain(activity.route),
                    track = activity.route.mapIndexed { index, point ->
                        RecordedTrackPointDraft(point.time.toEpochMilli(), point.latitude, point.longitude, point.altitudeMeters, point.verticalAccuracyMeters, index == 0)
                    },
                ),
                now,
            ).copy(
                source = ActivitySource(
                    kind = "health_connect",
                    displayName = activity.source.packageName,
                    externalId = activity.source.deduplicationKey,
                    importedAt = now.toString(),
                ),
                averageHeartRateBpm = heartRates.takeIf(List<Int>::isNotEmpty)?.average()?.toInt(),
                maximumHeartRateBpm = heartRates.maxOrNull(),
                heartRateSampleCount = heartRates.size.takeIf { it > 0 },
                energyKilocalories = activity.totalCaloriesKilocalories?.coerceAtLeast(0.0)?.toInt(),
            )
            activities.save(saved)
        }
        if (result.value.isNotEmpty()) sync.schedule(accountId)
        return result
    }

    private fun stableActivityId(source: HealthSourceIdentity): String =
        UUID.nameUUIDFromBytes("health-connect:${source.deduplicationKey}".toByteArray(StandardCharsets.UTF_8)).toString()

    private fun elevationGain(points: List<HealthRoutePoint>): Double = points.zipWithNext().sumOf { (a, b) ->
        ((b.altitudeMeters ?: return@sumOf 0.0) - (a.altitudeMeters ?: return@sumOf 0.0)).coerceAtLeast(0.0)
    }
}
