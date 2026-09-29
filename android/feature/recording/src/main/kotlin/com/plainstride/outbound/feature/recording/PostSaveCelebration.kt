package com.plainstride.outbound.feature.recording

import android.animation.ValueAnimator
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay
import kotlin.math.hypot

private val PostcardBackdrop = Color(0xFFFFF0DB)
private val PostcardPaper = Color(0xFFFFFCF2)
private val PostcardOrange = Color(0xFFF26429)
private val PostcardNavy = Color(0xFF1F3347)
private val PostcardCream = Color(0xFFFFD796)

@Composable
fun PostSaveCelebration(
    track: List<RecordedLocationSample>,
    sessionKey: String,
    onDone: () -> Unit,
) {
    val context = LocalContext.current
    val reducedMotion = remember { !ValueAnimator.areAnimatorsEnabled() }
    val progress = remember(sessionKey) { Animatable(if (reducedMotion) 1f else 0f) }
    val points = remember(track) { normalizedRoute(track) }

    LaunchedEffect(sessionKey, reducedMotion) {
        if (!reducedMotion) progress.animateTo(1f, tween(durationMillis = 1_400))
        delay(4_000)
        onDone()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(PostcardBackdrop)
            .semantics { contentDescription = context.getString(R.string.recording_post_save_accessibility) }
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .widthIn(max = 360.dp)
                .height(250.dp)
                .shadow(20.dp, RoundedCornerShape(28.dp), ambientColor = Color(0xFF3B2B1F).copy(alpha = 0.14f))
                .clip(RoundedCornerShape(28.dp))
                .background(PostcardPaper),
        ) {
            Canvas(Modifier.fillMaxSize()) {
                val pixelPoints = points.map { androidx.compose.ui.geometry.Offset(it.x * size.width, it.y * size.height) }
                val route = Path().apply {
                    pixelPoints.firstOrNull()?.let { moveTo(it.x, it.y) }
                    pixelPoints.drop(1).forEach { lineTo(it.x, it.y) }
                }
                val measure = PathMeasure().apply { setPath(route, false) }
                val partialRoute = Path()
                measure.getSegment(0f, measure.length * progress.value, partialRoute, true)
                drawPath(
                    path = partialRoute,
                    color = PostcardOrange,
                    style = Stroke(width = 7.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round),
                )

                val runner = pointOnPath(pixelPoints, progress.value)
                if (runner != null && progress.value > 0.04f) drawRunner(runner)

                pixelPoints.firstOrNull()?.let { drawCircle(PostcardNavy, radius = 5.5.dp.toPx(), center = it) }
                pixelPoints.lastOrNull()?.let { drawCircle(PostcardNavy, radius = 5.5.dp.toPx(), center = it) }
            }
        }

        Spacer(Modifier.height(22.dp))
        Text(
            text = stringResource(R.string.recording_post_save_message),
            color = PostcardNavy,
            fontSize = 20.sp,
            lineHeight = 26.sp,
            fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold,
        )
        Spacer(Modifier.height(22.dp))
        Button(
            onClick = onDone,
            modifier = Modifier.widthIn(min = 112.dp).height(48.dp),
            shape = RoundedCornerShape(50),
            colors = ButtonDefaults.buttonColors(containerColor = PostcardOrange, contentColor = Color.White),
        ) {
            Text(stringResource(R.string.recording_post_save_done), fontSize = 16.sp, fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold)
        }
    }
}

private data class NormalizedPoint(val x: Float, val y: Float)

