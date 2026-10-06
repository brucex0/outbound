package com.plainstride.outbound.core.designsystem

import android.annotation.SuppressLint
import android.content.pm.PackageManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas as AndroidCanvas
import android.graphics.Paint
import android.os.SystemClock
import android.provider.Settings
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.Dp
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.google.android.gms.maps.model.BitmapDescriptor
import com.google.android.gms.maps.model.CameraPosition
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import com.google.maps.android.compose.*
import kotlinx.coroutines.delay

data class MapCoordinate(val latitude: Double, val longitude: Double)
data class MapRouteSegment(val points: List<MapCoordinate>, val color: Color)
data class MapRouteMarker(
    val id: String,
    val coordinate: MapCoordinate,
    val title: String,
    val selected: Boolean = false,
    val icon: BitmapDescriptor? = null,
    val animatePosition: Boolean = false,
    val animatedRunner: Boolean = false,
    val runnerMoving: Boolean = true,
    val rotationDegrees: Float = 0f,
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
    onMarkerClick: ((String) -> Unit)? = null,
    bottomContentPadding: Dp = 0.dp,
    fitRoutePadding: Dp = 48.dp,
    fitRouteOnChange: Boolean = true,
    followCoordinate: MapCoordinate? = null,
    followAnimationDurationMs: Int = Int.MAX_VALUE,
    followBearingDegrees: Float? = null,
    followTiltDegrees: Float = 0f,
    followZoom: Float = 16f,
    onMapLoadedCallback: (() -> Unit)? = null,
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
    var mapLoaded by remember { mutableStateOf(false) }
    val fitRoutePaddingPx = with(androidx.compose.ui.platform.LocalDensity.current) { fitRoutePadding.toPx().toInt() }
    var didFocusOnUser by remember { mutableStateOf(false) }
    var didFocusRoute by remember { mutableStateOf(false) }
    var didFocusSelectedMarker by remember { mutableStateOf(false) }
    LaunchedEffect(focusOnUser, preciseLocationGranted, mapLoaded) {
        if (!mapLoaded) return@LaunchedEffect
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
    LaunchedEffect(points, fitRouteOnChange, bottomContentPadding, fitRoutePadding, mapLoaded) {
        if (!mapLoaded) return@LaunchedEffect
        if (fitRouteOnChange && points.isNotEmpty()) {
            val isInitialRouteFocus = !didFocusRoute
            if (!isInitialRouteFocus) delay(250)
            val bounds = LatLngBounds.builder().also { builder -> points.forEach { builder.include(LatLng(it.latitude, it.longitude)) } }.build()
            val update = CameraUpdateFactory.newLatLngBounds(bounds, fitRoutePaddingPx)
            runCatching {
                if (isInitialRouteFocus) camera.move(update) else camera.animate(update)
                didFocusRoute = true
            }
        }
    }
    LaunchedEffect(followCoordinate, followBearingDegrees, followTiltDegrees, followZoom, followAnimationDurationMs, mapLoaded) {
        if (!mapLoaded) return@LaunchedEffect
        followCoordinate?.let { coordinate ->
            val current = camera.position
            val target = CameraPosition.Builder()
                .target(LatLng(coordinate.latitude, coordinate.longitude))
                .zoom(followZoom)
                .bearing(followBearingDegrees ?: current.bearing)
                .tilt(if (followBearingDegrees == null) current.tilt else followTiltDegrees)
                .build()
            camera.animate(
                CameraUpdateFactory.newCameraPosition(target),
                durationMs = followAnimationDurationMs,
            )
        }
    }
    val selectedMarker = markers.firstOrNull(MapRouteMarker::selected)
    LaunchedEffect(selectedMarker?.id, mapLoaded) {
        if (!mapLoaded) return@LaunchedEffect
        selectedMarker?.let { marker ->
            if (didFocusSelectedMarker) {
                camera.animate(CameraUpdateFactory.newLatLng(LatLng(marker.coordinate.latitude, marker.coordinate.longitude)))
            }
            didFocusSelectedMarker = true
        }
    }
    GoogleMap(
        modifier = modifier.semantics { contentDescription = description },
        cameraPositionState = camera,
        properties = MapProperties(isMyLocationEnabled = showUserLocation && preciseLocationGranted),
        onMapLoaded = { mapLoaded = true; onMapLoadedCallback?.invoke() },
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
                val markerPosition = remember(marker.id) {
                    MarkerState(LatLng(marker.coordinate.latitude, marker.coordinate.longitude))
                }
                LaunchedEffect(marker.id, marker.coordinate, marker.animatePosition) {
                    val target = LatLng(marker.coordinate.latitude, marker.coordinate.longitude)
                    if (!marker.animatePosition) {
                        markerPosition.position = target
                    } else {
                        val start = markerPosition.position
                        val startedAt = SystemClock.uptimeMillis()
                        val durationMs = 900L
                        while (true) {
                            val progress = ((SystemClock.uptimeMillis() - startedAt).toFloat() / durationMs).coerceIn(0f, 1f)
                            markerPosition.position = LatLng(
                                start.latitude + (target.latitude - start.latitude) * progress,
                                start.longitude + (target.longitude - start.longitude) * progress,
                            )
                            if (progress >= 1f) break
                            delay(16)
                        }
                    }
                }
                if (marker.animatedRunner) {
                    val motionEnabled = remember(context) { systemMotionEnabled(context) }
                    val tint = MaterialTheme.colorScheme.primary
                    val figureColor = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.84f)
                    val runnerFrames = remember(context, tint, figureColor, mapLoaded) {
                        if (mapLoaded) createRunnerFrameIcons(context, tint, figureColor) else emptyList()
                    }
                    val isMoving = motionEnabled && marker.runnerMoving
                    var phase by remember(marker.id) { mutableFloatStateOf(0f) }
                    LaunchedEffect(marker.id, isMoving) {
                        if (!isMoving) {
                            phase = 0f
                            return@LaunchedEffect
                        }
                        val startedAt = SystemClock.uptimeMillis()
                        while (true) {
                            phase = ((SystemClock.uptimeMillis() - startedAt) % RUNNER_STRIDE_CYCLE_MS).toFloat() / RUNNER_STRIDE_CYCLE_MS
                            delay(RUNNER_FRAME_INTERVAL_MS)
                        }
                    }
                    val frame = if (isMoving) (phase * RUNNER_ANIMATION_FRAMES).toInt() else 0
                    Marker(
                        state = markerPosition,
                        title = marker.title,
                        icon = runnerFrames.getOrNull(frame) ?: BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE),
                        rotation = marker.rotationDegrees,
                        anchor = Offset(0.5f, 0.5f),
                        zIndex = if (marker.selected) 4f else 3f,
                        onClick = { onMarkerClick?.invoke(marker.id); true },
                    )
                } else {
                    Marker(
                        state = markerPosition,
                        title = marker.title,
                        icon = marker.icon ?: BitmapDescriptorFactory.defaultMarker(
                            if (marker.selected) BitmapDescriptorFactory.HUE_ORANGE else BitmapDescriptorFactory.HUE_AZURE,
                        ),
                        zIndex = if (marker.selected) 4f else 3f,
                        onClick = { onMarkerClick?.invoke(marker.id); true },
                    )
                }
            }
        }
    }
}

