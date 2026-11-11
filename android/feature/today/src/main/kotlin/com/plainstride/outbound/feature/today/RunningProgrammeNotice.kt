package com.plainstride.outbound.feature.today

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.RunningProgrammeProgress

@Composable
internal fun RunningProgrammeNotice(progress: RunningProgrammeProgress) {
    val source = progress.programme
    val total = progress.nominalSourceWeeks
    val needsReview = progress.programmeDoseStatus == "needs_review" || progress.programmeTimelineStatus == "needs_review"
    if ((source == null || total == null) && !needsReview) return
    val remaining = progress.minimumRemainingCalendarWeeks
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        if (source != null && total != null) {
            Text(stringResource(R.string.planning_programme_source_week, source.weekIndex, total), style = MaterialTheme.typography.titleSmall)
            when {
                source.status == "completed" -> Text(stringResource(R.string.planning_programme_preparation_complete), style = MaterialTheme.typography.bodySmall)
                progress.programmeDoseStatus == "needs_review" -> Text(stringResource(if (progress.programmeReviewReason == "conservative_recipe_fit") R.string.planning_programme_recipe_review else R.string.planning_programme_schedule_review), style = MaterialTheme.typography.bodySmall)
                progress.programmeTimelineStatus == "needs_review" -> Text(stringResource(R.string.planning_programme_timeline_review), style = MaterialTheme.typography.bodySmall)
                remaining != null -> Text(stringResource(R.string.planning_programme_minimum_remaining, remaining), style = MaterialTheme.typography.bodySmall)
            }
            Text(stringResource(R.string.planning_programme_exposure_notice), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
        } else {
            if (progress.programmeDoseStatus == "needs_review") Text(stringResource(R.string.planning_running_schedule_conflict), style = MaterialTheme.typography.bodySmall)
            Text(stringResource(if (progress.programmeDoseStatus == "needs_review") R.string.planning_programme_schedule_review else R.string.planning_programme_timeline_review), style = MaterialTheme.typography.bodySmall)
        }
    }
}
