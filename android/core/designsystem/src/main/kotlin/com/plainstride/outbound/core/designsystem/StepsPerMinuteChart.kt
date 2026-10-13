package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.activity.ActivityCadenceSummary

@Composable
fun StepsPerMinuteChart(summary: ActivityCadenceSummary, modifier: Modifier = Modifier, onExposed: () -> Unit = {}) {
    val description = listOfNotNull(
        summary.averageStepsPerMinute?.let { stringResource(R.string.running_cadence_average_format, it) },
        summary.maxStepsPerMinute?.let { stringResource(R.string.running_cadence_maximum_format, it) },
    ).joinToString(" • ")
    val numberLocale = LocalConfiguration.current.locales[0]
    val accent = MaterialTheme.colorScheme.primary
    val grid = MaterialTheme.colorScheme.outlineVariant
    LaunchedEffect(Unit) { onExposed() }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(stringResource(R.string.running_cadence_live_label), style = MaterialTheme.typography.titleMedium)
        Text(description, style = MaterialTheme.typography.bodySmall)
        val samples = summary.samples.filter { it.elapsedSeconds >= 0 && it.stepsPerMinute in 1..300 }.sortedBy { it.elapsedSeconds }
        if (samples.size > 1) {
            val low = (samples.minOf { it.stepsPerMinute } - 10).coerceAtLeast(0)
            val high = samples.maxOf { it.stepsPerMinute } + 10
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("$low–$high", style = MaterialTheme.typography.labelSmall)
                Text(stringResource(R.string.running_cadence_unit), style = MaterialTheme.typography.labelSmall)
            }
            Canvas(Modifier.fillMaxWidth().height(140.dp).semantics { contentDescription = description }) {
                drawLine(grid, Offset(0f, size.height), Offset(size.width, size.height))
                val duration = samples.maxOf { it.elapsedSeconds }.coerceAtLeast(1)
                fun point(index: Int): Offset {
                    val sample = samples[index]
                    return Offset(size.width * sample.elapsedSeconds / duration,
                        size.height * (1f - (sample.stepsPerMinute - low).toFloat() / (high - low)))
                }
                samples.indices.forEach { index ->
                    val current = point(index)
                    drawCircle(accent, 2.dp.toPx(), current)
                    if (index > 0 && samples[index - 1].segment == samples[index].segment) {
                        drawLine(accent, point(index - 1), current, 2.dp.toPx())
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text("0", style = MaterialTheme.typography.labelSmall)
                Text(String.format(numberLocale, "%.1f", samples.maxOf { it.elapsedSeconds } / 60.0), style = MaterialTheme.typography.labelSmall)
            }
            Text(stringResource(R.string.running_cadence_time_axis), style = MaterialTheme.typography.labelSmall)
        }
        Text(stringResource(R.string.running_cadence_coverage), style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant)
    }
}
