package com.plainstride.outbound.core.data

import android.util.Base64
import android.util.Log
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import java.util.zip.GZIPOutputStream
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.withTimeoutOrNull
import kotlinx.serialization.SerializationException
import com.plainstride.outbound.core.database.ActivityOriginalRouteEntity
import com.plainstride.outbound.core.model.activity.ActivityElevationMetadata
import com.plainstride.outbound.core.model.activity.TerrainElevationSampling
import androidx.room.withTransaction
import java.time.Instant
import java.util.UUID
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.database.ActivityDao
import com.plainstride.outbound.core.database.ActivityEntity
import com.plainstride.outbound.core.database.ActivityPhotoEntity
import com.plainstride.outbound.core.database.ActivitySplitEntity
import com.plainstride.outbound.core.database.ActivityTrackPointEntity
import com.plainstride.outbound.core.database.ActivityWithDetails
import com.plainstride.outbound.core.database.PlainstrideDatabase
import com.plainstride.outbound.core.database.SyncOutboxEntity
import com.plainstride.outbound.core.model.activity.ActivityCompanionType
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
import com.plainstride.outbound.core.network.ActivityPhotoUploadRequest
import com.plainstride.outbound.core.network.ActivityReflectionDto
import com.plainstride.outbound.core.network.ActivityRouteDto
import com.plainstride.outbound.core.network.ActivityRoutePointDto
import com.plainstride.outbound.core.network.ActivityUploadRequest
import com.plainstride.outbound.core.network.ApiResult
import com.plainstride.outbound.core.network.PlainstrideJson
import com.plainstride.outbound.core.network.RemoteActivityDto
import com.plainstride.outbound.core.network.apiCall

interface ActivityRepository {
    fun observeStatisticsPending(accountId: String): Flow<Boolean> = observePendingSyncCount(accountId).map { it > 0 }
    fun observeStatistics(accountId: String): Flow<JsonObject?>
    suspend fun refreshStatistics(accountId: String): Boolean
    suspend fun loadHistoryPage(accountId: String, targetCount: Int = 30): Boolean
    fun observeAll(accountId: String): Flow<List<SavedActivity>>
    fun observePage(accountId: String, offset: Int = 0, limit: Int = 30): Flow<ActivityPage>
    fun observePendingSyncCount(accountId: String): Flow<Int>
    suspend fun refreshActivity(accountId: String, activityId: String)
    suspend fun activity(accountId: String, activityId: String): SavedActivity?
    suspend fun save(activity: SavedActivity)
    suspend fun correctElevationIfNeeded(accountId: String, activityId: String): Boolean
    suspend fun edit(activity: SavedActivity)
    suspend fun delete(accountId: String, activityId: String, deletedAt: Instant = Instant.now())
    suspend fun retryRejected(accountId: String) {}
    suspend fun synchronize(accountId: String): ActivitySyncResult
}

fun interface ActivitySyncScheduler { fun schedule(accountId: String) }

data class ActivitySyncResult(
    val uploaded: Int,
    val downloaded: Int,
    val pending: Int,
    val failure: String? = null,
    val photosUploaded: Int = 0,
)

