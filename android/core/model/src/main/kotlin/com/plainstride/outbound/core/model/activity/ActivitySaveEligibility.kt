package com.plainstride.outbound.core.model.activity

enum class SaveEligibility { eligible, tooShort }

object ActivitySaveEligibility {
    const val MINIMUM_DURATION_SECONDS = 300
    const val MINIMUM_DISTANCE_METERS = 500.0

    fun evaluate(durationSeconds: Int, distanceMeters: Double): SaveEligibility =
        if (durationSeconds >= MINIMUM_DURATION_SECONDS || distanceMeters >= MINIMUM_DISTANCE_METERS) {
            SaveEligibility.eligible
        } else {
            SaveEligibility.tooShort
        }
}
