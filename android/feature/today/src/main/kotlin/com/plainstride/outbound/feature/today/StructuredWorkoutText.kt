package com.plainstride.outbound.feature.today

import android.content.Context
import android.content.res.Configuration
import com.plainstride.outbound.core.model.ActivitySuggestion
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.PlannedWorkout
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.StandaloneWorkout
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import java.math.BigDecimal
import java.text.NumberFormat
import java.util.Locale

/** Narrow authored-vocabulary resolver; arbitrary server/user text passes through. */
internal class StructuredWorkoutText(context: Context, localeTag: String) {
    private val displayLocale = Locale.forLanguageTag(localeTag)
    private val resources = context.createConfigurationContext(Configuration(context.resources.configuration).apply {
        setLocale(displayLocale)
    }).resources

    private fun text(value: String): String = authoredText(value) ?: value

    /** Match complete authored label shapes; never translate a free-form prefix or suffix. */
    private fun authoredText(value: String): String? {
        exactText(value)?.let { return it }
        NUMBERED.matchEntire(value)?.let { match ->
            val number = match.groupValues[2].toIntOrNull()?.takeIf { it > 0 } ?: return null
            val resource = when (match.groupValues[1]) {
                "Hard rep" -> R.string.structured_numbered_hard
                "Tempo block" -> R.string.structured_numbered_tempo
                "Surge" -> R.string.structured_numbered_surge
                "Hill rep" -> R.string.structured_numbered_hill
                "Pickup" -> R.string.structured_numbered_pickup
                "Run" -> R.string.structured_numbered_run
                "Walk" -> R.string.structured_numbered_walk
                "Easy recovery" -> R.string.structured_numbered_recovery
                "Gentle run" -> R.string.structured_numbered_gentle
                "Fast repeat" -> R.string.structured_numbered_fast
                else -> R.string.structured_numbered_uphill
            }
            return resources.getString(resource, number)
        }
        TIMED_LABEL.matchEntire(value)?.let { match ->
            val minutes = match.groupValues[2].toIntOrNull()?.takeIf { it > 0 } ?: return null
            return resources.getString(if (match.groupValues[1] == "Easy") R.string.structured_easy_minutes else R.string.structured_fast_minutes, minutes)
        }
        DISTANCE_LABEL.matchEntire(value)?.let { match ->
            val resource = when (match.groupValues[1]) {
                "Easy run" -> R.string.structured_easy_miles
                "Easy run with strides" -> R.string.structured_strides_miles
                "Endurance run" -> R.string.structured_endurance_miles
                else -> R.string.structured_race_miles
            }
            return resources.getString(resource, authoredNumber(match.groupValues[2]))
        }
        PREPARATION_DISTANCE.matchEntire(value)?.let { match ->
            return resources.getString(if (match.groupValues[2] == "Warm Up") R.string.structured_warmup_miles else R.string.structured_cooldown_miles, authoredNumber(match.groupValues[1]))
        }
        THRESHOLD_LABEL.matchEntire(value)?.let { match ->
            return resources.getString(R.string.structured_threshold_miles, authoredNumber(match.groupValues[1]), authoredNumber(match.groupValues[2]))
        }
        HALF_PACE_LABEL.matchEntire(value)?.let { match ->
            return resources.getString(R.string.structured_half_pace_miles, authoredNumber(match.groupValues[1]))
        }
        REPEAT_RECIPE.matchEntire(value)?.let { match ->
            val pace = when (match.groupValues[4]) {
                "5k-10k pace" -> R.string.structured_pace_five_ten
                "10k pace" -> R.string.structured_pace_ten
                else -> R.string.structured_pace_half_minus
            }
            return resources.getString(R.string.structured_repeat_recipe, authoredNumber(match.groupValues[1]),
                authoredDistance(match.groupValues[2], match.groupValues[3]), resources.getString(pace),
                authoredDistance(match.groupValues[5], match.groupValues[6]))
        }
        WEEK_WORKOUT.matchEntire(value)?.let { match ->
            val week = match.groupValues[1].toIntOrNull() ?: return null
            val workout = match.groupValues[2].toIntOrNull() ?: return null
            return resources.getString(R.string.structured_week_workout, week, workout)
        }
        // The adaptation engine prefixes only a known workout name or modality. Unknown
        // names (including user-authored names beginning with Lighter) remain untouched.
        LIGHTER.matchEntire(value)?.let { match ->
            val name = match.groupValues[1].takeIf { it in LIGHTER_WORKOUT_NAMES } ?: return null
            val original = exactText(name) ?: return null
            return resources.getString(R.string.structured_lighter_known, original)
        }
        return null
    }