/** Shared live-route map configuration for local recording and remote follower location sources. */
@Composable
fun PlainstrideLiveRouteMap(
    recordedRoute: List<MapCoordinate>,
    runnerLocation: MapCoordinate?,
    modifier: Modifier = Modifier,
    plannedRoute: List<MapCoordinate> = emptyList(),
    recordedRouteSegments: List<MapRouteSegment> = emptyList(),
    followRunner: Boolean = true,
    rotateWithRunner: Boolean = true,
    showRunnerMascot: Boolean = true,
    runnerMoving: Boolean = true,
    showUserLocation: Boolean = false,
    showEndpointMarkers: Boolean = false,
    interactive: Boolean = true,
    zoom: Float = 16f,
    bottomContentPadding: Dp = 0.dp,
) {
    var mapReady by remember { mutableStateOf(false) }
    val bearing = remember(recordedRoute, rotateWithRunner) {
        if (rotateWithRunner) routeBearing(recordedRoute) else null
    }
    val segments = buildList {
        if (plannedRoute.size > 1) add(MapRouteSegment(plannedRoute, Color(0xFFFF5200)))
        if (recordedRouteSegments.isNotEmpty()) addAll(recordedRouteSegments)
        else if (recordedRoute.size > 1) add(MapRouteSegment(recordedRoute, MaterialTheme.colorScheme.primary))
    }
    val mapPoints = when {
        recordedRoute.isNotEmpty() -> recordedRoute
        plannedRoute.isNotEmpty() -> plannedRoute
        else -> listOfNotNull(runnerLocation)
    }
    val runnerMarker = if (runnerLocation != null && (!showRunnerMascot || mapReady)) {
        listOf(
            MapRouteMarker(
                id = "live-runner",
                coordinate = runnerLocation,
                title = stringResource(R.string.route_map_runner),
                selected = true,
                animatePosition = true,
                animatedRunner = showRunnerMascot,
                runnerMoving = runnerMoving,
                rotationDegrees = bearing ?: 0f,
            ),
        )
    } else emptyList()
    PlainstrideRouteMap(
        points = mapPoints,
        modifier = modifier,
        showUserLocation = showUserLocation && !showRunnerMascot,
        preciseLocationGranted = showUserLocation && !showRunnerMascot,
        interactive = interactive,
        showEndpointMarkers = showEndpointMarkers,
        routeSegments = segments,
        markers = runnerMarker,
        bottomContentPadding = bottomContentPadding,
        fitRouteOnChange = false,
        followCoordinate = runnerLocation.takeIf { followRunner },
        followAnimationDurationMs = if (followRunner) 900 else Int.MAX_VALUE,
        followBearingDegrees = bearing.takeIf { followRunner },
        followTiltDegrees = if (bearing != null) 45f else 0f,
        followZoom = zoom,
        onMapLoadedCallback = { mapReady = true },
    )
}

