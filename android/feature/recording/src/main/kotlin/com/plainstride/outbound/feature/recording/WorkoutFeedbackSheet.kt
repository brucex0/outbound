package com.plainstride.outbound.feature.recording

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Chat
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp

// The caller owns draft selections and submission; dismissal retains edits.
data class WorkoutGuidanceReport(val spokenCueCount: Int = 0, val helpfulCueCount: Int = 0)
enum class WorkoutGuidanceFeedback(val wireValue: String) {
    HELPFUL("helpful"), TOO_MUCH("too_much"), TOO_GENERIC("too_generic"), BAD_TIMING("bad_timing")
}

@Composable
fun WorkoutFeedbackEntryPoint(hasFeedback: Boolean, enabled: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Surface(onClick = onClick, enabled = enabled, modifier = modifier.fillMaxWidth(), shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Row(Modifier.padding(16.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(Icons.AutoMirrored.Filled.Chat, contentDescription = null)
            Text(stringResource(R.string.recording_feedback_title), style = MaterialTheme.typography.titleSmall, modifier = Modifier.weight(1f))
            if (hasFeedback) Icon(Icons.Default.CheckCircle, stringResource(R.string.recording_feedback_added), tint = MaterialTheme.colorScheme.primary)
            Icon(Icons.AutoMirrored.Filled.KeyboardArrowRight, contentDescription = null)
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalLayoutApi::class)
@Composable
fun WorkoutFeedbackSheet(
    selected: ReflectionChoice?,
    continuationCapacity: ContinuationCapacity?,
    onSelect: (ReflectionChoice) -> Unit,
    onCapacitySelect: (ContinuationCapacity) -> Unit,
    onDismiss: () -> Unit,
    sessionEffortRating: Int? = null,
    onSessionEffortRating: (Int?) -> Unit = {},
    showsSessionEffort: Boolean = true,
    guidanceReport: WorkoutGuidanceReport = WorkoutGuidanceReport(),
    selectedGuidanceFeedback: WorkoutGuidanceFeedback? = null,
    onGuidanceFeedbackSelect: (WorkoutGuidanceFeedback) -> Unit = {},
    // Only DEBUG fixture callers supply controls for actual app preference review.
    previewControls: (@Composable () -> Unit)? = null,
) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true), dragHandle = null) {
        Row(Modifier.fillMaxWidth().heightIn(min = 56.dp).padding(horizontal = 12.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(stringResource(R.string.recording_feedback_title), style = MaterialTheme.typography.titleMedium, modifier = Modifier.weight(1f))
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.recording_feedback_done)) }
        }
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 20.dp, vertical = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
            if (BuildConfig.DEBUG) previewControls?.invoke()
            if (showsSessionEffort) FeedbackCard {
                Text(stringResource(R.string.recording_session_effort_header), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                Text(stringResource(R.string.recording_session_effort_detail), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    (1..10).forEach { rating ->
                        val description = stringResource(R.string.recording_session_effort_accessibility, rating)
                        FilterChip(selected = sessionEffortRating == rating, onClick = { onSessionEffortRating(rating) },
                            label = { Text(rating.toString()) }, modifier = Modifier.heightIn(min = 48.dp).widthIn(min = 48.dp).semantics { contentDescription = description })
                    }
                }
                sessionEffortRating?.let { rating ->
                    Text(stringResource(R.string.recording_session_effort_selected, rating), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    TextButton(onClick = { onSessionEffortRating(null) }) { Text(stringResource(R.string.recording_session_effort_clear)) }
                }
            }
            FeedbackCard {
                Text(stringResource(R.string.recording_workout_fit_header), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                FeedbackChoiceGroup(
                    labels = ReflectionChoice.entries.map { choice ->
                        stringResource(when (choice) {
                            ReflectionChoice.EASY -> R.string.recording_reflection_easy
                            ReflectionChoice.ABOUT_RIGHT -> R.string.recording_reflection_about_right
                            ReflectionChoice.TOO_HARD -> R.string.recording_reflection_too_hard
                        })
                    },
                    selectedIndex = ReflectionChoice.entries.indexOf(selected),
                    onSelect = { onSelect(ReflectionChoice.entries[it]) },
                )
                if (selected == ReflectionChoice.EASY) {
                    Text(stringResource(R.string.recording_capacity_prompt), style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
                    FeedbackChoiceGroup(
                        labels = ContinuationCapacity.entries.map { capacity ->
                            stringResource(when (capacity) {
                                ContinuationCapacity.NONE -> R.string.recording_capacity_none
                                ContinuationCapacity.TEN_MINUTES -> R.string.recording_capacity_ten_minutes
                                ContinuationCapacity.MUCH_LONGER -> R.string.recording_capacity_much_longer
                            })
                        },
                        selectedIndex = ContinuationCapacity.entries.indexOf(continuationCapacity),
                        onSelect = { onCapacitySelect(ContinuationCapacity.entries[it]) },
                    )
                }
                Text(stringResource(R.string.recording_effort_feedback_note), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
            if (guidanceReport.spokenCueCount > 0) {
                FeedbackCard {
                    Text(stringResource(R.string.recording_guidance_feedback_section_title), style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.SemiBold)
                    Text(stringResource(R.string.recording_guidance_feedback_summary_format, guidanceReport.spokenCueCount, guidanceReport.helpfulCueCount), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    WorkoutGuidanceFeedback.entries.chunked(2).forEach { choices ->
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            choices.forEach { feedback ->
                                FeedbackChoiceButton(
                                    stringResource(when (feedback) {
                                        WorkoutGuidanceFeedback.HELPFUL -> R.string.recording_guidance_feedback_helpful
                                        WorkoutGuidanceFeedback.TOO_MUCH -> R.string.recording_guidance_feedback_too_much
                                        WorkoutGuidanceFeedback.TOO_GENERIC -> R.string.recording_guidance_feedback_too_generic
                                        WorkoutGuidanceFeedback.BAD_TIMING -> R.string.recording_guidance_feedback_bad_timing
                                    }), selectedGuidanceFeedback == feedback, { onGuidanceFeedbackSelect(feedback) }, Modifier.weight(1f),
                                )
                            }
                        }
                    }
                    Text(stringResource(R.string.recording_guidance_feedback_privacy), style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }
    }
}

@Composable
private fun FeedbackCard(content: @Composable ColumnScope.() -> Unit) {
    Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surfaceContainer) {
        Column(Modifier.fillMaxWidth().padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

@Composable
private fun FeedbackChoiceButton(label: String, isSelected: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    OutlinedButton(onClick = onClick, modifier = modifier.semantics { selected = isSelected }, shape = RoundedCornerShape(8.dp), contentPadding = PaddingValues(horizontal = 6.dp, vertical = 8.dp), colors = ButtonDefaults.outlinedButtonColors(
        containerColor = if (isSelected) MaterialTheme.colorScheme.primary.copy(alpha = .12f) else MaterialTheme.colorScheme.surfaceContainer,
        contentColor = if (isSelected) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.onSurfaceVariant,
    )) { Text(label, style = MaterialTheme.typography.labelLarge, textAlign = TextAlign.Center) }
}

/** Keep three choices readable at accessibility sizes instead of splitting words. */
@Composable
private fun FeedbackChoiceGroup(labels: List<String>, selectedIndex: Int, onSelect: (Int) -> Unit) {
    val fontScale = LocalDensity.current.fontScale
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        if (maxWidth < 96.dp * fontScale * labels.size) {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                labels.forEachIndexed { index, label ->
                    FeedbackChoiceButton(label, selectedIndex == index, { onSelect(index) }, Modifier.fillMaxWidth())
                }
            }
        } else {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                labels.forEachIndexed { index, label ->
                    FeedbackChoiceButton(label, selectedIndex == index, { onSelect(index) }, Modifier.weight(1f))
                }
            }
        }
    }
}
