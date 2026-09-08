package com.plainstride.outbound.core.data

import androidx.room.withTransaction
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map
import kotlinx.serialization.encodeToString
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import com.plainstride.outbound.core.database.ActivityDao
import com.plainstride.outbound.core.database.ActivityEntity
import com.plainstride.outbound.core.database.ActivityPhotoEntity
import com.plainstride.outbound.core.database.ActivitySplitEntity
import com.plainstride.outbound.core.database.ActivityTrackPointEntity
import com.plainstride.outbound.core.database.ActivityWithDetails
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.database.SyncOutboxEntity
import com.plainstride.outbound.core.model.activity.ActivityPage
import com.plainstride.outbound.core.model.activity.ActivityPhoto
import com.plainstride.outbound.core.model.activity.ActivityReflection
import com.plainstride.outbound.core.model.activity.ActivitySource
import com.plainstride.outbound.core.model.activity.ActivitySplit
import com.plainstride.outbound.core.model.activity.ActivityTrackPoint
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.network.AccessTokenProvider
import com.plainstride.outbound.core.network.ActivitiesApiService
import com.plainstride.outbound.core.network.ActivityReflectionDto
import com.plainstride.outbound.core.network.ActivityRouteDto
import com.plainstride.outbound.core.network.ActivityRoutePointDto
import com.plainstride.outbound.core.network.ActivityUploadRequest
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.RemoteActivityDto
import com.plainstride.outbound.core.network.apiCall

interface ActivityRepository {
    fun observePage(accountId: String, offset: Int = 0, limit: Int = 30): Flow<ActivityPage>
    suspend fun activity(accountId: String, activityId: String): SavedActivity?
    suspend fun save(activity: SavedActivity)
    suspend fun edit(activity: SavedActivity)
    suspend fun delete(accountId: String, activityId: String, deletedAt: Instant = Instant.now())
    suspend fun synchronize(accountId: String): ActivitySyncResult
}

fun interface ActivitySyncScheduler { fun schedule(accountId: String) }

data class ActivitySyncResult(val uploaded: Int, val downloaded: Int, val pending: Int, val failure: String? = null)

