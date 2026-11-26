package com.plainstride.outbound.feature.activity

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.util.Log
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.DirectionsRun
import androidx.compose.material.icons.automirrored.outlined.DirectionsWalk
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.*
import androidx.compose.ui.graphics.layer.*
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.*
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.google.android.gms.maps.MapView
import com.google.android.gms.maps.GoogleMap
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import com.plainstride.outbound.core.model.activity.*
import kotlinx.coroutines.*
import java.time.Instant
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.time.format.DateTimeFormatterBuilder
import java.time.format.FormatStyle
import java.time.chrono.IsoChronology
import java.util.Locale

/** One preparation path for stored and Social detail; original media bytes stay untouched. */
@Composable
fun ActivitySharePreparation(
    activity: SavedActivity,
    unitSystem: MeasurementUnitSystem,
    loadAssets: suspend () -> ActivityShareAssets,
    export: suspend (Bitmap) -> ActivityExport?,
    onComplete: (ActivityExport?) -> Unit,
    onCancel: () -> Unit,
) {
    val context = LocalContext.current
    val mapResult = remember(activity) { CompletableDeferred<ActivityShareMapSnapshot?>() }
    val mapView = remember(activity) { MapView(context) }
    var assets by remember(activity) { mutableStateOf<ActivityShareAssets?>(null) }
    var backdrop by remember(activity) { mutableStateOf<Bitmap?>(null) }
    var ready by remember(activity) { mutableStateOf(false) }
    var drawn by remember(activity) { mutableStateOf(false) }
    val layer = rememberGraphicsLayer()
    DisposableEffect(mapView) {
        onDispose { mapView.onPause(); mapView.onStop(); mapView.onDestroy() }
    }
    LaunchedEffect(activity) {
        try {
            coroutineScope {
                val loadedAssets = async { loadAssets() }
                val snapshot = if (activity.track.size > 1) withTimeoutOrNull(15_000) { mapResult.await() } else null
                if (activity.track.size > 1 && snapshot == null) {
                    mapResult.complete(null)
                    Log.w("ActivityShare", "Map snapshot unavailable or timed out; using stats fallback")
                }
                assets = loadedAssets.await()
                backdrop = snapshot?.let { drawShareMap(it, requireNotNull(assets)) }
                snapshot?.bitmap?.recycle()
                ready = true
            }
        } catch (error: CancellationException) { throw error }
        catch (error: Exception) {
            Log.e("ActivityShare", "Share preparation failed type=${error.javaClass.simpleName}")
            onComplete(null)
        }
    }
    LaunchedEffect(ready, drawn) {
        if (ready && drawn) {
            withFrameNanos { }
            try {
                val bitmap = layer.toImageBitmap().asAndroidBitmap()
                onComplete(export(bitmap))
            } catch (error: CancellationException) { throw error }
            catch (error: Exception) {
                Log.e("ActivityShare", "Share image export failed type=${error.javaClass.simpleName}")
                onComplete(null)
            }
        }
    }
    // Compose's recorded layers can outlive disposal by a render frame. Let their
    // bitmap references be reclaimed together instead of recycling pixels in use.
    Dialog(onDismissRequest = onCancel, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CompositionLocalProvider(LocalDensity provides Density(1f, 1f)) {
                if (!ready && activity.track.size > 1) AndroidView(
                    factory = {
                        mapView.apply {
                            onCreate(null); onStart(); onResume()
                            getMapAsync { map ->
                                try {
                                    map.mapType = GoogleMap.MAP_TYPE_NORMAL
                                    map.isBuildingsEnabled = true
                                    map.uiSettings.setAllGesturesEnabled(false)
                                    map.uiSettings.isMapToolbarEnabled = false
                                    fitShareMap(map, activity, 1080, 1920)
                                    map.setOnMapLoadedCallback {
                                        map.snapshot { bitmap ->
                                            if (bitmap == null) mapResult.complete(null)
                                            else {
                                                val snapshot = captureShareMap(map, activity, bitmap)
                                                if (!mapResult.complete(snapshot)) bitmap.recycle()
                                            }
                                        }
                                    }
                                } catch (error: Exception) {
                                    Log.w("ActivityShare", "Map snapshot setup failed type=${error.javaClass.simpleName}")
                                    mapResult.complete(null)
                                }
                            }
                        }
                    },
                    modifier = Modifier.requiredSize(1080.dp, 1920.dp),
                )
                if (ready) ActivityShareCard(
                    activity, unitSystem, backdrop, requireNotNull(assets),
                    Modifier.requiredSize(1080.dp, 1920.dp).drawWithContent {
                        layer.record { this@drawWithContent.drawContent() }
                        drawLayer(layer)
                        if (!drawn) drawn = true
                    },
                )
            }
            Surface(Modifier.fillMaxSize(), color = MaterialTheme.colorScheme.surface) {
                Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center, horizontalAlignment = Alignment.CenterHorizontally) {
                    CircularProgressIndicator()
                    Spacer(Modifier.height(20.dp))
                    Text(stringResource(R.string.activity_share_preparing))
                }
            }
        }
    }
}

