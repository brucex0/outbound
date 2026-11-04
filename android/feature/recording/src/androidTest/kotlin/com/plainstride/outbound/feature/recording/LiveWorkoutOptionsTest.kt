package com.plainstride.outbound.feature.recording

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class LiveWorkoutOptionsTest {
    @get:Rule val ui = createComposeRule()
    private val context get() = InstrumentationRegistry.getInstrumentation().targetContext
    private fun label(id: Int) = context.getString(id)

    @Test fun liveTogglesAndSharingUseCurrentSessionWithoutChangingLaunchDefaults() {
        val original = RecordingLaunchConfiguration(goal = RecordingGoal(type = RecordingGoalType.DISTANCE, targetDistanceMeters = 1000.0), voiceGuideEnabled = true, autoStopAtGoal = false)
        val snapshot = mutableStateOf(RecordingSnapshot(status = RecordingStatus.ACTIVE, autoPauseEnabled = true))
        var sharingOpened = false
        ui.setContent {
            MaterialTheme {
                LiveWorkoutOptions(snapshot.value, original, 70.0, { sharingOpened = true }, 0) { option, enabled, _ ->
                    snapshot.value = when (option) {
                        "voice_guide" -> snapshot.value.copy(liveVoiceGuideEnabled = enabled)
                        "auto_pause" -> snapshot.value.copy(autoPauseEnabled = enabled)
                        else -> snapshot.value.copy(livePauseAtGoalEnabled = enabled)
                    }
                }
            }
        }
        ui.onNodeWithContentDescription(label(R.string.live_voice_guide)).assertIsOn().performClick().assertIsOff()
        ui.onNodeWithContentDescription(label(R.string.live_auto_pause)).assertIsOn().performClick().assertIsOff()
        ui.onNodeWithContentDescription(label(R.string.live_pause_at_goal)).assertIsOff().performClick().assertIsOn()
        ui.onNodeWithText(label(R.string.recording_cheer_on)).performClick()
        ui.runOnIdle { assertTrue(sharingOpened); assertEquals(RecordingStatus.ACTIVE, snapshot.value.status); assertTrue(original.voiceGuideEnabled); assertEquals(false, original.autoStopAtGoal) }
        // External/recovered recorder state is authoritative even while paused.
        ui.runOnIdle { snapshot.value = snapshot.value.copy(status = RecordingStatus.PAUSED, liveVoiceGuideEnabled = true) }
        ui.onNodeWithContentDescription(label(R.string.live_voice_guide)).assertIsOn()
    }

    @Test fun goalOptionIsOnlyAvailableForExplicitTargetsAndReportsAlreadyReachedGoal() {
        val goal = mutableStateOf(RecordingGoal(type = RecordingGoalType.FREESTYLE))
        var reached = false
        ui.setContent {
            MaterialTheme {
                LiveWorkoutOptions(RecordingSnapshot(status = RecordingStatus.ACTIVE, distanceMeters = 2000.0, elapsedSeconds = 600), RecordingLaunchConfiguration(goal = goal.value), 70.0, {}, 1) { _, _, alreadyReached -> reached = alreadyReached }
            }
        }
        ui.onNodeWithContentDescription(label(R.string.live_pause_at_goal)).assertDoesNotExist()
        ui.runOnIdle { goal.value = RecordingGoal(type = RecordingGoalType.WORKOUT) }
        ui.onNodeWithContentDescription(label(R.string.live_pause_at_goal)).assertDoesNotExist()
        ui.runOnIdle { goal.value = RecordingGoal(type = RecordingGoalType.DISTANCE, targetDistanceMeters = 1000.0) }
        ui.onNodeWithContentDescription(label(R.string.live_pause_at_goal)).performClick()
        ui.runOnIdle { assertTrue(reached) }
        ui.runOnIdle { goal.value = RecordingGoal(type = RecordingGoalType.TIME, targetDurationSeconds = 300) }
        ui.onNodeWithContentDescription(label(R.string.live_pause_at_goal)).assertIsDisplayed()
        ui.runOnIdle { goal.value = RecordingGoal(type = RecordingGoalType.CALORIES, targetCalories = 100) }
        ui.onNodeWithContentDescription(label(R.string.live_pause_at_goal)).assertIsDisplayed()
    }
}
