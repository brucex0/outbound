package com.plainstride.outbound.feature.activity

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.media.ExifInterface
import android.net.Uri
import android.util.Log
import android.widget.Toast
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectDragGesturesAfterLongPress
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.listSaver
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.core.content.FileProvider
import com.plainstride.outbound.core.model.activity.*
import java.io.File
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.text.DecimalFormatSymbols
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*

internal data class EditorShoe(val id: String, val name: String)
@Serializable
internal data class EditorPhoto(val photo: ActivityPhoto, val importPath: String? = null)
internal data class ActivityEditorDraft(
    val original: SavedActivity, val title: String, val startedAt: String, val distanceM: Double,
    val durationSecs: Int, val gearJson: String?, val photos: List<EditorPhoto>,
)

internal fun editorPace(type: ActivityType, seconds: Int, meters: Double): Double? {
    if (!meters.isFinite() || meters <= 0 || seconds <= 0) return null
    val pace = seconds / (meters / 1000)
    val bounds = when (type) {
        ActivityType.running -> 150.0..1500.0
        ActivityType.cycling -> 35.0..3600.0
        ActivityType.walking -> 240.0..3600.0
        ActivityType.hiking -> 200.0..3600.0
        ActivityType.swimming -> 150.0..3600.0
    }
    return pace.takeIf { it in bounds }
}