class OfflineFirstActivityRepository(
    private val database: PlainstrideDatabase,
    private val api: ActivitiesApiService,
    private val accessTokens: AccessTokenProvider,
    private val mediaStore: ActivityMediaStore,
    private val photos: ActivityPhotoRepository,
    private val analytics: ProductAnalytics,
    private val currentAccountId: () -> String?,
    private val now: () -> Instant = Instant::now,
) : ActivityRepository {
    private val reads = AccountReadRepository(database, accessTokens)
    private val syncMutex = kotlinx.coroutines.sync.Mutex()
    private val recoveredAccounts = mutableSetOf<String>()
    private fun context(accountId: String) = accessTokens.captureAccount(accountId)?.takeIf { currentAccountId() == accountId }
    private fun current(owner: com.plainstride.outbound.core.network.AccountRequestContext) = currentAccountId() == owner.accountId && accessTokens.isCurrent(owner)
    override suspend fun retryRejected(accountId: String) { context(accountId)?.let {
        reads.retryRejected(it)
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "performed_workout_retry")))
    } }
    private val historyDownloaded = mutableMapOf<String, Int>()
    private val historyCursors = mutableMapOf<String, String?>()
    private val historyHasMore = kotlinx.coroutines.flow.MutableStateFlow<Map<String, Boolean>>(emptyMap())
    private val historyMutex = kotlinx.coroutines.sync.Mutex()
    override fun observeStatisticsPending(accountId: String): Flow<Boolean> = reads.observe(accountId).map { it?.baseline?.statisticsDirty ?: true }
    override fun observeStatistics(accountId: String): Flow<JsonObject?> = reads.observeStatistics(accountId)
    override suspend fun refreshStatistics(accountId: String): Boolean {
        val owner = context(accountId) ?: return false
        val ticket = reads.statisticsTicket(owner) ?: return false
        val token = accessTokens.validAccessToken(owner) ?: return false
        val result = apiCall { api.statistics("Bearer $token", java.time.ZoneId.systemDefault().id, 2) }
        if (result !is ApiResult.Success) { Log.w("PlainstrideStatistics", "refresh_failed category=${(result as? ApiResult.Failure)?.error?.code?.name ?: "unavailable"}"); return false }
        val accepted = current(owner) && reads.acceptStatistics(owner, result.value, ticket)
        if (accepted) analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "server_statistics")))
        return accepted
    }
    override suspend fun loadHistoryPage(accountId: String, targetCount: Int): Boolean = historyMutex.withLock {
        val owner = context(accountId) ?: return@withLock false
        val token = accessTokens.validAccessToken(owner) ?: return@withLock false
        var downloaded = 0
        do {
            val page = apiCall { api.activities("Bearer $token", 30, 0, historyCursors[accountId]) }
            if (page !is ApiResult.Success) { Log.w("PlainstrideActivity", "history_page_failed category=${(page as? ApiResult.Failure)?.error?.code?.name ?: "unavailable"}"); return@withLock false }
            if (!current(owner)) return@withLock false
            for (remote in page.value.activities) if (mergeRemote(owner, remote, preserveRoute = true)) downloaded++
            historyCursors[accountId] = page.value.nextCursor
            historyHasMore.value = historyHasMore.value + (accountId to (page.value.hasMore && page.value.nextCursor != null))
        } while (dao.activeCount(accountId) < targetCount && historyHasMore.value[accountId] != false)
        historyDownloaded[accountId] = downloaded
        true
    }
    override suspend fun refreshActivity(accountId: String, activityId: String) {
        val owner = context(accountId) ?: return
        val local = activity(accountId, activityId)
        // An uncached notification carries a server ID; a local unsynced activity needs no fetch.
        val serverId = if (local == null) activityId else local.serverActivityId ?: return
        val token = accessTokens.validAccessToken(owner)
        if (token != null) {
            val response = apiCall { api.activities("Bearer $token", 1, 0, ids = serverId, includeRoute = true) }
            if (response is ApiResult.Success && current(owner)) response.value.activities.forEach { mergeRemote(owner, it) }
            else Log.w("PlainstrideActivity", "detail_refresh_failed category=${(response as? ApiResult.Failure)?.error?.code?.name ?: "account_changed"}")
        }
        if (current(owner)) cacheActivityPhotos(owner, local?.id ?: activityId)
    }
    private suspend fun cacheActivityPhotos(owner: com.plainstride.outbound.core.network.AccountRequestContext, activityId: String) =
        kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
            val accountId = owner.accountId
            if (!current(owner)) return@withContext
            val snapshot = activity(accountId, activityId) ?: return@withContext
            for (photo in snapshot.photos) {
                if (!current(owner)) return@withContext
                val remoteId = photo.remotePhotoId ?: continue
                try {
                    val cached = photo.localRelativePath?.let { path ->
                        // A missing cache file is expected and can be downloaded again.
                        try { mediaStore.read(path).isNotEmpty() } catch (_: java.io.FileNotFoundException) { false }
                    } ?: false
                    if (cached) continue
                    val bytes = photos.load(remoteId).getOrNull() ?: continue
                    if (!current(owner)) return@withContext
                    val path = mediaStore.write(accountId, snapshot.id, bytes)
                    val attached = database.withTransaction {
                        val latest = activity(accountId, snapshot.id)
                        val target = latest?.photos?.firstOrNull { it.id == photo.id && it.remotePhotoId == remoteId && it.remoteUpdatedAt == photo.remoteUpdatedAt }
                        if (!current(owner) || latest == null || latest.deletedAt != null || target == null
                            || target.localRelativePath != photo.localRelativePath) false
                        else {
                            dao.upsertPhotos(listOf(target.copy(localRelativePath = path).toEntity(latest, latest.photos.indexOfFirst { it.id == target.id })))
                            true
                        }
                    }
                    if (!attached) mediaStore.delete(path)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    Log.w("PlainstrideActivity", "photo_download_failed type=${error.javaClass.simpleName}")
                }
            }
        }

    private suspend fun refreshCachedMetadata(owner: com.plainstride.outbound.core.network.AccountRequestContext, authorization: String) {
        val accountId = owner.accountId
        if (!current(owner)) return
        val cached = dao.observeAll(accountId).first().mapNotNull { row -> row.activity.serverActivityId?.let { com.plainstride.outbound.core.network.CachedActivityVersion(it, row.activity.serverUpdatedAtEpochMs?.let { time -> Instant.ofEpochMilli(time).toString() }) } }
        for (batch in cached.chunked(200)) {
            val response = apiCall { api.cachedChanges(authorization, com.plainstride.outbound.core.network.CachedActivityVersions(batch)) }
            if (response !is ApiResult.Success || !current(owner)) {
                Log.w("PlainstrideActivity", "cached_metadata_refresh_failed category=${(response as? ApiResult.Failure)?.error?.code?.name ?: "account_changed"}")
                return
            }
            response.value.activities.forEach { mergeRemote(owner, it, preserveRoute = true) }
        }
    }
    private val dao: ActivityDao get() = database.activityDao()
    private val elevationCorrector = TerrainElevationCorrector(api)
    private val elevationCorrections = ConcurrentHashMap.newKeySet<Pair<String, String>>()

    override fun observeAll(accountId: String): Flow<List<SavedActivity>> = dao.observeAll(accountId).map { rows -> rows.map { it.toDomain() } }

    override fun observePendingSyncCount(accountId: String): Flow<Int> =
        database.syncOutboxDao().observeCount(accountId)

    override fun observePage(accountId: String, offset: Int, limit: Int): Flow<ActivityPage> {
        require(offset >= 0 && limit in 1..200)
        return dao.observePage(accountId, limit, offset).combine(historyHasMore) { summaries, remote ->
            val details = if (summaries.isEmpty()) emptyList() else dao.getMany(accountId, summaries.map { it.activityId })
            val byId = details.associateBy { it.activity.activityId }
            ActivityPage(summaries.mapNotNull { byId[it.activityId]?.toDomain() }, offset, limit, summaries.size == limit || remote[accountId] != false)
        }
    }

    override suspend fun activity(accountId: String, activityId: String): SavedActivity? = dao.getByReference(accountId, activityId)?.toDomain()

    override suspend fun save(activity: SavedActivity) = persistAndEnqueue(activity.copy(deletedAt = null))

    override suspend fun edit(activity: SavedActivity) {
        val owner = context(activity.accountId) ?: throw IOException("Activity owner changed")
        database.withTransaction {
        if (!current(owner)) throw IOException("Activity owner changed")
        val latest = dao.get(activity.accountId, activity.id)?.toDomain()
        if (latest?.deletedAt != null) throw IOException("Activity was deleted")
        // Title/gear edits may originate from a detail snapshot opened before enrichment.
        // Keep the newer terrain result when the edit has not changed route geometry.
        val sameGeometry = latest != null && latest.track.size == activity.track.size && activity.track.indices.all { index ->
            val a = activity.track[index]
            val b = latest.track[index]
            a.timestamp == b.timestamp && a.latitude == b.latitude && a.longitude == b.longitude && a.startsNewSegment == b.startsNewSegment
        }
        val updated = if (latest?.elevationMetadata != null && sameGeometry) activity.copy(
            track = latest.track, elevationGainM = latest.elevationGainM, elevationMetadata = latest.elevationMetadata,
        ) else activity
        latest?.photos.orEmpty().filter { old -> updated.photos.none { it.id == old.id } }.forEach { removed ->
            removed.remotePhotoId?.let { remoteId ->
                enqueue(activity.accountId, activity.id, "delete_photo", UUID.randomUUID().toString(), remoteId)
            }
        }
        persistAndEnqueue(updated.copy(localUpdatedAt = now().toString()))
        }
    }

    override suspend fun correctElevationIfNeeded(accountId: String, activityId: String): Boolean {
        val owner = context(accountId) ?: return false
        val key = accountId to activityId
        if (!current(owner) || !elevationCorrections.add(key)) return false
        val started = System.nanoTime()
        var source = "existing_on_device"
        try {
            val original = activity(accountId, activityId) ?: return false
            if (!original.needsElevationCorrection()) return false
            source = when {
                original.elevationMetadata != null -> "mapzen_upgrade_v2"
                original.serverActivityId == null -> "mapzen_terrain_v2"
                else -> "mapzen_backfill"
            }
            val token = accessTokens.validAccessToken(owner) ?: return false
            if (!current(owner)) return false
            val corrected = elevationCorrector.correct(original, "Bearer $token")
            val applied = database.withTransaction {
                val latest = activity(accountId, activityId) ?: return@withTransaction false
                // Do not resurrect deleted routes, overwrite edits, or write after an account switch.
                if (!current(owner) || latest.deletedAt != null
                    || latest.localUpdatedAt != original.localUpdatedAt || latest.track != original.track
                    || latest.elevationMetadata != original.elevationMetadata || latest.source != original.source
                    || latest.indoorJson != original.indoorJson) return@withTransaction false
                preserveOriginalElevationRoute(original)
                val revision = maxOf(now().toEpochMilli(), parseEpoch(original.localUpdatedAt) + 1)
                persistAndEnqueue(latest.copy(
                    elevationGainM = corrected.elevationGainM, elevationMetadata = corrected.elevationMetadata,
                    track = corrected.track, localUpdatedAt = instant(revision),
                ))
                true
            }
            if (applied) trackElevation("success", source, started)
            return applied
        } catch (error: CancellationException) {
            throw error // Leaving detail / stopping a worker is normal control flow.
        } catch (error: Exception) {
            val category = when (error) {
                is TerrainElevationCorrectionException -> error.category
                is IOException -> "network_unavailable"
                is SerializationException -> "invalid_response"
                is IllegalArgumentException -> "invalid_route"
                else -> "storage_or_unknown"
            }
            val status = (error as? TerrainElevationCorrectionException)?.httpStatus
            Log.w("ActivityElevation", "Terrain correction failed category=$category http_status=${status ?: 0} type=${error.javaClass.simpleName}")
            trackElevation("fallback", source, started, category)
            return false // Existing totals/route/outbox remain usable offline.
        } finally {
            elevationCorrections.remove(key)
        }
    }

    private fun SavedActivity.needsElevationCorrection(): Boolean {
        if (deletedAt != null || source.kind != "outbound" || track.size < 2) return false
        val metadata = elevationMetadata
        if (metadata != null && metadata.algorithmVersion != "terrain-v1") return false
        val indoor = indoorJson?.let { PlainstrideJson.parseToJsonElement(it).jsonObject }
        return indoor?.bool("indoor") != true && indoor?.bool("isIndoor") != true
    }

    private suspend fun preserveOriginalElevationRoute(activity: SavedActivity) {
        if (activity.elevationMetadata != null || !activity.needsElevationCorrection()
            || dao.hasOriginalRoute(activity.accountId, activity.id)) return
        val buffer = ByteArrayOutputStream()
        GZIPOutputStream(buffer).use { it.write(PlainstrideJson.encodeToString(activity.track).toByteArray(Charsets.UTF_8)) }
        dao.preserveOriginalRoute(ActivityOriginalRouteEntity(activity.accountId, activity.id, buffer.toByteArray()))
    }

    private fun trackElevation(result: String, source: String, started: Long, errorCategory: String? = null) {
        val milliseconds = (System.nanoTime() - started) / 1_000_000
        val latency = when {
            milliseconds < 250 -> "under_250ms"
            milliseconds < 1_000 -> "250ms_1s"
            milliseconds < 3_000 -> "1s_3s"
            milliseconds < 8_000 -> "3s_8s"
            else -> "8s_plus"
        }
        val properties = mutableMapOf<AnalyticsProperty, Any>(
            AnalyticsProperty.Result to result, AnalyticsProperty.SourceType to source, AnalyticsProperty.LatencyBucket to latency,
        )
        errorCategory?.let { properties[AnalyticsProperty.ErrorCategory] = it }
        analytics.record(AnalyticsEvent("activity_elevation_correction_completed", properties))
    }

    override suspend fun delete(accountId: String, activityId: String, deletedAt: Instant) {
        val owner = context(accountId) ?: throw IOException("Activity owner changed")
        database.withTransaction {
            if (!current(owner)) throw IOException("Activity owner changed")
            if (dao.tombstone(accountId, activityId, deletedAt.toEpochMilli()) == 0) return@withTransaction
            dao.deleteOriginalRoute(accountId, activityId)
            reads.deleted(accountId, activityId)
            enqueue(accountId, activityId, DELETE, deletedAt.toString(), "{}")
        }
    }

    override suspend fun synchronize(accountId: String): ActivitySyncResult = syncMutex.withLock {
        val owner = context(accountId) ?: return@withLock ActivitySyncResult(0, 0, pendingCount(accountId), "authentication_required")
        val token = accessTokens.validAccessToken(owner) ?: return@withLock ActivitySyncResult(0, 0, pendingCount(accountId), "authentication_required")
        val authorization = "Bearer $token"
        if (recoveredAccounts.add(accountId)) database.syncOutboxDao().recoverInterrupted(accountId)
        withTimeoutOrNull(15_000) {
            database.syncOutboxDao().pending(accountId, now().toEpochMilli(), 100)
                .filter { it.operationType == UPSERT }.map { it.aggregateId }.distinct()
                .forEach { if (current(owner)) correctElevationIfNeeded(accountId, it) }
        }
        var uploaded = 0
        var photosUploaded = 0
        var failure: String? = null
        for (operation in database.syncOutboxDao().pending(accountId, now().toEpochMilli(), 100)) {
            if (!current(owner)) break
            if (database.syncOutboxDao().claim(accountId, operation.operationId) == 0) continue
            try {
                val result = when (operation.operationType) {
                    UPSERT -> apiCall { api.upload(authorization, PlainstrideJson.decodeFromString<ActivityUploadRequest>(operation.payloadJson)) }
                    DELETE -> apiCall { api.delete(authorization, operation.aggregateId) }
                    "delete_photo" -> apiCall { api.deleteActivityPhoto(authorization, operation.payloadJson) }
                    else -> null
                }
                if (!current(owner)) {
                    database.syncOutboxDao().retry(accountId, operation.operationId, now().toEpochMilli())
                    break
                }
                if (result is ApiResult.Success) {
                    if (operation.operationType == UPSERT) {
                        val response = result.value as? com.plainstride.outbound.core.network.ActivityUploadResponse ?: throw IOException("Invalid upload acknowledgement")
                        acceptUpload(owner, operation, response, authorization)
                    } else database.withTransaction {
                        if (!current(owner)) throw IOException("Account changed")
                        reads.invalidate(owner)
                        database.syncOutboxDao().acknowledge(accountId, operation.operationId)
                    }
                    uploaded++
                } else {
                    val error = (result as? ApiResult.Failure)?.error
                    val conflict = operation.operationType == UPSERT && error?.httpStatus == 409 && error.wireCode == "performed_workout_conflict"
                    database.withTransaction {
                        if (conflict) {
                            val latestGeneration = dao.get(accountId, operation.aggregateId)?.activity?.mutationGeneration
                            if (latestGeneration == operation.mutationGeneration) {
                                reads.rejected(accountId, operation.aggregateId, operation.mutationGeneration)
                                database.syncOutboxDao().reject(accountId, operation.operationId)
                            } else {
                                // A later edit already owns a fresh operation; an obsolete rejected
                                // generation must not leave an invisible terminal row behind.
                                database.syncOutboxDao().acknowledge(accountId, operation.operationId)
                            }
                        } else {
                            val delayMs = (30_000L * (1L shl minOf(operation.attemptCount + 1, 7))).coerceAtMost(3_600_000L)
                            database.syncOutboxDao().retry(accountId, operation.operationId, now().toEpochMilli() + delayMs)
                        }
                    }
                    failure = if (conflict) "performed_workout_conflict" else error?.code?.name ?: "invalid_outbox_operation"
                    Log.w("PlainstrideActivity", "sync_failed category=$failure http_status=${error?.httpStatus ?: 0}")
                    dao.get(accountId, operation.aggregateId)?.toDomain()?.let { trackActivitySync("activity_sync_failed", it, failure) }
                }
            } catch (error: CancellationException) {
                kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) { database.syncOutboxDao().retry(accountId, operation.operationId, now().toEpochMilli()) }
                throw error
            } catch (error: Exception) {
                database.syncOutboxDao().retry(accountId, operation.operationId, now().toEpochMilli() + 30_000)
                failure = "local_reconciliation"
                Log.e("PlainstrideActivity", "sync_reconciliation_failed type=${error.javaClass.simpleName}")
            }
        }
        if (current(owner)) {
            dao.observeAll(accountId).first().map { it.toDomain() }
                .filter { it.serverActivityId != null && it.photos.any { photo -> photo.remotePhotoId == null } }
                .forEach { activity ->
                    if (current(owner)) {
                        val result = syncPhotos(owner, activity, authorization)
                        photosUploaded += result.uploaded
                        if (result.failed) failure = failure ?: "activity_photo_upload_failed"
                    }
                }
            refreshCachedMetadata(owner, authorization)
            historyCursors.remove(accountId)
            historyHasMore.value = historyHasMore.value + (accountId to true)
        }
        val pageLoaded = current(owner) && loadHistoryPage(accountId, 0)
        val downloaded = if (pageLoaded) historyDownloaded[accountId] ?: 0 else 0
        if (!pageLoaded) failure = failure ?: "history_page_failed"
        if (current(owner)) refreshStatistics(accountId)
        ActivitySyncResult(uploaded, downloaded, pendingCount(accountId), failure, photosUploaded)
    }

    private suspend fun acceptUpload(owner: com.plainstride.outbound.core.network.AccountRequestContext, operation: SyncOutboxEntity,
        response: com.plainstride.outbound.core.network.ActivityUploadResponse, authorization: String) {
        val reconciliation = response.reconciliation ?: throw IOException("Missing reconciliation receipt")
        val accountId = owner.accountId
        val source = dao.get(accountId, operation.aggregateId) ?: throw IOException("Missing upload source")
        val canonicalId = response.clientActivityId ?: source.activity.activityId
        val adopting = canonicalId != source.activity.activityId && source.activity.mutationGeneration == operation.mutationGeneration
        val target = if (adopting) dao.get(accountId, canonicalId) else null
        val remote = if (adopting) {
            val fetched = apiCall { api.activities(authorization, 1, 0, ids = response.id, includeRoute = true) }
            (fetched as? ApiResult.Success)?.value?.activities?.singleOrNull()?.takeIf { it.clientActivityId == canonicalId && it.id == response.id }
                ?: throw IOException("Canonical activity refresh failed")
        } else null
        if (!current(owner)) throw IOException("Account changed")
        val prepared = mutableListOf<String>()
        var adopted = false
        var switched = false
        try {
            val copiedPhotos = if (adopting) source.toDomain().photos.map { photo ->
                photo.copy(localRelativePath = photo.localRelativePath?.let { path -> mediaStore.write(accountId, canonicalId, mediaStore.read(path)).also(prepared::add) })
            } else emptyList()
            database.withTransaction {
                if (!current(owner)) throw IOException("Account changed")
                val latest = dao.get(accountId, operation.aggregateId) ?: throw IOException("Missing upload source")
                if (adopting && latest.activity.mutationGeneration == operation.mutationGeneration) {
                    val latestTarget = dao.get(accountId, canonicalId)
                    if (latestTarget != target || database.syncOutboxDao().hasActivityMutation(accountId, canonicalId)) throw IOException("Canonical generation changed")
                    val decoded = remote!!.clientData.toDomain(accountId, remote) ?: throw IOException("Invalid canonical activity")
                    val retained = (target?.toDomain()?.photos.orEmpty() + copiedPhotos).distinctBy { it.id }
                    val merged = retained.map { localPhoto ->
                        decoded.photos.firstOrNull { it.id == localPhoto.id }?.copy(localRelativePath = localPhoto.localRelativePath) ?: localPhoto
                    } + decoded.photos.filter { remotePhoto -> retained.none { it.id == remotePhoto.id } }
                    val targetActivity = target?.toDomain()
                    val sourceActivity = source.toDomain()
                    val routeOwner = when {
                        decoded.track.isNotEmpty() -> decoded
                        targetActivity?.track?.isNotEmpty() == true -> targetActivity
                        else -> sourceActivity
                    }
                    persist(decoded.copy(photos = merged, track = routeOwner.track, elevationMetadata = routeOwner.elevationMetadata,
                        elevationGainM = if (decoded.track.isNotEmpty()) decoded.elevationGainM else routeOwner.elevationGainM), enqueue = false)
                    dao.originalRoute(accountId, operation.aggregateId)?.let { dao.preserveOriginalRoute(it.copy(activityId = canonicalId)) }
                    dao.tombstone(accountId, operation.aggregateId, now().toEpochMilli())
                    dao.deleteOriginalRoute(accountId, operation.aggregateId)
                    switched = true
                } else if (canonicalId == latest.activity.activityId) {
                    // Metadata applies to the latest row; never restore a captured payload over an edit.
                    persist(latest.toDomain().copy(serverActivityId = response.id,
                        serverUpdatedAt = response.serverUpdatedAt ?: response.uploadedAt), enqueue = false)
                }
                reads.accepted(accountId, operation.aggregateId, operation.mutationGeneration, reconciliation)
                database.syncOutboxDao().acknowledge(accountId, operation.operationId)
            }
            adopted = switched
            if (adopted && current(owner)) mediaStore.deleteActivity(accountId, operation.aggregateId)
            trackActivitySync("activity_sync_completed", source.toDomain())
        } finally {
            if (!adopted) prepared.forEach { mediaStore.delete(it) }
        }
    }

    private data class PhotoSyncResult(val uploaded: Int, val failed: Boolean)

    private fun trackActivitySync(name: String, activity: SavedActivity, errorCategory: String? = null) {
        val boundedSource = when (activity.source.kind) {
            "outbound", "manual", "health_connect" -> activity.source.kind
            else -> "other"
        }
        val properties = mutableMapOf<AnalyticsProperty, Any>(
            AnalyticsProperty.SourceType to boundedSource,
            AnalyticsProperty.RouteSelected to (activity.track.size > 1),
        )
        errorCategory?.let { properties[AnalyticsProperty.ErrorCategory] = it }
        analytics.record(AnalyticsEvent(name, properties))
    }

    private suspend fun syncPhotos(owner: com.plainstride.outbound.core.network.AccountRequestContext, activity: SavedActivity, authorization: String): PhotoSyncResult {
        val serverActivityId = activity.serverActivityId ?: return PhotoSyncResult(0, activity.photos.isNotEmpty())
        val synchronizedPhotos = activity.photos.toMutableList()
        var uploaded = 0
        var failed = false
        for (index in synchronizedPhotos.indices) {
            if (!current(owner)) return PhotoSyncResult(uploaded, true)
            val photo = synchronizedPhotos[index]
            if (photo.remotePhotoId != null) continue
            val localPath = photo.localRelativePath
            val bytes = localPath?.let { path -> runCatching { mediaStore.read(path) }.getOrNull() }
            if (bytes == null) {
                failed = true
                continue
            }
            val result = apiCall {
                api.uploadActivityPhoto(
                    authorization,
                    ActivityPhotoUploadRequest(
                        activityId = serverActivityId,
                        clientPhotoId = photo.id,
                        base64 = Base64.encodeToString(bytes, Base64.NO_WRAP),
                        takenAt = photo.takenAt,
                        paceAtShot = photo.paceAtShot,
                        hrAtShot = photo.heartRateAtShot,
                        distAtShot = photo.distanceAtShotM,
                        latitude = photo.latitude,
                        longitude = photo.longitude,
                        captureContext = photo.captureContext,
                    ),
                )
            }
            val remote = (result as? ApiResult.Success)?.value
            if (remote == null) {
                failed = true
                continue
            }
            synchronizedPhotos[index] = photo.copy(
                remotePhotoId = remote.id,
                remoteUpdatedAt = remote.updatedAt,
                byteSize = remote.byteSize ?: photo.byteSize,
                sha256 = remote.sha256 ?: photo.sha256,
            )
            uploaded++
        }
        if (synchronizedPhotos != activity.photos) database.withTransaction {
            // Photo transfer can overlap detail enrichment; update only photo metadata
            // on the latest activity instead of restoring its previous elevation/route.
            val latest = dao.get(activity.accountId, activity.id)?.toDomain()
            if (current(owner) && latest != null && latest.deletedAt == null) {
                val transferred = synchronizedPhotos.associateBy { it.id }
                persist(latest.copy(photos = latest.photos.map { photo ->
                    val remote = transferred[photo.id]
                    if (remote?.remotePhotoId != null && photo.remotePhotoId == null
                        && activity.photos.firstOrNull { it.id == photo.id }?.localRelativePath == photo.localRelativePath) photo.copy(
                        remotePhotoId = remote.remotePhotoId, remoteUpdatedAt = remote.remoteUpdatedAt,
                        byteSize = remote.byteSize, sha256 = remote.sha256,
                    ) else photo
                }), enqueue = false)
            }
        }
        return PhotoSyncResult(uploaded, failed)
    }

    private suspend fun persistAndEnqueue(activity: SavedActivity) {
        val owner = context(activity.accountId) ?: throw IOException("Activity owner is no longer active")
        database.withTransaction {
            if (!current(owner)) throw IOException("Activity owner changed")
            val old = dao.get(activity.accountId, activity.id)?.activity
            val generation = (old?.mutationGeneration ?: 0) + 1
            val updated = activity.copy(localUpdatedAt = instant(maxOf(now().toEpochMilli(), (old?.localUpdatedAtEpochMs ?: 0) + 1)))
            preserveOriginalElevationRoute(updated)
            persist(updated, enqueue = false)
            dao.upsertActivity(updated.toEntity().copy(mutationGeneration = generation))
            reads.saved(updated, generation)
            database.syncOutboxDao().supersedeUnsent(activity.accountId, activity.id)
            enqueue(activity.accountId, activity.id, UPSERT, generation.toString(), PlainstrideJson.encodeToString(updated.toUploadRequest()), generation)
        }
    }

    private suspend fun persist(activity: SavedActivity, enqueue: Boolean) {
        require(activity.id.isNotBlank() && activity.accountId.isNotBlank())
        database.withTransaction {
            val existingOwner = dao.owner(activity.id)
            require(existingOwner == null || existingOwner == activity.accountId) { "Activity identity belongs to another account" }
            val generation = dao.get(activity.accountId, activity.id)?.activity?.mutationGeneration ?: 0
            dao.upsertActivity(activity.toEntity().copy(mutationGeneration = generation))
            dao.deleteTrack(activity.accountId, activity.id)
            dao.deleteSplits(activity.accountId, activity.id)
            dao.deletePhotos(activity.accountId, activity.id)
            if (activity.track.isNotEmpty()) dao.upsertTrack(activity.track.mapIndexed { index, point -> point.toEntity(activity, index) })
            if (activity.splits.isNotEmpty()) dao.upsertSplits(activity.splits.map { it.toEntity(activity) })
            if (activity.photos.isNotEmpty()) dao.upsertPhotos(activity.photos.mapIndexed { index, photo -> photo.toEntity(activity, index) })
            if (enqueue) enqueue(activity.accountId, activity.id, UPSERT, activity.localUpdatedAt, PlainstrideJson.encodeToString(activity.toUploadRequest()))
        }
    }

    private suspend fun mergeRemote(owner: com.plainstride.outbound.core.network.AccountRequestContext, remote: RemoteActivityDto, preserveRoute: Boolean = false): Boolean = database.withTransaction {
        val accountId = owner.accountId
        if (!current(owner)) return@withTransaction false
        val clientId = remote.clientActivityId ?: dao.getByReference(accountId, remote.id)?.activity?.activityId ?: remote.id
        val local = dao.get(accountId, clientId)?.toDomain()
        if (database.syncOutboxDao().hasActivityMutation(accountId, clientId)) return@withTransaction false
        val remoteUpdated = parseEpoch(remote.clientUpdatedAt ?: remote.updatedAt)
        if (local != null && parseEpoch(local.localUpdatedAt) > remoteUpdated) return@withTransaction false
        val remoteDeletedAt = remote.deletedAt
        if (remoteDeletedAt != null) {
            database.withTransaction {
                dao.tombstone(accountId, clientId, parseEpoch(remoteDeletedAt))
                dao.deleteOriginalRoute(accountId, clientId)
            }
            return@withTransaction true
        }
        val snapshot = remote.clientData
        val decoded = snapshot.toDomain(accountId, remote.copy(clientActivityId = clientId)) ?: return@withTransaction false
        // Keep private local files attached when a server refresh supplies metadata only.
        val localPhotos = local?.photos.orEmpty()
        val remotePhotoIds = decoded.photos.mapTo(mutableSetOf()) { it.id }
        val deletedPhotoIds = database.syncOutboxDao().pendingPhotoDeletions(accountId, clientId).toSet()
        val mergedById = decoded.photos.filterNot { it.remotePhotoId in deletedPhotoIds }.map { remotePhoto ->
            remotePhoto.copy(localRelativePath = localPhotos.firstOrNull { it.id == remotePhoto.id }?.localRelativePath)
        } + localPhotos.filterNot { it.id in remotePhotoIds }
        val mergedPhotos = localPhotos.mapNotNull { old -> mergedById.firstOrNull { it.id == old.id } } +
            mergedById.filter { remote -> localPhotos.none { it.id == remote.id } }
        persist(decoded.copy(photos = mergedPhotos, track = if (preserveRoute) local?.track.orEmpty() else decoded.track, elevationMetadata = if (preserveRoute) local?.elevationMetadata else decoded.elevationMetadata), enqueue = false)
        return@withTransaction true
    }

    private suspend fun enqueue(accountId: String, activityId: String, operation: String, revision: String, payload: String, generation: Long = 0) {
        val created = now().toEpochMilli()
        database.syncOutboxDao().enqueue(SyncOutboxEntity(
            operationId = UUID.randomUUID().toString(), accountId = accountId, aggregateType = "activity",
            aggregateId = activityId, operationType = operation,
            idempotencyKey = "activity:$activityId:$operation:$revision", payloadJson = payload,
            createdAtEpochMs = created, nextAttemptAtEpochMs = created, mutationGeneration = generation,
        ))
    }

    private suspend fun pendingCount(accountId: String): Int = database.syncOutboxDao().retryableCount(accountId)

    private companion object { const val UPSERT = "upsert"; const val DELETE = "delete" }
}

