package run.plainstride.feature.recording

import android.annotation.SuppressLint
import android.content.Context
import android.location.Location
import android.os.Looper
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

/**
 * Thin platform adapter. Permission requests remain an Activity/UI responsibility;
 * this source only reacts to the externally supplied permission state.
 */
class FusedRecordingLocationSource(
    context: Context,
    private val permissionState: StateFlow<LocationPermissionState>,
    private val scope: CoroutineScope,
    private val client: FusedLocationProviderClient =
        LocationServices.getFusedLocationProviderClient(context.applicationContext),
) {
    private val _samples = MutableSharedFlow<RecordedLocationSample>(
        extraBufferCapacity = 32,
        onBufferOverflow = BufferOverflow.DROP_OLDEST,
    )
    val samples: SharedFlow<RecordedLocationSample> = _samples

    private var permissionJob: Job? = null
    private var requested = false
    private val callback = object : LocationCallback() {
        override fun onLocationResult(result: LocationResult) {
            result.locations.forEach { _samples.tryEmit(it.toRecordingSample()) }
        }
    }

    fun start() {
        if (permissionJob != null) return
        permissionJob = scope.launch {
            permissionState.collectLatest { state ->
                when (state) {
                    LocationPermissionState.PRECISE,
                    LocationPermissionState.APPROXIMATE,
                    -> requestUpdates(state)
                    LocationPermissionState.NOT_REQUESTED,
                    LocationPermissionState.DENIED,
                    -> removeUpdates()
                }
            }
        }
    }

    fun stop() {
        permissionJob?.cancel()
        permissionJob = null
        removeUpdates()
    }

    @SuppressLint("MissingPermission")
    private fun requestUpdates(permission: LocationPermissionState) {
        if (requested) return
        val priority = if (permission == LocationPermissionState.PRECISE) {
            Priority.PRIORITY_HIGH_ACCURACY
        } else {
            Priority.PRIORITY_BALANCED_POWER_ACCURACY
        }
        val request = LocationRequest.Builder(priority, 1_000L)
            .setMinUpdateIntervalMillis(500L)
            .setMinUpdateDistanceMeters(1f)
            .setWaitForAccurateLocation(permission == LocationPermissionState.PRECISE)
            .build()
        try {
            client.requestLocationUpdates(request, callback, Looper.getMainLooper())
            requested = true
        } catch (_: SecurityException) {
            requested = false
        }
    }

    private fun removeUpdates() {
        if (!requested) return
        client.removeLocationUpdates(callback)
        requested = false
    }
}

private fun Location.toRecordingSample() = RecordedLocationSample(
    latitude = latitude,
    longitude = longitude,
    altitudeMeters = if (hasAltitude()) altitude else null,
    horizontalAccuracyMeters = if (hasAccuracy()) accuracy.toDouble() else Double.POSITIVE_INFINITY,
    verticalAccuracyMeters = if (android.os.Build.VERSION.SDK_INT >= 26 && hasVerticalAccuracy()) {
        verticalAccuracyMeters.toDouble()
    } else null,
    speedMetersPerSecond = if (hasSpeed()) speed.toDouble() else null,
    speedAccuracyMetersPerSecond = if (android.os.Build.VERSION.SDK_INT >= 26 && hasSpeedAccuracy()) {
        speedAccuracyMetersPerSecond.toDouble()
    } else null,
    capturedAtEpochMilliseconds = time,
    capturedAtElapsedRealtimeNanos = elapsedRealtimeNanos,
)
