package com.plainstride.outbound.feature.activity

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import com.google.zxing.BarcodeFormat
import com.google.zxing.MultiFormatWriter
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
import com.plainstride.outbound.core.data.ManualActivityFactory
import com.plainstride.outbound.core.data.ManualActivityInput
import com.plainstride.outbound.core.model.activity.ActivityPage
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.model.activity.SessionFormatting

enum class ActivityMessage { SAVED, UPDATED, DELETED, FAILED, EXPORT_UNAVAILABLE }
enum class ActivityExportFormat(val extension: String, val mimeType: String) {
    GPX("gpx", "application/gpx+xml"),
    GEOJSON("geojson", "application/geo+json"),
}
data class ActivityExport(val uri: android.net.Uri, val mimeType: String, val fileName: String)

data class ActivityUiState(
    val accountId: String? = null,
    val page: ActivityPage = ActivityPage(emptyList(), 0, PAGE_SIZE, false),
    val loading: Boolean = true,
    val mutating: Boolean = false,
    val selected: SavedActivity? = null,
) {
    companion object { const val PAGE_SIZE = 30 }
}

@HiltViewModel
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ActivityViewModel @Inject constructor(
    private val repository: ActivityRepository,
    private val mediaStore: ActivityMediaStore,
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

    fun start(accountId: String) {
        if (account.value == accountId) return
        account.value = accountId
        mutableState.value = mutableState.value.copy(accountId = accountId, loading = true)
        analytics.record(AnalyticsEvent("activity_history_opened", mapOf(AnalyticsProperty.Source to "me")))
    }

    fun loadMore() {
        if (!mutableState.value.page.hasMore || mutableState.value.loading) return
        val next = limit.value + ActivityUiState.PAGE_SIZE
        limit.value = next
        mutableState.value = mutableState.value.copy(loading = true)
        analytics.record(AnalyticsEvent("paginated_list_page_loaded", mapOf(
            AnalyticsProperty.Source to "activity_history",
            AnalyticsProperty.PageDepthBucket to when { next <= 60 -> "page_2"; next <= 120 -> "pages_3_4"; else -> "page_5_plus" },
        )))
    }

    fun open(activityId: String) {
        val accountId = account.value ?: return
        viewModelScope.launch {
            mutableState.value = mutableState.value.copy(loading = true)
            val activity = repository.activity(accountId, activityId)
            mutableState.value = mutableState.value.copy(selected = activity, loading = false)
            if (activity != null) analytics.record(AnalyticsEvent("activity_detail_opened", mapOf(AnalyticsProperty.Source to "history")))
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

    fun editTitle(title: String) = mutate(ActivityMessage.UPDATED) {
        val current = mutableState.value.selected ?: return@mutate
        val updated = current.copy(title = title.trim(), localUpdatedAt = Instant.now().toString())
        repository.edit(updated)
        mutableState.value = mutableState.value.copy(selected = updated)
        analytics.record(AnalyticsEvent("activity_edited", mapOf(AnalyticsProperty.Result to "success")))
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

    fun shareCard(activity: SavedActivity, unitSystem: MeasurementUnitSystem): ActivityExport? = runCatching {
        val directory = File(context.cacheDir, "activity_exports").apply { mkdirs() }
        val target = File(directory, "plainstride-${activity.id.filter(Char::isLetterOrDigit).take(64)}.png")
        val bitmap = Bitmap.createBitmap(1080, 1920, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        canvas.drawColor(Color.rgb(24, 28, 24))
        drawRouteBackdrop(canvas, activity)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE }
        paint.textSize = 42f
        canvas.drawText("PLAINSTRIDE", 72f, 90f, paint)
        paint.isFakeBoldText = true
        paint.textSize = 70f
        canvas.drawText(activity.title.take(24), 72f, 1240f, paint)
        paint.isFakeBoldText = false
        paint.color = Color.rgb(232, 126, 62)
        paint.textSize = 58f
        val distance = SessionFormatting.distance(activity.distanceM, unitSystem)
        val distanceUnit = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
        canvas.drawText("%.2f %s".format(distance.value, distanceUnit), 72f, 1400f, paint)
        canvas.drawText(formatDurationForCard(activity.durationSecs), 390f, 1400f, paint)
        activity.averagePaceSecsPerKm?.let { rawPace ->
            SessionFormatting.pace(rawPace, unitSystem)?.let { pace ->
                canvas.drawText("%d:%02d /%s".format(pace.minutes, pace.seconds, distanceUnit), 700f, 1400f, paint)
            }
        }
        paint.color = Color.LTGRAY
        paint.textSize = 30f
        canvas.drawText(context.getString(R.string.activity_distance).uppercase(), 72f, 1460f, paint)
        canvas.drawText(context.getString(R.string.activity_time).uppercase(), 390f, 1460f, paint)
        canvas.drawText(context.getString(R.string.activity_avg_pace).uppercase(), 700f, 1460f, paint)
        drawQr(canvas, "https://plainstride.ai/invite", 790, 1600, 220)
        target.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 95, it) }
        bitmap.recycle()
        analytics.record(AnalyticsEvent("activity_share_previewed", mapOf(AnalyticsProperty.SourceType to "activity_detail")))
        ActivityExport(FileProvider.getUriForFile(context, "${context.packageName}.activityphotos", target), "image/png", target.name)
    }.getOrElse { messages.tryEmit(ActivityMessage.EXPORT_UNAVAILABLE); null }

    fun trackShareAction(result: String) {
        analytics.record(AnalyticsEvent("activity_share_action", mapOf(
            AnalyticsProperty.SourceType to "activity_detail",
            AnalyticsProperty.Result to result,
        )))
    }

    fun trackCalorieExposure() {
        analytics.record(AnalyticsEvent("feature_exposed", mapOf(
            AnalyticsProperty.Feature to "completed_workout_calories",
        )))
    }

    private fun drawRouteBackdrop(canvas: Canvas, activity: SavedActivity) {
        val points = activity.track
        if (points.size < 2) return
        val minLat = points.minOf { it.latitude }; val maxLat = points.maxOf { it.latitude }
        val minLon = points.minOf { it.longitude }; val maxLon = points.maxOf { it.longitude }
        val latSpan = (maxLat - minLat).coerceAtLeast(0.00001); val lonSpan = (maxLon - minLon).coerceAtLeast(0.00001)
        val route = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.rgb(244, 132, 63); strokeWidth = 14f; style = Paint.Style.STROKE; strokeCap = Paint.Cap.ROUND; strokeJoin = Paint.Join.ROUND }
        val path = android.graphics.Path()
        points.forEachIndexed { index, point ->
            val x = 70f + ((point.longitude - minLon) / lonSpan * 940f).toFloat()
            val y = 160f + ((maxLat - point.latitude) / latSpan * 900f).toFloat()
            if (index == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        canvas.drawPath(path, Paint(route).apply { color = Color.argb(100, 0, 0, 0); strokeWidth = 26f })
        canvas.drawPath(path, route)
    }

    private fun drawQr(canvas: Canvas, value: String, left: Int, top: Int, size: Int) {
        val matrix = MultiFormatWriter().encode(value, BarcodeFormat.QR_CODE, size, size)
        val qr = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        for (y in 0 until size) for (x in 0 until size) qr.setPixel(x, y, if (matrix[x, y]) Color.BLACK else Color.WHITE)
        canvas.drawBitmap(qr, left.toFloat(), top.toFloat(), null); qr.recycle()
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
private fun formatDurationForCard(seconds: Int) = if (seconds >= 3_600) "%d:%02d:%02d".format(seconds / 3_600, seconds / 60 % 60, seconds % 60) else "%d:%02d".format(seconds / 60, seconds % 60)