private fun SavedActivity.toUploadRequest(): ActivityUploadRequest {
    val clientData = buildJsonObject {
        put("guideNudge", JsonPrimitive(guideNudge))
        sessionEffortRating?.let { put("sessionEffortRating", JsonPrimitive(it)) }
        performedWorkoutReference?.let { put("performedWorkoutReference", PlainstrideJson.encodeToJsonElement(com.plainstride.outbound.core.model.PerformedWorkoutReference.serializer(), it)) }
        plannedWorkoutCompletionQuality?.let { put("plannedWorkoutCompletionQuality", JsonPrimitive(it)) }
        walkingStepCount?.let { put("walkingStepCount", JsonPrimitive(it)) }
        if (averageHeartRateBpm != null || maximumHeartRateBpm != null || heartRateSampleCount != null) {
            put("healthMetrics", buildJsonObject {
                averageHeartRateBpm?.let { put("averageHeartRateBPM", JsonPrimitive(it)) }
                maximumHeartRateBpm?.let { put("maxHeartRateBPM", JsonPrimitive(it)) }
                heartRateSampleCount?.let { put("heartRateSampleCount", JsonPrimitive(it)) }
            })
        }
        energyKilocalories?.let { put("energyKilocalories", JsonPrimitive(it)) }
        goalJson?.let { put("goal", PlainstrideJson.parseToJsonElement(it)) }
        put("source", PlainstrideJson.parseToJsonElement(PlainstrideJson.encodeToString(source)))
        gearJson?.let { put("gear", PlainstrideJson.parseToJsonElement(it)) }
        indoorJson?.let { put("indoor", PlainstrideJson.parseToJsonElement(it)) }
        cadenceJson?.let { put("cadence", PlainstrideJson.parseToJsonElement(it)) }
        heartRateZonesJson?.let { put("heartRateZones", PlainstrideJson.parseToJsonElement(it)) }
        activityEventId?.let { put("activityEventID", JsonPrimitive(it)) }
        followedRouteId?.let { put("followedRouteId", JsonPrimitive(it)) }
        put("followedRouteCompleted", JsonPrimitive(followedRouteCompleted))
        put("recognitionBadgeIDs", PlainstrideJson.parseToJsonElement(PlainstrideJson.encodeToString(recognitionBadgeIds)))
    }
    return ActivityUploadRequest(
        clientActivityId = id, type = type.name, title = title, startedAt = startedAt, endedAt = endedAt,
        durationSecs = durationSecs, distanceM = distanceM, elevationM = elevationGainM,
        avgPace = averagePaceSecsPerKm, avgHeartRate = averageHeartRateBpm,
        energyKilocalories = energyKilocalories, activityEventId = activityEventId,
        followedRouteId = followedRouteId, followedRouteCompleted = followedRouteCompleted,
        route = track.takeIf { it.size > 1 }?.let { points -> ActivityRouteDto(points.map { ActivityRoutePointDto(it.timestamp, it.latitude, it.longitude, it.altitude, it.verticalAccuracy, it.startsNewSegment) }, elevationMetadata = elevationMetadata) },
        splits = PlainstrideJson.encodeToJsonElement(ListSerializer(ActivitySplit.serializer()), splits),
        reflection = reflection?.let { ActivityReflectionDto(it.title, it.body, it.highlight, it.progressNote) },
        companionType = companionType?.name,
        clientData = clientData, clientUpdatedAt = localUpdatedAt,
    )
}

