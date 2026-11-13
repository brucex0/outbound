package com.plainstride.outbound.feature.today

import android.content.Context
import android.content.res.Configuration
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.StandaloneWorkout
import java.util.Locale

/** Narrow authored-vocabulary resolver; arbitrary server/user text passes through. */
internal class StructuredWorkoutText(context: Context, localeTag: String) {
    private val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
        setLocale(Locale.forLanguageTag(localeTag))
    }).resources

    private fun text(value: String): String = when (value) {
        "Warm up walk" -> resources.getString(R.string.structured_warmup_walk)
        "Easy recovery" -> resources.getString(R.string.structured_easy_recovery)
        "Walk recovery" -> resources.getString(R.string.structured_walk_recovery)
        "Walk until your breathing settles." -> resources.getString(R.string.structured_walk_recovery_detail)
        "Recover easily before the next effort." -> resources.getString(R.string.structured_easy_recovery_detail)
        else -> value
    }

    private fun workout(value: PlannedWorkout) = value.copy(blocks = value.blocks.map { block ->
        block.copy(steps = block.steps.map { it.copy(label = text(it.label), detail = it.detail?.let(::text)) })
    })

    private fun effective(value: StandaloneWorkout) = value.copy(
        steps = value.steps.map { it.copy(label = text(it.label), detail = it.detail?.let(::text)) },
        guideInstructions = value.guideInstructions.copy(segments = value.guideInstructions.segments.map {
            it.copy(instruction = text(it.instruction), cue = text(it.cue), fallback = text(it.fallback))
        }),
    )

    private fun suggestion(value: ActivitySuggestion) = value.copy(
        steps = value.steps.map(::text), effectiveWorkout = value.effectiveWorkout?.let(::effective),
    )

    fun planning(value: PlanningState) = value.copy(today = value.today?.let(::workout),
        workouts = value.workouts.map(::workout), upcoming = value.upcoming.map(::workout))

    fun envelope(value: ActivitySuggestionEnvelope): ActivitySuggestionEnvelope {
        val advice = when {
            "recovery_change_recommended" in value.decision.reasons -> resources.getString(R.string.today_recovery_caution)
            "recovery_advised" in value.decision.reasons -> resources.getString(R.string.today_recovery_choice)
            "planned_workout_completed_today" in value.decision.reasons -> resources.getString(R.string.today_plan_completed_recovery)
            "unlinked_activity_logged_today" in value.decision.reasons -> resources.getString(R.string.today_plan_incomplete_after_activity)
            else -> null
        }
        return value.copy(primary = value.primary?.let(::suggestion)?.let { if (advice == null) it else it.copy(why = advice) },
            guideLine = advice ?: value.guideLine, alternates = value.alternates.map(::suggestion))
    }
}

internal fun <T, R> CachedResource<T>.mapValue(transform: (T) -> R): CachedResource<R> = when (this) {
    CachedResource.Loading -> CachedResource.Loading
    is CachedResource.Available -> CachedResource.Available(transform(value), isStale, updatedAtEpochMs)
    is CachedResource.Failed -> CachedResource.Failed(error, cachedValue?.let(transform))
}
