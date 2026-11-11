package com.plainstride.outbound.core.model

import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

/** Fixed Monday–Sunday account calendar; schedule timestamps encode local date labels. */
@Serializable
data class PlanningCalendarContext(
    val policyVersion: String,
    val timeZone: String,
    val firstWeekday: Int,
    val weekStart: String,
    val weekEnd: String,
    val planStartDate: String? = null,
    val planWeekIndex: Int? = null,
    val isPartialWeek: Boolean = false,
) {
    fun zone(): ZoneId = try { ZoneId.of(timeZone) } catch (_: java.time.DateTimeException) {
        android.util.Log.e("PlainstrideCalendar", "account_zone_failed category=invalid_time_zone")
        ZoneId.of("UTC")
    }
    fun resolved(now: Instant = Instant.now()): PlanningCalendarContext {
        val zone = zone()
        val monday = now.atZone(zone).toLocalDate().with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY))
        val start = planStartDate?.let { LocalDate.parse(it) }
        val index = start?.let { (ChronoUnit.WEEKS.between(it.with(TemporalAdjusters.previousOrSame(DayOfWeek.MONDAY)), monday).toInt() + 1).coerceAtLeast(1) }
        return copy(policyVersion = "monday-v1", firstWeekday = 2,
            weekStart = monday.atStartOfDay(zone).toInstant().toString(), weekEnd = monday.plusDays(7).atStartOfDay(zone).toInstant().toString(),
            planWeekIndex = index, isPartialWeek = index == 1 && start?.dayOfWeek != DayOfWeek.MONDAY)
    }
}
