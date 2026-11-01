package com.plainstride.outbound.feature.activity

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import android.util.Log
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalContext
import java.io.File

/** Documents retain original image metadata; the visual picker can return redacted copies.
 * Grants remain limited to the selected documents. Denying metadata access still imports pixels.
 */
@Composable
fun rememberActivityPhotoImportLauncher(
    onPermissionEvent: (String) -> Unit,
    onResult: (List<Uri>) -> Unit,
): () -> Unit {
    val context = LocalContext.current
    val documents = rememberLauncherForActivityResult(ActivityResultContracts.OpenMultipleDocuments(), onResult)
    val location = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        onPermissionEvent(if (granted) "granted" else "denied")
        documents.launch(arrayOf("image/*"))
    }
    return {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
            context.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION) != PackageManager.PERMISSION_GRANTED) {
            onPermissionEvent("requested")
            location.launch(Manifest.permission.ACCESS_MEDIA_LOCATION)
        } else {
            documents.launch(arrayOf("image/*"))
        }
    }
}

/** Copies before any normalization so EXIF orientation, date, and GPS remain available. */
fun copyActivityPhotoSource(context: Context, uri: Uri, destination: File) {
    val resolver = context.contentResolver
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && uri.authority == MediaStore.AUTHORITY &&
        context.checkSelfPermission(Manifest.permission.ACCESS_MEDIA_LOCATION) == PackageManager.PERMISSION_GRANTED) {
        try {
            val original = MediaStore.setRequireOriginal(uri)
            (resolver.openInputStream(original) ?: throw java.io.IOException("Original image unavailable")).use { input -> destination.outputStream().use(input::copyTo) }
            return
        } catch (error: java.io.IOException) {
            Log.w("PlainstridePhotoImport", "copy_original unavailable type=${error.javaClass.simpleName}")
        } catch (error: SecurityException) {
            Log.w("PlainstridePhotoImport", "copy_original denied type=${error.javaClass.simpleName}")
        } catch (error: UnsupportedOperationException) {
            Log.w("PlainstridePhotoImport", "copy_original unsupported type=${error.javaClass.simpleName}")
        }
    }
    // Document/cloud providers need not support MediaStore's original-file URI.
    checkNotNull(resolver.openInputStream(uri)).use { input -> destination.outputStream().use(input::copyTo) }
}
