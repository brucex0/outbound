package com.plainstride.outbound.feature.recording

import android.util.Log
import android.widget.Toast
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.padding
import androidx.compose.ui.Modifier
import androidx.compose.material3.Surface
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.activity.SavedActivity
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch

@Composable
internal fun GroupWorkoutCompletionPrompt(
    activity: SavedActivity,
    loadMatch: suspend (SavedActivity) -> PlannedWorkout?,
    link: suspend (SavedActivity, PlannedWorkout) -> String,
) {
    var match by remember(activity.id) { mutableStateOf<PlannedWorkout?>(null) }
    var dismissed by remember(activity.id) { mutableStateOf(false) }
    var busy by remember(activity.id) { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    LaunchedEffect(activity.id) {
        try { match = loadMatch(activity) }
        catch (error: Exception) {
            if (error is CancellationException) throw error
            Log.w("PlainstridePlanning", "group_completion_candidate_failed category=${error.javaClass.simpleName}")
        }
    }
    if (!dismissed) match?.let { workout ->
        Surface(color = MaterialTheme.colorScheme.surface, contentColor = MaterialTheme.colorScheme.onSurface, shape = MaterialTheme.shapes.medium) {
        Column(Modifier.padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(stringResource(R.string.plan_completion_group_question), style = MaterialTheme.typography.titleMedium)
            Text(stringResource(R.string.plan_completion_workout_duration, android.text.format.DateUtils.formatElapsedTime(workout.durationSeconds.toLong())), style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
            FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedButton(enabled = !busy, onClick = {
                    scope.launch {
                        busy = true
                        try {
                            val result = link(activity, workout)
                            if (result == "success") dismissed = true
                            else Toast.makeText(context, if (result == "pending") R.string.plan_completion_sync_first else R.string.plan_completion_failed, Toast.LENGTH_LONG).show()
                        } finally { busy = false }
                    }
                }) { Text(stringResource(R.string.plan_completion_count)) }
                OutlinedButton(enabled = !busy, onClick = { dismissed = true }) { Text(stringResource(R.string.plan_completion_not_now)) }
            }
            if (busy) CircularProgressIndicator()
        }
        }
    }
}
