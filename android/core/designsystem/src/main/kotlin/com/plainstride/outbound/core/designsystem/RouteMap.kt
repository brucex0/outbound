package com.plainstride.outbound.core.designsystem

import android.annotation.SuppressLint
import android.content.pm.PackageManager
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.maps.android.compose.*

data class MapCoordinate(val latitude: Double, val longitude: Double)
data class MapRouteSegment(val points: List<MapCoordinate>, val color: Color)
data class MapRouteMarker(
    val id: String,
    val coordinate: MapCoordinate,
    val title: String,
    val selected: Boolean = false,
)

/** Shared route renderer. Missing credentials fail closed to an accessible non-map state. */
@Composable
@SuppressLint("MissingPermission")
fun PlainstrideRouteMap(
    points: List<MapCoordinate>,
    modifier: Modifier = Modifier,
    showUserLocation: Boolean = false,
    preciseLocationGranted: Boolean = false,
    focusOnUser: Boolean = false,
    interactive: Boolean = true,
    showEndpointMarkers: Boolean = true,
    routeSegments: List<MapRouteSegment> = emptyList(),
    markers: List<MapRouteMarker> = emptyList(),
    bottomContentPadding: Dp = 0.dp,
) {
    val context = LocalContext.current
    val description = stringResource(R.string.route_map_description)
    val configured = remember(context) {
        runCatching {
            context.packageManager.getApplicationInfo(context.packageName, PackageManager.GET_META_DATA)
                .metaData?.getString("com.google.android.geo.API_KEY").orEmpty().isNotBlank()
        }.getOrDefault(false)
    }
    if (!configured) {
        Box(modifier, contentAlignment = Alignment.Center) { Text(stringResource(R.string.route_map_unavailable), color = MaterialTheme.colorScheme.onSurfaceVariant) }
        return
    }
    val camera = rememberCameraPositionState()
    var didFocusOnUser by remember { mutableStateOf(false) }
    LaunchedEffect(focusOnUser, preciseLocationGranted) {
        if (focusOnUser && preciseLocationGranted && !didFocusOnUser) {
            val client = LocationServices.getFusedLocationProviderClient(context)
            fun focus(location: android.location.Location?) {
                if (location != null && !didFocusOnUser) {
                    didFocusOnUser = true
                    camera.move(CameraUpdateFactory.newLatLngZoom(LatLng(location.latitude, location.longitude), 15f))
                }
            }
            client.lastLocation
                .addOnSuccessListener { location ->
                    if (location != null) focus(location)
                    else client.getCurrentLocation(Priority.PRIORITY_BALANCED_POWER_ACCURACY, CancellationTokenSource().token).addOnSuccessListener(::focus)
                }
        }
    }
    LaunchedEffect(points) {
        if (points.isNotEmpty()) {
            val bounds = LatLngBounds.builder().also { builder -> points.forEach { builder.include(LatLng(it.latitude, it.longitude)) } }.build()
            runCatching { camera.animate(CameraUpdateFactory.newLatLngBounds(bounds, 64)) }
        }
    }
    val selectedMarker = markers.firstOrNull(MapRouteMarker::selected)
    LaunchedEffect(selectedMarker?.id) {
        selectedMarker?.let { marker ->
            camera.animate(CameraUpdateFactory.newLatLng(LatLng(marker.coordinate.latitude, marker.coordinate.longitude)))
        }
    }
    GoogleMap(
        modifier = modifier.semantics { contentDescription = description },
        cameraPositionState = camera,
        properties = MapProperties(isMyLocationEnabled = showUserLocation && preciseLocationGranted),
        contentPadding = PaddingValues(bottom = bottomContentPadding),
        uiSettings = MapUiSettings(
            compassEnabled = interactive,
            indoorLevelPickerEnabled = interactive,
            mapToolbarEnabled = interactive,
            myLocationButtonEnabled = interactive && showUserLocation && preciseLocationGranted,
            rotationGesturesEnabled = interactive,
            scrollGesturesEnabled = interactive,
            scrollGesturesEnabledDuringRotateOrZoom = interactive,
            tiltGesturesEnabled = interactive,
            zoomControlsEnabled = false,
            zoomGesturesEnabled = interactive,
        ),
    ) {
        if (points.size > 1) {
            val latLngs = points.map { LatLng(it.latitude, it.longitude) }
            if (routeSegments.isEmpty()) {
                Polyline(points = latLngs, color = Color.Black.copy(alpha = 0.18f), width = 20f, zIndex = 1f)
                Polyline(points = latLngs, color = MaterialTheme.colorScheme.primary, width = 12f, zIndex = 2f)
            } else {
                routeSegments.filter { it.points.size > 1 }.forEach { segment ->
                    val segmentPoints = segment.points.map { LatLng(it.latitude, it.longitude) }
                    Polyline(points = segmentPoints, color = Color.Black.copy(alpha = 0.18f), width = 20f, zIndex = 1f)
                    Polyline(
                        points = segmentPoints,
                        color = segment.color,
                        width = 12f,
                        zIndex = 2f,
                    )
                }
            }
        }
        if (showEndpointMarkers) {
            points.firstOrNull()?.let { Marker(state = rememberUpdatedMarkerState(LatLng(it.latitude, it.longitude)), title = stringResource(R.string.route_start)) }
            points.lastOrNull()?.takeIf { points.size > 1 }?.let { Marker(state = rememberUpdatedMarkerState(LatLng(it.latitude, it.longitude)), title = stringResource(R.string.route_finish)) }
        }
        markers.forEach { marker ->
            key(marker.id) {
                Marker(
                    state = rememberUpdatedMarkerState(LatLng(marker.coordinate.latitude, marker.coordinate.longitude)),
                    title = marker.title,
                    icon = BitmapDescriptorFactory.defaultMarker(
                        if (marker.selected) BitmapDescriptorFactory.HUE_ORANGE else BitmapDescriptorFactory.HUE_AZURE,
                    ),
                    zIndex = if (marker.selected) 4f else 3f,
                )
            }
        }
    }
}
