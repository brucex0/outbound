package com.plainstride.outbound.core.model.activity

import kotlinx.serialization.Serializable

/**
 * Optional activity companion context (`With dog`).
 *
 * This is deliberately not an [ActivityType]: the canonical sport stays
 * running, walking, hiking, or cycling while this value records that the
 * person brought a dog. It never measures or describes the dog itself.
 */
@Serializable
enum class ActivityCompanionType {
    dog;

    companion object {
        val eligibleActivityTypes: Set<ActivityType> =
            setOf(ActivityType.running, ActivityType.walking, ActivityType.hiking, ActivityType.cycling)

        fun isEligibleFor(activityType: ActivityType): Boolean = activityType in eligibleActivityTypes
    }
}
