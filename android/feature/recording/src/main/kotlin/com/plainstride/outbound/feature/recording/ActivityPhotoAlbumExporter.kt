package com.plainstride.outbound.feature.recording

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File

enum class ActivityPhotoAlbumExportResult {
    SAVED,
    ALREADY_SAVED,
    PERMISSION_DENIED,
    FAILED,
}

class ActivityPhotoAlbumExporter(private val context: Context) {
    fun export(source: File, sessionId: String, takenAtEpochMs: Long): ActivityPhotoAlbumExportResult {
        if (!source.isFile) return ActivityPhotoAlbumExportResult.FAILED

        val safeSessionId = sessionId.filter { it.isLetterOrDigit() || it == '-' || it == '_' }
        if (safeSessionId.isEmpty()) return ActivityPhotoAlbumExportResult.FAILED
        val displayName = "Plainstride-$safeSessionId.jpg"
        val resolver = context.contentResolver
        val collection = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        } else {
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI
        }
        val albumPath = "${Environment.DIRECTORY_PICTURES}/Plainstride/"
        val legacyTarget = File(
            Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES),
            "Plainstride/$displayName",
        )

        val (selection, arguments) = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            "${MediaStore.Images.Media.DISPLAY_NAME} = ? AND ${MediaStore.Images.Media.RELATIVE_PATH} = ?" to
                arrayOf(displayName, albumPath)
        } else {
            "${MediaStore.Images.Media.DATA} = ?" to arrayOf(legacyTarget.absolutePath)
        }
        resolver.query(
            collection,
            arrayOf(MediaStore.Images.Media._ID),
            selection,
            arguments,
            null,
        )?.use { cursor ->
            if (cursor.moveToFirst()) return ActivityPhotoAlbumExportResult.ALREADY_SAVED
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            legacyTarget.parentFile?.mkdirs()
        }
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, "image/jpeg")
            put(MediaStore.Images.Media.DATE_TAKEN, takenAtEpochMs)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.Images.Media.RELATIVE_PATH, albumPath)
                put(MediaStore.Images.Media.IS_PENDING, 1)
            } else {
                @Suppress("DEPRECATION")
                put(MediaStore.Images.Media.DATA, legacyTarget.absolutePath)
            }
        }
        val destination = resolver.insert(collection, values)
            ?: return ActivityPhotoAlbumExportResult.FAILED

        return runCatching {
            val output = requireNotNull(resolver.openOutputStream(destination))
            source.inputStream().use { input -> output.use(input::copyTo) }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                resolver.update(
                    destination,
                    ContentValues().apply { put(MediaStore.Images.Media.IS_PENDING, 0) },
                    null,
                    null,
                )
            }
            ActivityPhotoAlbumExportResult.SAVED
        }.getOrElse {
            resolver.delete(destination, null, null)
            ActivityPhotoAlbumExportResult.FAILED
        }
    }
}