@Composable
internal fun ActivityShareCard(activity: SavedActivity, unitSystem: MeasurementUnitSystem, map: Bitmap?, assets: ActivityShareAssets, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val qr = remember(assets.referralUrl) { shareQr(assets.referralUrl) }
    val logo = remember(context) {
        val id = context.resources.getIdentifier("plainstride_app_icon", "drawable", context.packageName)
        if (id != 0) BitmapFactory.decodeResource(context.resources, id) else null
    }
    val locale = Locale.getDefault()
    val date = remember(activity.startedAt, locale) {
        val pattern = DateTimeFormatterBuilder.getLocalizedDateTimePattern(FormatStyle.FULL, null, IsoChronology.INSTANCE, locale).replace("MMMM", "MMM")
        try { Instant.parse(activity.startedAt).atZone(ZoneId.systemDefault()).format(DateTimeFormatter.ofPattern(pattern, locale)).uppercase(locale) }
        catch (error: java.time.DateTimeException) {
            Log.w("ActivityShare", "Share date unavailable type=${error.javaClass.simpleName}")
            ""
        }
    }
    val distance = SessionFormatting.distance(activity.distanceM, unitSystem)
    val unit = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
    val pace = activity.averagePaceSecsPerKm?.let { SessionFormatting.pace(it, unitSystem) }
    Box(modifier.background(Brush.verticalGradient(listOf(Color(.76f, .82f, .84f), Color(.42f, .48f, .50f))))) {
        if (map != null) Image(map.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop)
        Box(Modifier.fillMaxSize().background(Brush.verticalGradient(
            .18f to Color.Black.copy(alpha = 0f), .48f to Color.Black.copy(alpha = .12f),
            .78f to Color.Black.copy(alpha = .66f), 1f to Color.Black.copy(alpha = .82f),
        )))
        Column(Modifier.fillMaxSize().padding(start = 104.dp, end = 104.dp, bottom = 128.dp),
            verticalArrangement = Arrangement.Bottom) {
            val sport = when (activity.type) {
                ActivityType.cycling -> Icons.Outlined.DirectionsBike
                ActivityType.walking -> Icons.AutoMirrored.Outlined.DirectionsWalk
                ActivityType.hiking -> Icons.Outlined.Hiking
                ActivityType.swimming -> Icons.Outlined.Pool
                else -> Icons.AutoMirrored.Outlined.DirectionsRun
            }
            Icon(sport, null, Modifier.size(78.dp), tint = Color.White)
            Spacer(Modifier.height(34.dp))
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                FittedShareText(activity.title, 872, 62, 44, FontWeight.Bold, maxLines = 2)
                activity.companionType?.let { Text(stringResource(R.string.activity_share_with_dog), color = Color.White.copy(alpha = .86f), fontSize = 24.sp, lineHeight = 28.8.sp, fontWeight = FontWeight.SemiBold) }
                Text(date, color = Color.White.copy(alpha = .76f), fontSize = 24.sp, lineHeight = 28.8.sp, fontWeight = FontWeight.SemiBold)
            }
            Spacer(Modifier.height(34.dp))
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.Bottom) {
                Column(Modifier.width(500.dp), verticalArrangement = Arrangement.spacedBy(28.dp)) {
                    Row(horizontalArrangement = Arrangement.spacedBy(36.dp)) {
                        ShareStat(stringResource(R.string.activity_distance), String.format(locale, "%.2f", distance.value), unit)
                        ShareStat(stringResource(R.string.activity_time), shareDuration(activity.durationSecs))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(36.dp)) {
                        ShareStat(stringResource(R.string.activity_share_pace), pace?.let { "%d:%02d".format(it.minutes, it.seconds) } ?: "--", pace?.let { "/$unit" })
                        activity.elevationGainM?.let {
                            val elevation = SessionFormatting.elevation(it, unitSystem)
                            ShareStat(stringResource(R.string.activity_metric_elevation_gain), "%.0f".format(locale, elevation.value),
                                if (unitSystem == MeasurementUnitSystem.metric) "m" else "ft")
                        }
                    }
                }
                Spacer(Modifier.weight(1f))
                Column(horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                    Box(Modifier.size(264.dp, 52.dp), contentAlignment = Alignment.Center) {
                        Text(stringResource(R.string.activity_share_run_with_me), color = Color.White, fontSize = 32.sp, lineHeight = 38.4.sp, fontWeight = FontWeight.Black, letterSpacing = 1.6.sp, maxLines = 1)
                    }
                    Box(Modifier.size(264.dp).clip(RoundedCornerShape(28.dp)), contentAlignment = Alignment.Center) {
                        Image(qr.asImageBitmap(), null, Modifier.fillMaxSize(), filterQuality = FilterQuality.None)
                        assets.avatar?.let { avatar ->
                            Box(Modifier.size(106.dp).background(Color.White, CircleShape), contentAlignment = Alignment.Center) {
                                Image(avatar.asImageBitmap(), null, Modifier.size(96.dp).clip(CircleShape), contentScale = ContentScale.Crop)
                            }
                        }
                    }
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                        if (logo != null) Image(logo.asImageBitmap(), null, Modifier.size(76.dp).clip(RoundedCornerShape(16.dp)))
                        Text("Plainstride", color = Color.White, fontSize = 34.sp, lineHeight = 40.8.sp, fontWeight = FontWeight.Medium, letterSpacing = 1.1.sp)
                    }
                }
            }
        }
    }
}

