package com.plainstride.outbound.feature.activity

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.util.Log
import java.io.ByteArrayInputStream

/** BitmapFactory returns raw pixels; Compose does not apply the JPEG EXIF orientation. */
internal fun decodeActivityPhoto(bytes: ByteArray): Bitmap? {
    val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: run {
        Log.w("ActivityPhoto", "decode: unsupported or invalid image bytes")
        return null
    }
    val orientation = try {
        ByteArrayInputStream(bytes).use {
            ExifInterface(it).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
        }
    } catch (error: java.io.IOException) {
        Log.w("ActivityPhoto", "read orientation: metadata unavailable (${error.javaClass.simpleName})")
        ExifInterface.ORIENTATION_NORMAL
    }
    val transform = Matrix()
    when (orientation) {
        ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> transform.setScale(-1f, 1f)
        ExifInterface.ORIENTATION_ROTATE_180 -> transform.setRotate(180f)
        ExifInterface.ORIENTATION_FLIP_VERTICAL -> transform.setScale(1f, -1f)
        ExifInterface.ORIENTATION_TRANSPOSE -> {
            transform.setRotate(90f)
            transform.postScale(-1f, 1f)
        }
        ExifInterface.ORIENTATION_ROTATE_90 -> transform.setRotate(90f)
        ExifInterface.ORIENTATION_TRANSVERSE -> {
            transform.setRotate(90f)
            transform.postScale(1f, -1f)
        }
        ExifInterface.ORIENTATION_ROTATE_270 -> transform.setRotate(270f)
        else -> return bitmap
    }
    // Normalize only in-memory pixels, retaining full resolution and original file/metadata.
    return Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, transform, true).also {
        if (it !== bitmap) bitmap.recycle()
    }
}
