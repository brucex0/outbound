package run.plainstride.feature.health

import android.content.Context
import android.os.Build
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ExerciseRoute
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.metadata.Device
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import run.plainstride.core.analytics.AnalyticsEvent
import run.plainstride.core.analytics.AnalyticsProperty
import run.plainstride.core.analytics.ProductAnalytics
import java.time.Instant
import java.time.ZoneId
import kotlin.reflect.KClass

class DefaultHealthConnectRepository(
    private val context: Context,
    private val analytics: ProductAnalytics,
    private val client: HealthConnectClient?,
) : HealthConnectRepository {
    private val permissionHistory = context.getSharedPreferences("plainstride_health_connect", Context.MODE_PRIVATE)
    override fun availability(): HealthConnectAvailability = when (HealthConnectClient.getSdkStatus(context)) {
        HealthConnectClient.SDK_AVAILABLE -> HealthConnectAvailability.AVAILABLE
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> HealthConnectAvailability.UPDATE_REQUIRED
        else -> HealthConnectAvailability.UNAVAILABLE
    }

    override suspend fun permissionSnapshot(): HealthPermissionSnapshot {
        val available = availability()
        if (available != HealthConnectAvailability.AVAILABLE || client == null) {
            return HealthPermissionSnapshot(available, HealthPermissionState.UNAVAILABLE, emptySet(), PlainstrideHealthPermissions.all)
        }
        val granted = client.permissionController.getGrantedPermissions()
        val hadPermission = permissionHistory.getBoolean("ever_granted", false)
        val state = when {
            PlainstrideHealthPermissions.all.all(granted::contains) -> HealthPermissionState.GRANTED
            granted.any(PlainstrideHealthPermissions.all::contains) -> HealthPermissionState.PARTIAL
            hadPermission -> HealthPermissionState.REVOKED
            else -> HealthPermissionState.DENIED
        }
        if (granted.any(PlainstrideHealthPermissions.all::contains)) {
            permissionHistory.edit().putBoolean("ever_granted", true).apply()
        }
        return HealthPermissionSnapshot(available, state, granted, PlainstrideHealthPermissions.all)
    }

    override suspend fun write(activity: HealthActivity): HealthConnectResult<Unit> = healthOperation("health_connect_write") {
        if (activity.source.packageName != context.packageName) {
            return@healthOperation HealthConnectResult.Failure("external_source_writeback_disallowed")
        }
        val hc = client ?: return@healthOperation unavailableResult()
        val granted = hc.permissionController.getGrantedPermissions()
        val sessionPermission = HealthPermission.getWritePermission(ExerciseSessionRecord::class)
        if (sessionPermission !in granted) return@healthOperation HealthConnectResult.PermissionRequired(setOf(sessionPermission))

        val zone = ZoneId.systemDefault().rules
        val device = Device(
            manufacturer = Build.MANUFACTURER,
            model = Build.MODEL,
            type = Device.TYPE_PHONE,
        )
        fun metadata(suffix: String) = Metadata.activelyRecorded(
            clientRecordId = "${activity.source.sourceRecordId}:$suffix",
            clientRecordVersion = activity.source.sourceRecordVersion,
            device = device,
        )
        val route = if (HealthPermission.PERMISSION_WRITE_EXERCISE_ROUTE in granted && activity.route.isNotEmpty()) {
            ExerciseRoute(activity.route.map { point ->
                ExerciseRoute.Location(
                    time = point.time,
                    latitude = point.latitude,
                    longitude = point.longitude,
                    altitude = point.altitudeMeters?.let(Length::meters),
                    horizontalAccuracy = point.horizontalAccuracyMeters?.let(Length::meters),
                    verticalAccuracy = point.verticalAccuracyMeters?.let(Length::meters),
                )
            })
        } else null
        val records = mutableListOf<androidx.health.connect.client.records.Record>(
            ExerciseSessionRecord(
                startTime = activity.startTime,
                startZoneOffset = zone.getOffset(activity.startTime),
                endTime = activity.endTime,
                endZoneOffset = zone.getOffset(activity.endTime),
                exerciseType = activity.type.exerciseType,
                title = activity.title,
                exerciseRoute = route,
                metadata = metadata("session"),
            ),
        )
        val interval = activity.startTime to activity.endTime
        activity.distanceMeters?.takeIf { it.isFinite() && it >= 0 && HealthPermission.getWritePermission(DistanceRecord::class) in granted }?.let {
            records += DistanceRecord(interval.first, zone.getOffset(interval.first), interval.second, zone.getOffset(interval.second), Length.meters(it), metadata("distance"))
        }
        activity.totalCaloriesKilocalories?.takeIf { it.isFinite() && it >= 0 && HealthPermission.getWritePermission(TotalCaloriesBurnedRecord::class) in granted }?.let {
            records += TotalCaloriesBurnedRecord(interval.first, zone.getOffset(interval.first), interval.second, zone.getOffset(interval.second), Energy.kilocalories(it), metadata("calories"))
        }
        val validHeartRate = activity.heartRate.filter { it.time in activity.startTime..activity.endTime && it.beatsPerMinute in 30..240 }
        if (validHeartRate.isNotEmpty() && HealthPermission.getWritePermission(HeartRateRecord::class) in granted) {
            records += HeartRateRecord(
                startTime = activity.startTime,
                startZoneOffset = zone.getOffset(activity.startTime),
                endTime = activity.endTime,
                endZoneOffset = zone.getOffset(activity.endTime),
                samples = validHeartRate.map { HeartRateRecord.Sample(it.time, it.beatsPerMinute) },
                metadata = metadata("heart_rate"),
            )
        }
        hc.insertRecords(records)
        HealthConnectResult.Success(Unit)
    }

    override suspend fun importOnboardingActivities(now: Instant): HealthConnectResult<List<HealthActivity>> =
        healthOperation("health_connect_import") {
            val hc = client ?: return@healthOperation unavailableResult()
            val granted = hc.permissionController.getGrantedPermissions()
            val sessionPermission = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
            if (sessionPermission !in granted) return@healthOperation HealthConnectResult.PermissionRequired(setOf(sessionPermission))
            val start = now.minusSeconds(HealthConnectRepository.ONBOARDING_IMPORT_WEEKS * 7 * 24 * 60 * 60)
            val range = TimeRangeFilter.between(start, now)
            val sessions = readAll(hc, ExerciseSessionRecord::class, range)
                .filter { it.metadata.dataOrigin.packageName != context.packageName }
                .filter { it.exerciseType in supportedExerciseTypes }
            val distances = readIfGranted(hc, granted, DistanceRecord::class, range)
            val calories = readIfGranted(hc, granted, TotalCaloriesBurnedRecord::class, range)
            val heartRates = readIfGranted(hc, granted, HeartRateRecord::class, range)
            val seen = mutableSetOf<String>()
            val imported = sessions.mapNotNull { session ->
                val sourceId = session.metadata.clientRecordId ?: session.metadata.id
                val source = HealthSourceIdentity(
                    session.metadata.dataOrigin.packageName,
                    sourceId,
                    session.metadata.clientRecordVersion,
                    session.metadata.id,
                )
                if (!seen.add(source.deduplicationKey)) return@mapNotNull null
                val routeResult = session.exerciseRouteResult
                HealthActivity(
                    source = source,
                    type = session.exerciseType.toActivityType(),
                    title = session.title,
                    startTime = session.startTime,
                    endTime = session.endTime,
                    distanceMeters = distances.filter { it.sameOriginAndOverlaps(session) }.sumOf { it.distance.inMeters }.takeIf { it > 0 },
                    totalCaloriesKilocalories = calories.filter { it.sameOriginAndOverlaps(session) }.sumOf { it.energy.inKilocalories }.takeIf { it > 0 },
                    route = (routeResult as? ExerciseRouteResult.Data)?.exerciseRoute?.route.orEmpty().map {
                        HealthRoutePoint(it.time, it.latitude, it.longitude, it.altitude?.inMeters, it.horizontalAccuracy?.inMeters, it.verticalAccuracy?.inMeters)
                    },
                    routeState = when (routeResult) {
                        is ExerciseRouteResult.Data -> HealthRouteState.AVAILABLE
                        is ExerciseRouteResult.ConsentRequired -> HealthRouteState.CONSENT_REQUIRED
                        else -> HealthRouteState.NO_DATA
                    },
                    heartRate = heartRates.filter { it.sameOriginAndOverlaps(session) }.flatMap { record ->
                        record.samples.map { HealthHeartRateSample(it.time, it.beatsPerMinute) }
                    },
                )
            }
            HealthConnectResult.Success(imported)
        }

    private suspend fun <T> healthOperation(name: String, block: suspend () -> HealthConnectResult<T>): HealthConnectResult<T> {
        val result = runCatching { block() }.getOrElse { HealthConnectResult.Failure(it::class.simpleName?.lowercase() ?: "unknown") }
        analytics.record(
            AnalyticsEvent(
                name,
                mapOf(AnalyticsProperty.Result to when (result) {
                    is HealthConnectResult.Success -> "success"
                    is HealthConnectResult.PermissionRequired -> "permission_required"
                    is HealthConnectResult.Unavailable -> "unavailable"
                    is HealthConnectResult.Failure -> "failure"
                }),
            ),
        )
        return result
    }

    private fun unavailableResult() = HealthConnectResult.Unavailable(availability() == HealthConnectAvailability.UPDATE_REQUIRED)

    private suspend fun <T : androidx.health.connect.client.records.Record> readIfGranted(
        hc: HealthConnectClient,
        granted: Set<String>,
        type: KClass<T>,
        range: TimeRangeFilter,
    ): List<T> = if (HealthPermission.getReadPermission(type) in granted) readAll(hc, type, range) else emptyList()

    private suspend fun <T : androidx.health.connect.client.records.Record> readAll(
        hc: HealthConnectClient,
        type: KClass<T>,
        range: TimeRangeFilter,
    ): List<T> {
        val records = mutableListOf<T>()
        var token: String? = null
        do {
            val response = hc.readRecords(
                ReadRecordsRequest(
                    recordType = type,
                    timeRangeFilter = range,
                    pageSize = 500,
                    pageToken = token,
                ),
            )
            records += response.records
            token = response.pageToken
        } while (token != null)
        return records
    }
}

