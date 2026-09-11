package com.plainstride.outbound.feature.livecoach.audio

import android.content.Context
import android.content.res.Configuration
import com.plainstride.outbound.feature.livecoach.R
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMoment
import com.plainstride.outbound.feature.recording.RecordingSnapshot
import java.util.Locale
import kotlin.math.roundToInt

/** Resolves reviewed local wording from the requested locale without persisting the transcript. */
object LocalizedFallbackPhrases {
    fun phrase(context: Context, localeTag: String, moment: LiveCoachMoment): String {
        val localized = localizedContext(context, localeTag)
        val resource = when (moment) {
            LiveCoachMoment.Progress, LiveCoachMoment.TargetLocked, LiveCoachMoment.RacePaceLocked -> R.string.live_coach_cue_steady
            LiveCoachMoment.EarlyOverpace, LiveCoachMoment.RaceStartRestraint -> R.string.live_coach_cue_early_settle
            LiveCoachMoment.PaceAboveTarget -> R.string.live_coach_cue_ease_to_target
            LiveCoachMoment.PaceBelowTarget -> R.string.live_coach_cue_lift_to_target
            LiveCoachMoment.PaceInstability -> R.string.live_coach_cue_smooth_pace
            LiveCoachMoment.PaceDrift, LiveCoachMoment.RaceLateFade -> R.string.live_coach_cue_rebuild_rhythm
            LiveCoachMoment.RhythmRecovery -> R.string.live_coach_cue_rhythm_recovered
            LiveCoachMoment.RecoveryTooHard -> R.string.live_coach_cue_recovery_easy
            LiveCoachMoment.ClimbStart -> R.string.live_coach_cue_climb
            LiveCoachMoment.CrestRecovery -> R.string.live_coach_cue_crest
            LiveCoachMoment.FinishOpportunity, LiveCoachMoment.RaceLateStrength, LiveCoachMoment.RaceFinalKilometer -> R.string.live_coach_cue_finish
            LiveCoachMoment.RaceHalfwayAssessment -> R.string.live_coach_goal_distance_halfway
            LiveCoachMoment.UnexpectedStop -> R.string.live_coach_cue_pause
            LiveCoachMoment.ResumeAfterBreak -> R.string.live_coach_cue_resume
            LiveCoachMoment.SegmentTransition, LiveCoachMoment.WorkoutInstruction -> R.string.live_coach_cue_segment
            LiveCoachMoment.ChallengeStart -> R.string.live_coach_cue_challenge_start
            LiveCoachMoment.ChallengeComplete -> R.string.live_coach_cue_challenge_complete
        }
        return localized.getString(resource)
    }

    fun progress(context: Context, localeTag: String, snapshot: RecordingSnapshot, unitSystem: String, includePace: Boolean): String {
        val localized = localizedContext(context, localeTag)
        val parts = mutableListOf<String>()
        if (snapshot.distanceMeters >= 400) {
            val divisor = if (unitSystem == "imperial") 1_609.344 else 1_000.0
            val resource = if (unitSystem == "imperial") R.string.live_coach_progress_distance_miles else R.string.live_coach_progress_distance_kilometers
            parts += localized.getString(resource, snapshot.distanceMeters / divisor)
        }
        if (snapshot.elapsedSeconds >= 60) {
            val hours = snapshot.elapsedSeconds / 3_600
            val minutes = snapshot.elapsedSeconds / 60 % 60
            parts += if (hours > 0) localized.getString(R.string.live_coach_progress_duration_hours, hours, minutes)
            else localized.getString(R.string.live_coach_progress_duration_minutes, minutes)
        }
        if (includePace) {
            val pace = snapshot.currentPaceSecondsPerKilometer?.takeIf { it.isFinite() && it in 60.0..3_600.0 }
            if (pace == null) {
                parts += localized.getString(R.string.live_coach_progress_pace_settling)
            } else {
                val secondsPerUnit = if (unitSystem == "imperial") pace * 1.609344 else pace
                val total = secondsPerUnit.roundToInt()
                val resource = if (unitSystem == "imperial") R.string.live_coach_progress_pace_mile else R.string.live_coach_progress_pace_kilometer
                parts += localized.getString(resource, total / 60, total % 60)
            }
        }
        return parts.joinToString(" ").ifBlank { localized.getString(R.string.live_coach_progress_generic) }
    }

    fun goal(context: Context, localeTag: String, milestone: String, unitSystem: String): String {
        val localized = localizedContext(context, localeTag)
        val resource = when (milestone) {
            "distance_one_third" -> R.string.live_coach_goal_distance_one_third
            "distance_halfway" -> R.string.live_coach_goal_distance_halfway
            "distance_two_thirds" -> R.string.live_coach_goal_distance_two_thirds
            "distance_last_unit" -> if (unitSystem == "imperial") R.string.live_coach_goal_distance_last_mile else R.string.live_coach_goal_distance_last_kilometer
            "distance_300_remaining" -> if (unitSystem == "imperial") R.string.live_coach_goal_distance_quarter_mile_remaining else R.string.live_coach_goal_distance_300_remaining
            "distance_100_remaining" -> if (unitSystem == "imperial") R.string.live_coach_goal_distance_tenth_mile_remaining else R.string.live_coach_goal_distance_100_remaining
            "distance_complete" -> R.string.live_coach_goal_distance_complete
            "duration_one_third" -> R.string.live_coach_goal_duration_one_third
            "duration_halfway" -> R.string.live_coach_goal_duration_halfway
            "duration_two_thirds" -> R.string.live_coach_goal_duration_two_thirds
            "duration_five_remaining" -> R.string.live_coach_goal_duration_five_remaining
            "duration_one_remaining" -> R.string.live_coach_goal_duration_one_remaining
            else -> R.string.live_coach_goal_duration_complete
        }
        return localized.getString(resource)
    }

    private fun localizedContext(context: Context, localeTag: String): Context {
        val configuration = Configuration(context.resources.configuration)
        configuration.setLocale(Locale.forLanguageTag(localeTag))
        return context.createConfigurationContext(configuration)
    }
}
