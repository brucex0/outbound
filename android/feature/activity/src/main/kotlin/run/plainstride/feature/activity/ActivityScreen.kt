package run.plainstride.feature.activity

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.content.ContentValues
import android.provider.MediaStore
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.FileDownload
import androidx.compose.material.icons.outlined.Route
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import run.plainstride.core.designsystem.MapCoordinate
import run.plainstride.core.designsystem.PlainstrideRouteMap
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import run.plainstride.core.model.activity.ActivityPhoto
import run.plainstride.core.model.activity.ActivitySplit
import run.plainstride.core.model.activity.ActivityTrackPoint
import run.plainstride.core.model.activity.ActivityType
import run.plainstride.core.model.activity.SavedActivity

@Composable
fun RecentActivitiesRoute(
    accountId: String,
    onOpenHistory: () -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ActivityViewModel = hiltViewModel(key = "me_recent_activities"),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(accountId) { viewModel.start(accountId) }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        state.page.activities.take(3).forEach { activity -> ActivityRow(activity, onOpenHistory) }
        if (!state.loading && state.page.activities.isEmpty()) {
            Text(stringResource(R.string.activity_recent_empty), Modifier.padding(horizontal = 20.dp), color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}

@Composable
fun ActivityHistoryRoute(
    accountId: String,
    initialActivityId: String? = null,
    onBack: () -> Unit,
    onMessage: suspend (ActivityMessage) -> Unit,
    modifier: Modifier = Modifier,
    viewModel: ActivityViewModel = hiltViewModel(),
) {
    val state by viewModel.state.collectAsStateWithLifecycle()
    LaunchedEffect(accountId) { viewModel.start(accountId) }
    LaunchedEffect(initialActivityId, state.loading) { if (!state.loading && initialActivityId != null) viewModel.open(initialActivityId) }
    LaunchedEffect(viewModel) { viewModel.messages.collect(onMessage) }
    val selected = state.selected
    if (selected == null) ActivityHistoryScreen(state, viewModel::open, viewModel::loadMore, viewModel::createManual, onBack, modifier)
    else ActivityDetailScreen(selected, state.mutating, viewModel::closeDetail, viewModel::editTitle, viewModel::deleteSelected,
        { format -> viewModel.export(selected, format) }, { viewModel.shareCard(selected) }, viewModel::photoBytes, modifier)
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityHistoryScreen(
    state: ActivityUiState,
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
            items(state.page.activities, key = SavedActivity::id) { activity -> ActivityRow(activity, { onOpen(activity.id) }) }
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

@Composable private fun ActivityRow(activity: SavedActivity, onClick: () -> Unit) {
    Card(Modifier.fillMaxWidth().padding(horizontal = 16.dp).clickable(role = Role.Button, onClick = onClick)) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Column(Modifier.weight(1f)) {
                    Text(activity.title, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text(activityDate(activity.startedAt), color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
                ActivityTypeBadge(activity.type)
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                SummaryMetric(formatDistance(activity.distanceM), stringResource(R.string.activity_distance))
                SummaryMetric(formatDuration(activity.durationSecs), stringResource(R.string.activity_time))
                SummaryMetric(formatPace(activity.averagePaceSecsPerKm), stringResource(R.string.activity_pace))
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ActivityDetailScreen(
    activity: SavedActivity,
    mutating: Boolean,
    onBack: () -> Unit,
    onEdit: (String) -> Unit,
    onDelete: () -> Unit,
    onExport: (ActivityExportFormat) -> ActivityExport?,
    onShareCard: () -> ActivityExport?,
    photoBytes: (String) -> ByteArray?,
    modifier: Modifier,
) {
    val context = LocalContext.current
    var edit by rememberSaveable { mutableStateOf(false) }
    var delete by rememberSaveable { mutableStateOf(false) }
    var sharePreview by remember { mutableStateOf<ActivityExport?>(null) }
    Scaffold(modifier, contentWindowInsets = WindowInsets.safeDrawing, topBar = { TopAppBar(
        title = { Text(activity.title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
        navigationIcon = { IconButton(onClick = onBack) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.activity_back)) } },
        actions = {
            IconButton(onClick = { edit = true }) { Icon(Icons.Outlined.Edit, stringResource(R.string.activity_edit)) }
            IconButton(onClick = { sharePreview = onShareCard() }) { Icon(Icons.Outlined.Share, stringResource(R.string.activity_share_card)) }
        },
    ) }) { padding ->
        LazyColumn(Modifier.fillMaxSize().padding(padding), verticalArrangement = Arrangement.spacedBy(18.dp)) {
            item {
                Column(Modifier.padding(horizontal = 20.dp)) {
                    Text(activityDate(activity.startedAt), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Row(Modifier.fillMaxWidth().padding(top = 16.dp), horizontalArrangement = Arrangement.SpaceBetween) {
                        SummaryMetric(formatDistance(activity.distanceM), stringResource(R.string.activity_distance))
                        SummaryMetric(formatDuration(activity.durationSecs), stringResource(R.string.activity_time))
                        SummaryMetric(formatPace(activity.averagePaceSecsPerKm), stringResource(R.string.activity_avg_pace))
                    }
                }
            }
            if (activity.track.size > 1) item {
                SectionTitle(stringResource(R.string.activity_route))
                RouteChart(activity.track, Modifier.fillMaxWidth().height(240.dp).padding(horizontal = 20.dp))
            }
            if (activity.track.any { it.altitude != null }) item {
                SectionTitle(stringResource(R.string.activity_elevation))
                ElevationChart(activity.track, Modifier.fillMaxWidth().height(130.dp).padding(horizontal = 20.dp))
            }
            if (activity.splits.isNotEmpty()) item {
                SectionTitle(stringResource(R.string.activity_splits))
                SplitsTable(activity.splits)
            }
            if (activity.photos.isNotEmpty()) {
                item { SectionTitle(stringResource(R.string.activity_photos)) }
                items(activity.photos, key = ActivityPhoto::id) { photo -> ActivityPhotoCard(photo, photoBytes) }
            }
            activity.reflection?.let { reflection -> item {
                SectionTitle(stringResource(R.string.activity_reflection))
                Card(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) { Column(Modifier.padding(16.dp)) {
                    Text(reflection.title, fontWeight = FontWeight.SemiBold); Text(reflection.body, color = MaterialTheme.colorScheme.onSurfaceVariant)
                } }
            } }
            item {
                SectionTitle(stringResource(R.string.activity_export))
                Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                    ActivityExportFormat.entries.forEach { format -> OutlinedButton(onClick = {
                        onExport(format)?.let(context::shareExport)
                    }, enabled = activity.track.isNotEmpty(), modifier = Modifier.weight(1f)) {
                        Icon(Icons.Outlined.FileDownload, null); Spacer(Modifier.width(6.dp)); Text(format.name)
                    } }
                }
                TextButton(onClick = { delete = true }, enabled = !mutating, modifier = Modifier.fillMaxWidth().padding(20.dp)) {
                    Icon(Icons.Outlined.Delete, null, tint = MaterialTheme.colorScheme.error); Spacer(Modifier.width(6.dp)); Text(stringResource(R.string.activity_delete), color = MaterialTheme.colorScheme.error)
                }
            }
        }
    }
    if (edit) EditTitleDialog(activity.title, { edit = false }, { onEdit(it); edit = false })
    if (delete) AlertDialog(onDismissRequest = { delete = false }, title = { Text(stringResource(R.string.activity_delete_title)) },
        text = { Text(stringResource(R.string.activity_delete_body)) },
        confirmButton = { TextButton(onClick = { delete = false; onDelete() }) { Text(stringResource(R.string.activity_delete)) } },
        dismissButton = { TextButton(onClick = { delete = false }) { Text(stringResource(R.string.activity_cancel)) } })
    sharePreview?.let { export -> SharePreviewDialog(export, { sharePreview = null }, { context.saveImage(export) }, { context.shareExport(export) }) }
}

@Composable private fun SharePreviewDialog(export: ActivityExport, close:()->Unit, save:()->Unit, share:()->Unit) {
    val context=LocalContext.current
    val bitmap=remember(export.uri){context.contentResolver.openInputStream(export.uri)?.use(BitmapFactory::decodeStream)}
    AlertDialog(onDismissRequest=close,title={Text(stringResource(R.string.activity_share_preview))},text={bitmap?.let{Image(it.asImageBitmap(),stringResource(R.string.activity_share_preview_description),Modifier.fillMaxWidth().aspectRatio(9f/16f))}},confirmButton={Button({share();close()}){Text(stringResource(R.string.activity_share))}},dismissButton={Row{TextButton(save){Text(stringResource(R.string.activity_save_image))};TextButton(close){Text(stringResource(R.string.activity_cancel))}}})
}

private fun Context.saveImage(export:ActivityExport){
    val values=ContentValues().apply{put(MediaStore.Images.Media.DISPLAY_NAME,export.fileName);put(MediaStore.Images.Media.MIME_TYPE,"image/png");put(MediaStore.Images.Media.RELATIVE_PATH,"Pictures/Plainstride")}
    contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI,values)?.let{destination->contentResolver.openInputStream(export.uri)?.use{input->contentResolver.openOutputStream(destination)?.use(input::copyTo)}}
}

@Composable private fun RouteChart(points: List<ActivityTrackPoint>, modifier: Modifier) {
    PlainstrideRouteMap(points.map { MapCoordinate(it.latitude, it.longitude) }, modifier)
}

@Composable private fun ElevationChart(points: List<ActivityTrackPoint>, modifier: Modifier) {
    val color = MaterialTheme.colorScheme.tertiary
    val altitude = points.mapNotNull { it.altitude }
    val description = stringResource(R.string.activity_elevation_description)
    Canvas(modifier.semantics { contentDescription = description }) {
        if (altitude.size < 2) return@Canvas
        val min = altitude.min(); val range = (altitude.max() - min).coerceAtLeast(1.0)
        val offsets = altitude.mapIndexed { index, value -> Offset(index.toFloat() / (altitude.size - 1) * size.width, size.height - ((value - min) / range * size.height).toFloat()) }
        offsets.zipWithNext().forEach { (a, b) -> drawLine(color, a, b, 6f) }
    }
}

@Composable private fun SplitsTable(splits: List<ActivitySplit>) = Column(Modifier.padding(horizontal = 20.dp)) {
    splits.forEachIndexed { position, split ->
        Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(stringResource(R.string.activity_split_number, split.index + 1), fontWeight = FontWeight.Medium)
            Text(formatPace(split.paceSecsPerKm)); Text(formatDuration(split.durationSecs))
        }
        if (position != splits.lastIndex) HorizontalDivider()
    }
}

@Composable private fun ActivityPhotoCard(photo: ActivityPhoto, bytes: (String) -> ByteArray?) {
    val bitmap = remember(photo.localRelativePath) {
        photo.localRelativePath?.let(bytes)?.let { data -> BitmapFactory.decodeByteArray(data, 0, data.size) }
    }
    if (bitmap != null) Image(bitmap.asImageBitmap(), stringResource(R.string.activity_photo), Modifier.fillMaxWidth().padding(horizontal = 20.dp).aspectRatio(16f / 9f))
    else Card(Modifier.fillMaxWidth().padding(horizontal = 20.dp)) { Text(stringResource(R.string.activity_photo_pending), Modifier.padding(20.dp), color = MaterialTheme.colorScheme.onSurfaceVariant) }
}

@Composable private fun ActivityTypeBadge(type: ActivityType) = Surface(shape = CircleShape, color = MaterialTheme.colorScheme.secondaryContainer) {
    Text(activityTypeName(type), Modifier.padding(horizontal = 10.dp, vertical = 6.dp), style = MaterialTheme.typography.labelMedium)
}

@Composable private fun SummaryMetric(value: String, label: String) = Column(horizontalAlignment = Alignment.CenterHorizontally) {
    Text(value, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
    Text(label, style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable private fun SectionTitle(value: String) = Text(value, Modifier.padding(horizontal = 20.dp).semantics { heading() }, style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)

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
private fun formatDistance(meters: Double) = "%.2f km".format(meters / 1_000)
private fun formatDuration(seconds: Int) = if (seconds >= 3_600) "%d:%02d:%02d".format(seconds / 3_600, seconds / 60 % 60, seconds % 60) else "%d:%02d".format(seconds / 60, seconds % 60)
private fun formatPace(seconds: Double?) = seconds?.takeIf { it.isFinite() }?.let { "%d:%02d /km".format(it.toInt() / 60, it.toInt() % 60) } ?: "—"
private fun activityDate(value: String) = runCatching {
    DateTimeFormatter.ofLocalizedDateTime(FormatStyle.MEDIUM, FormatStyle.SHORT).format(Instant.parse(value).atZone(ZoneId.systemDefault()))
}.getOrDefault(value)

private fun Context.shareExport(export: ActivityExport) {
    startActivity(Intent.createChooser(Intent(Intent.ACTION_SEND).setType(export.mimeType).putExtra(Intent.EXTRA_STREAM, export.uri).putExtra(Intent.EXTRA_TITLE, export.fileName).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION), getString(R.string.activity_export)))
}