/** iOS EditActivityView's card order, draft semantics, and pinned save action. */
@OptIn(ExperimentalMaterial3Api::class, androidx.compose.foundation.ExperimentalFoundationApi::class)
@Composable
internal fun ActivityEditor(inputActivity: SavedActivity, inputUnits: MeasurementUnitSystem, viewModel: ActivityViewModel, dismiss: () -> Unit) {
    val activity = remember(inputActivity.id) { inputActivity }
    val units = remember(inputActivity.id) { inputUnits }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val initialDistance = remember(activity.id, units) { String.format(java.util.Locale.getDefault(), "%.2f", SessionFormatting.distance(activity.distanceM, units).value) }
    var title by rememberSaveable(activity.id) { mutableStateOf(activity.title) }
    var start by rememberSaveable(activity.id) { mutableStateOf(activity.startedAt) }
    var distance by rememberSaveable(activity.id) { mutableStateOf(initialDistance) }
    var hours by rememberSaveable(activity.id) { mutableStateOf((activity.durationSecs / 3600).toString()) }
    var minutes by rememberSaveable(activity.id) { mutableStateOf((activity.durationSecs / 60 % 60).toString()) }
    var seconds by rememberSaveable(activity.id) { mutableStateOf((activity.durationSecs % 60).toString()) }
    val originalShoe = remember(activity.gearJson) { editorGearValue(activity.gearJson, "shoeID") }
    var shoeId by rememberSaveable(activity.id) { mutableStateOf(originalShoe) }
    var shoes by remember { mutableStateOf<List<EditorShoe>>(emptyList()) }
    var photos by rememberSaveable(activity.id, stateSaver = listSaver(
        save = { list -> list.map { Json.encodeToString(it) } },
        restore = { list -> list.map { Json.decodeFromString<EditorPhoto>(it) } },
    )) { mutableStateOf(activity.photos.map { EditorPhoto(it) }) }
    var selection by rememberSaveable { mutableStateOf(emptySet<String>()) }
    var preview by rememberSaveable { mutableStateOf<Int?>(null) }
    var saving by remember { mutableStateOf(false) }
    var importing by remember { mutableStateOf(false) }
    var confirmDiscard by rememberSaveable { mutableStateOf(false) }
    var shoeMenu by remember { mutableStateOf(false) }
    val temporaryFiles = rememberSaveable(saver = listSaver<MutableList<File>, String>(
        save = { it.map(File::getPath) }, restore = { it.map(::File).toMutableList() },
    )) { mutableListOf<File>() }
    var cameraPath by rememberSaveable { mutableStateOf<String?>(null) }
    val busy = saving || importing
    val titleLabel = stringResource(R.string.activity_title)
    val distanceLabel = stringResource(R.string.activity_distance)
    val h = hours.toIntOrNull(); val m = minutes.toIntOrNull(); val s = seconds.toIntOrNull()
    val duration = (h ?: 0) * 3600 + (m ?: 0) * 60 + (s ?: 0)
    val separator = DecimalFormatSymbols.getInstance().decimalSeparator
    val normalizedDistance = distance.replace(separator, '.')
    val meters = if (distance == initialDistance) activity.distanceM else normalizedDistance.takeIf { it.matches(Regex("[0-9]+(?:\\.[0-9]*)?|\\.[0-9]+")) }
        ?.toDoubleOrNull()?.let { SessionFormatting.distanceMeters(it, units) } ?: Double.NaN
    val valid = meters.isFinite() && meters >= 0 && h != null && h in 0..999 && m != null && m in 0..59 && s != null && s in 0..59 && duration > 0
    val changed = (title.trim().isNotEmpty() && title.trim() != activity.title) || start != activity.startedAt || distance != initialDistance || duration != activity.durationSecs || shoeId != originalShoe || photos.map { it.photo.id } != activity.photos.map { it.id }
    val cancel = { if (!busy) { if (changed) confirmDiscard = true else dismiss() } }
    fun failed(operation: String, error: Exception? = null, message: Int = R.string.editor_photo_failed) {
        Log.w("PlainstrideActivity", "$operation failed type=${error?.javaClass?.simpleName ?: "unavailable"}")
        Toast.makeText(context, message, Toast.LENGTH_SHORT).show()
    }
    fun importUris(uris: List<Uri>, captured: Boolean = false) {
        if (uris.isEmpty()) return
        importing = true
        scope.launch {
            try {
                for (uri in uris) {
                    try {
                        val photo = withContext(Dispatchers.IO) {
                            val directory = File(context.cacheDir, "activity_exports").apply { mkdirs() }
                            val file = File.createTempFile("edit-photo-", ".jpg", directory)
                            temporaryFiles += file
                            context.contentResolver.openInputStream(uri)?.use { input -> file.outputStream().use { input.copyTo(it) } } ?: error("Image unavailable")
                            check(file.length() > 0)
                            // Read placement before normalizing to the same bounded JPEG model as iOS.
                            val options = android.graphics.BitmapFactory.Options().apply { inJustDecodeBounds = true }
                            android.graphics.BitmapFactory.decodeFile(file.path, options)
                            check(options.outWidth > 0 && options.outHeight > 0)
                            val metadata = editorPhotoMetadata(file, activity, captured)
                            normalizeEditorPhoto(file)
                            EditorPhoto(metadata, file.path)
                        }
                        photos = photos + photo
                        viewModel.trackEditorPhoto("photo_captured", photo.photo.latitude != null)
                    } catch (error: kotlinx.coroutines.CancellationException) { throw error }
                    catch (error: Exception) { failed("edit_photo_import", error) }
                }
            } finally { importing = false }
        }
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.PickMultipleVisualMedia()) { importUris(it) }
    val camera = rememberLauncherForActivityResult(ActivityResultContracts.TakePicture()) { success ->
        val file = cameraPath?.let(::File)
        if (success && file != null) importUris(listOf(Uri.fromFile(file)), captured = true)
        cameraPath = null
    }
    fun launchCamera() {
        viewModel.trackEditorPhoto("photo_capture_attempted")
        try {
            val file = File.createTempFile("edit-camera-", ".jpg", File(context.cacheDir, "activity_exports").apply { mkdirs() })
            temporaryFiles += file; cameraPath = file.path
            camera.launch(FileProvider.getUriForFile(context, "${context.packageName}.activityphotos", file))
        } catch (error: Exception) { failed("edit_photo_camera", error) }
    }
    val cameraPermission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) launchCamera() else failed("edit_photo_camera_permission")
    }
    LaunchedEffect(activity.id) {
        viewModel.trackEditor()
        try { shoes = viewModel.editorShoes(activity.accountId) }
        catch (error: kotlinx.coroutines.CancellationException) { throw error }
        catch (error: Exception) { failed("edit_shoes_load", error, R.string.activity_failed) }
    }
    DisposableEffect(Unit) { onDispose {
        val host = generateSequence(context as android.content.Context?) { (it as? android.content.ContextWrapper)?.baseContext }.filterIsInstance<android.app.Activity>().firstOrNull()
        if (host?.isChangingConfigurations != true) temporaryFiles.forEach { if (it.exists() && !it.delete()) Log.w("PlainstrideActivity", "edit_photo_temporary_cleanup failed") }
    } }
    fun move(from: Int, to: Int): Boolean {
        if (from !in photos.indices || to !in photos.indices || from == to || busy) return false
        photos = photos.toMutableList().apply { add(to, removeAt(from)) }
        viewModel.trackEditorPhoto("photo_reordered")
        return true
    }
    Dialog(onDismissRequest = cancel, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false, dismissOnBackPress = !busy, dismissOnClickOutside = false)) {
        BackHandler { cancel() }
        Scaffold(
            containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
            topBar = { CenterAlignedTopAppBar(title = { Text(stringResource(R.string.editor_title), style = MaterialTheme.typography.titleMedium) }, navigationIcon = { TextButton(onClick = cancel, enabled = !busy) { Text(stringResource(R.string.activity_cancel)) } }) },
            bottomBar = {
                Surface(tonalElevation = 3.dp) {
                    Button(onClick = {
                        saving = true
                        scope.launch {
                            try {
                                val gear = if (shoeId == originalShoe) activity.gearJson else shoeId?.let { id ->
                                    buildJsonObject { put("shoeID", id); put("shoeName", shoes.firstOrNull { it.id == id }?.name.orEmpty()) }.toString()
                                }
                                if (viewModel.saveEditor(ActivityEditorDraft(activity, title, start, meters, duration, gear, photos))) dismiss()
                                else Toast.makeText(context, R.string.activity_failed, Toast.LENGTH_SHORT).show()
                            } finally { saving = false }
                        }
                    }, enabled = !busy && changed && valid, shape = RoundedCornerShape(12.dp), modifier = Modifier.navigationBarsPadding().imePadding().padding(16.dp).fillMaxWidth().height(50.dp)) {
                        Text(stringResource(if (saving) R.string.editor_saving else R.string.editor_save))
                    }
                }
            },
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                EditorCard(stringResource(R.string.editor_activity)) {
                    EditorRow(stringResource(R.string.activity_title)) {
                        BasicTextField(title, { title = it }, enabled = !busy, singleLine = true,
                            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.End), modifier = Modifier.weight(1f).semantics { contentDescription = titleLabel })
                    }
                    EditorRow(stringResource(R.string.editor_date)) {
                        val date = Instant.parse(start).atZone(ZoneId.systemDefault())
                        TextButton(enabled = !busy, onClick = {
                            DatePickerDialog(context, { _, year, month, day ->
                                start = date.withDayOfMonth(1).withYear(year).withMonth(month + 1).withDayOfMonth(day).toInstant().toString()
                            }, date.year, date.monthValue - 1, date.dayOfMonth).show()
                        }) { Text(date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM))) }
                        TextButton(enabled = !busy, onClick = {
                            TimePickerDialog(context, { _, hour, minute -> start = date.withHour(hour).withMinute(minute).toInstant().toString() }, date.hour, date.minute, android.text.format.DateFormat.is24HourFormat(context)).show()
                        }) { Text(date.format(DateTimeFormatter.ofLocalizedTime(FormatStyle.SHORT))) }
                    }
                }
                EditorCard(null) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(stringResource(R.string.editor_photos), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
                        if (selection.isNotEmpty()) {
                            IconButton(enabled = !busy, onClick = { photos = photos.filterNot { it.photo.id in selection }; selection = emptySet(); viewModel.trackEditorPhoto("photo_removed") }) { Icon(Icons.Outlined.Delete, stringResource(R.string.editor_delete_photos), tint = MaterialTheme.colorScheme.error) }
                            IconButton(enabled = !busy, onClick = { selection = emptySet() }) { Icon(Icons.Outlined.Close, stringResource(R.string.activity_cancel)) }
                        } else {
                            IconButton(enabled = !busy, onClick = {
                                if (context.checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED) launchCamera()
                                else cameraPermission.launch(android.Manifest.permission.CAMERA)
                            }) { Icon(Icons.Outlined.CameraAlt, stringResource(R.string.editor_take_photo), tint = MaterialTheme.colorScheme.primary) }
                            IconButton(enabled = !busy, onClick = { viewModel.trackEditorPhoto("photo_capture_attempted"); picker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)) }) { Icon(Icons.Outlined.PhotoLibrary, stringResource(R.string.editor_import_photo), tint = MaterialTheme.colorScheme.primary) }
                        }
                    }
                    if (photos.isEmpty()) Text(stringResource(R.string.editor_no_photos), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    else LazyRow(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                        itemsIndexed(photos, key = { _, photo -> photo.photo.id }) { index, photo ->
                            val bytes by produceState<ByteArray?>(null, photo) { value = withContext(Dispatchers.IO) { photo.importPath?.let(::editorReadPhoto) ?: photo.photo.localRelativePath?.let(viewModel::photoBytes) } }
                            val bitmap = remember(bytes) { bytes?.let { decodeActivityPhoto(it, 232) } }
                            val caption = when (photo.photo.captureContext) {
                                "preActivity" -> stringResource(R.string.activity_photo_start)
                                "paused" -> stringResource(R.string.activity_photo_finish)
                                else -> String.format(java.util.Locale.getDefault(), "%.1f %s", SessionFormatting.distance(photo.photo.distanceAtShotM ?: 0.0, units).value, if (units == MeasurementUnitSystem.metric) "km" else "mi")
                            }
                            val previous = stringResource(R.string.editor_move_previous); val next = stringResource(R.string.editor_move_next)
                            Box(Modifier.size(104.dp).clip(RoundedCornerShape(12.dp))
                                .border(if (photo.photo.id in selection) 3.dp else 0.dp, MaterialTheme.colorScheme.primary, RoundedCornerShape(12.dp))
                                .semantics { selected = photo.photo.id in selection; customActions = listOf(CustomAccessibilityAction(previous) { move(index, index - 1) }, CustomAccessibilityAction(next) { move(index, index + 1) }) }
                                .combinedClickable(enabled = !busy, onClick = {
                                    if (selection.isEmpty()) { preview = index; viewModel.trackEditorPhoto("photo_previewed") }
                                    else selection = if (photo.photo.id in selection) selection - photo.photo.id else selection + photo.photo.id
                                }, onLongClick = { selection = selection + photo.photo.id })
                                .pointerInput(photo.photo.id, busy) {
                                    var offset = 0f
                                    detectDragGesturesAfterLongPress(onDragStart = { if (!busy) { selection = selection + photo.photo.id; offset = 0f } }, onDrag = { change, amount ->
                                        if (!busy) { change.consume(); offset += amount.x
                                            val step = 116.dp.toPx()
                                            if (kotlin.math.abs(offset) >= step) { val from = photos.indexOfFirst { it.photo.id == photo.photo.id }; if (move(from, from + if (offset > 0) 1 else -1)) offset = 0f }
                                        }
                                    })
                                }) {
                                if (bitmap != null) Image(bitmap.asImageBitmap(), caption, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
                                else Icon(Icons.Outlined.CameraAlt, stringResource(R.string.activity_photo_pending), Modifier.align(Alignment.Center))
                                Text(caption, Modifier.align(Alignment.BottomStart).padding(6.dp).background(MaterialTheme.colorScheme.surface.copy(alpha = .85f), RoundedCornerShape(8.dp)).padding(horizontal = 6.dp, vertical = 2.dp), style = MaterialTheme.typography.labelSmall)
                                if (photo.photo.id in selection) Icon(Icons.Outlined.CheckCircle, stringResource(R.string.editor_selected), Modifier.align(Alignment.TopEnd).padding(5.dp), tint = MaterialTheme.colorScheme.primary)
                            }
                        }
                    }
                    if (importing) LinearProgressIndicator(Modifier.fillMaxWidth())
                }
                EditorCard(stringResource(R.string.editor_details)) {
                    EditorRow(stringResource(R.string.activity_distance)) {
                        BasicTextField(distance, { distance = it }, enabled = !busy, singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
                            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface, textAlign = TextAlign.End), modifier = Modifier.weight(1f).semantics { contentDescription = distanceLabel })
                        Text(if (units == MeasurementUnitSystem.metric) "km" else "mi", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    Text(stringResource(R.string.editor_duration))
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        EditorDuration(hours, { hours = it }, R.string.editor_hours, !busy, Modifier.weight(1f))
                        EditorDuration(minutes, { minutes = it }, R.string.editor_minutes, !busy, Modifier.weight(1f))
                        EditorDuration(seconds, { seconds = it }, R.string.editor_seconds, !busy, Modifier.weight(1f))
                    }
                    EditorRow(stringResource(R.string.activity_avg_pace)) {
                        val pace = if (valid) editorPace(activity.type, duration, meters)?.let { SessionFormatting.pace(it, units) } else null
                        Text(pace?.let { "%d:%02d /%s".format(it.minutes, it.seconds, if (units == MeasurementUnitSystem.metric) "km" else "mi") } ?: "—", color = MaterialTheme.colorScheme.onSurfaceVariant)
                    }
                    if (!valid) Text(stringResource(R.string.editor_invalid), color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                }
                EditorCard(stringResource(R.string.editor_gear)) {
                    EditorRow(stringResource(R.string.editor_shoes)) {
                        Box {
                            TextButton(enabled = !busy, onClick = { shoeMenu = true }) { Text(shoes.firstOrNull { it.id == shoeId }?.name ?: if (shoeId == originalShoe && shoeId != null) editorGearValue(activity.gearJson, "shoeName").orEmpty() else stringResource(R.string.editor_none)) }
                            DropdownMenu(shoeMenu, { shoeMenu = false }) {
                                DropdownMenuItem(text = { Text(stringResource(R.string.editor_none)) }, onClick = { shoeId = null; shoeMenu = false })
                                shoes.forEach { shoe -> DropdownMenuItem(text = { Text(shoe.name) }, onClick = { shoeId = shoe.id; shoeMenu = false }) }
                            }
                        }
                    }
                }
            }
        }
    }
    if (confirmDiscard) AlertDialog(onDismissRequest = { confirmDiscard = false }, title = { Text(stringResource(R.string.editor_discard_title)) },
        confirmButton = { TextButton(onClick = dismiss) { Text(stringResource(R.string.editor_discard), color = MaterialTheme.colorScheme.error) } },
        dismissButton = { TextButton(onClick = { confirmDiscard = false }) { Text(stringResource(R.string.activity_cancel)) } })
    preview?.let { index -> ActivityPhotoLightbox(photos.map { it.photo.copy(localRelativePath = it.importPath ?: it.photo.localRelativePath) }, index,
        photoBytes = { path -> if (path.startsWith("/")) editorReadPhoto(path) else viewModel.photoBytes(path) }, onSelected = { preview = it }, onClose = { preview = null }) }
}

