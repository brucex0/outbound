package com.plainstride.outbound.feature.activity

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.core.content.FileProvider
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.time.Instant
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.launch
import com.plainstride.outbound.core.analytics.AnalyticsEvent
import com.plainstride.outbound.core.analytics.AnalyticsProperty
import com.plainstride.outbound.core.analytics.ProductAnalytics
import com.plainstride.outbound.core.data.ActivityExporter
import com.plainstride.outbound.core.data.ActivityMediaStore
import com.plainstride.outbound.core.data.ActivityRepository
import com.plainstride.outbound.core.data.ActivitySyncScheduler
import com.plainstride.outbound.core.data.ManualActivityFactory
import com.plainstride.outbound.core.data.ManualActivityInput
import com.plainstride.outbound.core.model.activity.ActivityPage
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SavedActivity

enum class ActivityMessage { SAVED, UPDATED, DELETED, FAILED, EXPORT_UNAVAILABLE }
enum class ActivityExportFormat(val extension: String, val mimeType: String) {
    GPX("gpx", "application/gpx+xml"),
    GEOJSON("geojson", "application/geo+json"),
}
data class ActivityExport(val uri: android.net.Uri, val mimeType: String, val fileName: String)

data class ActivityUiState(
    val detailLoading: Boolean = false, val detailFailed: Boolean = false,
    val accountId: String? = null,
    val page: ActivityPage = ActivityPage(emptyList(), 0, PAGE_SIZE, false),
    val loading: Boolean = true,
    val mutating: Boolean = false,
    val selected: SavedActivity? = null,
    val groupAttribution: com.plainstride.outbound.core.model.activity.GroupActivityAttribution? = null,
) {
    companion object { const val PAGE_SIZE = 30 }
}

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ActivityViewModel @Inject constructor(
    private val database: com.plainstride.outbound.core.database.PlainstrideDatabase,
    private val groups: com.plainstride.outbound.core.data.GroupActivityRepository,
    private val repository: ActivityRepository,
    private val syncScheduler: ActivitySyncScheduler,
    private val mediaStore: ActivityMediaStore,
    private val shareAssets: ActivityShareAssetLoader,
    private val analytics: ProductAnalytics,
    @param:ApplicationContext private val context: Context,
) : ViewModel() {
    private val account = MutableStateFlow<String?>(null)
    private val limit = MutableStateFlow(ActivityUiState.PAGE_SIZE)
    private val mutableState = MutableStateFlow(ActivityUiState())
    val state: StateFlow<ActivityUiState> = mutableState.asStateFlow()
    val messages = MutableSharedFlow<ActivityMessage>(extraBufferCapacity = 4)

    init {
        viewModelScope.launch {
            account.filterNotNull().combine(limit) { id, pageLimit -> id to pageLimit }
                .flatMapLatest { (id, pageLimit) -> repository.observePage(id, limit = pageLimit) }
                .collect { page ->
                    mutableState.value = mutableState.value.copy(page = page, loading = false)
                }
        }
    }

    fun start(accountId: String, trackHistory: Boolean = true) {
        if (account.value == accountId) return
        account.value = accountId
        mutableState.value = mutableState.value.copy(accountId = accountId, loading = true)
        if (trackHistory) analytics.record(AnalyticsEvent("activity_history_opened", mapOf(AnalyticsProperty.Source to "me")))
    }

    fun loadMore() {
        if (!mutableState.value.page.hasMore || mutableState.value.loading) return
        val next = limit.value + ActivityUiState.PAGE_SIZE
        mutableState.value = mutableState.value.copy(loading = true)
        viewModelScope.launch {
            val id = account.value ?: return@launch
            if (repository.loadHistoryPage(id, next)) limit.value = next
            else messages.emit(ActivityMessage.FAILED)
            mutableState.value = mutableState.value.copy(loading = false)
        }
        analytics.record(AnalyticsEvent("paginated_list_page_loaded", mapOf(
            AnalyticsProperty.Source to "activity_history",
            AnalyticsProperty.PageDepthBucket to when { next <= 60 -> "page_2"; next <= 120 -> "pages_3_4"; else -> "page_5_plus" },
        )))
    }

    fun open(activityId: String, source: String = "history") {
        val accountId = account.value ?: return
        val selected = mutableState.value.selected
        if (selected?.id == activityId || selected?.serverActivityId == activityId) return
        viewModelScope.launch {
            try {
                mutableState.value = mutableState.value.copy(detailLoading = true, detailFailed = false)
                var activity = repository.activity(accountId, activityId)
                if (activity == null) {
                    repository.refreshActivity(accountId, activityId)
                    activity = repository.activity(accountId, activityId)
                }
                mutableState.value = mutableState.value.copy(selected = activity, detailLoading = false, detailFailed = activity == null, groupAttribution = null)
                if (activity == null) Log.w("PlainstrideActivity", "detail_load unavailable source=$source")
                val loadedActivity = activity
                if (loadedActivity != null) analytics.record(AnalyticsEvent("activity_detail_opened", mapOf(AnalyticsProperty.Source to source)))
                if (loadedActivity != null) launch {
                    repository.refreshActivity(accountId, loadedActivity.id)
                    if (account.value == accountId && mutableState.value.selected?.id == loadedActivity.id) {
                        mutableState.value = mutableState.value.copy(selected = repository.activity(accountId, loadedActivity.id))
                    }
                    if (repository.correctElevationIfNeeded(accountId, loadedActivity.id)) {
                        syncScheduler.schedule(accountId)
                        val refreshed = repository.activity(accountId, loadedActivity.id)
                        if (account.value == accountId && mutableState.value.selected?.id == loadedActivity.id) {
                            mutableState.value = mutableState.value.copy(selected = refreshed)
                        }
                    }
                }
                loadedActivity?.activityEventId?.let { event ->
                    val detail = groups.detail(event)
                    if (account.value == accountId && mutableState.value.selected?.id == loadedActivity.id) {
                        mutableState.value = mutableState.value.copy(groupAttribution = detail?.attribution(accountId))
                    }
                }
            } catch (error: Exception) {
                if (error is kotlinx.coroutines.CancellationException) throw error
                Log.w("PlainstrideActivity", "detail_load failed type=${error.javaClass.simpleName}")
                mutableState.value = mutableState.value.copy(detailLoading = false, detailFailed = true)
            }
        }
    }

    fun closeDetail() { mutableState.value = mutableState.value.copy(selected = null) }

    fun trackMeRecentAction(destination: String) {
        analytics.record(AnalyticsEvent(
            "me_destination_opened",
            mapOf(
                AnalyticsProperty.Destination to destination,
                AnalyticsProperty.EntrySource to "me_recent",
            ),
        ))
    }

    internal suspend fun editorShoes(accountId: String): List<EditorShoe> =
        database.gearDao().forAccount(accountId).filter { it.retiredAtEpochMs == null }.map {
            EditorShoe(it.gearId, listOf(it.brand.trim(), it.model.trim()).filter(String::isNotEmpty).joinToString(" ").ifEmpty { it.name })
        }

    fun trackEditor(feature: String = "activity_editor") {
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to feature)))
    }

    fun trackPhotoLocationPermission(result: String) {
        analytics.record(AnalyticsEvent("photo_import_location_access", mapOf(
            AnalyticsProperty.SourceType to "activity_edit", AnalyticsProperty.Result to result,
        )))
    }

    fun trackEditorPhoto(name: String, locationAttached: Boolean? = null) {
        val properties = mutableMapOf<AnalyticsProperty, Any>(AnalyticsProperty.SourceType to "activity_edit")
        locationAttached?.let { properties[AnalyticsProperty.LocationAttached] = it }
        analytics.record(AnalyticsEvent(name, properties))
    }

    internal suspend fun saveEditor(draft: ActivityEditorDraft): Boolean {
        if (mutableState.value.mutating) return false
        mutableState.value = mutableState.value.copy(mutating = true)
        val written = mutableListOf<String>()
        var committed = false
        try {
            val current = repository.activity(draft.original.accountId, draft.original.id)
                ?: error("Activity unavailable")
            check(account.value == current.accountId)
            val photos = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                draft.photos.map { photo ->
                    if (photo.importPath == null) current.photos.firstOrNull { it.id == photo.photo.id } ?: photo.photo else {
                        val bytes = File(photo.importPath).readBytes()
                        val path = mediaStore.write(current.accountId, current.id, bytes)
                        written += path
                        photo.photo.copy(localRelativePath = path, byteSize = bytes.size.toLong())
                    }
                }
            }
            val updated = current.copy(
                title = draft.title.trim().ifEmpty { current.title },
                startedAt = draft.startedAt,
                endedAt = Instant.parse(draft.startedAt).plusSeconds(draft.durationSecs.toLong()).toString(),
                distanceM = draft.distanceM, durationSecs = draft.durationSecs,
                averagePaceSecsPerKm = editorPace(current.type, draft.durationSecs, draft.distanceM),
                gearJson = draft.gearJson, photos = photos,
                localUpdatedAt = Instant.now().toString(),
            )
            kotlinx.coroutines.withContext(kotlinx.coroutines.NonCancellable) {
                check(account.value == current.accountId)
                repository.edit(updated)
                committed = true
            }
            try { syncScheduler.schedule(current.accountId) }
            catch (error: Exception) { Log.w("PlainstrideActivity", "edit_sync_schedule failed type=${error.javaClass.simpleName}") }
            if (account.value == current.accountId && mutableState.value.selected?.id == current.id) {
                mutableState.value = mutableState.value.copy(selected = updated)
            }
            analytics.record(AnalyticsEvent("activity_edited", mapOf(AnalyticsProperty.Result to "success")))
            kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                current.photos.filter { old -> photos.none { it.id == old.id } }.mapNotNull { it.localRelativePath }.forEach { path ->
                    if (!mediaStore.delete(path)) Log.w("PlainstrideActivity", "edit_removed_photo_cleanup failed")
                }
            }
            trackEditor("activity_editor_saved")
            return true
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (error: Exception) {
            Log.w("PlainstrideActivity", "edit_save failed committed=$committed type=${error.javaClass.simpleName}")
            analytics.record(AnalyticsEvent("activity_operation_failed", mapOf(AnalyticsProperty.ErrorCategory to "local_storage")))
            return committed
        } finally {
            if (!committed) written.forEach { path ->
                if (!mediaStore.delete(path)) Log.w("PlainstrideActivity", "edit_save media_cleanup failed")
            }
            mutableState.value = mutableState.value.copy(mutating = false)
        }
    }

    fun deleteSelected() = mutate(ActivityMessage.DELETED) {
        val current = mutableState.value.selected ?: return@mutate
        repository.delete(current.accountId, current.id)
        current.photos.mapNotNull { it.localRelativePath }.forEach(mediaStore::delete)
        mutableState.value = mutableState.value.copy(selected = null)
        analytics.record(AnalyticsEvent("activity_deleted", mapOf(
            AnalyticsProperty.SourceType to "activity_history",
            AnalyticsProperty.CountBucket to "one",
        )))
    }

    fun createManual(
        type: ActivityType,
        title: String,
        durationMinutes: Int,
        distanceKilometers: Double,
        elevationMeters: Double?,
    ) = mutate(ActivityMessage.SAVED) {
        val accountId = account.value ?: return@mutate
        repository.save(ManualActivityFactory.create(ManualActivityInput(
            accountId = accountId,
            type = type,
            title = title,
            startedAt = Instant.now().minusSeconds(durationMinutes * 60L),
            durationSecs = durationMinutes * 60,
            distanceM = distanceKilometers * 1_000,
            elevationGainM = elevationMeters,
        )))
        analytics.record(AnalyticsEvent("manual_activity_saved", mapOf(
            AnalyticsProperty.ActivityType to type.name,
            AnalyticsProperty.DurationBucket to durationBucket(durationMinutes * 60),
            AnalyticsProperty.DistanceBucket to distanceBucket(distanceKilometers * 1_000),
        )))
    }

    fun export(activity: SavedActivity, format: ActivityExportFormat): ActivityExport? = runCatching {
        require(activity.track.isNotEmpty())
        val directory = File(context.cacheDir, "activity_exports").apply { mkdirs() }
        directory.listFiles()?.filter { it.lastModified() < System.currentTimeMillis() - 86_400_000L }?.forEach(File::delete)
        val safeId = activity.id.filter { it.isLetterOrDigit() || it == '-' || it == '_' }.take(80)
        val target = File(directory, "plainstride-$safeId.${format.extension}")
        target.writeText(when (format) { ActivityExportFormat.GPX -> ActivityExporter.gpx(activity); ActivityExportFormat.GEOJSON -> ActivityExporter.geoJson(activity) })
        analytics.record(AnalyticsEvent("activity_exported", mapOf(AnalyticsProperty.Result to format.name.lowercase())))
        ActivityExport(FileProvider.getUriForFile(context, "${context.packageName}.activityphotos", target), format.mimeType, target.name)
    }.getOrElse { messages.tryEmit(ActivityMessage.EXPORT_UNAVAILABLE); null }

    fun trackSplitsViewed(count: Int) = analytics.record(AnalyticsEvent("activity_splits_viewed", mapOf(
        AnalyticsProperty.SourceType to "me_activity_detail",
        AnalyticsProperty.CountBucket to photoAnnotationCountBucket(count),
    )))

    fun trackRoutePhotoPreview() = analytics.record(AnalyticsEvent("photo_previewed", mapOf(
        AnalyticsProperty.SourceType to "route_annotation",
    )))

    suspend fun loadShareAssets(activity: SavedActivity): ActivityShareAssets = shareAssets.load(activity)

    fun shareCard(activity: SavedActivity, bitmap: Bitmap, sourceType: String = "activity_detail"): ActivityExport? = runCatching {
        val directory = File(context.cacheDir, "activity_exports").apply { mkdirs() }
        val target = File(directory, "plainstride-${activity.id.filter(Char::isLetterOrDigit).take(64)}.png")
        target.outputStream().use { check(bitmap.compress(Bitmap.CompressFormat.PNG, 100, it)) }
        analytics.record(AnalyticsEvent("activity_share_previewed", mapOf(
            AnalyticsProperty.SourceType to sourceType,
            AnalyticsProperty.CountBucket to photoAnnotationCountBucket(activity.photos.count { it.latitude != null && it.longitude != null }),
        )))
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(AnalyticsProperty.Feature to "activity_share_map_card")))
        ActivityExport(FileProvider.getUriForFile(context, "${context.packageName}.activityphotos", target), "image/png", target.name)
    }.getOrElse { error ->
        Log.e("ActivityShare", "Share card preparation failed type=${error.javaClass.simpleName}")
        messages.tryEmit(ActivityMessage.EXPORT_UNAVAILABLE)
        null
    }

    fun trackShareAction(result: String, sourceType: String = "activity_detail") {
        analytics.record(AnalyticsEvent("activity_share_action", mapOf(
            AnalyticsProperty.SourceType to sourceType,
            AnalyticsProperty.Result to result,
        )))
    }

    fun trackSocialShareAction(result: String) {
        analytics.record(AnalyticsEvent("activity_share_action", mapOf(
            AnalyticsProperty.SourceType to "social_feed",
            AnalyticsProperty.Result to result,
        )))
    }

    fun trackCadenceExposure() = analytics.record(AnalyticsEvent(
        "feature_exposed", mapOf(AnalyticsProperty.Feature to "running_cadence_summary"),
    ))

    fun trackCalorieExposure() {
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(
            AnalyticsProperty.Feature to "completed_workout_calories",
        )))
    }

    fun photoBytes(relativePath: String): ByteArray? = runCatching { mediaStore.read(relativePath) }.getOrNull()

    private fun mutate(success: ActivityMessage, action: suspend () -> Unit) {
        if (mutableState.value.mutating) return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(mutating = true)
            runCatching { action() }.onSuccess { messages.emit(success) }.onFailure {
                analytics.record(AnalyticsEvent("activity_operation_failed", mapOf(AnalyticsProperty.ErrorCategory to "local_storage")))
                messages.emit(ActivityMessage.FAILED)
            }
            mutableState.value = mutableState.value.copy(mutating = false)
        }
    }
}

private fun durationBucket(seconds: Int) = when { seconds < 300 -> "under_5m"; seconds < 1_800 -> "5_30m"; seconds < 3_600 -> "30_60m"; else -> "60m_plus" }
private fun distanceBucket(meters: Double) = when { meters < 1_000 -> "under_1k"; meters < 5_000 -> "1_5k"; meters < 10_000 -> "5_10k"; else -> "10k_plus" }

private fun photoAnnotationCountBucket(count: Int) = when (count) { 0 -> "0"; 1 -> "1"; in 2..3 -> "2_3"; in 4..7 -> "4_7"; else -> "8_plus" }
