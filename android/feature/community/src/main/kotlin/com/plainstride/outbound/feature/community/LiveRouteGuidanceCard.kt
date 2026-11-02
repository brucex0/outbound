package com.plainstride.outbound.feature.community

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.MyLocation
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SessionFormatting
import com.plainstride.outbound.feature.recording.FollowedRouteConfiguration
import com.plainstride.outbound.feature.recording.RecordingSnapshot
import java.text.NumberFormat
import kotlin.math.roundToInt

/** Replays accepted recording fixes when this map surface is restored, then consumes new fixes once. */
@Composable
fun LiveRouteGuidanceCard(
    snapshot: RecordingSnapshot,
    route: FollowedRouteConfiguration,
    units: MeasurementUnitSystem,
    onDirectionsResult: (Boolean) -> Unit,
) {
    if (route.points.size < 2) return
    val engine = remember(snapshot.sessionId, route) {
        RouteGuidanceEngine(route.points.map { GuidancePoint(it.latitude, it.longitude, it.altitudeMeters) }, route.reverse)
    }
    var guidance by remember(engine) { mutableStateOf(engine.initialState) }
    var consumed by remember(engine) { mutableIntStateOf(0) }
    LaunchedEffect(engine, snapshot.track.size) {
        for (index in consumed until snapshot.track.size) {
            val fix = snapshot.track[index]
            guidance = engine.update(GuidanceFix(GuidancePoint(fix.latitude, fix.longitude, fix.altitudeMeters), fix.horizontalAccuracyMeters))
            consumed = index + 1
        }
    }
    val context = LocalContext.current
    val acquiring = guidance.signal == GuidanceSignal.ACQUIRING
    val status = stringResource(when (guidance.signal) {
        GuidanceSignal.ACQUIRING -> R.string.route_guidance_acquiring
        GuidanceSignal.ON_ROUTE, GuidanceSignal.REJOINED -> R.string.route_guidance_on_route
        GuidanceSignal.DEVIATED -> R.string.route_guidance_off_route
        GuidanceSignal.WRONG_WAY -> R.string.route_guidance_wrong_way
        GuidanceSignal.ARRIVED -> R.string.route_guidance_arrived
    })
    val distance = SessionFormatting.distance(guidance.remainingM, units)
    val distanceText = NumberFormat.getNumberInstance().apply {
        minimumFractionDigits = 1
        maximumFractionDigits = 1
    }.format(distance.value)
    val progressText = stringResource(
        R.string.route_guidance_progress, distanceText,
        stringResource(if (units == MeasurementUnitSystem.metric) R.string.route_guidance_km else R.string.route_guidance_mi),
        (guidance.progress * 100).roundToInt(),
    )
    Surface(
        modifier = Modifier.fillMaxWidth().then(if (acquiring) Modifier.clickable(role = Role.Button) {
            val start = if (route.reverse) route.points.last() else route.points.first()
            onDirectionsResult(openRouteStartDirections(context, start.latitude, start.longitude))
        } else Modifier),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface.copy(alpha = 0.94f),
        tonalElevation = 4.dp,
    ) {
        Column(Modifier.padding(13.dp), verticalArrangement = Arrangement.spacedBy(9.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Icon(Icons.Default.MyLocation, null, tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f)) {
                    Text(stringResource(R.string.route_guidance_title), style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(status, style = MaterialTheme.typography.titleSmall, fontWeight = FontWeight.Bold)
                }
                Text(progressText, modifier = Modifier.weight(0.8f), style = MaterialTheme.typography.labelMedium)
            }
            LinearProgressIndicator(progress = { guidance.progress.toFloat().coerceIn(0f, 1f) }, modifier = Modifier.fillMaxWidth())
        }
    }
}

private fun openRouteStartDirections(context: Context, latitude: Double, longitude: Double): Boolean {
    val uri = Uri.Builder().scheme("https").authority("www.google.com").path("/maps/dir/")
        .appendQueryParameter("api", "1")
        .appendQueryParameter("destination", "$latitude,$longitude")
        .appendQueryParameter("travelmode", "driving")
        .build()
    // Prefer native Maps without relying on package-visibility queries; the same URL
    // supports the browser or another registered handler when Google Maps is absent.
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri).setPackage("com.google.android.apps.maps"))
        return true
    } catch (_: ActivityNotFoundException) {
        Log.i("RouteNavigation", "Open route-start directions: Google Maps unavailable; trying URL handler")
    } catch (error: SecurityException) {
        Log.w("RouteNavigation", "Open route-start directions: native handler denied type=${error.javaClass.simpleName}")
    }
    try {
        context.startActivity(Intent(Intent.ACTION_VIEW, uri))
        return true
    } catch (error: ActivityNotFoundException) {
        Log.e("RouteNavigation", "Open route-start directions failed: no URL handler type=${error.javaClass.simpleName}")
    } catch (error: SecurityException) {
        Log.e("RouteNavigation", "Open route-start directions failed: URL handler denied type=${error.javaClass.simpleName}")
    }
    Toast.makeText(context, R.string.route_directions_open_failed, Toast.LENGTH_SHORT).show()
    return false
}
