package run.plainstride.core.designsystem

import android.content.pm.PackageManager
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.maps.android.compose.*

data class MapCoordinate(val latitude: Double, val longitude: Double)

/** Shared route renderer. Missing credentials fail closed to an accessible non-map state. */
@Composable
fun PlainstrideRouteMap(
    points: List<MapCoordinate>,
    modifier: Modifier = Modifier,
    showUserLocation: Boolean = false,
    preciseLocationGranted: Boolean = false,
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
    LaunchedEffect(points) {
        if (points.isNotEmpty()) {
            val bounds = LatLngBounds.builder().also { builder -> points.forEach { builder.include(LatLng(it.latitude, it.longitude)) } }.build()
            runCatching { camera.animate(CameraUpdateFactory.newLatLngBounds(bounds, 64)) }
        }
    }
    GoogleMap(
        modifier = modifier.semantics { contentDescription = description },
        cameraPositionState = camera,
        properties = MapProperties(isMyLocationEnabled = showUserLocation && preciseLocationGranted),
        uiSettings = MapUiSettings(myLocationButtonEnabled = showUserLocation && preciseLocationGranted, zoomControlsEnabled = false),
    ) {
        if (points.size > 1) Polyline(points = points.map { LatLng(it.latitude, it.longitude) }, color = MaterialTheme.colorScheme.primary, width = 12f)
        points.firstOrNull()?.let { Marker(state = rememberUpdatedMarkerState(LatLng(it.latitude, it.longitude)), title = stringResource(R.string.route_start)) }
        points.lastOrNull()?.takeIf { points.size > 1 }?.let { Marker(state = rememberUpdatedMarkerState(LatLng(it.latitude, it.longitude)), title = stringResource(R.string.route_finish)) }
    }
}