private fun createRunnerFrameIcons(context: Context, tint: Color, figureColor: Color): List<BitmapDescriptor> {
    val density = context.resources.displayMetrics.density
    val size = (32f * density).toInt().coerceAtLeast(1)
    val bodyColor = figureColor.toArgb()
    val tintColor = tint.toArgb()
    return List(RUNNER_ANIMATION_FRAMES) { frame ->
        val bitmap = Bitmap.createBitmap(size, size, Bitmap.Config.ARGB_8888)
        val canvas = AndroidCanvas(bitmap)
        val scale = density
        val center = size / 2f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        paint.color = android.graphics.Color.WHITE
        paint.alpha = 235
        canvas.drawCircle(center, center, 11.5f * scale, paint)

        val stride = kotlin.math.sin(2.0 * Math.PI * frame / RUNNER_ANIMATION_FRAMES).toFloat() * 38f
        fun point(x: Float, y: Float) = Offset(x * scale, y * scale)
        fun limb(start: Offset, angleDegrees: Float, lengthDp: Float, widthDp: Float, color: Int) {
            val angle = Math.toRadians(angleDegrees.toDouble())
            val endX = start.x + kotlin.math.sin(angle).toFloat() * lengthDp * scale
            val endY = start.y + kotlin.math.cos(angle).toFloat() * lengthDp * scale
            paint.color = color
            paint.alpha = android.graphics.Color.alpha(color)
            paint.style = Paint.Style.STROKE
            paint.strokeCap = Paint.Cap.ROUND
            paint.strokeWidth = widthDp * scale
            canvas.drawLine(start.x, start.y, endX, endY, paint)
        }

        limb(point(13f, 19f), -stride, 9f, 3f, bodyColor)
        limb(point(19f, 19f), stride, 9f, 3f, bodyColor)
        limb(point(12f, 13f), stride * 0.9f, 8f, 2.5f, bodyColor)
        limb(point(20f, 13f), -stride * 0.9f, 8f, 2.5f, bodyColor)

        paint.color = tintColor
        paint.alpha = android.graphics.Color.alpha(tintColor)
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = 8f * scale
        canvas.drawLine(16f * scale, 10f * scale, 16f * scale, 21f * scale, paint)

        paint.color = bodyColor
        paint.alpha = android.graphics.Color.alpha(bodyColor)
        paint.style = Paint.Style.FILL
        canvas.drawCircle(16f * scale, 7f * scale, 3.5f * scale, paint)

        paint.color = android.graphics.Color.WHITE
        paint.alpha = 255
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = 1.2f * scale
        canvas.drawCircle(center, center, 11.5f * scale, paint)
        BitmapDescriptorFactory.fromBitmap(bitmap)
    }
}

private fun systemMotionEnabled(context: Context): Boolean = runCatching {
    Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) > 0f
}.getOrDefault(true)

private const val RUNNER_ANIMATION_FRAMES = 10
private const val RUNNER_STRIDE_CYCLE_MS = 606
private const val RUNNER_FRAME_INTERVAL_MS = 66L

private fun routeBearing(route: List<MapCoordinate>): Float? {
    val end = route.lastOrNull() ?: return null
    val start = route.asReversed().drop(1).firstOrNull { distanceMeters(it, end) >= 3.0 } ?: return null
    val startLatitude = Math.toRadians(start.latitude)
    val endLatitude = Math.toRadians(end.latitude)
    val longitudeDelta = Math.toRadians(end.longitude - start.longitude)
    val y = kotlin.math.sin(longitudeDelta) * kotlin.math.cos(endLatitude)
    val x = kotlin.math.cos(startLatitude) * kotlin.math.sin(endLatitude) -
        kotlin.math.sin(startLatitude) * kotlin.math.cos(endLatitude) * kotlin.math.cos(longitudeDelta)
    return ((Math.toDegrees(kotlin.math.atan2(y, x)) + 360.0) % 360.0).toFloat()
}

private fun distanceMeters(a: MapCoordinate, b: MapCoordinate): Double {
    val lat1 = Math.toRadians(a.latitude)
    val lat2 = Math.toRadians(b.latitude)
    val deltaLat = lat2 - lat1
    val deltaLon = Math.toRadians(b.longitude - a.longitude)
    val haversine = kotlin.math.sin(deltaLat / 2).let { it * it } +
        kotlin.math.cos(lat1) * kotlin.math.cos(lat2) * kotlin.math.sin(deltaLon / 2).let { it * it }
    return 6_371_000.0 * 2.0 * kotlin.math.atan2(kotlin.math.sqrt(haversine), kotlin.math.sqrt(1.0 - haversine))
}
