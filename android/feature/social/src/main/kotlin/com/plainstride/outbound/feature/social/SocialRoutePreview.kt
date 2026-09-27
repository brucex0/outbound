package com.plainstride.outbound.feature.social

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.LruCache
import java.io.File
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Route
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import androidx.compose.foundation.shape.RoundedCornerShape
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.google.android.gms.maps.model.MapStyleOptions
import com.google.maps.android.compose.GoogleMap
import com.google.maps.android.compose.MapEffect
import com.google.maps.android.compose.MapProperties
import com.google.maps.android.compose.MapUiSettings
import com.google.maps.android.compose.Polyline
import com.google.maps.android.compose.rememberCameraPositionState
import com.plainstride.outbound.core.designsystem.MapCoordinate
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.Request
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicBoolean

private object SocialPreviewBitmapCache {
    val maps = PreviewBitmapLruCache(24 * 1024 * 1024)
    val photos = PreviewBitmapLruCache(12 * 1024 * 1024)
}

private class PreviewBitmapLruCache(maxBytes: Int) : LruCache<String, Bitmap>(maxBytes) {
    override fun sizeOf(key: String, value: Bitmap): Int = value.byteCount
}

@Composable
internal fun SocialRoutePreview(
    activity: FeedActivity,
    loadPhotoThumbnail: suspend (String) -> ByteArray?,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val dependencies = remember(context) {
        EntryPointAccessors.fromApplication(
            context.applicationContext,
            SocialAvatarDependencies::class.java,
        )
    }
    val photoUrl = activity.photos.firstOrNull()?.thumbnailUrl
    val route = remember(activity.route) { activity.route.routeCoordinates().filter {
        it.latitude.isFinite() && it.longitude.isFinite() &&
            it.latitude in -90.0..90.0 && it.longitude in -180.0..180.0
    } }
    val absolutePhotoUrl = remember(photoUrl, dependencies) {
        photoUrl?.let { normalizedPreviewUrl(it, dependencies.apiBaseUrl()) }
    }
    val photoCacheKey = absolutePhotoUrl ?: photoUrl
    val photoBitmap by produceState<Bitmap?>(photoCacheKey?.let(SocialPreviewBitmapCache.photos::get), photoCacheKey) {
        if (photoCacheKey == null || value != null) return@produceState
        val bytes = withContext(Dispatchers.IO) {
            val downloaded = photoUrl?.let { runCatching { loadPhotoThumbnail(it) }.getOrNull() }
            downloaded ?: absolutePhotoUrl?.let { url ->
                runCatching {
                    dependencies.httpClient().newCall(Request.Builder().url(url).build()).execute().use { response ->
                        if (response.isSuccessful) response.body?.bytes() else null
                    }
                }.getOrNull()
            }
        } ?: return@produceState
        val decoded = withContext(Dispatchers.Default) { decodePreviewBitmap(bytes, 720) }
        if (decoded != null) {
            SocialPreviewBitmapCache.photos.put(photoCacheKey, decoded)
            value = decoded
        }
    }

    val description = stringResource(
        if (absolutePhotoUrl != null) R.string.social_activity_photo
        else R.string.social_route,
    )
    BoxWithConstraints(modifier.semantics { contentDescription = description }.clipToBounds()) {
        if (photoBitmap != null) {
            Image(
                bitmap = photoBitmap!!.asImageBitmap(),
                contentDescription = description,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Crop,
            )
        } else if (absolutePhotoUrl == null && route.size > 1) {
            val density = androidx.compose.ui.platform.LocalDensity.current
            val mapWidthPx = with(density) { maxWidth.toPx().toInt() }.coerceAtLeast(1)
            val mapHeightPx = with(density) { maxHeight.toPx().toInt() }.coerceAtLeast(1)
            val routeKey = remember(route) { routeCacheKey(route) }
            val mapKey = "$routeKey|${mapWidthPx}x${mapHeightPx}"
            val cachedMap = remember(mapKey) { SocialPreviewBitmapCache.maps.get(mapKey) }
            var snapshot by remember(mapKey) { mutableStateOf(cachedMap) }
            var diskCacheLoaded by remember(mapKey) { mutableStateOf(cachedMap != null) }
            val scope = rememberCoroutineScope()
            LaunchedEffect(mapKey, cachedMap) {
                if (cachedMap == null) {
                    snapshot = withContext(Dispatchers.IO) { readCachedRoutePreview(context.cacheDir, mapKey) }
                    snapshot?.let { SocialPreviewBitmapCache.maps.put(mapKey, it) }
                }
                diskCacheLoaded = true
            }
            if (snapshot != null) {
                Image(
                    bitmap = snapshot!!.asImageBitmap(),
                    contentDescription = description,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                )
            } else if (!diskCacheLoaded) {
                RoutePreviewPlaceholder(Modifier.fillMaxSize())
            } else {
                val camera = rememberCameraPositionState()
                val latLngs = remember(route) { route.map { LatLng(it.latitude, it.longitude) } }
                val captureStarted = remember(mapKey) { AtomicBoolean(false) }
                LaunchedEffect(camera, latLngs, maxWidth, maxHeight) {
                    val bounds = LatLngBounds.builder().also { builder -> latLngs.forEach(builder::include) }.build()
                    runCatching { camera.animate(CameraUpdateFactory.newLatLngBounds(bounds, 24)) }
                }
                GoogleMap(
                    modifier = Modifier.fillMaxSize(),
                    cameraPositionState = camera,
                    contentPadding = PaddingValues(bottom = maxHeight / 3),
                    properties = MapProperties(
                        isBuildingEnabled = false,
                        mapStyleOptions = MapStyleOptions(
                            """[{"featureType":"poi","elementType":"all","stylers":[{"visibility":"off"}]}]""",
                        ),
                    ),
                    uiSettings = MapUiSettings(
                        compassEnabled = false,
                        indoorLevelPickerEnabled = false,
                        mapToolbarEnabled = false,
                        myLocationButtonEnabled = false,
                        rotationGesturesEnabled = false,
                        scrollGesturesEnabled = false,
                        tiltGesturesEnabled = false,
                        zoomControlsEnabled = false,
                        zoomGesturesEnabled = false,
                    ),
                ) {
                    Polyline(points = latLngs, color = Color.White.copy(alpha = .92f), width = 14.dp.value, startCap = com.google.android.gms.maps.model.RoundCap(), endCap = com.google.android.gms.maps.model.RoundCap(), jointType = com.google.android.gms.maps.model.JointType.ROUND, zIndex = 1f)
                    Polyline(points = latLngs, color = Color(0xFFFF9500), width = 8.dp.value, startCap = com.google.android.gms.maps.model.RoundCap(), endCap = com.google.android.gms.maps.model.RoundCap(), jointType = com.google.android.gms.maps.model.JointType.ROUND, zIndex = 2f)
                    MapEffect(mapKey) { map ->
                        map.setOnMapLoadedCallback {
                            if (captureStarted.compareAndSet(false, true)) {
                                map.snapshot { bitmap ->
                                    if (bitmap != null) {
                                        snapshot = bitmap
                                        SocialPreviewBitmapCache.maps.put(mapKey, bitmap)
                                        scope.launch(Dispatchers.IO) {
                                            writeCachedRoutePreview(context.cacheDir, mapKey, bitmap)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else {
            RoutePreviewPlaceholder(Modifier.fillMaxSize())
        }
    }
}

@Composable
private fun RoutePreviewPlaceholder(modifier: Modifier = Modifier) {
    Box(
        modifier.background(
            Brush.linearGradient(
                listOf(MaterialTheme.colorScheme.primary.copy(alpha = .28f), MaterialTheme.colorScheme.background),
            ),
        ),
        contentAlignment = Alignment.Center,
    ) {
        androidx.compose.material3.Icon(
            Icons.Outlined.Route,
            stringResource(R.string.social_route),
            modifier = Modifier.size(54.dp),
            tint = MaterialTheme.colorScheme.primary.copy(alpha = .65f),
        )
    }
}

private fun normalizedPreviewUrl(value: String, baseUrl: String): String? {
    val trimmed = value.trim().takeIf(String::isNotEmpty) ?: return null
    val parsed = trimmed.toHttpUrlOrNull()
    if (parsed != null) {
        if (parsed.isHttps || parsed.host in setOf("localhost", "127.0.0.1", "10.0.2.2")) return parsed.toString()
        return parsed.newBuilder().scheme("https").build().toString()
    }
    val base = baseUrl.toHttpUrlOrNull() ?: return null
    val path = if (base.encodedPath.trimEnd('/').endsWith("/v1")) trimmed.trimStart('/') else "v1/${trimmed.trimStart('/')}"
    return base.resolve(path)?.toString()
}

private fun decodePreviewBitmap(bytes: ByteArray, maxPixelSize: Int): Bitmap? {
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
    var sampleSize = 1
    while (bounds.outWidth / sampleSize > maxPixelSize || bounds.outHeight / sampleSize > maxPixelSize) sampleSize *= 2
    return BitmapFactory.decodeByteArray(bytes, 0, bytes.size, BitmapFactory.Options().apply { inSampleSize = sampleSize })
}

private fun routeCacheKey(points: List<MapCoordinate>): String {
    val raw = buildString {
        points.forEach { point ->
            append("%.6f,%.6f;".format(point.latitude, point.longitude))
        }
    }
    return MessageDigest.getInstance("SHA-256").digest(raw.toByteArray()).joinToString("") { "%02x".format(it) }
}

private fun routePreviewFile(cacheDir: File, key: String): File {
    val digest = MessageDigest.getInstance("SHA-256").digest(key.toByteArray())
        .joinToString("") { "%02x".format(it) }
    return File(File(cacheDir, "SocialRoutePreviews"), "$digest.jpg")
}

private fun readCachedRoutePreview(cacheDir: File, key: String): Bitmap? =
    runCatching { routePreviewFile(cacheDir, key).takeIf(File::isFile)?.let { BitmapFactory.decodeFile(it.path) } }.getOrNull()

private fun writeCachedRoutePreview(cacheDir: File, key: String, bitmap: Bitmap) {
    runCatching {
        val file = routePreviewFile(cacheDir, key)
        file.parentFile?.mkdirs()
        file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.JPEG, 82, it) }
    }
}
