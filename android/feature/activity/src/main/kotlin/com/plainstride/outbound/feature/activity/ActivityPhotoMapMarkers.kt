package com.plainstride.outbound.feature.activity

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import androidx.compose.runtime.*
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.LocalDensity
import com.google.android.gms.maps.model.BitmapDescriptorFactory
import com.plainstride.outbound.core.designsystem.MapCoordinate
import com.plainstride.outbound.core.designsystem.MapRouteMarker
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class ActivityMapPhoto(val id: String, val latitude: Double?, val longitude: Double?, val title: String, val bytes: ByteArray?)

@Composable
fun rememberActivityPhotoMarkers(photos: List<ActivityMapPhoto>, selectedId: String?, mapLoaded: Boolean): List<MapRouteMarker> {
    val density = LocalDensity.current.density
    val icons by produceState<Map<String, com.google.android.gms.maps.model.BitmapDescriptor>>(emptyMap(), photos, mapLoaded, density) {
        if (!mapLoaded) return@produceState
        val bitmaps = withContext(Dispatchers.Default) {
            photos.associate { photo ->
                val image = photo.bytes?.let { decodeActivityPhoto(it, maxPixelSize = (84 * density).toInt()) }
                val icon = Bitmap.createBitmap((50 * density).toInt(), (50 * density).toInt(), Bitmap.Config.ARGB_8888)
                drawCircularPhoto(Canvas(icon), image, RectF(4 * density, 4 * density, 46 * density, 46 * density), 1.5f * density)
                image?.recycle()
                photo.id to icon
            }
        }
        value = bitmaps.mapValues { (_, bitmap) -> BitmapDescriptorFactory.fromBitmap(bitmap).also { bitmap.recycle() } }
    }
    return photos.mapNotNull { photo ->
        val latitude = photo.latitude ?: return@mapNotNull null
        val longitude = photo.longitude ?: return@mapNotNull null
        if (!latitude.isFinite() || !longitude.isFinite() || latitude !in -90.0..90.0 || longitude !in -180.0..180.0) return@mapNotNull null
        // Wait for a thumbnail or camera placeholder, rather than flashing a generic map pin.
        val icon = icons[photo.id] ?: return@mapNotNull null
        MapRouteMarker(photo.id, MapCoordinate(latitude, longitude), photo.title,
            selected = photo.id == selectedId, icon = icon, anchor = Offset(.5f, .92f))
    }
}

internal fun drawCircularPhoto(canvas: Canvas, image: Bitmap?, frame: RectF, border: Float) {
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = Color.WHITE
        setShadowLayer(border * 3, 0f, border * 1.3f, Color.argb(90, 0, 0, 0))
    }
    canvas.drawOval(frame, paint)
    paint.clearShadowLayer()
    val inner = RectF(frame).apply { inset(border, border) }
    val saved = canvas.save()
    canvas.clipPath(Path().apply { addOval(inner, Path.Direction.CW) })
    if (image == null) {
        canvas.drawColor(Color.rgb(255, 149, 0))
        paint.color = Color.WHITE
        val centerX = frame.centerX()
        val centerY = frame.centerY()
        val radius = frame.width() * .13f
        canvas.drawRoundRect(RectF(centerX - radius * 2, centerY - radius * 1.3f, centerX + radius * 2, centerY + radius * 1.3f), radius * .3f, radius * .3f, paint)
        paint.color = Color.rgb(255, 149, 0)
        canvas.drawCircle(centerX, centerY, radius * .8f, paint)
    } else {
        paint.isFilterBitmap = true
        val scale = maxOf(frame.width() / image.width, frame.height() / image.height)
        val width = image.width * scale
        val height = image.height * scale
        canvas.drawBitmap(image, null, RectF(frame.centerX() - width / 2, frame.centerY() - height / 2, frame.centerX() + width / 2, frame.centerY() + height / 2), paint)
    }
    canvas.restoreToCount(saved)
}