    private fun authoredDistance(number: String, unit: String): String = resources.getString(when (unit.trim()) {
        "m" -> R.string.structured_distance_meters
        "k" -> R.string.structured_distance_km
        else -> R.string.structured_distance_miles
    }, authoredNumber(number))

    // Source recipes use English numeric notation. Preserve exact values while avoiding
    // a Spanish reader interpreting the source's 1,200 metres as 1.2 metres.
    private fun authoredNumber(number: String): String {
        val value = BigDecimal(number.replace(",", ""))
        return NumberFormat.getNumberInstance(displayLocale).apply {
            maximumFractionDigits = value.scale().coerceAtLeast(0)
        }.format(value)
    }

    private companion object {
        val NUMBERED = Regex("""(Hard rep|Tempo block|Surge|Hill rep|Pickup|Run|Walk|Easy recovery|Gentle run|Fast repeat|Uphill) ([1-9][0-9]*)""")
        val TIMED_LABEL = Regex("""(Easy|Fast) ([1-9][0-9]*) min""")
        val DISTANCE_LABEL = Regex("""(Easy run|Easy run with strides|Endurance run|Race effort) ([0-9]+(?:\.[0-9]+)?) mi""")
        val PREPARATION_DISTANCE = Regex("""([0-9]+(?:\.[0-9]+)?) miles (Warm Up|Cool Down)""")
        val THRESHOLD_LABEL = Regex("""Lactate threshold ([0-9]+) miles w/ ([0-9]+) min tempo""")
        val HALF_PACE_LABEL = Regex("""([0-9]+) miles ?@ HMP""")
        val REPEAT_RECIPE = Regex("""([0-9]+)x([0-9]+(?:\.[0-9]+)?|[0-9]{1,3}(?:,[0-9]{3})+)(m|k| miles) @ (5k-10k pace|10k pace|HMP -10s) w\. ([0-9]+(?:\.[0-9]+)?)(m| miles) jog rest""")
        val WEEK_WORKOUT = Regex("""Week ([1-9][0-9]*), Workout ([1-9][0-9]*)""")
        val LIGHTER = Regex("""Lighter (.+)""")
        val LIGHTER_WORKOUT_NAMES = setOf("run", "walk", "bike", "strength", "swim", "hiit", "skate", "mobility",
            "Long endurance ride", "Controlled bike intervals", "Recovery spin", "Easy aerobic ride", "Long brisk walk",
            "Brisk walk", "Full-body strength", "Mobility reset")
    }