private val HealthActivityType.exerciseType: Int get() = when (this) {
    HealthActivityType.RUN -> ExerciseSessionRecord.EXERCISE_TYPE_RUNNING
    HealthActivityType.WALK -> ExerciseSessionRecord.EXERCISE_TYPE_WALKING
    HealthActivityType.CYCLE -> ExerciseSessionRecord.EXERCISE_TYPE_BIKING
}
private val supportedExerciseTypes = setOf(
    ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
    ExerciseSessionRecord.EXERCISE_TYPE_WALKING,
    ExerciseSessionRecord.EXERCISE_TYPE_BIKING,
)
private fun Int.toActivityType() = when (this) {
    ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> HealthActivityType.WALK
    ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> HealthActivityType.CYCLE
    else -> HealthActivityType.RUN
}
private fun DistanceRecord.sameOriginAndOverlaps(session: ExerciseSessionRecord) =
    metadata.dataOrigin == session.metadata.dataOrigin && startTime < session.endTime && endTime > session.startTime
private fun TotalCaloriesBurnedRecord.sameOriginAndOverlaps(session: ExerciseSessionRecord) =
    metadata.dataOrigin == session.metadata.dataOrigin && startTime < session.endTime && endTime > session.startTime
private fun HeartRateRecord.sameOriginAndOverlaps(session: ExerciseSessionRecord) =
    metadata.dataOrigin == session.metadata.dataOrigin && startTime < session.endTime && endTime > session.startTime
