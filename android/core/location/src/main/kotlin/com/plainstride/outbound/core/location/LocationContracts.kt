package com.plainstride.outbound.core.location

data class LocationSample(
    val latitude: Double,
    val longitude: Double,
    val altitudeMeters: Double?,
    val horizontalAccuracyMeters: Double,
    val verticalAccuracyMeters: Double?,
    val capturedAtEpochMilliseconds: Long,
)

interface LocationSource {
    suspend fun start()
    suspend fun stop()
}
