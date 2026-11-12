package com.plainstride.outbound.core.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.ZoneId
import java.time.format.DateTimeParseException

/** Suggestion dates are logical account-calendar dates, not UTC date labels. */
fun ActivitySuggestionEnvelope.isCurrent(
    now: Instant = Instant.now(),
    zone: ZoneId = ZoneOffset.UTC,
): Boolean = try {
    LocalDate.parse(validForDate) == now.atZone(zone).toLocalDate() &&
        !now.plusSeconds(5 * 60).isBefore(Instant.parse(generatedAt)) && now.isBefore(Instant.parse(validUntil))
} catch (_: DateTimeParseException) {
    false
}
