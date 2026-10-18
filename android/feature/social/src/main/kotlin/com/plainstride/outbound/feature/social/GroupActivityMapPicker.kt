package com.plainstride.outbound.feature.social

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Geocoder
import android.location.LocationManager
import android.util.Log
import android.os.SystemClock
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LocationOn
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.maps.android.compose.*
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.util.Locale

@Composable
internal fun GroupActivityMapPicker(initial: LatLng?, initialQuery: String, close: () -> Unit, select: (LatLng, String?, String) -> Unit) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current
    // A regional viewport is only a starting place; it is never selected until the user interacts.
    val fallback = remember {
        when (Locale.getDefault().country) {
            "CN" -> LatLng(39.9042, 116.4074)
            "ES" -> LatLng(40.4168, -3.7038)
            "CA" -> LatLng(43.6532, -79.3832)
            else -> LatLng(37.7749, -122.4194)
        }
    }
    val camera = rememberCameraPositionState { position = CameraPosition.fromLatLngZoom(initial ?: fallback, if (initial != null) 15f else 10f) }
    var point by remember { mutableStateOf(initial) }
    var name by remember { mutableStateOf<String?>(initialQuery.takeIf { initial != null && it.isNotBlank() }) }
    var source by remember { mutableStateOf("map") }
    var interacted by remember { mutableStateOf(false) }
    var loaded by remember { mutableStateOf(false) }
    var query by remember { mutableStateOf(initialQuery) }
    var searching by remember { mutableStateOf(false) }
    var results by remember { mutableStateOf<List<android.location.Address>>(emptyList()) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(query) {
        results = emptyList(); failed = false; searching = false
        if (query.trim().length < 3) return@LaunchedEffect
        delay(350)
        searching = true
        try {
            results = withContext(Dispatchers.IO) {
                @Suppress("DEPRECATION")
                Geocoder(context, Locale.getDefault()).getFromLocationName(query.trim(), 5).orEmpty()
            }
            failed = results.isEmpty()
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "Activity map search failed (type=${error.javaClass.simpleName})")
            failed = true
        } finally { searching = false }
    }
    LaunchedEffect(loaded) {
        if (!loaded || initial != null) return@LaunchedEffect
        val permitted = context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED || context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED
        if (!permitted) return@LaunchedEffect
        try {
            val fix = withContext(Dispatchers.IO) {
                val manager = context.getSystemService(Context.LOCATION_SERVICE) as LocationManager
                manager.getProviders(true).mapNotNull { manager.getLastKnownLocation(it) }
                    .filter { it.hasAccuracy() && it.accuracy <= 10_000f && (SystemClock.elapsedRealtimeNanos() - it.elapsedRealtimeNanos) in 0L..1_800_000_000_000L }
                    .maxByOrNull { it.elapsedRealtimeNanos }
            }
            if (fix != null && !interacted) {
                val target = LatLng(fix.latitude, fix.longitude)
                point = target
                camera.move(CameraUpdateFactory.newLatLngZoom(target, 15f))
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstrideSocial", "Activity map initial location failed (type=${error.javaClass.simpleName})")
        }
    }
    LaunchedEffect(camera) {
        snapshotFlow { camera.isMoving to camera.cameraMoveStartedReason }.collect { (moving, reason) ->
            if (moving && (reason == CameraMoveStartedReason.GESTURE || reason == CameraMoveStartedReason.API_ANIMATION)) {
                interacted = true; name = null; source = "map"; results = emptyList(); focus.clearFocus()
            }
            if (!moving && interacted) point = camera.position.target
        }
    }
    Dialog(onDismissRequest = close, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.imePadding()) {
                OutlinedTextField(query, { query = it.take(120) }, Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 8.dp), label = { Text(stringResource(R.string.group_plan_map_search)) }, singleLine = true)
                if (searching) LinearProgressIndicator(Modifier.fillMaxWidth())
                if (failed) Text(stringResource(R.string.group_plan_search_failed), Modifier.padding(horizontal = 16.dp), style = MaterialTheme.typography.bodySmall)
                LazyColumn(Modifier.fillMaxWidth().heightIn(max = 200.dp)) { items(results) { address ->
                    val label = address.getAddressLine(0) ?: address.featureName.orEmpty()
                    TextButton({
                        val target = LatLng(address.latitude, address.longitude)
                        interacted = true; point = target; name = label; source = "autocomplete"; results = emptyList(); focus.clearFocus()
                        scope.launch { camera.move(CameraUpdateFactory.newLatLngZoom(target, 15f)) }
                    }, Modifier.fillMaxWidth()) { Text(label) }
                }
                }
                Text(stringResource(R.string.group_plan_map_help), Modifier.padding(horizontal = 16.dp, vertical = 8.dp), style = MaterialTheme.typography.bodySmall)
                Box(Modifier.weight(1f)) {
                    GoogleMap(Modifier.fillMaxSize(), cameraPositionState = camera,
                        uiSettings = MapUiSettings(zoomControlsEnabled = true, zoomGesturesEnabled = true, scrollGesturesEnabled = true),
                        onMapLoaded = { loaded = true },
                        onMapClick = { target ->
                            interacted = true; point = target; name = null; source = "map"; results = emptyList(); focus.clearFocus()
                            scope.launch { camera.move(CameraUpdateFactory.newLatLngZoom(target, maxOf(camera.position.zoom, 15f))) }
                        })
                    // Anchor the tip to the camera target so panning chooses the exact meeting point.
                    Icon(Icons.Default.LocationOn, stringResource(R.string.group_plan_map_pin), Modifier.align(Alignment.Center).offset(y = (-20).dp).size(40.dp), tint = MaterialTheme.colorScheme.primary)
                }
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    TextButton(close) { Text(stringResource(R.string.social_cancel)) }
                    TextButton({ point?.let { select(camera.position.target, name, source) } }, enabled = point != null && !camera.isMoving) { Text(stringResource(R.string.social_done)) }
                }
            }
        }
    }
}
