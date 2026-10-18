package com.plainstride.outbound.feature.social

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.location.Geocoder
import android.util.Log
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun GroupActivityComposer(
    close: () -> Unit,
    locationSelected: (String) -> Unit,
    create: (CreateEventBody, (Boolean) -> Unit) -> Unit,
) {
    var title by rememberSaveable { mutableStateOf("") }
    var activity by rememberSaveable { mutableStateOf("running") }
    var startValue by rememberSaveable { mutableStateOf(ZonedDateTime.now().plusDays(1).toString()) }
    val start = ZonedDateTime.parse(startValue)
    var duration by rememberSaveable { mutableIntStateOf(0) }
    var location by rememberSaveable { mutableStateOf("") }
    var latitude by rememberSaveable { mutableStateOf<Double?>(null) }
    var longitude by rememberSaveable { mutableStateOf<Double?>(null) }
    var note by rememberSaveable { mutableStateOf("") }
    var virtual by rememberSaveable { mutableStateOf(true) }
    var submitting by remember { mutableStateOf(false) }
    var searching by remember { mutableStateOf(false) }
    var suggestions by remember { mutableStateOf<List<android.location.Address>>(emptyList()) }
    var searchFailed by remember { mutableStateOf(false) }
    var mapOpen by rememberSaveable { mutableStateOf(false) }
    var searchRevision by remember { mutableIntStateOf(0) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun selectLocation(name: String, lat: Double, lon: Double, source: String) {
        searchRevision++
        location = name.take(120); latitude = lat; longitude = lon
        suggestions = emptyList(); searchFailed = false
        locationSelected(source)
    }
    LaunchedEffect(location, latitude) {
        if (latitude != null || location.trim().length < 3) return@LaunchedEffect
        kotlinx.coroutines.delay(350)
        val revision = searchRevision
        searching = true
        try {
            val results = withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                Geocoder(context, Locale.getDefault()).getFromLocationName(location.trim(), 5).orEmpty()
            }
            if (revision == searchRevision) { suggestions = results; searchFailed = results.isEmpty() }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "Activity meetup autocomplete failed (type=${error.javaClass.simpleName})")
            if (revision == searchRevision) searchFailed = true
        } finally { searching = false }
    }
    Dialog(onDismissRequest = { if (!submitting) close() }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Scaffold(topBar = { TopAppBar(title = { Text(stringResource(R.string.group_plan_activity)) }, navigationIcon = {
                TextButton(close, enabled = !submitting) { Text(stringResource(R.string.social_cancel)) }
            }) }) { padding ->
                Column(Modifier.padding(padding).verticalScroll(rememberScrollState()).imePadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                    OutlinedTextField(title, { title = it.take(80) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.group_activity_title)) }, placeholder = { Text(stringResource(R.string.group_plan_title_hint)) }, singleLine = true)
                    PlanChoice(stringResource(R.string.group_plan_type), activity, listOf("running", "cycling", "hiking", "walking", "swimming", "strength", "mobility").zip(listOf(R.string.group_plan_running, R.string.group_plan_cycling, R.string.group_plan_hiking, R.string.group_plan_walking, R.string.group_plan_swimming, R.string.group_plan_strength, R.string.group_plan_mobility)).map { it.first to stringResource(it.second) }) { activity = it }
                    Text(stringResource(R.string.group_plan_datetime), style = MaterialTheme.typography.titleMedium)
                    OutlinedButton({
                        DatePickerDialog(context, { _, year, month, day -> startValue = start.withDayOfMonth(1).withYear(year).withMonth(month + 1).withDayOfMonth(day).toString() }, start.year, start.monthValue - 1, start.dayOfMonth).apply { datePicker.minDate = System.currentTimeMillis(); show() }
                    }, Modifier.fillMaxWidth()) { Text(start.format(DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.MEDIUM))) }
                    OutlinedButton({ TimePickerDialog(context, { _, hour, minute -> startValue = start.withHour(hour).withMinute(minute).withSecond(0).withNano(0).toString() }, start.hour, start.minute, android.text.format.DateFormat.is24HourFormat(context)).show() }, Modifier.fillMaxWidth()) { Text(start.format(DateTimeFormatter.ofLocalizedTime(java.time.format.FormatStyle.SHORT))) }
                    PlanChoice(stringResource(R.string.group_plan_duration), duration.toString(), listOf(0,30,45,60,90,120,180,240).map { it.toString() to if (it == 0) stringResource(R.string.group_plan_duration_default) else stringResource(R.string.group_plan_minutes, it) }) { duration = it.toInt() }
                    OutlinedTextField(location, { location = it.take(120); latitude = null; longitude = null; searchRevision++; suggestions = emptyList(); searchFailed = false }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.group_activity_location)) }, placeholder = { Text(stringResource(R.string.group_plan_location_hint)) }, singleLine = true)
                    if (searching) LinearProgressIndicator(Modifier.fillMaxWidth())
                    if (searchFailed) Text(stringResource(R.string.group_plan_search_failed), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    suggestions.forEach { address ->
                        val name = address.getAddressLine(0) ?: address.featureName.orEmpty()
                        TextButton({ selectLocation(name, address.latitude, address.longitude, "autocomplete") }) { Text(name) }
                    }
                    TextButton({ mapOpen = true }) { Text(stringResource(R.string.group_plan_map)) }
                    OutlinedTextField(note, { note = it.take(240) }, Modifier.fillMaxWidth(), label = { Text(stringResource(R.string.group_plan_note)) }, placeholder = { Text(stringResource(R.string.group_plan_note_hint)) }, minLines = 2, maxLines = 4)
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                        Text(stringResource(R.string.group_plan_virtual), Modifier.weight(1f)); Switch(virtual, { virtual = it })
                    }
                    Text(stringResource(R.string.group_plan_virtual_help), style = MaterialTheme.typography.bodySmall)
                    Button(onClick = {
                        submitting = true
                        create(CreateEventBody(title = title.trim(), startsAt = start.toInstant().toString(), durationMinutes = if (duration == 0) 60 else duration, locationName = location.trim().ifEmpty { null }, latitude = latitude, longitude = longitude, note = note.trim().ifEmpty { null }, activityType = activity, participationMode = if (virtual) "hybrid" else "in_person")) { success -> submitting = false; if (success) close() else android.widget.Toast.makeText(context, context.getString(R.string.social_profile_action_failed), android.widget.Toast.LENGTH_LONG).show() }
                    }, enabled = title.isNotBlank() && start.isAfter(ZonedDateTime.now()) && !submitting && !searching, modifier = Modifier.fillMaxWidth()) {
                        if (submitting) CircularProgressIndicator(Modifier.size(20.dp), strokeWidth = 2.dp) else Text(stringResource(R.string.group_plan_create))
                    }
                }
            }
        }
    }
    if (mapOpen) {
        var point by remember { mutableStateOf(latitude?.let { LatLng(it, longitude!!) }) }
        val camera = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(point ?: LatLng(0.0, 0.0), if (point == null) 2f else 14f) }
        Dialog(onDismissRequest = { mapOpen = false }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(Modifier.fillMaxSize()) { Column {
                Text(stringResource(R.string.group_plan_map_help), Modifier.padding(16.dp))
                GoogleMap(Modifier.weight(1f), cameraPositionState = camera, onMapClick = { point = it }) { point?.let { Marker(state = MarkerState(position = it)) } }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton({ mapOpen = false }) { Text(stringResource(R.string.social_cancel)) }
                    TextButton({ point?.let { selected ->
                        val fallback = String.format(Locale.ROOT, "%.5f, %.5f", selected.latitude, selected.longitude)
                        selectLocation(fallback, selected.latitude, selected.longitude, "map")
                        val revision = searchRevision
                        mapOpen = false
                        scope.launch {
                            try {
                                val name = withContext(Dispatchers.IO) {
                                    @Suppress("DEPRECATION")
                                    Geocoder(context, Locale.getDefault()).getFromLocation(selected.latitude, selected.longitude, 1)?.firstOrNull()?.getAddressLine(0)
                                }
                                if (revision == searchRevision && name != null) location = name.take(120)
                            } catch (error: Exception) {
                                if (error is CancellationException) throw error
                                // The selected coordinates remain valid when no address is available.
                                Log.w("PlainstrideSocial", "Activity meetup reverse geocoding failed (type=${error.javaClass.simpleName})")
                            }
                        }
                    } }, enabled = point != null) { Text(stringResource(R.string.social_done)) }
                }
            } }
        }
    }
}

@Composable
private fun PlanChoice(label: String, value: String, options: List<Pair<String, String>>, select: (String) -> Unit) {
    var expanded by remember { mutableStateOf(false) }
    Column {
        Text(label, style = MaterialTheme.typography.labelLarge)
        Box {
            OutlinedButton({ expanded = true }, Modifier.fillMaxWidth()) { Text(options.first { it.first == value }.second) }
            DropdownMenu(expanded, { expanded = false }) { options.forEach { (key, name) -> DropdownMenuItem(text = { Text(name) }, onClick = { select(key); expanded = false }) } }
        }
    }
}
