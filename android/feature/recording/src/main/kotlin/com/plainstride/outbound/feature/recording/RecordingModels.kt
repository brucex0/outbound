package com.plainstride.outbound.feature.recording

import com.plainstride.outbound.core.model.activity.ActivityCompanionType
import kotlinx.serialization.Serializable

@Serializable
enum class ActivityKind {
    RUNNING,
    WALKING,
    HIKING,
    CYCLING,
    SWIMMING,
}

@Serializable
enum class RecordingStatus { IDLE, ACTIVE, PAUSED, AWAITING_SAVE }

@Serializable
enum class LocationPermissionState { NOT_REQUESTED, PRECISE, APPROXIMATE, DENIED }

@Serializable
data class RecordedLocationSample(
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double?,
    val horizontalAccuracyMeters: Double,
    val verticalAccuracyMeters: Double?,
    val speedMetersPerSecond: Double?,
    val speedAccuracyMetersPerSecond: Double?,
    /** Wall-clock UTC milliseconds for persistence and cross-device interchange. */
    val capturedAtEpochMilliseconds: Long,
    /** Monotonic elapsed-realtime nanos, used only for same-boot ordering and deltas. */
    val capturedAtElapsedRealtimeNanos: Long,
)

@Serializable
data class RecordingSnapshot(
    val sessionId: String? = null,
    val accountId: String? = null,
    val activityKind: ActivityKind = ActivityKind.RUNNING,
    val status: RecordingStatus = RecordingStatus.IDLE,
    val revision: Long = 0,
    val startedAtEpochMilliseconds: Long? = null,
    val recordedAtEpochMilliseconds: Long = 0,
    val elapsedSeconds: Long = 0,
    val distanceMeters: Double = 0.0,
    val elevationGainMeters: Double = 0.0,
    val currentPaceSecondsPerKilometer: Double? = null,
    val latestLocation: RecordedLocationSample? = null,
    val track: List<RecordedLocationSample> = emptyList(),
    val recovered: Boolean = false,
    val companionType: ActivityCompanionType? = null,
) {
    val saveEligibility: ActivitySaveEligibility
        get() = ActivitySaveEligibility.evaluate(elapsedSeconds, distanceMeters)
}

enum class ActivitySaveEligibility {
    ELIGIBLE,
    TOO_SHORT;

    companion object {
        const val MINIMUM_DURATION_SECONDS = 300L
        const val MINIMUM_DISTANCE_METERS = 500.0

        fun evaluate(durationSeconds: Long, distanceMeters: Double): ActivitySaveEligibility =
            if (durationSeconds >= MINIMUM_DURATION_SECONDS || distanceMeters >= MINIMUM_DISTANCE_METERS) {
                ELIGIBLE
            } else {
                TOO_SHORT
            }
    }
}

sealed interface RecordingEvent {
    data class CommandApplied(val commandId: String, val status: RecordingStatus) : RecordingEvent
    data class CommandIgnored(val commandId: String, val reason: String) : RecordingEvent
    data class SessionFinished(val commandId: String, val snapshot: RecordingSnapshot) : RecordingEvent
    data class SessionDiscarded(val commandId: String, val sessionId: String?) : RecordingEvent
    data class LocationUnavailable(val permission: LocationPermissionState) : RecordingEvent
    data class Failure(val commandId: String?, val operation: String, val cause: Throwable) : RecordingEvent
}
