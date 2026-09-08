package com.plainstride.outbound.feature.health

import java.time.Instant

enum class HealthConnectAvailability { AVAILABLE, UPDATE_REQUIRED, UNAVAILABLE }
enum class HealthPermissionState { GRANTED, PARTIAL, DENIED, REVOKED, UNAVAILABLE }
enum class HealthActivityType { RUN, WALK, CYCLE }

data class HealthRoutePoint(
    val time: Instant,
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double? = null,
    val horizontalAccuracyMeters: Double? = null,
    val verticalAccuracyMeters: Double? = null,
)

data class HealthHeartRateSample(val time: Instant, val beatsPerMinute: Long)

/** Source identity is mandatory so imports remain deduplicated without comparing health facts. */
data class HealthSourceIdentity(
    val packageName: String,
    val sourceRecordId: String,
    val sourceRecordVersion: Long = 1,
    val healthConnectRecordId: String? = null,
) {
    val deduplicationKey: String get() = "$packageName:$sourceRecordId:$sourceRecordVersion"
}

enum class HealthRouteState { AVAILABLE, CONSENT_REQUIRED, NO_DATA }

data class HealthActivity(
    val source: HealthSourceIdentity,
    val type: HealthActivityType,
    val title: String?,
    val startTime: Instant,
    val endTime: Instant,
    val distanceMeters: Double? = null,
    val totalCaloriesKilocalories: Double? = null,
    val route: List<HealthRoutePoint> = emptyList(),
    val routeState: HealthRouteState = if (route.isEmpty()) HealthRouteState.NO_DATA else HealthRouteState.AVAILABLE,
    val heartRate: List<HealthHeartRateSample> = emptyList(),
)

data class HealthPermissionSnapshot(
    val availability: HealthConnectAvailability,
    val state: HealthPermissionState,
    val grantedPermissions: Set<String>,
    val requestedPermissions: Set<String>,
) {
    val missingPermissions: Set<String> get() = requestedPermissions - grantedPermissions
}

sealed interface HealthConnectResult<out T> {
    data class Success<T>(val value: T) : HealthConnectResult<T>
    data class PermissionRequired(val missingPermissions: Set<String>) : HealthConnectResult<Nothing>
    data class Unavailable(val updateRequired: Boolean) : HealthConnectResult<Nothing>
    data class Failure(val category: String) : HealthConnectResult<Nothing>
}

interface HealthConnectRepository {
    fun availability(): HealthConnectAvailability
    suspend fun permissionSnapshot(): HealthPermissionSnapshot
    suspend fun write(activity: HealthActivity): HealthConnectResult<Unit>
    suspend fun importOnboardingActivities(now: Instant = Instant.now()): HealthConnectResult<List<HealthActivity>>

    companion object {
        const val ONBOARDING_IMPORT_WEEKS = 8L
    }
}
