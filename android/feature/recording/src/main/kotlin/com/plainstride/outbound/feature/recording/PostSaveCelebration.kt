package com.plainstride.outbound.feature.recording

import android.animation.ValueAnimator
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.spring
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlin.math.cos
import kotlin.math.hypot
import kotlin.math.sin

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
    val accessibilityLabel = stringResource(R.string.recording_post_save_accessibility)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(PostcardBackdrop)
            .semantics { contentDescription = accessibilityLabel }
            .padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        PostSaveCelebrationCard(
            track = track,
            sessionKey = sessionKey,
            modifier = Modifier.fillMaxWidth().widthIn(max = 360.dp).height(250.dp),
        )

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

@Composable
fun PostSaveCelebrationCard(
    track: List<RecordedLocationSample>,
    sessionKey: String,
    modifier: Modifier = Modifier,
) {
    val accessibilityLabel = stringResource(R.string.recording_post_save_accessibility)
    val reducedMotion = remember { !ValueAnimator.areAnimatorsEnabled() }
    val progress = remember(sessionKey) { Animatable(if (reducedMotion) 1f else 0f) }
    val sundaeProgress = remember(sessionKey) { Animatable(if (reducedMotion) 1f else 0f) }
    val sundaeOpacity = remember(sessionKey) { Animatable(1f) }
    val points = remember(track) { normalizedRoute(track) }

    LaunchedEffect(sessionKey, reducedMotion) {
        if (!reducedMotion) {
            progress.animateTo(1f, tween(durationMillis = 1_400))
            sundaeProgress.animateTo(1f, spring(dampingRatio = 0.58f, stiffness = 420f))
        }
        kotlinx.coroutines.delay(2_000)
        sundaeOpacity.animateTo(0f, tween(durationMillis = 350))
    }

    Box(
        modifier = modifier
            .shadow(20.dp, RoundedCornerShape(28.dp), ambientColor = Color(0xFF3B2B1F).copy(alpha = 0.14f))
            .clip(RoundedCornerShape(28.dp))
            .background(PostcardPaper)
            .semantics { contentDescription = accessibilityLabel },
    ) {
        Canvas(Modifier.fillMaxSize()) {
            val pixelPoints = points.map { Offset(it.x * size.width, it.y * size.height) }
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

            val finish = pixelPoints.lastOrNull()
            val runner = pointOnPath(pixelPoints, progress.value)
            if (runner != null && finish != null && progress.value > 0.04f) {
                drawRunner(runner)
            }
            pixelPoints.firstOrNull()?.let { drawCircle(PostcardNavy, radius = 5.5.dp.toPx(), center = it) }
            finish?.let { drawCircle(PostcardNavy, radius = 5.5.dp.toPx(), center = it) }

            if (finish != null && sundaeProgress.value > 0f && sundaeOpacity.value > 0f) {
                val inset = 46.dp.toPx()
                val burstCenter = Offset(
                    x = (finish.x).coerceIn(inset, size.width - inset),
                    y = (finish.y - 33.dp.toPx()).coerceIn(inset, size.height - inset),
                )
                drawSundaeBurst(burstCenter, sundaeProgress.value, sundaeOpacity.value)
            }
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

private fun pointOnPath(points: List<Offset>, fraction: Float): Offset? {
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
            return Offset(start.x + (end.x - start.x) * t, start.y + (end.y - start.y) * t)
        }
        remaining -= length
    }
    return points.last()
}

private fun DrawScope.drawRunner(center: Offset) {
    val runnerWidth = 48.dp.toPx()
    val runnerHeight = 58.dp.toPx()
    val anchor = Offset(center.x - runnerWidth / 2, center.y - runnerHeight / 2)
    fun p(x: Float, y: Float) = Offset(anchor.x + x.dp.toPx(), anchor.y + y.dp.toPx())

    drawCircle(PostcardCream, 6.dp.toPx(), p(24f, 5f))
    val cap = Path().apply {
        val start = p(17f, 11f)
        val control = p(24f, 3f)
        val end = p(32f, 9f)
        moveTo(start.x, start.y)
        quadraticTo(control.x, control.y, end.x, end.y)
        lineTo(p(34f, 11f).x, p(34f, 11f).y)
    }
    drawPath(cap, PostcardOrange, style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))

    val body = Path().apply { moveTo(p(24f, 19f).x, p(24f, 19f).y); lineTo(p(23f, 33f).x, p(23f, 33f).y) }
    drawPath(body, PostcardOrange, style = Stroke(width = 8.dp.toPx(), cap = StrokeCap.Round))

    val limbs = Path().apply {
        moveTo(p(23f, 23f).x, p(23f, 23f).y); lineTo(p(14f, 15f).x, p(14f, 15f).y)
        moveTo(p(25f, 23f).x, p(25f, 23f).y); lineTo(p(34f, 14f).x, p(34f, 14f).y)
        moveTo(p(23f, 32f).x, p(23f, 32f).y); lineTo(p(14f, 43f).x, p(14f, 43f).y); lineTo(p(9f, 43f).x, p(9f, 43f).y)
        moveTo(p(25f, 32f).x, p(25f, 32f).y); lineTo(p(34f, 40f).x, p(34f, 40f).y); lineTo(p(39f, 38f).x, p(39f, 38f).y)
    }
    drawPath(limbs, PostcardNavy, style = Stroke(width = 4.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
}

private fun DrawScope.drawSundaeBurst(center: Offset, progress: Float, opacity: Float) {
    val sprinkles = listOf(Color(0xFFF55975), Color(0xFF40AE91), Color(0xFFFFAE33), Color(0xFF7666C8))
    val angles = listOf(-150f, -112f, -72f, -28f, 18f, 58f, 105f, 148f)
    angles.forEachIndexed { index, degrees ->
        val angle = Math.toRadians(degrees.toDouble())
        val startRadius = 18.dp.toPx()
        val endRadius = 37.dp.toPx() * progress
        val start = Offset(center.x + cos(angle).toFloat() * startRadius, center.y + sin(angle).toFloat() * startRadius)
        val end = Offset(center.x + cos(angle).toFloat() * endRadius, center.y + sin(angle).toFloat() * endRadius)
        drawLine(sprinkles[index % sprinkles.size].copy(alpha = opacity), start, end, strokeWidth = 4.dp.toPx(), cap = StrokeCap.Round)
    }

    val cone = Path().apply {
        moveTo(center.x - 16.dp.toPx(), center.y - 3.dp.toPx())
        lineTo(center.x + 16.dp.toPx(), center.y - 3.dp.toPx())
        lineTo(center.x + 2.dp.toPx(), center.y + 33.dp.toPx())
        quadraticTo(center.x, center.y + 36.dp.toPx(), center.x - 2.dp.toPx(), center.y + 33.dp.toPx())
        close()
    }
    drawPath(cone, Color(0xFFCC7A3D).copy(alpha = opacity))

    val scoops = listOf(
        Triple(-10f, -10f, Color(0xFF8CC9A1)),
        Triple(2f, -18f, Color(0xFFFC8A9B)),
        Triple(13f, -8f, Color(0xFFFFD580)),
    )
    scoops.forEachIndexed { index, (x, y, color) ->
        val radius = listOf(13f, 15f, 12f)[index].dp.toPx()
        drawCircle(color.copy(alpha = opacity), radius, Offset(center.x + x.dp.toPx(), center.y + y.dp.toPx()))
    }

    val stem = Path().apply {
        moveTo(center.x + 8.dp.toPx(), center.y - 30.dp.toPx())
        quadraticTo(center.x + 15.dp.toPx(), center.y - 34.dp.toPx(), center.x + 17.dp.toPx(), center.y - 27.dp.toPx())
    }
    drawPath(stem, Color(0xFF337A4F).copy(alpha = opacity), style = Stroke(width = 2.dp.toPx(), cap = StrokeCap.Round))
    drawCircle(Color(0xFFE0344D).copy(alpha = opacity), 4.5.dp.toPx(), Offset(center.x + 7.5.dp.toPx(), center.y - 31.5.dp.toPx()))
}