class OfflineFirstActivityRepository(
    private val database: PlainstrideDatabase,
    private val api: ActivitiesApiService,
    private val accessTokens: AccessTokenProvider,
    private val now: () -> Instant = Instant::now,
) : ActivityRepository {
    private val dao: ActivityDao get() = database.activityDao()

    override fun observePage(accountId: String, offset: Int, limit: Int): Flow<ActivityPage> {
        require(offset >= 0 && limit in 1..200)
        return dao.observePage(accountId, limit, offset).map { summaries ->
            val details = if (summaries.isEmpty()) emptyList() else dao.getMany(accountId, summaries.map { it.activityId })
            val byId = details.associateBy { it.activity.activityId }
            ActivityPage(summaries.mapNotNull { byId[it.activityId]?.toDomain() }, offset, limit, summaries.size == limit)
        }
    }

    override suspend fun activity(accountId: String, activityId: String): SavedActivity? = dao.get(accountId, activityId)?.toDomain()

    override suspend fun save(activity: SavedActivity) = persistAndEnqueue(activity.copy(deletedAt = null))

    override suspend fun edit(activity: SavedActivity) = persistAndEnqueue(activity.copy(localUpdatedAt = now().toString()))

    override suspend fun delete(accountId: String, activityId: String, deletedAt: Instant) {
        database.withTransaction {
            if (dao.tombstone(accountId, activityId, deletedAt.toEpochMilli()) == 0) return@withTransaction
            enqueue(accountId, activityId, DELETE, deletedAt.toString(), "{}")
        }
    }

    override suspend fun synchronize(accountId: String): ActivitySyncResult {
        val token = accessTokens.validAccessToken() ?: return ActivitySyncResult(0, 0, pendingCount(accountId), "authentication_required")
        val authorization = "Bearer $token"
        var uploaded = 0
        var failure: String? = null
        for (operation in database.syncOutboxDao().pending(accountId, now().toEpochMilli(), 100)) {
            if (database.syncOutboxDao().claim(accountId, operation.operationId) == 0) continue
            val result = when (operation.operationType) {
                UPSERT -> apiCall { api.upload(authorization, PlainstrideJson.decodeFromString(operation.payloadJson)) }
                DELETE -> apiCall { api.delete(authorization, operation.aggregateId) }
                else -> null
            }
            if (result is ApiResult.Success) {
                database.syncOutboxDao().acknowledge(accountId, operation.operationId)
                if (operation.operationType == UPSERT) {
                    val existing = dao.get(accountId, operation.aggregateId)?.toDomain()
                    val response = result.value
                    if (existing != null && response is com.plainstride.outbound.core.network.ActivityUploadResponse) {
                        persist(existing.copy(serverActivityId = response.id, serverUpdatedAt = response.serverUpdatedAt ?: response.uploadedAt), enqueue = false)
                    }
                }
                uploaded++
            } else {
                val attempt = operation.attemptCount + 1
                val delayMs = (30_000L * (1L shl minOf(attempt, 7))).coerceAtMost(3_600_000L)
                database.syncOutboxDao().retry(accountId, operation.operationId, now().toEpochMilli() + delayMs)
                failure = (result as? ApiResult.Failure)?.error?.code?.name ?: "invalid_outbox_operation"
            }
        }
        var downloaded = 0
        var offset = 0
        do {
            val page = apiCall { api.activities(authorization, 200, offset) }
            if (page !is ApiResult.Success) {
                failure = (page as? ApiResult.Failure)?.error?.code?.name
                break
            }
            page.value.activities.forEach { remote -> if (mergeRemote(accountId, remote)) downloaded++ }
            offset += page.value.activities.size
        } while (page.value.hasMore && page.value.activities.isNotEmpty())
        return ActivitySyncResult(uploaded, downloaded, pendingCount(accountId), failure)
    }

    private suspend fun persistAndEnqueue(activity: SavedActivity) {
        val payload = PlainstrideJson.encodeToString(activity.toUploadRequest())
        database.withTransaction {
            persist(activity, enqueue = false)
            enqueue(activity.accountId, activity.id, UPSERT, activity.localUpdatedAt, payload)
        }
    }

    private suspend fun persist(activity: SavedActivity, enqueue: Boolean) {
        require(activity.id.isNotBlank() && activity.accountId.isNotBlank())
        database.withTransaction {
            dao.upsertActivity(activity.toEntity())
            dao.deleteTrack(activity.accountId, activity.id)
            dao.deleteSplits(activity.accountId, activity.id)
            dao.deletePhotos(activity.accountId, activity.id)
            if (activity.track.isNotEmpty()) dao.upsertTrack(activity.track.mapIndexed { index, point -> point.toEntity(activity, index) })
            if (activity.splits.isNotEmpty()) dao.upsertSplits(activity.splits.map { it.toEntity(activity) })
            if (activity.photos.isNotEmpty()) dao.upsertPhotos(activity.photos.map { it.toEntity(activity) })
            if (enqueue) enqueue(activity.accountId, activity.id, UPSERT, activity.localUpdatedAt, PlainstrideJson.encodeToString(activity.toUploadRequest()))
        }
    }

    private suspend fun mergeRemote(accountId: String, remote: RemoteActivityDto): Boolean {
        val clientId = remote.clientActivityId ?: return false
        val local = dao.get(accountId, clientId)?.toDomain()
        val remoteUpdated = parseEpoch(remote.clientUpdatedAt ?: remote.updatedAt)
        if (local != null && parseEpoch(local.localUpdatedAt) > remoteUpdated) return false
        val remoteDeletedAt = remote.deletedAt
        if (remoteDeletedAt != null) {
            dao.tombstone(accountId, clientId, parseEpoch(remoteDeletedAt))
            return true
        }
        val snapshot = remote.clientData ?: return false
        val decoded = snapshot.toDomain(accountId, remote) ?: return false
        persist(decoded, enqueue = false)
        return true
    }

    private suspend fun enqueue(accountId: String, activityId: String, operation: String, revision: String, payload: String) {
        val created = now().toEpochMilli()
        database.syncOutboxDao().enqueue(SyncOutboxEntity(
            operationId = UUID.randomUUID().toString(), accountId = accountId, aggregateType = "activity",
            aggregateId = activityId, operationType = operation,
            idempotencyKey = "activity:$activityId:$operation:$revision", payloadJson = payload,
            createdAtEpochMs = created, nextAttemptAtEpochMs = created,
        ))
    }

    private suspend fun pendingCount(accountId: String): Int = database.syncOutboxDao().count(accountId)

    private companion object { const val UPSERT = "upsert"; const val DELETE = "delete" }
}