private fun normalizedRoute(track: List<RecordedLocationSample>): List<NormalizedPoint> {
    if (track.size < 2) return listOf(
        NormalizedPoint(0.08f, 0.74f), NormalizedPoint(0.24f, 0.54f), NormalizedPoint(0.39f, 0.64f),
        NormalizedPoint(0.57f, 0.35f), NormalizedPoint(0.74f, 0.45f), NormalizedPoint(0.92f, 0.20f),
    )

    val minLongitude = track.minOf { it.longitude }
    val maxLongitude = track.maxOf { it.longitude }
    val minLatitude = track.minOf { it.latitude }
    val maxLatitude = track.maxOf { it.latitude }
    val longitudeSpan = (maxLongitude - minLongitude).coerceAtLeast(0.000001)
    val latitudeSpan = (maxLatitude - minLatitude).coerceAtLeast(0.000001)
    val scale = minOf(0.82 / longitudeSpan, 0.58 / latitudeSpan)
    val width = longitudeSpan * scale
    val height = latitudeSpan * scale
    val xOffset = (1.0 - width) / 2.0
    val yOffset = (1.0 - height) / 2.0

    return track.map { point ->
        NormalizedPoint(
            x = (xOffset + (point.longitude - minLongitude) * scale).toFloat(),
            y = (1.0 - yOffset - (point.latitude - minLatitude) * scale).toFloat(),
        )
    }
}

private fun pointOnPath(points: List<androidx.compose.ui.geometry.Offset>, fraction: Float): androidx.compose.ui.geometry.Offset? {
    if (points.isEmpty()) return null
    if (points.size == 1) return points.first()
    val lengths = points.zipWithNext { a, b -> hypot(b.x - a.x, b.y - a.y) }
    val total = lengths.sum()
    if (total <= 0f) return points.first()
    var remaining = fraction.coerceIn(0f, 1f) * total
    lengths.forEachIndexed { index, length ->
        if (remaining <= length) {
            val start = points[index]
            val end = points[index + 1]
            val t = if (length == 0f) 0f else remaining / length
            return androidx.compose.ui.geometry.Offset(
                start.x + (end.x - start.x) * t,
                start.y + (end.y - start.y) * t,
            )
        }
        remaining -= length
    }
    return points.last()
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawRunner(center: androidx.compose.ui.geometry.Offset) {
    val runnerWidth = 48.dp.toPx()
    val runnerHeight = 58.dp.toPx()
    val headRadius = 6.dp.toPx()
    val limbStroke = 4.dp.toPx()
    val bodyStroke = 8.dp.toPx()
    val scaleX = runnerWidth / 48.dp.toPx()
    val scaleY = runnerHeight / 58.dp.toPx()
    val anchor = androidx.compose.ui.geometry.Offset(center.x - runnerWidth / 2, center.y - runnerHeight / 2)
    fun p(x: Float, y: Float) = androidx.compose.ui.geometry.Offset(anchor.x + x * scaleX, anchor.y + y * scaleY)

    drawCircle(PostcardCream, headRadius, p(24f, 5f))
    val cap = Path().apply {
        val start = p(17f, 11f)
        val control = p(24f, 3f)
        val end = p(32f, 9f)
        val finish = p(34f, 11f)
        moveTo(start.x, start.y)
        quadraticTo(control.x, control.y, end.x, end.y)
        lineTo(finish.x, finish.y)
    }
    drawPath(cap, PostcardOrange, style = Stroke(width = limbStroke, cap = StrokeCap.Round, join = StrokeJoin.Round))

    val body = Path().apply {
        val start = p(24f, 19f)
        val end = p(23f, 33f)
        moveTo(start.x, start.y)
        lineTo(end.x, end.y)
    }
    drawPath(body, PostcardOrange, style = Stroke(width = bodyStroke, cap = StrokeCap.Round))

    val limbs = Path().apply {
        moveTo(p(23f, 23f).x, p(23f, 23f).y); lineTo(p(14f, 15f).x, p(14f, 15f).y)
        moveTo(p(25f, 23f).x, p(25f, 23f).y); lineTo(p(34f, 14f).x, p(34f, 14f).y)
        moveTo(p(23f, 32f).x, p(23f, 32f).y); lineTo(p(14f, 43f).x, p(14f, 43f).y); lineTo(p(9f, 43f).x, p(9f, 43f).y)
        moveTo(p(25f, 32f).x, p(25f, 32f).y); lineTo(p(34f, 40f).x, p(34f, 40f).y); lineTo(p(39f, 38f).x, p(39f, 38f).y)
    }
    drawPath(limbs, PostcardNavy, style = Stroke(width = limbStroke, cap = StrokeCap.Round, join = StrokeJoin.Round))
}
