package com.plainstride.outbound.core.model.activity

import kotlin.math.truncate

enum class MeasurementUnitSystem { metric, imperial }

enum class DistanceUnit { kilometer, mile }

enum class ElevationUnit { meter, foot }

data class DistanceMeasurement(val value: Double, val unit: DistanceUnit)

data class ElevationMeasurement(val value: Double, val unit: ElevationUnit)

data class PaceMeasurement(
    val totalSecondsPerUnit: Int,
    val unit: DistanceUnit,
) {
    val minutes: Int get() = totalSecondsPerUnit / 60
    val seconds: Int get() = totalSecondsPerUnit % 60
}

data class DurationComponents(val hours: Int, val minutes: Int, val seconds: Int)

/** Locale-free measurement semantics. UI layers own decimal, unit, and spoken localization. */
object SessionFormatting {
    private const val METERS_PER_MILE = 1_609.344
    private const val FEET_PER_METER = 3.28084

    fun distance(meters: Double, unitSystem: MeasurementUnitSystem): DistanceMeasurement =
        when (unitSystem) {
            MeasurementUnitSystem.metric -> DistanceMeasurement(meters / 1_000.0, DistanceUnit.kilometer)
            MeasurementUnitSystem.imperial -> DistanceMeasurement(meters / METERS_PER_MILE, DistanceUnit.mile)
        }

    fun distanceMeters(value: Double, unitSystem: MeasurementUnitSystem): Double =
        when (unitSystem) {
            MeasurementUnitSystem.metric -> value * 1_000.0
            MeasurementUnitSystem.imperial -> value * METERS_PER_MILE
        }

    fun elevation(meters: Double, unitSystem: MeasurementUnitSystem): ElevationMeasurement =
        when (unitSystem) {
            MeasurementUnitSystem.metric -> ElevationMeasurement(meters, ElevationUnit.meter)
            MeasurementUnitSystem.imperial -> ElevationMeasurement(meters * FEET_PER_METER, ElevationUnit.foot)
        }

    fun pace(secondsPerKilometer: Double, unitSystem: MeasurementUnitSystem): PaceMeasurement? {
        if (!secondsPerKilometer.isFinite() || secondsPerKilometer <= 0.0) return null
        val secondsPerUnit = when (unitSystem) {
            MeasurementUnitSystem.metric -> secondsPerKilometer
            MeasurementUnitSystem.imperial -> secondsPerKilometer * (METERS_PER_MILE / 1_000.0)
        }
        return PaceMeasurement(
            totalSecondsPerUnit = truncate(secondsPerUnit).toInt(),
            unit = if (unitSystem == MeasurementUnitSystem.metric) DistanceUnit.kilometer else DistanceUnit.mile,
        )
    }

    fun duration(totalSeconds: Int): DurationComponents = DurationComponents(
        hours = totalSeconds / 3_600,
        minutes = (totalSeconds % 3_600) / 60,
        seconds = totalSeconds % 60,
    )
}