    private fun exactText(value: String): String? = when (value) {
        "Warm up walk" -> resources.getString(R.string.structured_warmup_walk)
        "Easy recovery" -> resources.getString(R.string.structured_easy_recovery)
        "Walk recovery" -> resources.getString(R.string.structured_walk_recovery)
        "Walk until your breathing settles." -> resources.getString(R.string.structured_walk_recovery_detail)
        "Recover easily before the next effort." -> resources.getString(R.string.structured_easy_recovery_detail)
        "Warm up jog" -> resources.getString(R.string.structured_warmup_jog)
        "Cooldown walk" -> resources.getString(R.string.structured_cooldown_walk)
        "Cooldown jog" -> resources.getString(R.string.structured_cooldown_jog)
        "Comfortable run-walk" -> resources.getString(R.string.structured_comfortable_run_walk)
        "Tempo effort" -> resources.getString(R.string.structured_tempo_effort)
        "Fast relaxed running" -> resources.getString(R.string.structured_fast_relaxed)
        "Long aerobic running" -> resources.getString(R.string.structured_long_aerobic)
        "Very easy jog" -> resources.getString(R.string.structured_very_easy_jog)
        "Easy run" -> resources.getString(R.string.structured_easy_run)
        "Easy run-walk" -> resources.getString(R.string.structured_easy_run_walk)
        "Controlled tempo run" -> resources.getString(R.string.structured_controlled_tempo)
        "Relaxed speed session" -> resources.getString(R.string.structured_relaxed_speed)
        "Long easy run" -> resources.getString(R.string.structured_long_easy_run)
        "Recovery jog" -> resources.getString(R.string.structured_recovery_jog)
        "Easy aerobic run" -> resources.getString(R.string.structured_easy_aerobic_run)
        "Start easier than you think you need to." -> resources.getString(R.string.structured_start_easier)
        "Let your breathing settle before you stop." -> resources.getString(R.string.structured_settle_before_stop)
        "Alternate comfortable jogging and walking as needed; keep the whole main session easy." -> resources.getString(R.string.structured_run_walk_detail)
        "Strong but controlled; never sprinting." -> resources.getString(R.string.structured_controlled_detail)
        "Fast enough to feel sharp, relaxed enough to stay smooth." -> resources.getString(R.string.structured_fast_detail)
        "Keep this patient and conversational." -> resources.getString(R.string.structured_patient_detail)
        "You should be able to speak in short sentences." -> resources.getString(R.string.structured_sentences_detail)
        "Mobility reset" -> resources.getString(R.string.structured_mobility_reset)
        "Easy mobility flow" -> resources.getString(R.string.structured_mobility_flow)
        "Move through hips, calves, back, and shoulders without forcing range." -> resources.getString(R.string.structured_mobility_detail)
        "Warm up walk or jog" -> resources.getString(R.string.structured_warmup_walk_jog)
        "Easy float" -> resources.getString(R.string.structured_easy_float)
        "Walk back recovery" -> resources.getString(R.string.structured_walk_back)
        "Main effort" -> resources.getString(R.string.structured_main_effort)
        "Run" -> resources.getString(R.string.structured_run)
        "Walk" -> resources.getString(R.string.structured_walk)
        "Bike, walk, row, or mobility circuit" -> resources.getString(R.string.structured_cross_train_options)
        "Optional cross-train or full rest" -> resources.getString(R.string.structured_optional_rest)
        "Ease into the session." -> resources.getString(R.string.structured_ease_session)
        "Let your breathing settle." -> resources.getString(R.string.structured_settle_breathing)
        "No rush." -> resources.getString(R.string.structured_no_rush)
        "Stay well below strain." -> resources.getString(R.string.structured_below_strain)
        "Finish feeling refreshed." -> resources.getString(R.string.structured_finish_refreshed)
        "Start more gently than you think you need to." -> resources.getString(R.string.structured_start_gentler)
        "Stay under control for the whole middle." -> resources.getString(R.string.structured_middle_control)
        "Walk a bit before you stop completely." -> resources.getString(R.string.structured_walk_before_stop)
        "Keep this relaxed." -> resources.getString(R.string.structured_keep_relaxed)
        "Controlled discomfort." -> resources.getString(R.string.structured_controlled_discomfort)
        "Bring your breathing down before the next block." -> resources.getString(R.string.structured_breathing_next_block)
        "Let the effort taper off." -> resources.getString(R.string.structured_taper_effort)
        "Quick but controlled." -> resources.getString(R.string.structured_quick_controlled)
        "Walk or jog until you feel ready again." -> resources.getString(R.string.structured_walk_jog_ready)
        "Bring things back down slowly." -> resources.getString(R.string.structured_down_slowly)
        "Start relaxed." -> resources.getString(R.string.structured_start_relaxed)
        "Run by feel, not by force." -> resources.getString(R.string.structured_run_by_feel)
        "Recover while still moving." -> resources.getString(R.string.structured_recover_moving)
        "Find a smooth hill." -> resources.getString(R.string.structured_smooth_hill)
        "Short, tall, and powerful." -> resources.getString(R.string.structured_short_tall_powerful)
        "Reset fully before the next climb." -> resources.getString(R.string.structured_reset_climb)
        "Shake the legs out." -> resources.getString(R.string.structured_shake_legs)
        "Stay relaxed." -> resources.getString(R.string.structured_stay_relaxed_period)
        "Quick, light, and under control." -> resources.getString(R.string.structured_quick_light_controlled)
        "Reset before the next pickup." -> resources.getString(R.string.structured_reset_pickup)
        "Keep this short and easy." -> resources.getString(R.string.structured_short_easy)
        "Stay loose and calm." -> resources.getString(R.string.structured_loose_calm)
        "Start controlled, then build into the second half." -> resources.getString(R.string.structured_build_second_half)
        "Let the effort taper fully." -> resources.getString(R.string.structured_taper_fully)
        "Bring the session down calmly." -> resources.getString(R.string.structured_bring_calmly)
        "Bring your breathing back down." -> resources.getString(R.string.structured_breathing_back)
        "Ease in gently." -> resources.getString(R.string.structured_ease_gently)
        "Ease into the workout." -> resources.getString(R.string.structured_ease_workout)
        "Finish with a few quick relaxed strides." -> resources.getString(R.string.structured_finish_strides)
        "Get loose before the first run segment." -> resources.getString(R.string.structured_loose_first_run)
        "Keep the effort below strain." -> resources.getString(R.string.structured_effort_below)
        "Keep the pace light." -> resources.getString(R.string.structured_pace_light)
        "Keep the whole run conversational." -> resources.getString(R.string.structured_run_conversation)
        "Let the effort settle." -> resources.getString(R.string.structured_effort_settle)
        "Let the session settle." -> resources.getString(R.string.structured_session_settle)
        "Recover fully before the next run." -> resources.getString(R.string.structured_recover_before_run)
        "Recover fully." -> resources.getString(R.string.structured_recover_fully_period)
        "Relax the pace." -> resources.getString(R.string.structured_relax_pace)
        "Run this at controlled half-marathon effort." -> resources.getString(R.string.structured_controlled_half)
        "Settle in gradually." -> resources.getString(R.string.structured_settle_gradually)
        "Start controlled and build late." -> resources.getString(R.string.structured_build_late)
        "Stay loose." -> resources.getString(R.string.structured_stay_loose)
        "Stay mostly aerobic." -> resources.getString(R.string.structured_mostly_aerobic)
        "Stay smooth through the middle." -> resources.getString(R.string.structured_middle_smooth)
        "Walk a bit before stopping." -> resources.getString(R.string.structured_walk_before_stopping)
        "Walk, bike, mobility, or take the day off entirely." -> resources.getString(R.string.structured_rest_options)
        "Controlled tempo" -> resources.getString(R.string.structured_controlled_tempo_phase)
        "Cooldown" -> resources.getString(R.string.structured_cooldown)
        "Ease down" -> resources.getString(R.string.structured_ease_down)
        "Easy cooldown" -> resources.getString(R.string.structured_easy_cooldown)
        "Easy running" -> resources.getString(R.string.structured_easy_running)
        "Easy warm-up" -> resources.getString(R.string.structured_easy_warmup)
        "Final gentle run" -> resources.getString(R.string.structured_final_gentle)
        "Gentle movement" -> resources.getString(R.string.structured_gentle_movement)
        "Gentle start" -> resources.getString(R.string.structured_gentle_start)
        "Settle in" -> resources.getString(R.string.structured_settle_in)
        "Walk it down" -> resources.getString(R.string.structured_walk_down)
        "Warm-up walk" -> resources.getString(R.string.structured_warmup_walk_hyphen)
        "Comfortable conversation effort" -> resources.getString(R.string.structured_comfortable_conversation)
        "Comfortably hard; short phrases, never straining" -> resources.getString(R.string.structured_hard_short_phrases)
        "Compact steps" -> resources.getString(R.string.structured_compact_steps)
        "Controlled speed" -> resources.getString(R.string.structured_controlled_speed)
        "Conversational running" -> resources.getString(R.string.structured_conversational_running)
        "Drive arms without tensing" -> resources.getString(R.string.structured_arms_relaxed)
        "Easy jog or walk" -> resources.getString(R.string.structured_easy_jog_walk)
        "Easy jog, walk, or a mix" -> resources.getString(R.string.structured_easy_jog_walk_mix)
        "Easy jogging, not a sprint" -> resources.getString(R.string.structured_jog_not_sprint)
        "Easy running or walking" -> resources.getString(R.string.structured_easy_running_walking)
        "Easy running toward a moderate hill" -> resources.getString(R.string.structured_toward_hill)
        "Fast feet and tall hips" -> resources.getString(R.string.structured_fast_feet_hips)
        "Fast feet, relaxed upper body" -> resources.getString(R.string.structured_fast_feet_relaxed)
        "Finish fast, not strained" -> resources.getString(R.string.structured_finish_fast)
        "Finish with control" -> resources.getString(R.string.structured_finish_control)
        "Jog gently" -> resources.getString(R.string.structured_jog_gently)
        "Jog or walk until settled" -> resources.getString(R.string.structured_jog_walk_settled)
        "Keep the effort easy" -> resources.getString(R.string.structured_effort_easy)
        "Let breathing settle" -> resources.getString(R.string.structured_breathing_settle)
        "Let your breathing come down" -> resources.getString(R.string.structured_breathing_come_down)
        "Let your breathing settle" -> resources.getString(R.string.structured_your_breathing_settle)
        "Light feet and relaxed hands" -> resources.getString(R.string.structured_light_feet_hands)
        "Match the first easy effort" -> resources.getString(R.string.structured_match_easy)
        "Match the first repeat" -> resources.getString(R.string.structured_match_repeat)
        "Match the first three" -> resources.getString(R.string.structured_match_three)
        "No need to rush" -> resources.getString(R.string.structured_no_rush_plain)
        "Quick and controlled" -> resources.getString(R.string.structured_quick_controlled_plain)
        "Quick and relaxed" -> resources.getString(R.string.structured_quick_relaxed)
        "Recover completely" -> resources.getString(R.string.structured_recover_completely)
        "Recover fully" -> resources.getString(R.string.structured_recover_fully)
        "Relax your breathing" -> resources.getString(R.string.structured_relax_breathing)
        "Relaxed conversational running" -> resources.getString(R.string.structured_relaxed_conversation)
        "Relaxed walk or shuffle" -> resources.getString(R.string.structured_walk_shuffle)
        "Relaxed walking" -> resources.getString(R.string.structured_relaxed_walking)
        "Same calm effort" -> resources.getString(R.string.structured_same_calm)
        "Settle before the final run" -> resources.getString(R.string.structured_settle_final)
        "Small, comfortable steps" -> resources.getString(R.string.structured_small_steps)
        "Smooth and slightly quicker" -> resources.getString(R.string.structured_smooth_quicker)
        "Stay relaxed" -> resources.getString(R.string.structured_stay_relaxed)
        "Stay tall and relaxed" -> resources.getString(R.string.structured_tall_relaxed)
        "Strong but sustainable" -> resources.getString(R.string.structured_strong_sustainable)
        "Strong, not all-out" -> resources.getString(R.string.structured_strong_not_allout)
        "Strong, tall, controlled" -> resources.getString(R.string.structured_strong_tall_control)
        "Use all of the recovery" -> resources.getString(R.string.structured_all_recovery)
        "Very easy running or brisk walking" -> resources.getString(R.string.structured_very_easy_walk)
        "Walk easily and let your body warm up" -> resources.getString(R.string.structured_walk_warm)
        "Walk easily until breathing settles" -> resources.getString(R.string.structured_walk_breathing)
        "Walk or jog back safely" -> resources.getString(R.string.structured_back_safely)
        "Long endurance ride" -> resources.getString(R.string.structured_long_ride)
        "Controlled bike intervals" -> resources.getString(R.string.structured_bike_intervals)
        "Recovery spin" -> resources.getString(R.string.structured_recovery_spin)
        "Easy aerobic ride" -> resources.getString(R.string.structured_easy_ride)
        "Keep every effort controlled and spin easily between repeats." -> resources.getString(R.string.structured_controlled_spin)
        "Use a smooth cadence and sustainable pressure." -> resources.getString(R.string.structured_smooth_cadence)
        "Long brisk walk" -> resources.getString(R.string.structured_long_walk)
        "Brisk walk" -> resources.getString(R.string.structured_brisk_walk)
        "Move with purpose, but keep it sustainable." -> resources.getString(R.string.structured_purposeful_walk)
        "Full-body strength" -> resources.getString(R.string.structured_full_strength)
        "Full-body strength circuit" -> resources.getString(R.string.structured_strength_circuit)
        "Keep two or three reps in reserve. Leave the session better than you started." -> resources.getString(R.string.structured_reserve_reps)
        "Recovery reset" -> resources.getString(R.string.structured_recovery_reset)
        "Keep this restorative. Pain or illness beats training targets today." -> resources.getString(R.string.structured_restorative_targets)
        "Keep it relaxed and let the routine count." -> resources.getString(R.string.structured_relaxed_routine)
        "Keep the whole thing restorative." -> resources.getString(R.string.structured_restorative_all)
        "Start easy and settle your breathing." -> resources.getString(R.string.structured_adjusted_start)
        "Easy walk-run" -> resources.getString(R.string.structured_easy_walk_run)
        "Keep the effort conversational." -> resources.getString(R.string.structured_effort_conversation)
        "Finish still feeling in control." -> resources.getString(R.string.structured_finish_controlled)
        "Relax your shoulders." -> resources.getString(R.string.structured_relax_shoulders)
        "Easy jog or brisk walk" -> resources.getString(R.string.structured_jog_brisk_walk)
        "Finish feeling fresh." -> resources.getString(R.string.structured_finish_fresh)
        "run" -> resources.getString(R.string.structured_modality_run)
        "walk" -> resources.getString(R.string.structured_modality_walk)
        "bike" -> resources.getString(R.string.structured_modality_bike)
        "strength" -> resources.getString(R.string.structured_modality_strength)
        "swim" -> resources.getString(R.string.structured_modality_swim)
        "hiit" -> resources.getString(R.string.structured_modality_hiit)
        "skate" -> resources.getString(R.string.structured_modality_skate)
        "mobility" -> resources.getString(R.string.structured_modality_mobility)
        "Very easy" -> resources.getString(R.string.structured_effort_very_easy)
        "Easy" -> resources.getString(R.string.structured_effort_easy_label)
        "Steady" -> resources.getString(R.string.structured_effort_steady)
        "Comfortably hard" -> resources.getString(R.string.structured_effort_comfortably_hard)
        "Fast and controlled" -> resources.getString(R.string.structured_effort_fast_control)
        "Maximum" -> resources.getString(R.string.structured_effort_maximum)
        "Run · 29 min · beginner intervals" -> resources.getString(R.string.structured_summary_run_walk)
        "Run · 30 min · conversational effort" -> resources.getString(R.string.structured_summary_easy30)
        "Keep the main part very easy and relaxed." -> resources.getString(R.string.structured_adapt_very_easy)
        "Keep the main part comfortable and conversational." -> resources.getString(R.string.structured_adapt_easy)
        "Keep the main part steady and controlled." -> resources.getString(R.string.structured_adapt_steady)
        "Follow your selected effort in the main part. Keep the warmup and cooldown relaxed." -> resources.getString(R.string.structured_adapt_guidance)
        "Very easy run" -> resources.getString(R.string.structured_very_easy_run)
        "Steady run" -> resources.getString(R.string.structured_steady_run)
        "Very easy ride" -> resources.getString(R.string.structured_very_easy_ride)
        "Easy ride" -> resources.getString(R.string.structured_easy_ride_label)
        "Steady ride" -> resources.getString(R.string.structured_steady_ride)
        "Very easy walk" -> resources.getString(R.string.structured_very_easy_walk_label)
        "Easy walk" -> resources.getString(R.string.structured_easy_walk)
        "Steady walk" -> resources.getString(R.string.structured_steady_walk)
        "Guided 1.5K" -> resources.getString(R.string.structured_guided15)
        "Guided 3K" -> resources.getString(R.string.structured_guided3)
        "Guided 5K" -> resources.getString(R.string.structured_guided5)
        "Guided 10K" -> resources.getString(R.string.structured_guided10)
        "Guided Half Marathon" -> resources.getString(R.string.structured_guided_half)
        "Guided Marathon" -> resources.getString(R.string.structured_guided_marathon)
        "First Run-Walk" -> resources.getString(R.string.structured_first_run_walk)
        "Easy 30" -> resources.getString(R.string.structured_easy30)
        "Recovery 20" -> resources.getString(R.string.structured_recovery20)
        "Speed Run" -> resources.getString(R.string.structured_speed_run)
        "Tempo 35" -> resources.getString(R.string.structured_tempo35)
        "Fartlek Pyramid" -> resources.getString(R.string.structured_fartlek_pyramid)
        "Hill Six" -> resources.getString(R.string.structured_hill_six)
        "Run · 1.5 km · controlled hard effort" -> resources.getString(R.string.structured_summary_guided15)
        "Run · 3 km · steady-to-hard effort" -> resources.getString(R.string.structured_summary_guided3)
        "Run · 5 km · steady effort" -> resources.getString(R.string.structured_summary_guided5)
        "Run · 10 km · aerobic effort" -> resources.getString(R.string.structured_summary_guided10)
        "Run · 21.1 km · prepared endurance effort" -> resources.getString(R.string.structured_summary_guided_half)
        "Run · 42.2 km · prepared marathon effort" -> resources.getString(R.string.structured_summary_guided_marathon)
        "Run or walk · 20 min · very easy" -> resources.getString(R.string.structured_summary_recovery20)
        "Run · 30 min · 4 × 2 min fast" -> resources.getString(R.string.structured_summary_speed)
        "Run · 35 min · 15 min controlled tempo" -> resources.getString(R.string.structured_summary_tempo35)
        "Run · 33 min · 1-2-3-2-1 min surges" -> resources.getString(R.string.structured_summary_pyramid)
        "Run · 32 min · 6 × 45 sec uphill" -> resources.getString(R.string.structured_summary_hill)
        else -> null
    }

