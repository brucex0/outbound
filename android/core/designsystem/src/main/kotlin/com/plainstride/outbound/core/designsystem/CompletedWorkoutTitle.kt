package com.plainstride.outbound.core.designsystem

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.CompletedWorkoutDisplayContext

/** Used only by private recording/history surfaces, never exported titles. */
@Composable
fun CompletedWorkoutTitle(
    title: String,
    context: CompletedWorkoutDisplayContext?,
    modifier: Modifier = Modifier,
    titleStyle: TextStyle = MaterialTheme.typography.titleMedium,
    titleWeight: FontWeight? = null,
    titleColor: Color = LocalContentColor.current,
    fallbackMaxLines: Int = 1,
) {
    Column(modifier.fillMaxWidth().semantics(mergeDescendants = true) {}, verticalArrangement = Arrangement.spacedBy(4.dp)) {
        Text(title, style = titleStyle, fontWeight = titleWeight, color = titleColor,
            maxLines = if (context == null) fallbackMaxLines else 1, overflow = TextOverflow.Ellipsis)
        if (context != null) {
            Text(stringResource(R.string.completed_workout_plan_day_week, planTitle(context.planTitleKey), context.dayNumber, context.weekNumber),
                style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant,
                maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
    }
}

@Composable
private fun planTitle(key: String): String = stringResource(when (key) {
    "training_plan.title.consistency" -> R.string.completed_plan_consistency
    "training_plan.title.comeback" -> R.string.completed_plan_comeback
    "training_plan.title.5k" -> R.string.completed_plan_5k
    "training_plan.title.base_30" -> R.string.completed_plan_base_30
    "training_plan.title.10k" -> R.string.completed_plan_10k
    "training_plan.title.10mile" -> R.string.completed_plan_10mile
    "training_plan.title.half" -> R.string.completed_plan_half
    "training_plan.title.marathon" -> R.string.completed_plan_marathon
    "training_plan.title.half_hansons_beginner" -> R.string.completed_plan_half_hansons_beginner
    "training_plan.title.half_hansons_advanced" -> R.string.completed_plan_half_hansons_advanced
    "training_plan.title.adaptive_consistency" -> R.string.completed_plan_adaptive_consistency
    "training_plan.title.adaptive_comeback" -> R.string.completed_plan_adaptive_comeback
    "training_plan.title.adaptive_5k" -> R.string.completed_plan_adaptive_5k
    "training_plan.title.adaptive_10k" -> R.string.completed_plan_adaptive_10k
    "training_plan.title.adaptive_10mile" -> R.string.completed_plan_adaptive_10mile
    "training_plan.title.adaptive_half" -> R.string.completed_plan_adaptive_half
    "training_plan.title.adaptive_marathon" -> R.string.completed_plan_adaptive_marathon
    else -> R.string.completed_workout_plan_fallback
})
