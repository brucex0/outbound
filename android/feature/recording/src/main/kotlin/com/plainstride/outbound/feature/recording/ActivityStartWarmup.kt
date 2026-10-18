package com.plainstride.outbound.feature.recording

import android.annotation.SuppressLint
import android.os.Looper
import android.util.Log
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.google.android.gms.location.LocationCallback
import com.google.android.gms.location.LocationRequest
import com.google.android.gms.location.LocationResult
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.plainstride.outbound.core.location.LocationPermissionAccess

/** Warm only while Today is visible; never request permission or retain background updates. */
@SuppressLint("MissingPermission")
@Composable
fun ActivityStartWarmup(viewModel: RecordingViewModel) {
    val context = LocalContext.current
    val owner = LocalLifecycleOwner.current
    DisposableEffect(owner, viewModel) {
        val client = LocationServices.getFusedLocationProviderClient(context)
        val callback = object : LocationCallback() {
            override fun onLocationResult(result: LocationResult) {
                result.lastLocation?.let(viewModel::updateStartLocation)
            }
        }
        fun stop() { client.removeLocationUpdates(callback) }
        fun start() {
            stop()
            viewModel.warmStartVoice()
            if (!LocationPermissionAccess.hasPermission(context)) return
            try {
                client.requestLocationUpdates(
                    LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 5_000L)
                        .setMinUpdateIntervalMillis(1_000L).build(),
                    callback,
                    Looper.getMainLooper(),
                ).addOnFailureListener { error ->
                    Log.w("RecordingStart", "today_location_warmup_failed type=${error.javaClass.simpleName}")
                }
            } catch (error: SecurityException) {
                Log.w("RecordingStart", "today_location_warmup_permission_changed type=${error.javaClass.simpleName}")
            }
        }
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> start()
                Lifecycle.Event.ON_PAUSE -> stop()
                else -> Unit
            }
        }
        owner.lifecycle.addObserver(observer)
        if (owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) start()
        onDispose {
            owner.lifecycle.removeObserver(observer)
            stop()
        }
    }
}
