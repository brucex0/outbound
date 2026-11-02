package com.plainstride.outbound.feature.activity

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.plainstride.outbound.core.model.activity.MeasurementUnitSystem
import com.plainstride.outbound.core.model.activity.SessionFormatting
import kotlin.math.roundToInt

data class ActivitySplitDisplay(val number: Int, val paceSecondsPerKilometer: Double, val elevationChangeMeters: Double?)

/** A common table for stored and share-safe Social splits. Timing is supplied by each source. */
@Composable
fun ActivitySplitChart(
    splits: List<ActivitySplitDisplay>,
    unitSystem: MeasurementUnitSystem,
    modifier: Modifier = Modifier,
    horizontalPadding: androidx.compose.ui.unit.Dp = 16.dp,
    onViewed: (Int) -> Unit = {},
) {
    if (splits.isEmpty()) return
    var expanded by rememberSaveable { mutableStateOf(false) }
    val fastest = splits.map { it.paceSecondsPerKilometer }.filter { it.isFinite() && it > 0 }.minOrNull() ?: 0.0
    val showElevation = splits.any { it.elevationChangeMeters != null }
    val unit = if (unitSystem == MeasurementUnitSystem.metric) "km" else "mi"
    val fontScale = LocalDensity.current.fontScale.coerceAtLeast(1f)
    val numberWidth = 30.dp * fontScale
    val paceWidth = 54.dp * fontScale
    val elevationWidth = 42.dp * fontScale
    val rowStyle = TextStyle(fontSize = 12.sp, lineHeight = 15.sp, fontFeatureSettings = "tnum")
    val headerStyle = TextStyle(fontSize = 11.sp, lineHeight = 13.sp, fontWeight = FontWeight.SemiBold)
    val secondary = MaterialTheme.colorScheme.onSurfaceVariant

    Column(modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 48.dp).clickable {
                expanded = !expanded
                if (expanded) onViewed(splits.size)
            }.padding(horizontal = horizontalPadding, vertical = 12.dp).semantics { heading() },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(stringResource(R.string.activity_splits_title), Modifier.weight(1f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
            Text("${splits.size} $unit", style = rowStyle, color = secondary)
            Spacer(Modifier.width(6.dp))
            Icon(if (expanded) Icons.Outlined.KeyboardArrowUp else Icons.Outlined.KeyboardArrowDown, null,
                Modifier.size(14.dp), tint = secondary)
        }
        AnimatedVisibility(expanded, enter = fadeIn(), exit = fadeOut()) {
            Column(Modifier.padding(bottom = 10.dp)) {
                Row(Modifier.fillMaxWidth().padding(horizontal = horizontalPadding).padding(top = 4.dp, bottom = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(unit.uppercase(), Modifier.width(numberWidth), style = headerStyle, color = secondary)
                    Text(stringResource(R.string.activity_splits_pace), Modifier.width(paceWidth), style = headerStyle, color = secondary)
                    Spacer(Modifier.weight(1f))
                    if (showElevation) Text(stringResource(R.string.activity_splits_elev), Modifier.width(elevationWidth),
                        style = headerStyle, color = secondary, textAlign = TextAlign.End)
                }
                splits.forEach { split ->
                    Row(Modifier.fillMaxWidth().padding(horizontal = horizontalPadding, vertical = 3.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(split.number.toString(), Modifier.width(numberWidth), style = rowStyle, color = secondary)
                        val pace = SessionFormatting.pace(split.paceSecondsPerKilometer, unitSystem)
                        Text(pace?.let { "%d:%02d /%s".format(it.minutes, it.seconds, unit) } ?: "--",
                            Modifier.width(paceWidth), style = rowStyle, maxLines = 1)
                        BoxWithConstraints(Modifier.weight(1f).height(18.dp), contentAlignment = Alignment.CenterStart) {
                            val fraction = splitPaceFraction(split.paceSecondsPerKilometer, fastest)
                            val width = (maxWidth * fraction.toFloat()).coerceAtLeast(18.dp).coerceAtMost(maxWidth)
                            Box(Modifier.width(width).height(14.dp).clip(CircleShape).background(Color(0xFF007AFF)))
                        }
                        if (showElevation) {
                            val elevation = split.elevationChangeMeters?.let {
                                val value = SessionFormatting.elevation(it, unitSystem).value.roundToInt()
                                if (value > 0) "+$value" else value.toString()
                            } ?: "--"
                            Text(elevation, Modifier.width(elevationWidth), style = rowStyle, color = secondary, textAlign = TextAlign.End)
                        }
                    }
                }
            }
        }
    }
}
