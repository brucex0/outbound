package run.plainstride.feature.recording

enum class RecordingGoalType { FREESTYLE, DISTANCE, TIME, CALORIES, WORKOUT }

data class RecordingGoal(
    val type: RecordingGoalType = RecordingGoalType.FREESTYLE,
    val targetDistanceMeters: Double? = null,
    val targetDurationSeconds: Long? = null,
    val targetCalories: Int? = null,
)

data class StructuredWorkoutStep(
    val title: String,
    val detail: String? = null,
)

data class RecordingLaunchConfiguration(
    val activityKind: ActivityKind = ActivityKind.RUNNING,
    val title: String? = null,
    val goal: RecordingGoal = RecordingGoal(),
    val workoutSteps: List<StructuredWorkoutStep> = emptyList(),
    val entrySource: String = "quick_start",
    val suggestionId: String? = null,
    val plannedWorkoutId: String? = null,
    val gearId: String? = null,
)

enum class RecordingSurfaceMode { MAP, CAMERA }

enum class ReflectionChoice { STRONG, STEADY, TOUGH }
