package com.plainstride.outbound.core.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeParseException

/** The server's suggestion day is UTC; a device's local evening may belong to the previous date. */
fun ActivitySuggestionEnvelope.isCurrent(now: Instant = Instant.now()): Boolean = try {
    LocalDate.parse(validForDate) == now.atOffset(ZoneOffset.UTC).toLocalDate() &&
        !now.plusSeconds(5 * 60).isBefore(Instant.parse(generatedAt)) && now.isBefore(Instant.parse(validUntil))
} catch (_: DateTimeParseException) {
    false
}
