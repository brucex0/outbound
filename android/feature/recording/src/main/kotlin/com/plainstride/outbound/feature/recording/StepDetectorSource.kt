package com.plainstride.outbound.feature.recording

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.Sensor
import android.hardware.SensorEvent
import android.hardware.SensorEventListener
import android.hardware.SensorManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import kotlinx.coroutines.channels.awaitClose
import kotlinx.coroutines.flow.callbackFlow

internal class StepDetectorSource(private val context: Context) {
    /** Hardware timestamps avoid cadence distortion when events are delivered in a batch. */
    fun steps() = callbackFlow<Long> {
        val manager = context.getSystemService(SensorManager::class.java)
        val sensor = manager?.getDefaultSensor(Sensor.TYPE_STEP_DETECTOR)
        // Missing hardware or denied optional motion access is normal control flow.
        if (sensor == null || (Build.VERSION.SDK_INT >= 29 && ContextCompat.checkSelfPermission(
                context, Manifest.permission.ACTIVITY_RECOGNITION,
            ) != PackageManager.PERMISSION_GRANTED)) {
            close()
            return@callbackFlow
        }
        val listener = object : SensorEventListener {
            override fun onSensorChanged(event: SensorEvent) {
                if (event.sensor.type == Sensor.TYPE_STEP_DETECTOR && trySend(event.timestamp).isFailure && !isClosedForSend) {
                    Log.e("RecordingMotion", "Step event delivery failed reason=buffer_full")
                    close()
                }
            }
            override fun onAccuracyChanged(sensor: Sensor?, accuracy: Int) = Unit
        }
        try {
            val registered = manager.registerListener(listener, sensor, SensorManager.SENSOR_DELAY_NORMAL, 0, Handler(Looper.getMainLooper()))
            if (!registered) {
                Log.e("RecordingMotion", "Step detector registration failed reason=registration_rejected")
                close()
            }
        } catch (error: RuntimeException) {
            Log.e("RecordingMotion", "Step detector registration failed type=${error.javaClass.simpleName}")
            close()
        }
        awaitClose { manager.unregisterListener(listener) }
    }
}
