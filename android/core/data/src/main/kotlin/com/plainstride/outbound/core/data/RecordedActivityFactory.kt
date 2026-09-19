package com.plainstride.outbound.core.data

import java.time.Instant
import com.plainstride.outbound.core.model.activity.ActivityCompanionType
import com.plainstride.outbound.core.model.activity.ActivityTrackPoint
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.SavedActivity

/** Module-neutral save boundary used to convert a finished recorder snapshot before its journal is cleared. */
data class RecordedActivityDraft(
    val sessionId: String,
    val accountId: String,
    val type: ActivityType,
    val title: String,
    val startedAtEpochMs: Long,
    val endedAtEpochMs: Long,
    val durationSecs: Int,
    val distanceM: Double,
    val elevationGainM: Double,
    val track: List<RecordedTrackPointDraft>,
    val companionType: ActivityCompanionType? = null,
)

data class RecordedTrackPointDraft(
    val timestampEpochMs: Long,
    val latitude: Double,
    val longitude: Double,
    val altitude: Double?,
    val verticalAccuracy: Double?,
    val startsNewSegment: Boolean = false,
)

object RecordedActivityFactory {
    fun create(draft: RecordedActivityDraft, savedAt: Instant = Instant.now()): SavedActivity {
        require(draft.sessionId.isNotBlank() && draft.accountId.isNotBlank())
        require(draft.durationSecs >= 0 && draft.distanceM >= 0 && draft.distanceM.isFinite())
        return SavedActivity(
            id = draft.sessionId,
            accountId = draft.accountId,
            type = draft.type,
            title = draft.title.trim().ifEmpty { "Activity" },
            createdAt = savedAt.toString(),
            startedAt = Instant.ofEpochMilli(draft.startedAtEpochMs).toString(),
            endedAt = Instant.ofEpochMilli(draft.endedAtEpochMs).toString(),
            durationSecs = draft.durationSecs,
            distanceM = draft.distanceM,
            averagePaceSecsPerKm = draft.distanceM.takeIf { it > 0 }?.let { draft.durationSecs / (it / 1_000.0) },
            elevationGainM = draft.elevationGainM,
            track = draft.track.map { point ->
                ActivityTrackPoint(
                    timestamp = Instant.ofEpochMilli(point.timestampEpochMs).toString(),
                    latitude = point.latitude,
                    longitude = point.longitude,
                    altitude = point.altitude,
                    verticalAccuracy = point.verticalAccuracy,
                    startsNewSegment = point.startsNewSegment,
                )
            },
            localUpdatedAt = savedAt.toString(),
            companionType = draft.companionType,
        )
    }
}