private fun SavedActivity.toEntity() = ActivityEntity(
    id, accountId, serverActivityId, type.name, title, guideNudge, reflection?.let { PlainstrideJson.encodeToString(it) },
    parseEpoch(createdAt), parseEpoch(startedAt), parseEpoch(endedAt), durationSecs, distanceM, averagePaceSecsPerKm,
    elevationGainM, walkingStepCount, averageHeartRateBpm, maximumHeartRateBpm, heartRateSampleCount, energyKilocalories,
    PlainstrideJson.encodeToString(source), gearJson, goalJson, indoorJson, cadenceJson, heartRateZonesJson, activityEventId,
    followedRouteId, followedRouteCompleted, PlainstrideJson.encodeToString(recognitionBadgeIds), parseEpoch(localUpdatedAt),
    serverUpdatedAt?.let(::parseEpoch), deletedAt?.let(::parseEpoch), companionType?.name,
    elevationMetadata?.let { PlainstrideJson.encodeToString(it) },
    sessionEffortRating,
    performedWorkoutReference?.let { PlainstrideJson.encodeToString(it) },
    plannedWorkoutCompletionQuality,
)

private fun ActivityTrackPoint.toEntity(activity: SavedActivity, index: Int) = ActivityTrackPointEntity(activity.accountId, activity.id, index, parseEpoch(timestamp), latitude, longitude, altitude, verticalAccuracy, startsNewSegment)
private fun ActivitySplit.toEntity(activity: SavedActivity) = ActivitySplitEntity(activity.accountId, activity.id, index, distanceM, durationSecs, paceSecsPerKm, elevationGainM, averageHeartRateBpm)
private fun ActivityPhoto.toEntity(activity: SavedActivity, index: Int) = ActivityPhotoEntity(activity.accountId, activity.id, id, parseEpoch(takenAt), paceAtShot, heartRateAtShot, distanceAtShotM, latitude, longitude, captureContext, localRelativePath, remotePhotoId, remoteUpdatedAt?.let(::parseEpoch), byteSize, sha256, index)

