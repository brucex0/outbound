package com.plainstride.outbound.core.model

import java.time.Instant
import java.time.ZonedDateTime
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ActivitySuggestionValidityTest {
    private val envelope = ActivitySuggestionEnvelope(
        status = "suggested", source = "adaptive", relationship = "noPlanSuggestion", guideLine = "",
        planningStatus = PlanningStatus.stable, generatedAt = "2026-11-09T07:16:48Z",
        validForDate = "2026-11-09", validUntil = "2026-11-10T00:00:00Z",
        activityWatermark = ActivityWatermark(), decision = SuggestionDecision("fixture", emptyList(), emptyList()),
    )

    @Test fun losAngelesEveningUsesCanonicalServerDay() {
        val evening = ZonedDateTime.parse("2026-11-08T23:37:00-08:00[America/Los_Angeles]")
        assertTrue(envelope.isCurrent(evening.toInstant()))
    }

    @Test fun expiresAtServerBoundaryAndRejectsFutureOrMalformedPayloads() {
        assertFalse(envelope.isCurrent(Instant.parse("2026-11-10T00:00:00Z")))
        assertTrue(envelope.isCurrent(Instant.parse("2026-11-09T07:16:00Z")))
        assertFalse(envelope.isCurrent(Instant.parse("2026-11-09T07:00:00Z")))
        assertFalse(envelope.copy(validUntil = "invalid").isCurrent(Instant.parse("2026-11-09T08:00:00Z")))
    }
}
