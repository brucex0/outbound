package com.plainstride.outbound.core.location

import android.Manifest
import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.content.pm.PackageManager
import androidx.core.app.ActivityCompat

/** Shared permission state for outdoor setup, weather, and activity recording. */
object LocationPermissionAccess {
    private const val PREFERENCES = "recording_permissions"
    private const val REQUESTED_KEY = "location_requested"

    val requestPermissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION,
    )

    fun hasPrecisePermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun hasApproximatePermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED

    fun hasPermission(context: Context): Boolean =
        hasPrecisePermission(context) || hasApproximatePermission(context)

    fun wasRequestedBefore(context: Context): Boolean {
        if (context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getBoolean(REQUESTED_KEY, false)) return true
        val activity = context.findActivity() ?: return false
        return requestPermissions.any { ActivityCompat.shouldShowRequestPermissionRationale(activity, it) }
    }

    fun markRequested(context: Context) {
        context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(REQUESTED_KEY, true)
            .apply()
    }

    private fun Context.findActivity(): Activity? = when (this) {
        is Activity -> this
        is ContextWrapper -> baseContext.findActivity()
        else -> null
    }
}