private fun ActivityWithDetails.toDomain(): SavedActivity = with(activity) {
    SavedActivity(
        activityId, accountId, serverActivityId, ActivityType.valueOf(type), title, guideNudge,
        reflectionJson?.let(PlainstrideJson::decodeFromString), instant(createdAtEpochMs), instant(startedAtEpochMs), instant(endedAtEpochMs),
        durationSecs, distanceM, averagePaceSecsPerKm, elevationGainM, walkingStepCount, averageHeartRateBpm,
        maximumHeartRateBpm, heartRateSampleCount, energyKilocalories, PlainstrideJson.decodeFromString(sourceJson), gearJson,
        goalJson, indoorJson, cadenceJson, heartRateZonesJson, activityEventId, followedRouteId, followedRouteCompleted,
        PlainstrideJson.decodeFromString(recognitionBadgeIdsJson), track.sortedBy { it.pointIndex }.map { ActivityTrackPoint(instant(it.timestampEpochMs), it.latitude, it.longitude, it.altitude, it.verticalAccuracy, it.startsNewSegment) },
        splits.sortedBy { it.splitIndex }.map { ActivitySplit(it.splitIndex, it.distanceM, it.durationSecs, it.paceSecsPerKm, it.elevationGainM, it.averageHeartRateBpm) },
        photos.sortedBy { it.sortIndex }.map { ActivityPhoto(it.photoId, instant(it.takenAtEpochMs), it.paceAtShot, it.heartRateAtShot, it.distanceAtShotM, it.latitude, it.longitude, it.captureContext, it.localRelativePath, it.remotePhotoId, it.remoteUpdatedAtEpochMs?.let(::instant), it.byteSize, it.sha256) },
        instant(localUpdatedAtEpochMs), serverUpdatedAtEpochMs?.let(::instant), deletedAtEpochMs?.let(::instant),
        companionType?.let { value -> runCatching { ActivityCompanionType.valueOf(value) }.getOrNull() },
        elevationMetadata = elevationMetadataJson?.let { PlainstrideJson.decodeFromString<ActivityElevationMetadata>(it) },
        sessionEffortRating = sessionEffortRating,
        performedWorkoutReference = performedWorkoutReferenceJson?.let { PlainstrideJson.decodeFromString<com.plainstride.outbound.core.model.PerformedWorkoutReference>(it) },
        plannedWorkoutCompletionQuality = plannedWorkoutCompletionQuality,
    )
}

