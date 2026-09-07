package run.plainstride.core.weather

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat
import com.google.android.gms.location.CurrentLocationRequest
import com.google.android.gms.location.FusedLocationProviderClient
import com.google.android.gms.location.Priority
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

interface WeatherLocationSource {
    fun hasPermission(): Boolean
    suspend fun currentApproximateLocation(): ApproximateLocation?
}

class FusedWeatherLocationSource(
    private val context: Context,
    private val client: FusedLocationProviderClient,
) : WeatherLocationSource {
    override fun hasPermission(): Boolean = ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.ACCESS_COARSE_LOCATION,
    ) == PackageManager.PERMISSION_GRANTED

    override suspend fun currentApproximateLocation(): ApproximateLocation? {
        if (!hasPermission()) return null
        val request = CurrentLocationRequest.Builder()
            .setPriority(Priority.PRIORITY_BALANCED_POWER_ACCURACY)
            .setMaxUpdateAgeMillis(5 * 60 * 1_000L)
            .setDurationMillis(10_000L)
            .build()
        @Suppress("MissingPermission")
        return suspendCancellableCoroutine { continuation ->
            val cancellation = com.google.android.gms.tasks.CancellationTokenSource()
            continuation.invokeOnCancellation { cancellation.cancel() }
            client.getCurrentLocation(request, cancellation.token)
                .addOnSuccessListener { location ->
                    continuation.resume(location?.let {
                        ApproximateLocation(it.latitude, it.longitude, if (it.hasAltitude()) it.altitude else null).rounded()
                    })
                }
                .addOnFailureListener { continuation.resume(null) }
                .addOnCanceledListener { continuation.cancel() }
        }
    }
}
