package com.plainstride.outbound.feature.activity

import android.content.Context
import android.content.Intent
import android.content.ContentValues
import android.graphics.BitmapFactory
import android.provider.MediaStore
import androidx.compose.foundation.BorderStroke
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.CameraAlt
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.Lightbulb
import androidx.compose.material.icons.outlined.People
import androidx.compose.material.icons.outlined.Route
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Smartphone
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedCard
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.TopAppBarDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.MapRouteMarker
import com.plainstride.outbound.core.designsystem.MapRouteSegment
import com.plainstride.outbound.core.designsystem.PlainstrideRouteMap
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.math.roundToInt
import com.plainstride.outbound.core.model.activity.ActivityPhoto
import com.plainstride.outbound.core.model.activity.ActivitySplit
import com.plainstride.outbound.core.model.activity.ActivityTrackPoint
import com.plainstride.outbound.core.model.activity.ActivityType
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SavedActivity
import com.plainstride.outbound.core.model.activity.SessionFormatting
import com.plainstride.outbound.core.model.activity.WorkoutCalorieEstimator
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

@Composable
fun RecentActivitiesRoute(
    accountId: String,
    unitSystem: MeasurementUnitSystem,
    weightKilograms: Double?,
    onOpenActivity: (String) -> Unit,
    onOpenAll: () -> Unit,
    onImportHealth: () -> Unit,
    onMessage: suspend (ActivityMessage) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ActivityViewModel = hiltViewModel(key = "me_recent_activities"),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    var manualEntry by rememberSaveable { mutableStateOf(false) }
    var trackedCalorieExposure by rememberSaveable { mutableStateOf(false) }
    LaunchedEffect(accountId) { viewModel.start(accountId) }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    LaunchedEffect(state.page.activities, weightKilograms) {
        if (!trackedCalorieExposure && state.page.activities.take(3).any { recentKilocalories(it, weightKilograms) != null }) {
            viewModel.trackCalorieExposure()
            trackedCalorieExposure = true
        }
    }
    OutlinedCard(
        modifier = modifier.fillMaxWidth(),
        shape = RoundedCornerShape(20.dp),
        colors = CardDefaults.outlinedCardColors(containerColor = MaterialTheme.colorScheme.surfaceContainerLow),
        border = BorderStroke(1.dp, MaterialTheme.colorScheme.onSurface.copy(alpha = 0.07f)),
        elevation = CardDefaults.outlinedCardElevation(defaultElevation = 1.dp),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(
                    stringResource(R.string.activity_recent_title),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.labelMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                IconButton(
                    onClick = {
                        viewModel.trackMeRecentAction("manual_workout")
                        manualEntry = true
                    },
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(Icons.Outlined.Add, stringResource(R.string.activity_add_manual), tint = MaterialTheme.colorScheme.primary)
                }
                IconButton(
                    onClick = {
                        viewModel.trackMeRecentAction("health_connect")
                        onImportHealth()
                    },
                    modifier = Modifier.size(48.dp),
                ) {
                    Icon(Icons.Outlined.Download, stringResource(R.string.activity_recent_import), tint = MaterialTheme.colorScheme.primary)
                }
                TextButton(
                    onClick = {
                        viewModel.trackMeRecentAction("activity_history")
                        onOpenAll()
                    },
                    modifier = Modifier.heightIn(min = 48.dp),
                    contentPadding = PaddingValues(horizontal = 8.dp),
                ) {
                    Text(stringResource(R.string.activity_recent_all))
                }
            }
            state.page.activities.take(3).forEach { activity ->
                CompactRecentActivityRow(activity, unitSystem, weightKilograms) { onOpenActivity(activity.id) }
            }
            if (state.loading && state.page.activities.isEmpty()) {
                Box(Modifier.fillMaxWidth().padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                    CircularProgressIndicator(Modifier.size(24.dp), strokeWidth = 2.dp)
                }
            } else if (state.page.activities.isEmpty()) {
                Text(
                    stringResource(R.string.activity_recent_empty),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
    if (manualEntry) ManualActivityDialog(
        onDismiss = { manualEntry = false },
        onSave = { type, title, duration, distance, elevation ->
            viewModel.createManual(type, title, duration, distance, elevation)
            manualEntry = false
        },
    )
}

@Composable
private fun CompactRecentActivityRow(
    activity: SavedActivity,
    unitSystem: MeasurementUnitSystem,
    weightKilograms: Double?,
    onClick: () -> Unit,
) {
    val kilocalories = remember(activity, weightKilograms) {
        recentKilocalories(activity, weightKilograms)
    }
    val minutes = (activity.durationSecs / 60.0).roundToInt().coerceAtLeast(1)
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = 64.dp)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            Text(
                activity.title,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.SemiBold,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(activityShortDate(activity.startedAt), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            Text(
                kilocalories?.let { stringResource(R.string.activity_completed_duration_calories_format, minutes, it) }
                    ?: stringResource(R.string.activity_completed_duration_format, minutes),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        Text(formatRecentDistance(activity.distanceM, unitSystem), style = MaterialTheme.typography.bodyMedium)
    }
}

private fun recentKilocalories(activity: SavedActivity, weightKilograms: Double?): Int? =
    activity.energyKilocalories?.takeIf { it > 0 }
        ?: WorkoutCalorieEstimator.estimate(
            activityType = activity.type,
            distanceMeters = activity.distanceM,
            durationSeconds = activity.durationSecs,
            elevationGainMeters = activity.elevationGainM ?: 0.0,
            weightKilograms = weightKilograms,
        ).kilocalories

@Composable
fun ActivityHistoryRoute(
    accountId: String,
    unitSystem: MeasurementUnitSystem,
    weightKilograms: Double?,
    initialActivityId: String? = null,
    onBack: () -> Unit,
    onMessage: suspend (ActivityMessage) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ActivityViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(accountId, initialActivityId) {
        viewModel.start(accountId)
        initialActivityId?.let(viewModel::open)
    }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    val selected = state.selected
    if (selected == null) ActivityHistoryScreen(state, unitSystem, viewModel::open, viewModel::loadMore, viewModel::createManual, onBack, modifier)
    else ActivityDetailScreen(
        activity = selected,
        unitSystem = unitSystem,
        weightKilograms = weightKilograms,
        mutating = state.mutating,
        onBack = viewModel::closeDetail,
        onEdit = viewModel::editTitle,
        onDelete = viewModel::deleteSelected,
        onShareCard = { viewModel.shareCard(selected, unitSystem) },
        onShareAction = viewModel::trackShareAction,
        onCalorieExposure = viewModel::trackCalorieExposure,
        photoBytes = viewModel::photoBytes,
        modifier = modifier,
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityHistoryScreen(
    state: ActivityUiState,
    unitSystem: MeasurementUnitSystem,
    onOpen: (String) -> Unit,
    onLoadMore: () -> Unit,
    onManual: (ActivityType, String, Int, Double, Double?) -> Unit,
    onBack: () -> Unit,
    modifier: Modifier,
) {
    var manualEntry by rememberSaveable { mutableStateOf(false) }
    Scaffold(modifier, contentWindowInsets = WindowInsets.safeDrawing, topBar = { TopAppBar(
        title = { Text(stringResource(R.string.activity_history)) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.activity_back)) } },
        actions = { IconButton(onClick = { manualEntry = true }) { Icon(Icons.Outlined.Add, stringResource(R.string.activity_add_manual)) } },
    ) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            if (!state.loading && state.page.activities.isEmpty()) item { EmptyHistory(Modifier.fillParentMaxSize()) }
            items(state.page.activities, key = SavedActivity::id) { activity -> ActivityRow(activity, unitSystem, { onOpen(activity.id) }) }
            if (state.page.hasMore) item { OutlinedButton(onClick = onLoadMore, enabled = !state.loading, modifier = Modifier.fillMaxWidth().padding(20.dp).heightIn(min = 48.dp)) {
                Text(stringResource(R.string.activity_load_more))
            } }
            if (state.loading) item { Box(Modifier.fillMaxWidth().padding(24.dp), contentAlignment = Alignment.Center) { CircularProgressIndicator() } }
        }
    }
    if (manualEntry) ManualActivityDialog(onDismiss = { manualEntry = false }, onSave = { type, title, duration, distance, elevation ->
        onManual(type, title, duration, distance, elevation); manualEntry = false
    })
}

@Composable private fun EmptyHistory(modifier: Modifier) = Box(modifier.padding(32.dp), contentAlignment = Alignment.Center) {
    Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Icon(Icons.Outlined.Route, null, Modifier.size(48.dp), tint = MaterialTheme.colorScheme.primary)
        Text(stringResource(R.string.activity_empty_title), style = MaterialTheme.typography.titleLarge)
        Text(stringResource(R.string.activity_empty_body), color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable private fun ActivityRow(activity: SavedActivity, unitSystem: MeasurementUnitSystem, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp).clickable(role = Role.Button, onClick = onClick)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    Text(activity.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(activityDate(activity.startedAt), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    ActivityTypeBadge(activity.type)
                    if (activity.companionType != null) {
                        Text(
                            stringResource(R.string.activity_companion_dog_title),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.padding(top = 4.dp),
                        )
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                SummaryMetric(formatDistance(activity.distanceM, unitSystem), stringResource(R.string.activity_distance))
                SummaryMetric(formatDuration(activity.durationSecs), stringResource(R.string.activity_time))
                SummaryMetric(formatPace(activity.averagePaceSecsPerKm, unitSystem), stringResource(R.string.activity_pace))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityDetailScreen(
    activity: SavedActivity,
    unitSystem: MeasurementUnitSystem,
    weightKilograms: Double?,
    mutating: Boolean,
    onBack: () -> Unit,
    onEdit: (String) -> Unit,
    onDelete: () -> Unit,
    onShareCard: () -> ActivityExport?,
    onShareAction: (String) -> Unit,
    onCalorieExposure: () -> Unit,
    photoBytes: (String) -> ByteArray?,
    modifier: Modifier,
) {
    val context = LocalContext.current
    val calorieEstimate = remember(activity, weightKilograms) {
        activity.energyKilocalories?.takeIf { it > 0 }
            ?: WorkoutCalorieEstimator.estimate(
                activityType = activity.type,
                distanceMeters = activity.distanceM,
                durationSeconds = activity.durationSecs,
                elevationGainMeters = activity.elevationGainM ?: 0.0,
                weightKilograms = weightKilograms,
            ).kilocalories
    }
    val elevationPoints = remember(activity.track) { elevationProfile(activity.track) }
    val splits = remember(activity.track, unitSystem) { computeDetailSplits(activity.track, unitSystem) }
    val routeSegments = remember(activity.track) { paceColoredRouteSegments(activity.track) }
    var edit by rememberSaveable { mutableStateOf(false) }
    var delete by rememberSaveable { mutableStateOf(false) }
    var sharePreview by remember { mutableStateOf<ActivityExport?>(null) }
    var selectedPhotoIndex by rememberSaveable(activity.id) { mutableStateOf(firstLocatedPhotoIndex(activity.photos)) }
    var lightboxPhotoIndex by rememberSaveable(activity.id) { mutableStateOf<Int?>(null) }
    LaunchedEffect(calorieEstimate) { if (calorieEstimate != null) onCalorieExposure() }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val density = LocalDensity.current
        val collapsedHeight = 108.dp
        val splitHeight = maxHeight * 0.52f
        val expandedHeight = (maxHeight - 48.dp).coerceAtLeast(splitHeight)
        var sheetLevel by rememberSaveable(activity.id) { mutableStateOf(ActivitySheetLevel.Split) }
        var dragOffsetPx by remember { mutableFloatStateOf(0f) }
        val targetHeight = when (sheetLevel) {
            ActivitySheetLevel.Collapsed -> collapsedHeight
            ActivitySheetLevel.Split -> splitHeight
            ActivitySheetLevel.Expanded -> expandedHeight
        }
        val animatedHeight by animateDpAsState(targetHeight, label = "activity-detail-sheet")
        val sheetHeight = if (dragOffsetPx == 0f) animatedHeight else {
            (targetHeight + with(density) { dragOffsetPx.toDp() }).coerceIn(collapsedHeight, expandedHeight)
        }

        if (activity.track.size > 1) {
            val markers = activity.photos.mapIndexedNotNull { index, photo ->
                val latitude = photo.latitude ?: return@mapIndexedNotNull null
                val longitude = photo.longitude ?: return@mapIndexedNotNull null
                MapRouteMarker(
                    id = photo.id,
                    coordinate = MapCoordinate(latitude, longitude),
                    title = photoMapLabel(index, activity.photos.size, photo.distanceAtShotM, unitSystem, context),
                    selected = index == selectedPhotoIndex,
                )
            }
            PlainstrideRouteMap(
                points = activity.track.map { MapCoordinate(it.latitude, it.longitude) },
                modifier = Modifier.fillMaxSize(),
                interactive = true,
                showEndpointMarkers = false,
                routeSegments = routeSegments,
                markers = markers,
                bottomContentPadding = sheetHeight,
            )
        } else {
            Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
                Text(stringResource(R.string.activity_map_no_route), color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }

        TopAppBar(
            title = { Text(activity.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
            navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.activity_back)) } },
            actions = {
                IconButton(onClick = { sharePreview = onShareCard() }) { Icon(Icons.Outlined.Share, stringResource(R.string.activity_share_card)) }
                IconButton(onClick = { edit = true }) { Icon(Icons.Outlined.Edit, stringResource(R.string.activity_edit)) }
            },
            colors = TopAppBarDefaults.topAppBarColors(containerColor = MaterialTheme.colorScheme.surface.copy(alpha = 0.90f)),
            modifier = Modifier.align(Alignment.TopCenter),
        )

        Surface(
            modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(sheetHeight),
            shape = RoundedCornerShape(topStart = if (sheetLevel == ActivitySheetLevel.Expanded) 0.dp else 22.dp, topEnd = if (sheetLevel == ActivitySheetLevel.Expanded) 0.dp else 22.dp),
            color = MaterialTheme.colorScheme.surface,
            shadowElevation = 16.dp,
        ) {
            Column {
                val collapsedPx = with(density) { collapsedHeight.toPx() }
                val expandedPx = with(density) { expandedHeight.toPx() }
                val basePx = with(density) { targetHeight.toPx() }
                val toggleDescription = stringResource(
                    if (sheetLevel == ActivitySheetLevel.Expanded) R.string.activity_sheet_collapse else R.string.activity_sheet_expand,
                )
                Box(
                    Modifier.fillMaxWidth().height(32.dp)
                        .pointerInput(basePx, collapsedPx, expandedPx) {
                            fun settle() {
                                val actual = basePx + dragOffsetPx
                                sheetLevel = ActivitySheetLevel.entries.minBy { level ->
                                    val height = when (level) {
                                        ActivitySheetLevel.Collapsed -> collapsedPx
                                        ActivitySheetLevel.Split -> with(density) { splitHeight.toPx() }
                                        ActivitySheetLevel.Expanded -> expandedPx
                                    }
                                    abs(height - actual)
                                }
                                dragOffsetPx = 0f
                            }
                            detectVerticalDragGestures(
                                onVerticalDrag = { change, amount ->
                                    change.consume()
                                    dragOffsetPx = (dragOffsetPx - amount).coerceIn(collapsedPx - basePx, expandedPx - basePx)
                                },
                                onDragEnd = ::settle,
                                onDragCancel = ::settle,
                            )
                        }
                        .clickable {
                            sheetLevel = if (sheetLevel == ActivitySheetLevel.Expanded) ActivitySheetLevel.Split else ActivitySheetLevel.Expanded
                        }
                        .semantics { contentDescription = toggleDescription },
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.width(42.dp).height(5.dp).clip(CircleShape).background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.35f)))
                }

                if (sheetLevel == ActivitySheetLevel.Collapsed) {
                    CollapsedActivitySummary(activity, unitSystem) { sheetLevel = ActivitySheetLevel.Split }
                } else {
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        userScrollEnabled = sheetLevel == ActivitySheetLevel.Expanded,
                    ) {
                        item {
                            ActivityStatsHero(
                                activity = activity,
                                unitSystem = unitSystem,
                                calorieEstimate = calorieEstimate,
                                selectedPhotoIndex = selectedPhotoIndex,
                                onSelectPhoto = { index ->
                                    if (index == selectedPhotoIndex) lightboxPhotoIndex = index else selectedPhotoIndex = index
                                },
                                photoBytes = photoBytes,
                            )
                        }
                        if (activity.activityEventId != null) item { SharedActivitySection() }
                        if (hasActivityMetadata(activity)) item { ActivityMetadataSection(activity) }
                        if (elevationPoints.size > 1) item { ElevationProfileSection(elevationPoints, unitSystem) }
                        if (splits.isNotEmpty()) item { ActivitySplitsSection(splits, unitSystem) }
                        item { CompanionReflectionCard(activity) }
                        item {
                            TextButton(
                                onClick = { delete = true },
                                enabled = !mutating,
                                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
                            ) {
                                Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error)
                                Spacer(Modifier.width(6.dp))
                                Text(stringResource(R.string.activity_delete), color = MaterialTheme.colorScheme.error)
                            }
                        }
                        item { Spacer(Modifier.navigationBarsPadding().height(24.dp)) }
                    }
                }
            }
        }
    }
    if (edit) EditTitleDialog(activity.title, { edit = false }, { onEdit(it); edit = false })
    if (delete) AlertDialog(onDismissRequest = { delete = false }, title = { Text(stringResource(R.string.activity_delete_title)) },
        text = { Text(stringResource(R.string.activity_delete_body)) },
        confirmButton = { TextButton(onClick = { delete = false; onDelete() }) { Text(stringResource(R.string.activity_delete)) } },
        dismissButton = { TextButton(onClick = { delete = false }) { Text(stringResource(R.string.activity_cancel)) } })
    sharePreview?.let { export -> SharePreviewDialog(
        export = export,
        close = { sharePreview = null },
        save = { onShareAction(if (context.saveImage(export)) "saved_to_photos" else "save_failed") },
        share = { context.shareExport(export); onShareAction("share_sheet_opened") },
    ) }
    lightboxPhotoIndex?.let { index ->
        ActivityPhotoLightbox(
            photos = activity.photos,
            initialIndex = index,
            photoBytes = photoBytes,
            onSelected = { selectedPhotoIndex = it },
            onClose = { lightboxPhotoIndex = null },
        )
    }
}

private enum class ActivitySheetLevel { Collapsed, Split, Expanded }

private data class DetailActivityStat(val label: String, val value: String)
private data class DetailElevationPoint(val distanceMeters: Double, val altitudeMeters: Double)
private data class DetailSplit(
    val number: Int,
    val paceSecondsPerKilometer: Double,
    val elevationChangeMeters: Double?,
)

@Composable
private fun CollapsedActivitySummary(activity: SavedActivity, unitSystem: MeasurementUnitSystem, expand: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().clickable(onClick = expand).padding(horizontal = 18.dp, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text(formatDistance(activity.distanceM, unitSystem), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
            Text(activity.title, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        SummaryMetric(formatPace(activity.averagePaceSecsPerKm, unitSystem), stringResource(R.string.activity_avg_pace), Alignment.End)
        SummaryMetric(formatDuration(activity.durationSecs), stringResource(R.string.activity_metric_moving_time), Alignment.End)
    }
}

@Composable
private fun ActivityStatsHero(
    activity: SavedActivity,
    unitSystem: MeasurementUnitSystem,
    calorieEstimate: Int?,
    selectedPhotoIndex: Int,
    onSelectPhoto: (Int) -> Unit,
    photoBytes: (String) -> ByteArray?,
) {
    val stats = buildList {
        add(DetailActivityStat(stringResource(R.string.activity_distance), formatDistance(activity.distanceM, unitSystem)))
        add(DetailActivityStat(stringResource(R.string.activity_avg_pace), formatPace(activity.averagePaceSecsPerKm, unitSystem)))
        add(DetailActivityStat(stringResource(R.string.activity_metric_moving_time), formatDuration(activity.durationSecs)))
        if (activity.type == ActivityType.walking && activity.walkingStepCount != null) {
            add(DetailActivityStat(stringResource(R.string.activity_metric_steps), "%,d".format(activity.walkingStepCount)))
        }
        if (calorieEstimate != null) add(DetailActivityStat(stringResource(R.string.activity_metric_calories), calorieEstimate.toString()))
        add(DetailActivityStat(stringResource(R.string.activity_metric_elevation_gain), formatElevation(activity.elevationGainM, unitSystem)))
    }
    Column(Modifier.fillMaxWidth().padding(top = 4.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
        Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(3.dp)) {
            Text(activity.title, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 2)
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                if (activity.companionType != null) {
                    Text(
                        stringResource(R.string.activity_companion_dog_title),
                        style = MaterialTheme.typography.labelMedium,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                Text(activityDate(activity.startedAt), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        }
        if (activity.photos.isNotEmpty()) ActivityPhotoStrip(activity.photos, selectedPhotoIndex, onSelectPhoto, photoBytes, unitSystem)
        Column(Modifier.padding(horizontal = 28.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            stats.chunked(2).forEach { row ->
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                    row.forEach { stat -> DetailStatCell(stat, Modifier.weight(1f)) }
                    if (row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun DetailStatCell(stat: DetailActivityStat, modifier: Modifier = Modifier) = Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
    Text(stat.label, style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Text(stat.value, style = MaterialTheme.typography.titleLarge, fontWeight = FontWeight.Bold, maxLines = 1)
}

@Composable
private fun ActivityPhotoStrip(
    photos: List<ActivityPhoto>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
    photoBytes: (String) -> ByteArray?,
    unitSystem: MeasurementUnitSystem,
) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp), contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = 20.dp)) {
        itemsIndexed(photos, key = { _, photo -> photo.id }) { index, photo ->
            val bitmap = remember(photo.localRelativePath) {
                photo.localRelativePath?.let(photoBytes)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
            }
            val selected = index == selectedIndex
            Card(
                onClick = { onSelect(index) },
                modifier = Modifier.width(132.dp).height(104.dp).then(
                    if (selected) Modifier.border(2.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(12.dp)) else Modifier,
                ),
                shape = RoundedCornerShape(12.dp),
            ) {
                Box(Modifier.fillMaxSize()) {
                    if (bitmap != null) Image(bitmap.asImageBitmap(), stringResource(R.string.activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                    else Box(Modifier.fillMaxSize().background(MaterialTheme.colorScheme.surfaceVariant), contentAlignment = Alignment.Center) {
                        Icon(Icons.Outlined.CameraAlt, stringResource(R.string.activity_photo_pending))
                    }
                    Text(
                        photoLabel(index, photos.size, photo.distanceAtShotM, unitSystem),
                        Modifier.align(Alignment.BottomStart).fillMaxWidth().background(Color.Black.copy(alpha = 0.60f)).padding(horizontal = 8.dp, vertical = 5.dp),
                        color = Color.White,
                        style = MaterialTheme.typography.labelSmall,
                    )
                }
            }
        }
    }
}

@Composable
private fun SharedActivitySection() = Row(
    Modifier.fillMaxWidth().padding(horizontal = 18.dp, vertical = 12.dp),
    horizontalArrangement = Arrangement.spacedBy(12.dp),
) {
    Icon(Icons.Outlined.People, null, tint = MaterialTheme.colorScheme.primary)
    Column {
        Text(stringResource(R.string.activity_shared_title), fontWeight = FontWeight.SemiBold)
        Text(stringResource(R.string.activity_shared_detail), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun ActivityMetadataSection(activity: SavedActivity) = Column(
    Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 10.dp),
    verticalArrangement = Arrangement.spacedBy(12.dp),
) {
    if (activity.source.kind != "outbound") {
        MetadataRow(Icons.Outlined.Smartphone, activity.source.displayName, activity.source.deviceName.orEmpty())
    }
    jsonString(activity.gearJson, "shoeName", "displayName", "name")?.let {
        MetadataRow(Icons.AutoMirrored.Outlined.DirectionsRun, stringResource(R.string.activity_meta_shoes), it)
    }
    if (jsonBoolean(activity.indoorJson, "isIndoor") == true) {
        MetadataRow(Icons.AutoMirrored.Outlined.DirectionsRun, stringResource(R.string.activity_meta_treadmill), stringResource(R.string.activity_meta_indoor_run))
    }
    val averageCadence = jsonInt(activity.cadenceJson, "averageStepsPerMinute", "averageSpm")
    val maximumCadence = jsonInt(activity.cadenceJson, "maxStepsPerMinute", "maximumSpm")
    if (averageCadence != null || maximumCadence != null) {
        val detail = listOfNotNull(
            averageCadence?.let { stringResource(R.string.activity_meta_cadence_average, it) },
            maximumCadence?.let { stringResource(R.string.activity_meta_cadence_maximum, it) },
        ).joinToString(" • ")
        MetadataRow(Icons.AutoMirrored.Outlined.DirectionsRun, stringResource(R.string.activity_meta_cadence_title), detail)
    }
}

@Composable
private fun MetadataRow(icon: androidx.compose.ui.graphics.vector.ImageVector, title: String, detail: String) = Row(
    Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.Top,
) {
    Icon(icon, null, Modifier.size(24.dp), tint = MaterialTheme.colorScheme.primary)
    Column {
        Text(title, fontWeight = FontWeight.SemiBold)
        if (detail.isNotBlank()) Text(detail, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant, maxLines = 2)
    }
}

@Composable
private fun ElevationProfileSection(points: List<DetailElevationPoint>, unitSystem: MeasurementUnitSystem) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().animateContentSize()) {
        DisclosureHeader(
            title = stringResource(R.string.activity_elevation),
            detail = formatElevation(points.maxOf { it.altitudeMeters }, unitSystem),
            expanded = expanded,
            toggle = { expanded = !expanded },
        )
        AnimatedVisibility(expanded, enter = fadeIn(), exit = fadeOut()) {
            ElevationProfileChart(points, Modifier.fillMaxWidth().height(132.dp).padding(horizontal = 16.dp, vertical = 10.dp))
        }
    }
}

@Composable
private fun ElevationProfileChart(points: List<DetailElevationPoint>, modifier: Modifier) {
    val lineColor = MaterialTheme.colorScheme.primary
    val fillColor = lineColor.copy(alpha = 0.14f)
    val description = stringResource(R.string.activity_elevation_description)
    Canvas(modifier.semantics { contentDescription = description }) {
        if (points.size < 2) return@Canvas
        val minAltitude = points.minOf { it.altitudeMeters }
        val maxAltitude = points.maxOf { it.altitudeMeters }
        val altitudeRange = (maxAltitude - minAltitude).coerceAtLeast(1.0)
        val maxDistance = points.maxOf { it.distanceMeters }.coerceAtLeast(1.0)
        val offsets = points.map {
            Offset(
                x = (it.distanceMeters / maxDistance * size.width).toFloat(),
                y = size.height - ((it.altitudeMeters - minAltitude) / altitudeRange * size.height * 0.86f).toFloat(),
            )
        }
        val fill = Path().apply {
            moveTo(offsets.first().x, size.height)
            offsets.forEach { lineTo(it.x, it.y) }
            lineTo(offsets.last().x, size.height)
            close()
        }
        val line = Path().apply {
            moveTo(offsets.first().x, offsets.first().y)
            offsets.drop(1).forEach { lineTo(it.x, it.y) }
        }
        drawPath(fill, fillColor)
        drawPath(line, lineColor, style = Stroke(width = 5f))
    }
}

@Composable
private fun ActivitySplitsSection(splits: List<DetailSplit>, unitSystem: MeasurementUnitSystem) {
    var expanded by rememberSaveable { mutableStateOf(false) }
    val fastest = splits.minOf { it.paceSecondsPerKilometer }
    val slowest = splits.maxOf { it.paceSecondsPerKilometer }
    val showElevation = splits.any { it.elevationChangeMeters != null }
    Column(Modifier.fillMaxWidth().animateContentSize()) {
        DisclosureHeader(
            title = stringResource(R.string.activity_splits_title),
            detail = "${splits.size} ${distanceUnit(unitSystem)}",
            expanded = expanded,
            toggle = { expanded = !expanded },
        )
        AnimatedVisibility(expanded, enter = fadeIn(), exit = fadeOut()) {
            Column(Modifier.padding(bottom = 10.dp)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp)) {
                    Text(distanceUnit(unitSystem).uppercase(), Modifier.width(34.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(stringResource(R.string.activity_splits_pace), Modifier.width(68.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Spacer(Modifier.weight(1f))
                    if (showElevation) Text(stringResource(R.string.activity_splits_elev), Modifier.width(48.dp), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                splits.forEach { split ->
                    SplitRow(split, fastest, slowest, showElevation, unitSystem)
                }
            }
        }
    }
}

@Composable
private fun SplitRow(split: DetailSplit, fastest: Double, slowest: Double, showElevation: Boolean, unitSystem: MeasurementUnitSystem) {
    val fraction = splitPaceFraction(split.paceSecondsPerKilometer, fastest, slowest)
    Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(split.number.toString(), Modifier.width(34.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(formatPace(split.paceSecondsPerKilometer, unitSystem), Modifier.width(68.dp), style = MaterialTheme.typography.bodySmall, maxLines = 1)
        Box(Modifier.weight(1f).height(18.dp), contentAlignment = Alignment.CenterStart) {
            Box(Modifier.fillMaxWidth(fraction.toFloat()).height(14.dp).clip(CircleShape).background(Color(0xFF2F80ED)))
        }
        if (showElevation) Text(formatSignedElevation(split.elevationChangeMeters, unitSystem), Modifier.width(48.dp), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}

@Composable
private fun DisclosureHeader(title: String, detail: String, expanded: Boolean, toggle: () -> Unit) = Row(
    Modifier.fillMaxWidth().clickable(onClick = toggle).padding(horizontal = 16.dp, vertical = 12.dp).semantics { heading() },
    verticalAlignment = Alignment.CenterVertically,
) {
    Text(title, Modifier.weight(1f), fontWeight = FontWeight.SemiBold)
    Text(detail, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
    Icon(Icons.Outlined.KeyboardArrowDown, null, Modifier.padding(start = 6.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
private fun CompanionReflectionCard(activity: SavedActivity) {
    val reflection = activity.reflection
    Card(
        Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 16.dp),
        colors = androidx.compose.material3.CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.55f)),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.AutoMirrored.Outlined.DirectionsRun, null, tint = MaterialTheme.colorScheme.primary)
                Column {
                    Text(reflection?.title ?: stringResource(R.string.activity_guide_reflection_title), fontWeight = FontWeight.SemiBold)
                    Text(stringResource(R.string.activity_guide_companion), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            Text(reflection?.body ?: stringResource(R.string.activity_guide_reflection_body), style = MaterialTheme.typography.bodyMedium)
            if (activity.guideNudge.isNotBlank()) {
                Row(
                    Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).background(MaterialTheme.colorScheme.primary.copy(alpha = 0.08f)).padding(10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(Icons.Outlined.Lightbulb, null, Modifier.size(18.dp), tint = MaterialTheme.colorScheme.primary)
                    Text(activity.guideNudge, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityPhotoLightbox(
    photos: List<ActivityPhoto>,
    initialIndex: Int,
    photoBytes: (String) -> ByteArray?,
    onSelected: (Int) -> Unit,
    onClose: () -> Unit,
) {
    val pagerState = rememberPagerState(initialPage = initialIndex.coerceIn(0, photos.lastIndex)) { photos.size }
    LaunchedEffect(pagerState.currentPage) { onSelected(pagerState.currentPage) }
    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Box(Modifier.fillMaxSize().background(Color.Black).statusBarsPadding().navigationBarsPadding()) {
            HorizontalPager(pagerState, Modifier.fillMaxSize()) { page ->
                val photo = photos[page]
                val bitmap = remember(photo.localRelativePath) {
                    photo.localRelativePath?.let(photoBytes)?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                }
                if (bitmap != null) Image(bitmap.asImageBitmap(), stringResource(R.string.activity_photo), Modifier.fillMaxSize(), contentScale = ContentScale.Fit)
                else Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) { Icon(Icons.Outlined.CameraAlt, stringResource(R.string.activity_photo_pending), tint = Color.White) }
            }
            IconButton(onClick = onClose, modifier = Modifier.align(Alignment.TopEnd).padding(12.dp)) { Icon(Icons.Outlined.Close, stringResource(R.string.activity_back), tint = Color.White) }
            Text("${pagerState.currentPage + 1} / ${photos.size}", Modifier.align(Alignment.BottomCenter).padding(20.dp), color = Color.White)
        }
    }
}

@Composable private fun SharePreviewDialog(export: ActivityExport, close:()->Unit, save:()->Unit, share:()->Unit) {
    val context=LocalContext.current
    val bitmap=remember(export.uri){context.contentResolver.openInputStream(export.uri)?.use(BitmapFactory::decodeStream)}
    AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.activity_share_preview))},text={bitmap?.let{Image(it.asImageBitmap(),stringResource(R.string.activity_share_preview_description),Modifier.fillMaxWidth().aspectRatio(9f/16f))}},confirmButton={Button({share();close()}){Text(stringResource(R.string.activity_share))}},dismissButton={Row{TextButton(save){Text(stringResource(R.string.activity_save_image))};TextButton(close){Text(stringResource(R.string.activity_cancel))}}})
}

private fun Context.saveImage(export: ActivityExport): Boolean = runCatching {
    val values = ContentValues().apply {
        put(MediaStore.Images.Media.DISPLAY_NAME, export.fileName)
        put(MediaStore.Images.Media.MIME_TYPE, "image/png")
        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Plainstride")
    }
    val destination = requireNotNull(contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values))
    val input = requireNotNull(contentResolver.openInputStream(export.uri))
    val output = requireNotNull(contentResolver.openOutputStream(destination))
    input.use { source -> output.use(source::copyTo) }
}.isSuccess

@Composable private fun ActivityTypeBadge(type: ActivityType) = Surface(shape = CircleShape, color = MaterialTheme.colorScheme.secondaryContainer) {
    Text(activityTypeName(type), Modifier.padding(horizontal = 10.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium)
}

@Composable private fun SummaryMetric(value: String, label: String, alignment: Alignment.Horizontal = Alignment.CenterHorizontally) = Column(horizontalAlignment = alignment) {
    Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable private fun EditTitleDialog(initial: String, onDismiss: () -> Unit, onSave: (String) -> Unit) {
    var value by rememberSaveable { mutableStateOf(initial) }
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.activity_edit_title)) },
        text = { OutlinedTextField(value, { value = it }, label = { Text(stringResource(R.string.activity_title)) }, singleLine = true) },
        confirmButton = { TextButton(onClick = { onSave(value) }, enabled = value.isNotBlank()) { Text(stringResource(R.string.activity_save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.activity_cancel)) } })
}

@Composable private fun ManualActivityDialog(onDismiss: () -> Unit, onSave: (ActivityType, String, Int, Double, Double?) -> Unit) {
    var type by rememberSaveable { mutableStateOf(ActivityType.running) }
    var title by rememberSaveable { mutableStateOf("") }
    var duration by rememberSaveable { mutableStateOf("") }
    var distance by rememberSaveable { mutableStateOf("") }
    var elevation by rememberSaveable { mutableStateOf("") }
    val valid = title.isNotBlank() && (duration.toIntOrNull() ?: 0) > 0 && (distance.toDoubleOrNull() ?: -1.0) >= 0
    AlertDialog(onDismissRequest = onDismiss, title = { Text(stringResource(R.string.activity_manual_title)) }, text = {
        LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
            item { Column { ActivityType.entries.chunked(3).forEach { row -> Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) { row.forEach { option ->
                if (type == option) FilledTonalButton(onClick = { type = option }) { Text(activityTypeName(option)) }
                else TextButton(onClick = { type = option }) { Text(activityTypeName(option)) }
            } } } } }
            item { OutlinedTextField(title, { title = it }, label = { Text(stringResource(R.string.activity_title)) }, singleLine = true) }
            item { OutlinedTextField(duration, { duration = it.filter(Char::isDigit) }, label = { Text(stringResource(R.string.activity_duration_minutes)) }, singleLine = true) }
            item { OutlinedTextField(distance, { distance = decimalInput(it) }, label = { Text(stringResource(R.string.activity_distance_km)) }, singleLine = true) }
            item { OutlinedTextField(elevation, { elevation = decimalInput(it) }, label = { Text(stringResource(R.string.activity_elevation_meters)) }, singleLine = true) }
        }
    }, confirmButton = { TextButton(onClick = { onSave(type, title, duration.toInt(), distance.toDouble(), elevation.toDoubleOrNull()) }, enabled = valid) { Text(stringResource(R.string.activity_save)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.activity_cancel)) } })
}

@Composable private fun activityTypeName(type: ActivityType) = stringResource(when (type) {
    ActivityType.running -> R.string.activity_type_running; ActivityType.walking -> R.string.activity_type_walking
    ActivityType.hiking -> R.string.activity_type_hiking; ActivityType.cycling -> R.string.activity_type_cycling
    ActivityType.swimming -> R.string.activity_type_swimming
})

private fun decimalInput(value: String) = value.filter { it.isDigit() || it == '.' }.let { filtered -> if (filtered.count { it == '.' } <= 1) filtered else filtered.dropLast(1) }
private fun formatDistance(meters: Double, unitSystem: MeasurementUnitSystem): String {
    val distance = SessionFormatting.distance(meters, unitSystem)
    return "%.2f %s".format(distance.value, distanceUnit(unitSystem))
}
private fun formatRecentDistance(meters: Double, unitSystem: MeasurementUnitSystem): String {
    val distance = SessionFormatting.distance(meters, unitSystem)
    return "%.1f %s".format(distance.value, distanceUnit(unitSystem))
}
private fun formatDuration(seconds: Int) = if (seconds >= 3_600) "%d:%02d:%02d".format(seconds / 3_600, seconds / 60 % 60, seconds % 60) else "%d:%02d".format(seconds / 60, seconds % 60)
private fun formatPace(seconds: Double?, unitSystem: MeasurementUnitSystem): String {
    val pace = seconds?.let { SessionFormatting.pace(it, unitSystem) } ?: return "—"
    return "%d:%02d /%s".format(pace.minutes, pace.seconds, distanceUnit(unitSystem))
}
private fun formatElevation(meters: Double?, unitSystem: MeasurementUnitSystem): String {
    val elevation = meters?.let { SessionFormatting.elevation(it, unitSystem) } ?: return "—"
    return "%.0f %s".format(elevation.value, if (unitSystem == MeasurementUnitSystem.metric) "m" else "ft")
}
private fun formatSignedElevation(meters: Double?, unitSystem: MeasurementUnitSystem): String {
    val elevation = meters?.let { SessionFormatting.elevation(it, unitSystem).value } ?: return "--"
    return if (elevation > 0) "+%.0f".format(elevation) else "%.0f".format(elevation)
}
private fun distanceUnit(unitSystem: MeasurementUnitSystem) = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
private fun activityDate(value: String) = runCatching {
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault(value)

private fun activityShortDate(value: String) = runCatching {
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault(value)

@Composable
private fun photoLabel(index: Int, count: Int, distanceMeters: Double?, unitSystem: MeasurementUnitSystem): String = when (index) {
    0 -> stringResource(R.string.activity_photo_start)
    count - 1 -> stringResource(R.string.activity_photo_finish)
    else -> distanceMeters?.let { formatDistance(it, unitSystem) } ?: stringResource(R.string.activity_photo)
}

private fun photoMapLabel(
    index: Int,
    count: Int,
    distanceMeters: Double?,
    unitSystem: MeasurementUnitSystem,
    context: Context,
): String = when (index) {
    0 -> context.getString(R.string.activity_photo_start)
    count - 1 -> context.getString(R.string.activity_photo_finish)
    else -> distanceMeters?.let { formatDistance(it, unitSystem) } ?: context.getString(R.string.activity_photo)
}

private fun firstLocatedPhotoIndex(photos: List<ActivityPhoto>): Int =
    photos.indexOfFirst { it.latitude != null && it.longitude != null }.takeIf { it >= 0 } ?: 0

private fun hasActivityMetadata(activity: SavedActivity): Boolean =
    activity.source.kind != "outbound" || activity.gearJson != null || activity.indoorJson != null || activity.cadenceJson != null

private val activityDetailJson = Json { ignoreUnknownKeys = true }

private fun jsonString(value: String?, vararg keys: String): String? = parseJsonObject(value)?.let { json ->
    keys.firstNotNullOfOrNull { key -> json[key]?.jsonPrimitive?.contentOrNull?.takeIf(String::isNotBlank) }
}

private fun jsonInt(value: String?, vararg keys: String): Int? = parseJsonObject(value)?.let { json ->
    keys.firstNotNullOfOrNull { key -> json[key]?.jsonPrimitive?.intOrNull }
}

private fun jsonBoolean(value: String?, key: String): Boolean? = parseJsonObject(value)?.get(key)?.jsonPrimitive?.booleanOrNull

private fun parseJsonObject(value: String?) = value?.let { runCatching { activityDetailJson.parseToJsonElement(it).jsonObject }.getOrNull() }

private fun elevationProfile(points: List<ActivityTrackPoint>): List<DetailElevationPoint> {
    if (points.size < 2) return emptyList()
    val distances = cumulativeDistances(points)
    return points.mapIndexedNotNull { index, point ->
        val altitude = point.altitude ?: return@mapIndexedNotNull null
        if (point.verticalAccuracy?.let { it < 0 } == true) return@mapIndexedNotNull null
        DetailElevationPoint(distances[index], altitude)
    }
}

private fun computeDetailSplits(points: List<ActivityTrackPoint>, unitSystem: MeasurementUnitSystem): List<DetailSplit> {
    if (points.size < 2) return emptyList()
    val timestamps = points.map { point -> runCatching { Instant.parse(point.timestamp) }.getOrNull() ?: return emptyList() }
    val distances = cumulativeDistances(points)
    val splitDistanceMeters = if (unitSystem == MeasurementUnitSystem.metric) 1_000.0 else 1_609.344
    val result = mutableListOf<DetailSplit>()
    var splitStartIndex = 0
    var splitNumber = 1
    for (index in 1 until points.size) {
        if (distances[index] >= splitNumber * splitDistanceMeters || index == points.lastIndex) {
            val distance = distances[index] - distances[splitStartIndex]
            val duration = java.time.Duration.between(timestamps[splitStartIndex], timestamps[index]).toMillis() / 1_000.0
            if (distance > 20.0 && duration > 0.0) {
                result += DetailSplit(
                    number = splitNumber,
                    paceSecondsPerKilometer = duration / (distance / 1_000.0),
                    elevationChangeMeters = points[splitStartIndex].altitude?.let { start -> points[index].altitude?.minus(start) },
                )
                splitStartIndex = index
                splitNumber += 1
            }
        }
    }
    return result
}

private fun paceColoredRouteSegments(points: List<ActivityTrackPoint>): List<MapRouteSegment> {
    if (points.size < 2) return emptyList()
    if (points.drop(1).any(ActivityTrackPoint::startsNewSegment)) {
        val groups = mutableListOf<MutableList<MapCoordinate>>(mutableListOf())
        points.forEachIndexed { index, point ->
            if (index > 0 && point.startsNewSegment) groups.add(mutableListOf())
            groups.last() += MapCoordinate(point.latitude, point.longitude)
        }
        return groups.filter { it.size > 1 }.map { MapRouteSegment(it, Color(0xFFFF9500)) }
    }
    val result = mutableListOf<MapRouteSegment>()
    var start = 0
    while (start < points.lastIndex) {
        val end = min(start + 15, points.lastIndex)
        val distance = haversineMeters(points[start], points[end])
        val duration = runCatching {
            java.time.Duration.between(Instant.parse(points[start].timestamp), Instant.parse(points[end].timestamp)).toMillis() / 1_000.0
        }.getOrDefault(0.0)
        val pace = if (distance > 0.0 && duration > 0.0) duration / (distance / 1_000.0) else 0.0
        result += MapRouteSegment(
            points = points.subList(start, end + 1).map { MapCoordinate(it.latitude, it.longitude) },
            color = paceColor(pace),
        )
        start = end
    }
    return result
}

private fun paceColor(pace: Double): Color {
    if (!pace.isFinite() || pace <= 0.0) return Color(0xFFFF9500)
    val fraction = ((pace - 240.0) / 180.0).coerceIn(0.0, 1.0)
    return if (fraction < 0.5) {
        val red = (fraction / 0.5 * 255).toInt()
        Color(red, 255, 0)
    } else {
        val green = ((1.0 - (fraction - 0.5) / 0.5) * 255).toInt()
        Color(255, green, 0)
    }
}

private fun splitPaceFraction(pace: Double, fastest: Double, slowest: Double): Double {
    if (pace <= 0 || fastest <= 0 || slowest <= fastest) return 0.85
    val normalized = (slowest - pace) / (slowest - fastest)
    return 0.28 + normalized.coerceIn(0.0, 1.0) * 0.72
}

private fun cumulativeDistances(points: List<ActivityTrackPoint>): List<Double> {
    if (points.isEmpty()) return emptyList()
    val result = MutableList(points.size) { 0.0 }
    for (index in 1 until points.size) result[index] = result[index - 1] + haversineMeters(points[index - 1], points[index])
    return result
}

private fun haversineMeters(first: ActivityTrackPoint, second: ActivityTrackPoint): Double {
    val earthRadius = 6_371_000.0
    val latitudeDelta = Math.toRadians(second.latitude - first.latitude)
    val longitudeDelta = Math.toRadians(second.longitude - first.longitude)
    val firstLatitude = Math.toRadians(first.latitude)
    val secondLatitude = Math.toRadians(second.latitude)
    val value = sin(latitudeDelta / 2) * sin(latitudeDelta / 2) +
        cos(firstLatitude) * cos(secondLatitude) * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
    return earthRadius * 2 * atan2(sqrt(value), sqrt(1 - value))
}

private fun Context.shareExport(export: ActivityExport) {
    startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType(export.mimeType).putExtra(Intent.EXTRA_STREAM, export.uri).putExtra(Intent.EXTRA_TITLE, export.fileName).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), getString(R.string.activity_export)))
}