private fun SavedActivity.toUploadRequest(): ActivityUploadRequest {
    val clientData = PlainstrideJson.encodeToJsonElement(SavedActivity.serializer(), this).jsonObject
    return ActivityUploadRequest(
        clientActivityId = id, type = type.name, title = title, startedAt = startedAt, endedAt = endedAt,
        durationSecs = durationSecs, distanceM = distanceM, elevationM = elevationGainM,
        avgPace = averagePaceSecsPerKm, avgHeartRate = averageHeartRateBpm,
        energyKilocalories = energyKilocalories, activityEventId = activityEventId,
        followedRouteId = followedRouteId, followedRouteCompleted = followedRouteCompleted.takeIf { it },
        route = track.takeIf { it.size > 1 }?.let { points -> ActivityRouteDto(points.map { ActivityRoutePointDto(it.timestamp, it.latitude, it.longitude, it.altitude, it.verticalAccuracy, it.startsNewSegment) }) },
        splits = PlainstrideJson.encodeToJsonElement(ListSerializer(ActivitySplit.serializer()), splits),
        reflection = reflection?.let { ActivityReflectionDto(it.title, it.body, it.highlight, it.progressNote) },
        clientData = clientData, clientUpdatedAt = localUpdatedAt,
    )
}

private fun SavedActivity.toEntity() = ActivityEntity(
    id, accountId, serverActivityId, type.name, title, guideNudge, reflection?.let { PlainstrideJson.encodeToString(it) },
    parseEpoch(createdAt), parseEpoch(startedAt), parseEpoch(endedAt), durationSecs, distanceM, averagePaceSecsPerKm,
    elevationGainM, walkingStepCount, averageHeartRateBpm, maximumHeartRateBpm, heartRateSampleCount, energyKilocalories,
    PlainstrideJson.encodeToString(source), gearJson, goalJson, indoorJson, cadenceJson, heartRateZonesJson, activityEventId,
    followedRouteId, followedRouteCompleted, PlainstrideJson.encodeToString(recognitionBadgeIds), parseEpoch(localUpdatedAt),
    serverUpdatedAt?.let(::parseEpoch), deletedAt?.let(::parseEpoch),
)

private fun ActivityTrackPoint.toEntity(activity: SavedActivity, index: Int) = ActivityTrackPointEntity(activity.accountId, activity.id, index, parseEpoch(timestamp), latitude, longitude, altitude, verticalAccuracy, startsNewSegment)
private fun ActivitySplit.toEntity(activity: SavedActivity) = ActivitySplitEntity(activity.accountId, activity.id, index, distanceM, durationSecs, paceSecsPerKm, elevationGainM, averageHeartRateBpm)
private fun ActivityPhoto.toEntity(activity: SavedActivity) = ActivityPhotoEntity(activity.accountId, activity.id, id, parseEpoch(takenAt), paceAtShot, heartRateAtShot, distanceAtShotM, latitude, longitude, captureContext, localRelativePath, remotePhotoId, remoteUpdatedAt?.let(::parseEpoch), byteSize, sha256)

private fun ActivityWithDetails.toDomain(): SavedActivity = with(activity) {
    SavedActivity(
        activityId, accountId, serverActivityId, ActivityType.valueOf(type), title, guideNudge,
        reflectionJson?.let(PlainstrideJson::decodeFromString), instant(createdAtEpochMs), instant(startedAtEpochMs), instant(endedAtEpochMs),
        durationSecs, distanceM, averagePaceSecsPerKm, elevationGainM, walkingStepCount, averageHeartRateBpm,
        maximumHeartRateBpm, heartRateSampleCount, energyKilocalories, PlainstrideJson.decodeFromString(sourceJson), gearJson,
        goalJson, indoorJson, cadenceJson, heartRateZonesJson, activityEventId, followedRouteId, followedRouteCompleted,
        PlainstrideJson.decodeFromString(recognitionBadgeIdsJson), track.sortedBy { it.pointIndex }.map { ActivityTrackPoint(instant(it.timestampEpochMs), it.latitude, it.longitude, it.altitude, it.verticalAccuracy, it.startsNewSegment) },
        splits.sortedBy { it.splitIndex }.map { ActivitySplit(it.splitIndex, it.distanceM, it.durationSecs, it.paceSecsPerKm, it.elevationGainM, it.averageHeartRateBpm) },
        photos.sortedBy { it.takenAtEpochMs }.map { ActivityPhoto(it.photoId, instant(it.takenAtEpochMs), it.paceAtShot, it.heartRateAtShot, it.distanceAtShotM, it.latitude, it.longitude, it.captureContext, it.localRelativePath, it.remotePhotoId, it.remoteUpdatedAtEpochMs?.let(::instant), it.byteSize, it.sha256) },
        instant(localUpdatedAtEpochMs), serverUpdatedAtEpochMs?.let(::instant), deletedAtEpochMs?.let(::instant),
    )
}