@Composable private fun EditorCard(title: String?, content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(20.dp), color = MaterialTheme.colorScheme.surface) {
        Column(Modifier.fillMaxWidth().padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (title != null) Text(title, style = MaterialTheme.typography.titleMedium)
            content()
        }
    }
}
@Composable private fun EditorRow(title: String, content: @Composable RowScope.() -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 40.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(title); Spacer(Modifier.weight(1f)); content()
    }
}
@Composable private fun EditorDuration(value: String, change: (String) -> Unit, label: Int, enabled: Boolean, modifier: Modifier) {
    val labelText = stringResource(label)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(stringResource(label), style = MaterialTheme.typography.labelSmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        BasicTextField(value, change, enabled = enabled, singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            textStyle = MaterialTheme.typography.bodyLarge.copy(color = MaterialTheme.colorScheme.onSurface),
            modifier = Modifier.fillMaxWidth().semantics { contentDescription = labelText }
                .border(1.dp, MaterialTheme.colorScheme.outlineVariant, RoundedCornerShape(6.dp))
                .padding(horizontal = 10.dp, vertical = 8.dp))
    }
}

private fun editorPhotoMetadata(file: File, activity: SavedActivity, captured: Boolean): ActivityPhoto {
    val exif = editorExif(file)
    val now = Instant.now()
    val taken = if (captured) now else {
        val raw = exif?.getAttribute(ExifInterface.TAG_DATETIME_ORIGINAL) ?: exif?.getAttribute(ExifInterface.TAG_DATETIME)
        try {
            val local = raw?.let { LocalDateTime.parse(it, DateTimeFormatter.ofPattern("yyyy:MM:dd HH:mm:ss")) }
            val offset = exif?.getAttribute(ExifInterface.TAG_OFFSET_TIME_ORIGINAL)?.let(ZoneOffset::of)
            local?.atZone(offset ?: ZoneId.systemDefault())?.toInstant() ?: now
        } catch (error: Exception) { Log.w("PlainstrideActivity", "edit_photo_metadata date_unavailable type=${error.javaClass.simpleName}"); now }
    }
    val start = Instant.parse(activity.startedAt); val end = Instant.parse(activity.endedAt)
    val route = activity.track
    var cumulative = 0.0
    val samples = route.mapIndexed { index, point ->
        if (index > 0) cumulative += editorDistance(route[index - 1].latitude, route[index - 1].longitude, point.latitude, point.longitude)
        Triple(Instant.parse(point.timestamp), point, cumulative)
    }
    val gps = FloatArray(2)
    val coordinate = if (captured) route.lastOrNull()?.let { it.latitude to it.longitude }
        else if (exif?.getLatLong(gps) == true && gps[0].isFinite() && gps[1].isFinite() && gps[0] in -90f..90f && gps[1] in -180f..180f && samples.any { editorDistance(gps[0].toDouble(), gps[1].toDouble(), it.second.latitude, it.second.longitude) <= 500 }) gps[0].toDouble() to gps[1].toDouble() else null
    val distance = if (captured) activity.distanceM else when {
        samples.isEmpty() -> 0.0
        taken <= samples.first().first -> samples.first().third
        taken >= samples.last().first -> samples.last().third
        else -> samples.zipWithNext().firstOrNull { (a, b) -> taken >= a.first && taken <= b.first }?.let { (a, b) ->
            val span = java.time.Duration.between(a.first, b.first).toMillis()
            val fraction = if (span > 0) java.time.Duration.between(a.first, taken).toMillis().toDouble() / span else 1.0
            a.third + (b.third - a.third) * fraction
        } ?: 0.0
    }
    return ActivityPhoto(UUID.randomUUID().toString(), taken.toString(), activity.averagePaceSecsPerKm, activity.averageHeartRateBpm, distance,
        coordinate?.first, coordinate?.second, if (captured || taken >= end) "paused" else if (taken < start) "preActivity" else "active")
}
private fun editorDistance(a: Double, b: Double, c: Double, d: Double): Double {
    val result = FloatArray(1); android.location.Location.distanceBetween(a, b, c, d, result); return result[0].toDouble()
}

