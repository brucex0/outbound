package com.plainstride.outbound.feature.recording

import android.annotation.SuppressLint
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.plainstride.outbound.core.location.LocationPermissionAccess
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeoutOrNull

private const val ACQUISITION_BURST_MS = 8_000L
private const val POOR_SIGNAL_BACKOFF_MS = 20_000L

/** Acquire accurate fixes in bounded bursts, only while Today is visible and resumed. */
@SuppressLint("MissingPermission")
@Composable
fun ActivityStartWarmup(viewModel: RecordingViewModel) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    LaunchedEffect(owner, viewModel) {
        val client = LocationServices.getFusedLocationProviderClient(context)
        fun stop(callback: LocationCallback) {
            client.removeLocationUpdates(callback).addOnFailureListener { error ->
                Log.w("RecordingStart", "today_location_warmup_remove_failed type=${error.javaClass.simpleName}")
            }
        }
        fun diagnostic(mode: String) {
            if (BuildConfig.DEBUG) Log.d("RecordingStart", "today_location_warmup mode=$mode")
        }
        owner.lifecycle.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            viewModel.warmStartVoice()
            if (!LocationPermissionAccess.hasPermission(context)) return@repeatOnLifecycle
            val sessionJob = currentCoroutineContext().job
            var reportedResult = false
            fun reportResult() {
                if (!reportedResult) {
                    reportedResult = true
                    viewModel.trackStartWarmupResult()
                }
            }
            // Passive updates reuse fixes requested by other foreground consumers;
            // they do not ask the provider to power up GPS for this warmup.
            val passive = object : LocationCallback() {
                override fun onLocationResult(result: LocationResult) {
                    if (sessionJob.isActive) result.locations.forEach(viewModel::updateStartLocation)
                }
            }
            suspend fun acquireAccurateFix(): Boolean {
                val ready = CompletableDeferred<Unit>()
                val callback = object : LocationCallback() {
                    override fun onLocationResult(result: LocationResult) {
                        if (!sessionJob.isActive) return
                        result.locations.forEach(viewModel::updateStartLocation)
                        if (viewModel.hasAccurateStartLocation()) ready.complete(Unit)
                    }
                }
                diagnostic("acquiring")
                return try {
                    withTimeoutOrNull(ACQUISITION_BURST_MS) {
                        val burstJob = currentCoroutineContext().job
                        client.requestLocationUpdates(
                            LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1_000L)
                                .setMinUpdateIntervalMillis(1_000L)
                                .setDurationMillis(ACQUISITION_BURST_MS).build(),
                            callback,
                            Looper.getMainLooper(),
                        ).addOnSuccessListener { if (!burstJob.isActive) stop(callback) }.await()
                        ready.await()
                        true
                    } ?: false
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    Log.w("RecordingStart", "today_location_warmup_burst_failed type=${error.javaClass.simpleName}")
                    false
                } finally {
                    stop(callback)
                }
            }
            try {
                try {
                    client.requestLocationUpdates(
                        LocationRequest.Builder(Priority.PRIORITY_PASSIVE, 5_000L)
                            .setMinUpdateIntervalMillis(5_000L).build(),
                        passive,
                        Looper.getMainLooper(),
                    ).addOnSuccessListener { if (!sessionJob.isActive) stop(passive) }.await()
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    // Passive reuse is optional; bounded active bursts still provide warmup.
                    Log.w("RecordingStart", "today_location_warmup_passive_failed type=${error.javaClass.simpleName}")
                }
                while (currentCoroutineContext().isActive && LocationPermissionAccess.hasPermission(context)) {
                    val accurate = if (viewModel.hasAccurateStartLocation()) true else acquireAccurateFix()
                    reportResult()
                    diagnostic(if (accurate) "idle" else "backoff")
                    delay(if (accurate) viewModel.startWarmupRefreshDelayMillis() else POOR_SIGNAL_BACKOFF_MS)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                Log.w("RecordingStart", "today_location_warmup_failed type=${error.javaClass.simpleName}")
                reportResult()
            } finally {
                stop(passive)
                diagnostic("stopped")
            }
        }
    }
}