private fun JsonObject.toDomain(accountId: String, remote: RemoteActivityDto): SavedActivity? = runCatching {
    val activityType = string("type") ?: string("activityType") ?: "running"
    val routePoints = (this["track"] as? JsonArray)?.mapNotNull(::trackPoint)
        ?: this["route"]?.jsonObject?.get("points")?.jsonArray?.mapNotNull(::trackPoint).orEmpty()
    SavedActivity(
        id = remote.clientActivityId!!, accountId = accountId, serverActivityId = remote.id,
        type = ActivityType.valueOf(activityType), title = string("title") ?: "Activity", guideNudge = string("guideNudge") ?: "",
        reflection = obj("reflection")?.let { ActivityReflection(it.string("title") ?: "", it.string("body") ?: "", it.string("highlight") ?: "", it.string("progressNote")) },
        createdAt = string("createdAt") ?: remote.createdAt, startedAt = string("startedAt")!!,
        endedAt = string("endedAt") ?: string("startedAt")!!, durationSecs = int("durationSecs") ?: 0,
        distanceM = double("distanceM") ?: 0.0, averagePaceSecsPerKm = double("averagePaceSecsPerKm") ?: double("avgPace"),
        elevationGainM = double("elevationGainM") ?: double("elevationM"), walkingStepCount = int("walkingStepCount"),
        averageHeartRateBpm = obj("healthMetrics")?.int("averageHeartRateBPM") ?: int("averageHeartRateBpm"),
        maximumHeartRateBpm = obj("healthMetrics")?.int("maxHeartRateBPM") ?: int("maximumHeartRateBpm"),
        heartRateSampleCount = obj("healthMetrics")?.int("heartRateSampleCount") ?: int("heartRateSampleCount"),
        energyKilocalories = int("energyKilocalories"),
        source = obj("source")?.let { ActivitySource(it.string("kind") ?: "outbound", it.string("displayName") ?: "Plainstride", it.string("deviceName"), it.string("externalId") ?: it.string("externalID"), it.string("importedAt")) } ?: ActivitySource(),
        gearJson = raw("gear"), goalJson = raw("goal"), indoorJson = raw("indoor"), cadenceJson = raw("cadence"), heartRateZonesJson = raw("heartRateZones"),
        activityEventId = string("activityEventId") ?: string("activityEventID"), followedRouteId = string("followedRouteId"),
        followedRouteCompleted = bool("followedRouteCompleted") ?: false,
        recognitionBadgeIds = array("recognitionBadgeIds")?.mapNotNull { it.jsonPrimitive.contentOrNull }
            ?: array("recognitionBadgeIDs")?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty(),
        track = routePoints, splits = array("splits")?.mapIndexedNotNull(::split).orEmpty(),
        photos = remote.photos.map { ActivityPhoto(it.clientPhotoId ?: it.id, it.takenAt, it.paceAtShot, it.hrAtShot, it.distAtShot, it.latitude, it.longitude, it.captureContext, null, it.id, it.updatedAt, it.byteSize, it.sha256) },
        localUpdatedAt = remote.clientUpdatedAt ?: remote.updatedAt, serverUpdatedAt = remote.updatedAt,
    )
}.getOrNull()

private fun trackPoint(element: JsonElement): ActivityTrackPoint? = runCatching { element.jsonObject }.getOrNull()?.let { p ->
    val timestamp = p.string("timestamp") ?: return null
    val latitude = p.double("latitude") ?: return null
    val longitude = p.double("longitude") ?: return null
    ActivityTrackPoint(timestamp, latitude, longitude, p.double("altitude"), p.double("verticalAccuracy"), p.bool("startsNewSegment") ?: false)
}

private fun split(index: Int, element: JsonElement): ActivitySplit? = runCatching { element.jsonObject }.getOrNull()?.let { p ->
    ActivitySplit(p.int("index") ?: index, p.double("distanceM") ?: return null, p.int("durationSecs") ?: return null, p.double("paceSecsPerKm") ?: p.double("pace"), p.double("elevationGainM"), p.int("averageHeartRateBpm"))
}

private fun JsonObject.string(key: String) = this[key]?.takeUnless { it is JsonNull }?.jsonPrimitive?.contentOrNull
private fun JsonObject.double(key: String) = this[key]?.jsonPrimitive?.doubleOrNull
private fun JsonObject.int(key: String) = this[key]?.jsonPrimitive?.intOrNull
private fun JsonObject.bool(key: String) = this[key]?.jsonPrimitive?.booleanOrNull
private fun JsonObject.obj(key: String) = this[key]?.takeUnless { it is JsonNull }?.let { runCatching { it.jsonObject }.getOrNull() }
private fun JsonObject.array(key: String) = this[key]?.takeUnless { it is JsonNull }?.let { runCatching { it.jsonArray }.getOrNull() }
private fun JsonObject.raw(key: String) = this[key]?.takeUnless { it is JsonNull }?.toString()
private fun parseEpoch(value: String): Long = Instant.parse(value).toEpochMilli()
private fun instant(value: Long): String = Instant.ofEpochMilli(value).toString()