/** New imports use iOS's 2048px cap and the server's JPEG/5MB contract. Existing files are untouched. */
private fun normalizeEditorPhoto(file: File) {
    val originalExif = editorExif(file)
    val tags = listOf(
        ExifInterface.TAG_DATETIME_ORIGINAL, ExifInterface.TAG_DATETIME_DIGITIZED, ExifInterface.TAG_DATETIME,
        ExifInterface.TAG_OFFSET_TIME_ORIGINAL, ExifInterface.TAG_OFFSET_TIME_DIGITIZED, ExifInterface.TAG_OFFSET_TIME,
        ExifInterface.TAG_GPS_LATITUDE, ExifInterface.TAG_GPS_LATITUDE_REF,
        ExifInterface.TAG_GPS_LONGITUDE, ExifInterface.TAG_GPS_LONGITUDE_REF,
        ExifInterface.TAG_GPS_ALTITUDE, ExifInterface.TAG_GPS_ALTITUDE_REF,
        ExifInterface.TAG_GPS_DATESTAMP, ExifInterface.TAG_GPS_TIMESTAMP,
    ).associateWith { originalExif?.getAttribute(it) }
    val bitmap = decodeActivityPhoto(file.readBytes(), 2048) ?: error("Image decoding failed")
    try { file.outputStream().use { check(bitmap.compress(android.graphics.Bitmap.CompressFormat.JPEG, 90, it)) } }
    finally { bitmap.recycle() }
    ExifInterface(file).apply {
        tags.forEach { (tag, value) -> if (value != null) setAttribute(tag, value) }
        setAttribute(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL.toString())
        saveAttributes()
    }
    check(file.length() <= 5 * 1024 * 1024) { "Image exceeds upload limit" }
}

private fun editorGearValue(json: String?, key: String): String? {
    if (json == null) return null
    return try { Json.parseToJsonElement(json).jsonObject[key]?.jsonPrimitive?.contentOrNull }
    catch (error: Exception) { Log.w("PlainstrideActivity", "edit_gear_decode failed type=${error.javaClass.simpleName}"); null }
}
private fun editorReadPhoto(path: String): ByteArray? = try { File(path).readBytes() }
catch (error: java.io.IOException) { Log.w("PlainstrideActivity", "edit_photo_read unavailable type=${error.javaClass.simpleName}"); null }

private fun editorExif(file: File): ExifInterface? = try { ExifInterface(file) }
catch (error: java.io.IOException) {
    // Metadata is optional for valid library images; decoding still validates pixels.
    Log.w("PlainstrideActivity", "edit_photo_exif unavailable type=${error.javaClass.simpleName}")
    null
}
