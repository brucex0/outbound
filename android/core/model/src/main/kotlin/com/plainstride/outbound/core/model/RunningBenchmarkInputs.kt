package com.plainstride.outbound.core.model

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

fun runningBenchmarkLocalDate(now: Instant, zone: ZoneId): LocalDate = now.atZone(zone).toLocalDate()

fun runningBenchmarkDurationSeconds(value: String): Int? {
    val raw = value.split(':')
    if (raw.size != 3) return null
    val parts = raw.map { it.toIntOrNull() }
    val hours = parts[0] ?: return null
    val minutes = parts[1] ?: return null
    val seconds = parts[2] ?: return null
    if (hours !in 0..24 || minutes !in 0..59 || seconds !in 0..59) return null
    return (hours * 3600 + minutes * 60 + seconds).takeIf { it in 1..86400 }
}
