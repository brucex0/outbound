package com.plainstride.outbound.progress

import com.plainstride.outbound.feature.progress.*
import java.time.Instant
import java.time.ZoneId
import kotlinx.serialization.json.*

private fun JsonObject.obj(key: String) = getValue(key).jsonObject
private fun JsonObject.array(key: String) = getValue(key).jsonArray.map { it.jsonObject }
private fun JsonObject.text(key: String) = getValue(key).jsonPrimitive.content
private fun JsonObject.number(key: String) = getValue(key).jsonPrimitive.double
private fun JsonObject.integer(key: String) = getValue(key).jsonPrimitive.int
private fun JsonObject.optionalNumber(key: String) = get(key)?.jsonPrimitive?.doubleOrNull
private fun JsonObject.optionalText(key: String) = get(key)?.jsonPrimitive?.contentOrNull
private fun JsonObject.date(key: String) = Instant.parse(text(key))
private fun String.enumKey() = replace(Regex("([a-z])([A-Z])"), "$1_$2").uppercase()
fun JsonObject.statisticsTotals() = ProgressPeriodTotals(integer("activityCount"), number("distanceMeters"), integer("durationSeconds"), number("elevationMeters"))
fun JsonObject.progressSnapshot(zone: ZoneId): ProgressStatsSnapshot {
    fun JsonObject.effort(): ProgressBestEffort = ProgressBestEffort(
        if (text("kind") == "bestWeeklyDistance") BestEffortKind.BEST_WEEK else BestEffortKind.valueOf(text("kind").enumKey()),
        optionalText("activityID"), optionalText("activityTitle"), date("date"), optionalNumber("durationSeconds")?.toInt(), optionalNumber("distanceMeters"), optionalNumber("elevationMeters"), BestEffortSource.valueOf(text("source").enumKey()),
    )
    fun JsonObject.insight(): ProgressInsight {
        val raw = obj("evidence").entries.single(); val e = raw.value.jsonObject
        val evidence = when (raw.key) {
            "rollingDistance" -> ProgressInsightEvidence.RollingDistance(e.integer("percent"), e.number("currentMeters"), e.number("previousMeters"))
            "activeWeeks" -> ProgressInsightEvidence.ActiveWeeks(e.integer("count"), e.integer("total"))
            "longRunShare" -> ProgressInsightEvidence.LongRunShare(e.integer("percent"), e.number("longRunMeters"), e.number("weekMeters"))
            "heartRateEfficiency" -> ProgressInsightEvidence.HeartRateEfficiency(e.integer("pacePercent"), e.integer("heartRateDifference"))
            "loadRamp" -> ProgressInsightEvidence.LoadRamp(e.integer("percent"), e.number("current"), e.number("previous"))
            "intensityBalance" -> ProgressInsightEvidence.IntensityBalance(e.integer("highIntensityPercent"))
            "goalCompletion" -> ProgressInsightEvidence.GoalCompletion(e.integer("completed"), e.integer("total"))
            "preferredTime" -> ProgressInsightEvidence.PreferredTime(ProgressDayPart.valueOf(e.text("dayPart").enumKey()), e.integer("percent"), e.integer("total"))
            else -> error("Unknown statistics evidence")
        }
        return ProgressInsight(text("id"), ProgressInsightCategory.valueOf(text("category").enumKey()), ProgressInsightConfidence.valueOf(text("confidence").enumKey()), text("symbolName"), evidence)
    }
    val load = obj("trainingLoad")
    val momentum = get("momentumNote")?.takeUnless { it is JsonNull }?.jsonObject?.let { ProgressMomentumNote(MomentumKind.valueOf(it.text("kind").enumKey()), it.integer("activityCount")) }
    val ranges = mapOf("fourWeeks" to ProgressTrendRange.FOUR_WEEKS, "threeMonths" to ProgressTrendRange.THREE_MONTHS, "sixMonths" to ProgressTrendRange.SIX_MONTHS, "oneYear" to ProgressTrendRange.ONE_YEAR)
    return ProgressStatsSnapshot(
        obj("currentWeek").statisticsTotals(),
        array("weeklyBuckets").map { ProgressWeekBucket(it.date("startDate").atZone(zone).toLocalDate(), it.date("endDate").atZone(zone).toLocalDate(), it.integer("activityCount"), it.number("distanceMeters"), it.integer("durationSeconds"), it.number("elevationMeters")) },
        array("comparisons").map { ProgressPeriodComparison(if (it.text("kind") == "rolling28Days") ProgressComparisonKind.ROLLING_28_DAYS else ProgressComparisonKind.valueOf(it.text("kind").enumKey()), it.date("currentStart"), it.date("currentEnd"), it.date("previousStart"), it.date("previousEnd"), it.obj("current").statisticsTotals(), it.obj("previous").statisticsTotals()) },
        array("trendSeries").map { ProgressTrendSeries(ranges.getValue(it.text("range")), it.array("buckets").map { b -> ProgressTrendBucket(b.date("startDate"), b.date("endDate"), b.obj("totals").statisticsTotals()) }) },
        ProgressTrainingLoadSnapshot(load.number("currentSevenDays"), load.number("previousSevenDays"), load.optionalNumber("rampPercent"), load.optionalNumber("highIntensityPercent"), load.integer("heartRateActivityCount")),
        array("insights").map { it.insight() }, array("bestEfforts").map { it.effort() },
        array("personalRecords").map { ProgressPersonalRecord(it.text("title"), it.number("targetMeters"), it.obj("effort").effort()) },
        array("racePredictions").map { ProgressRacePrediction(it.text("title"), it.number("targetMeters"), it.integer("predictedSeconds"), PredictionConfidence.valueOf(it.text("confidence").enumKey())) },
        momentum, integer("eligibleActivityCount"),
    )
}