@Composable
private fun ShareStat(label: String, value: String, unit: String? = null) {
    val measurer = rememberTextMeasurer()
    val valueWidth = measurer.measure(value, TextStyle(fontSize = 56.sp, fontWeight = FontWeight.Bold)).size.width
    val unitWidth = unit?.let { measurer.measure(it, TextStyle(fontSize = 28.sp, fontWeight = FontWeight.SemiBold)).size.width + 8 } ?: 0
    val scale = (232f / (valueWidth + unitWidth).coerceAtLeast(1)).coerceIn(.7f, 1f)
    Column(Modifier.width(232.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(verticalAlignment = Alignment.Bottom) {
            Text(value, color = Color.White, fontSize = (56 * scale).sp, lineHeight = (67.2 * scale).sp, fontWeight = FontWeight.Bold, maxLines = 1, modifier = Modifier.alignByBaseline())
            if (unit != null) {
                Spacer(Modifier.width(8.dp))
                Text(unit, color = Color.White.copy(alpha = .82f), fontSize = (28 * scale).sp, lineHeight = (33.6 * scale).sp, fontWeight = FontWeight.SemiBold, maxLines = 1, modifier = Modifier.alignByBaseline())
            }
        }
        FittedShareText(label, 232, 24, 19, FontWeight.Medium, color = Color.White.copy(alpha = .8f))
    }
}

@Composable
private fun FittedShareText(value: String, width: Int, maxSize: Int, minSize: Int, weight: FontWeight, maxLines: Int = 1, color: Color = Color.White) {
    val measurer = rememberTextMeasurer()
    val size = remember(value, width, measurer) {
        (maxSize downTo minSize).firstOrNull { size ->
            !measurer.measure(value, TextStyle(fontSize = size.sp, lineHeight = (size * 1.2).sp, fontWeight = weight), maxLines = maxLines, constraints = Constraints(maxWidth = width)).hasVisualOverflow
        } ?: minSize
    }
    Text(value, color = color, fontSize = size.sp, lineHeight = (size * 1.2).sp, fontWeight = weight, maxLines = maxLines, overflow = TextOverflow.Ellipsis)
}

internal fun shareQr(value: String): Bitmap {
    val matrix = QRCodeWriter().encode(value, BarcodeFormat.QR_CODE, 264, 264,
        mapOf(EncodeHintType.ERROR_CORRECTION to ErrorCorrectionLevel.H, EncodeHintType.MARGIN to 1))
    return Bitmap.createBitmap(264, 264, Bitmap.Config.ARGB_8888).apply {
        for (y in 0 until height) for (x in 0 until width) setPixel(x, y, if (matrix[x, y]) android.graphics.Color.BLACK else android.graphics.Color.WHITE)
    }
}

private fun shareDuration(seconds: Int) = if (seconds >= 3600) "%d:%02d:%02d".format(seconds / 3600, seconds / 60 % 60, seconds % 60) else "%d:%02d".format(seconds / 60, seconds % 60)