    private fun workout(value: PlannedWorkout) = value.copy(title = text(value.title), prescription = value.prescription?.let(::prescription), blocks = value.blocks.map { block ->
        block.copy(steps = block.steps.map { it.copy(label = text(it.label), detail = it.detail?.let(::text)) })
    })

    private fun prescription(value: JsonObject): JsonObject = JsonObject(value.mapValues { (key, field) ->
        if (key in setOf("summary", "purpose", "guideCue", "effortLabel")) {
            (field as? JsonPrimitive)?.contentOrNull?.let(::authoredText)?.let(::JsonPrimitive) ?: field
        } else field
    })

    private fun effective(value: StandaloneWorkout) = value.copy(
        title = text(value.title), detail = text(value.detail),
        steps = value.steps.map { it.copy(label = text(it.label), detail = it.detail?.let(::text)) },
        guideInstructions = value.guideInstructions.copy(segments = value.guideInstructions.segments.map {
            it.copy(instruction = text(it.instruction), cue = text(it.cue), fallback = text(it.fallback))
        }),
    )

    private fun suggestion(value: ActivitySuggestion) = value.copy(
        title = text(value.title), effortLabel = text(value.effortLabel), why = text(value.why),
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
            guideLine = advice ?: text(value.guideLine), alternates = value.alternates.map(::suggestion))
    }
}

internal fun <T, R> CachedResource<T>.mapValue(transform: (T) -> R): CachedResource<R> = when (this) {
    CachedResource.Loading -> CachedResource.Loading
    is CachedResource.Available -> CachedResource.Available(transform(value), isStale, updatedAtEpochMs)
    is CachedResource.Failed -> CachedResource.Failed(error, cachedValue?.let(transform))
}
