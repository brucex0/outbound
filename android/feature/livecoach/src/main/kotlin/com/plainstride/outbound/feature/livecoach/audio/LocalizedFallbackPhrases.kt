package com.plainstride.outbound.feature.livecoach.audio

import android.content.Context
import com.plainstride.outbound.feature.livecoach.R
import com.plainstride.outbound.feature.livecoach.network.LiveCoachMoment

/** Resolves reviewed local wording from the requested locale without persisting the transcript. */
object LocalizedFallbackPhrases {
    fun phrase(context: Context, localeTag: String, moment: LiveCoachMoment): String {
        val localized = context.createConfigurationContext(context.resources.configuration.apply { setLocale(java.util.Locale.forLanguageTag(localeTag)) })
        val resource = when (moment) {
            LiveCoachMoment.Progress, LiveCoachMoment.TargetLocked -> R.string.live_coach_cue_steady
            LiveCoachMoment.ClimbStart -> R.string.live_coach_cue_climb
            LiveCoachMoment.FinishOpportunity -> R.string.live_coach_cue_finish
            LiveCoachMoment.UnexpectedStop -> R.string.live_coach_cue_pause
            LiveCoachMoment.ResumeAfterBreak -> R.string.live_coach_cue_resume
            else -> R.string.live_coach_cue_adjust
        }
        return localized.getString(resource)
    }
}