private fun JsonObject.toDomain(accountId: String, remote: RemoteActivityDto): SavedActivity? = runCatching {
    fun stringValue(key: String) = string(key)
    fun intValue(key: String) = int(key)
    fun boolValue(key: String) = bool(key)
    fun objectValue(key: String) = obj(key)
    fun rawValue(key: String) = raw(key)
    val routePoints = remote.route?.get("points")?.jsonArray?.mapNotNull(::trackPoint).orEmpty()
    val health = objectValue("healthMetrics")
    SavedActivity(
        id = remote.clientActivityId ?: remote.id, accountId = accountId, serverActivityId = remote.id,
        type = ActivityType.valueOf(remote.activityType),
        title = remote.title, guideNudge = stringValue("guideNudge") ?: "",
        reflection = remote.reflection?.let { ActivityReflection(it.title, it.body, it.highlight, it.progressNote) },
        createdAt = remote.createdAt, startedAt = remote.startedAt,
        endedAt = remote.endedAt,
        durationSecs = remote.durationSecs, distanceM = remote.distanceM,
        averagePaceSecsPerKm = remote.avgPace,
        elevationGainM = remote.elevationGainM, walkingStepCount = intValue("walkingStepCount"),
        averageHeartRateBpm = health?.int("averageHeartRateBPM"),
        maximumHeartRateBpm = health?.int("maxHeartRateBPM"),
        heartRateSampleCount = health?.int("heartRateSampleCount"),
        energyKilocalories = intValue("energyKilocalories"),
        sessionEffortRating = intValue("sessionEffortRating")?.takeIf { it in 1..10 },
        performedWorkoutReference = objectValue("performedWorkoutReference")?.let { PlainstrideJson.decodeFromJsonElement(com.plainstride.outbound.core.model.PerformedWorkoutReference.serializer(), it) },
        plannedWorkoutCompletionQuality = stringValue("plannedWorkoutCompletionQuality"),
        source = objectValue("source")?.let { ActivitySource(it.string("kind") ?: "outbound", it.string("displayName") ?: "Plainstride", it.string("deviceName"), it.string("externalID"), it.string("importedAt")) } ?: ActivitySource(),
        gearJson = rawValue("gear"), goalJson = rawValue("goal"), indoorJson = rawValue("indoor"), cadenceJson = rawValue("cadence"), heartRateZonesJson = rawValue("heartRateZones"),
        activityEventId = stringValue("activityEventID"), followedRouteId = stringValue("followedRouteId"),
        followedRouteCompleted = boolValue("followedRouteCompleted") ?: false,
        recognitionBadgeIds = array("recognitionBadgeIDs")?.mapNotNull { it.jsonPrimitive.contentOrNull }.orEmpty(),
        elevationMetadata = remote.route?.get("elevationMetadata")?.takeUnless { it is JsonNull }
            ?.let { PlainstrideJson.decodeFromJsonElement(ActivityElevationMetadata.serializer(), it) },
        track = routePoints,
        photos = remote.photos.map { ActivityPhoto(it.clientPhotoId ?: it.id, it.takenAt, it.paceAtShot, it.hrAtShot, it.distAtShot, it.latitude, it.longitude, it.captureContext, null, it.id, it.updatedAt, it.byteSize, it.sha256) },
        companionType = remote.companionType?.let { value -> runCatching { ActivityCompanionType.valueOf(value.lowercase()) }.getOrNull() },
        localUpdatedAt = remote.clientUpdatedAt ?: remote.updatedAt, serverUpdatedAt = remote.updatedAt,
    )
}.getOrElse { error ->
    Log.w("ActivitySync", "Activity restore decoding failed type=${error.javaClass.simpleName}")
    null
}

private fun trackPoint(element: JsonElement): ActivityTrackPoint? = runCatching { element.jsonObject }.getOrNull()?.let { p ->
    val timestamp = p.string("timestamp") ?: return null
    val latitude = p.double("latitude") ?: return null
    val longitude = p.double("longitude") ?: return null
    ActivityTrackPoint(timestamp, latitude, longitude, p.double("altitude"), p.double("verticalAccuracy"), p.bool("startsNewSegment") ?: false)
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
