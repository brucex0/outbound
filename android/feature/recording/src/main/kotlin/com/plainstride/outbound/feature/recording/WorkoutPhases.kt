package com.plainstride.outbound.feature.recording

/** One authored timeline for the full dashboard, compact phase, and coach section identity. */
data class WorkoutPhase(
    val title: String,
    val detail: String?,
    val startSeconds: Long? = null,
    val endSeconds: Long? = null,
    val startMeters: Double? = null,
    val endMeters: Double? = null,
    val instructionId: String? = null,
) {
    fun progress(elapsedSeconds: Long, distanceMeters: Double): Float = if (endMeters != null && startMeters != null) {
        ((distanceMeters - startMeters) / (endMeters - startMeters)).coerceIn(0.0, 1.0).toFloat()
    } else {
        ((elapsedSeconds - (startSeconds ?: 0)).toDouble() / ((endSeconds ?: 1) - (startSeconds ?: 0))).coerceIn(0.0, 1.0).toFloat()
    }
    fun hasStarted(elapsedSeconds: Long, distanceMeters: Double): Boolean =
        startMeters?.let { distanceMeters >= it } ?: (elapsedSeconds >= (startSeconds ?: 0))
    fun isComplete(elapsedSeconds: Long, distanceMeters: Double): Boolean =
        endMeters?.let { distanceMeters >= it } ?: (elapsedSeconds >= (endSeconds ?: Long.MAX_VALUE))
}

fun RecordingLaunchConfiguration.workoutPhases(): List<WorkoutPhase> {
    val timed = workoutSteps.filter { (it.durationSeconds ?: 0) > 0 }
    if (timed.isNotEmpty()) {
        var elapsed = 0L
        return timed.map { step ->
            val start = elapsed
            elapsed += requireNotNull(step.durationSeconds)
            WorkoutPhase(step.title, step.detail, startSeconds = start, endSeconds = elapsed)
        }
    }
    return guideInstructions?.segments.orEmpty().mapNotNull { instruction ->
        val trigger = instruction.trigger
        when (trigger.type) {
            "distance" -> {
                val start = trigger.startMeters?.takeIf { it.isFinite() && it >= 0 } ?: return@mapNotNull null
                val end = trigger.endMeters?.takeIf { it.isFinite() && it > start } ?: return@mapNotNull null
                WorkoutPhase(instruction.effort.feel, instruction.instruction, startMeters = start, endMeters = end, instructionId = instruction.id)
            }
            "elapsed_time" -> {
                val start = trigger.startSeconds?.takeIf { it >= 0 } ?: return@mapNotNull null
                val end = trigger.endSeconds?.takeIf { it > start } ?: return@mapNotNull null
                WorkoutPhase(instruction.effort.feel, instruction.instruction, startSeconds = start.toLong(), endSeconds = end.toLong(), instructionId = instruction.id)
            }
            else -> null
        }
    }
}

fun List<WorkoutPhase>.currentPhaseIndex(elapsedSeconds: Long, distanceMeters: Double): Int? =
    indexOfFirst { it.hasStarted(elapsedSeconds, distanceMeters) && !it.isComplete(elapsedSeconds, distanceMeters) }
        .takeIf { it >= 0 }
