package com.plainstride.outbound.feature.today

import com.plainstride.outbound.core.network.CreateTrainingGoalRequest
import com.plainstride.outbound.core.network.PlanRecommendation
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.time.LocalDate

/** Nominal running source length never invents a user race deadline. */
fun PlanRecommendation.activationGoalRequest(today: LocalDate = LocalDate.now()): CreateTrainingGoalRequest {
    val template = this.template
    val focus = template["focus"]?.jsonPrimitive?.contentOrNull ?: throw IllegalArgumentException("Missing plan focus")
    val sport = template["sport"]?.jsonPrimitive?.contentOrNull ?: throw IllegalArgumentException("Missing plan activity")
    val activities = when (sport) {
        "mixed" -> listOf(com.plainstride.outbound.core.model.Modality.run, com.plainstride.outbound.core.model.Modality.walk, com.plainstride.outbound.core.model.Modality.bike)
        "walk" -> listOf(com.plainstride.outbound.core.model.Modality.walk)
        "bike" -> listOf(com.plainstride.outbound.core.model.Modality.bike)
        else -> listOf(com.plainstride.outbound.core.model.Modality.run)
    }
    val targetDistance = when (focus) {
        "fiveK" -> 5_000.0
        "tenK" -> 10_000.0
        "tenMile" -> 16_093.4
        "halfMarathon" -> 21_097.5
        "marathon" -> 42_195.0
        else -> null
    }
    val eventFocused = targetDistance != null
    return CreateTrainingGoalRequest(
        type = if (eventFocused) "eventPreparation" else "endurance",
        activities = activities,
        baselineContext = "currentlyActive",
        targetDate = if (eventFocused && com.plainstride.outbound.core.model.Modality.run !in activities) today.plusWeeks(this.durationWeeks.toLong()).toString() else null,
        targetDistanceMeters = targetDistance,
        eventIntent = if (eventFocused) "finish" else null,
        priority = if (focus == "comeback") "rebuild" else "fitness",
        daysPerWeekTarget = this.sessionsPerWeek,
        maxSessionMinutes = this.longSessionMinutes,
        riskTolerance = "balanced",
        constraints = mapOf("candidateID" to this.id, "templateID" to (template["id"]?.jsonPrimitive?.contentOrNull ?: "")),
    )
}
