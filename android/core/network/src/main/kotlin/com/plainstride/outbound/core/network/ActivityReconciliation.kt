package com.plainstride.outbound.core.network

import kotlinx.serialization.Serializable

@Serializable data class CanonicalWorkoutCompletion(
    val activityId: String,
    val plannedWorkoutId: String,
    val planVersionId: String,
    val status: String,
    val prescribedDurationSeconds: Int,
)
@Serializable data class ActivityReconciliation(
    val planningRevision: Long,
    val statisticsRevision: Long,
    val completion: CanonicalWorkoutCompletion? = null,
)

data class AccountRequestContext(val accountId: String, val generation: Long)
