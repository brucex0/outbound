package com.plainstride.outbound.feature.activity

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Point
import android.graphics.RectF
import com.google.android.gms.maps.GoogleMap
import com.google.android.gms.maps.CameraUpdateFactory
import com.google.android.gms.maps.model.LatLng
import com.google.android.gms.maps.model.LatLngBounds
import com.plainstride.outbound.core.model.activity.SavedActivity
import kotlin.math.*

data class ActivityShareMapSnapshot(val bitmap: Bitmap, val segments: List<List<Point>>, val photoPoints: Map<String, Point>)

internal fun fitShareMap(map: GoogleMap, activity: SavedActivity, width: Int, height: Int) {
    // Match iOS's portrait Mercator bounds and 18%/22% route margins.
    val points = activity.track
    val coordinates = points.map { LatLng(it.latitude, it.longitude) }
    val minX = coordinates.minOf { it.longitude / 360 + .5 }
    val maxX = coordinates.maxOf { it.longitude / 360 + .5 }
    fun mercatorY(latitude: Double): Double = (1 - ln(tan(Math.PI / 4 + Math.toRadians(latitude.coerceIn(-85.0, 85.0)) / 2)) / Math.PI) / 2
    val minY = coordinates.minOf { mercatorY(it.latitude) }
    val maxY = coordinates.maxOf { mercatorY(it.latitude) }
    val mapPoint = 1.0 / 268_435_456
    var spanX = maxX - minX + mapPoint
    var spanY = maxY - minY + mapPoint
    if (spanX < 300 * mapPoint) spanX += 600 * mapPoint
    if (spanY < 300 * mapPoint) spanY += 600 * mapPoint
    val aspect = width.toDouble() / height
    if (spanX / spanY > aspect) spanY = spanX / aspect else spanX = spanY * aspect
    spanX *= 1.36
    spanY *= 1.44
    val x = (minX + maxX) / 2
    val y = (minY + maxY) / 2
    fun latitude(y: Double) = Math.toDegrees(atan(sinh(Math.PI * (1 - 2 * y))))
    val bounds = LatLngBounds(LatLng(latitude(y + spanY / 2), (x - spanX / 2 - .5) * 360),
        LatLng(latitude(y - spanY / 2), (x + spanX / 2 - .5) * 360))
    map.moveCamera(CameraUpdateFactory.newLatLngBounds(bounds, width, height, 0))
}

internal fun captureShareMap(map: GoogleMap, activity: SavedActivity, bitmap: Bitmap): ActivityShareMapSnapshot {
    val segments = mutableListOf<MutableList<Point>>()
    activity.track.forEach { point ->
        if (segments.isEmpty() || point.startsNewSegment) segments += mutableListOf<Point>()
        segments.last() += map.projection.toScreenLocation(LatLng(point.latitude, point.longitude))
    }
    val photos = activity.photos.mapNotNull { photo ->
        val lat = photo.latitude ?: return@mapNotNull null
        val lon = photo.longitude ?: return@mapNotNull null
        if (!lat.isFinite() || !lon.isFinite() || lat !in -90.0..90.0 || lon !in -180.0..180.0) return@mapNotNull null
        photo.id to map.projection.toScreenLocation(LatLng(lat, lon))
    }.toMap()
    return ActivityShareMapSnapshot(bitmap, segments, photos)
}

internal fun drawShareMap(snapshot: ActivityShareMapSnapshot, assets: ActivityShareAssets): Bitmap {
    val output = Bitmap.createBitmap(1080, 1920, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(output)
    canvas.scale(1080f / snapshot.bitmap.width, 1920f / snapshot.bitmap.height)
    val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { isFilterBitmap = true }
    canvas.drawBitmap(snapshot.bitmap, 0f, 0f, paint)
    val path = Path()
    snapshot.segments.forEach { segment ->
        segment.forEachIndexed { index, point ->
            if (index == 0) path.moveTo(point.x.toFloat(), point.y.toFloat()) else path.lineTo(point.x.toFloat(), point.y.toFloat())
        }
    }
    paint.style = Paint.Style.STROKE
    paint.strokeCap = Paint.Cap.ROUND
    paint.strokeJoin = Paint.Join.ROUND
    paint.color = Color.argb(71, 0, 0, 0)
    paint.strokeWidth = 15f
    canvas.drawPath(path, paint)
    paint.color = Color.rgb(255, 149, 0)
    paint.strokeWidth = 10f
    canvas.drawPath(path, paint)
    paint.style = Paint.Style.FILL
    val endpoints = listOfNotNull(snapshot.segments.firstOrNull()?.firstOrNull()?.let { it to Color.rgb(52, 199, 89) },
        snapshot.segments.lastOrNull()?.lastOrNull()?.let { it to Color.rgb(255, 45, 85) })
    endpoints.forEach { (point, color) ->
        paint.color = Color.WHITE
        canvas.drawCircle(point.x.toFloat(), point.y.toFloat(), 14f, paint)
        paint.color = color
        canvas.drawCircle(point.x.toFloat(), point.y.toFloat(), 9f, paint)
    }
    snapshot.photoPoints.forEach { (id, point) ->
        if (point.x < 60 || point.x > snapshot.bitmap.width - 60 || point.y < 120 || point.y > snapshot.bitmap.height - 120) return@forEach
        val image = assets.photos[id] ?: return@forEach
        val left = (point.x - 72f).coerceIn(6f, snapshot.bitmap.width - 150f)
        val top = (point.y - 144f).coerceIn(6f, snapshot.bitmap.height - 150f)
        drawCircularPhoto(canvas, image, RectF(left, top, left + 144, top + 144), 4f)
    }
    return output
}
