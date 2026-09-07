package run.plainstride.core.model

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject

@Serializable enum class Modality { run, walk, bike, swim, strength, hiit, skate, mobility }
@Serializable enum class TrainingStimulus { easyAerobic, longEndurance, threshold, speed, strength, hypertrophy, power, skill, recovery, mobility }
@Serializable enum class PlanningStatus { stable, reassessing, updated, needsAttention }
@Serializable enum class PrimaryMotivation { generalFitness, consistency, performance, weightLoss, weightMaintenance }
@Serializable enum class RunGoalType { time, distance, calories }

@Serializable
data class WorkoutStep(
    val id: String,
    val label: String,
    val kind: String,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val detail: String? = null,
    val target: JsonObject? = null,
)

@Serializable
data class WorkoutBlock(
    val id: String? = null,
    val blockType: String,
    val modality: Modality,
    val stimulus: TrainingStimulus,
    val durationSeconds: Int? = null,
    val distanceMeters: Double? = null,
    val repeats: Int? = null,
    val restSeconds: Int? = null,
    val metadata: JsonObject? = null,
    val steps: List<WorkoutStep> = emptyList(),
)

@Serializable
data class PlannedWorkout(
    val id: String,
    val scheduledDate: String,
    val modality: Modality,
    val stimulus: TrainingStimulus,
    val title: String,
    val durationSeconds: Int,
    val distanceMeters: Double? = null,
    val targetCalories: Int? = null,
    val intensityModel: String? = null,
    val intensityTarget: JsonObject? = null,
    val prescription: JsonObject? = null,
    val isKeyWorkout: Boolean,
    val status: String,
    val blocks: List<WorkoutBlock> = emptyList(),
)

@Serializable
data class TrainingGoal(
    val id: String,
    val type: String,
    val primaryModality: Modality,
    val targetDate: String? = null,
    val targetDistanceMeters: Double? = null,
    val targetEventName: String? = null,
    val priority: String? = null,
    val preferredDays: List<String> = emptyList(),
    val daysPerWeekTarget: Int? = null,
    val maxSessionMinutes: Int? = null,
    val riskTolerance: String? = null,
    val primaryMotivation: PrimaryMotivation? = null,
    val preferredRunGoalType: RunGoalType? = null,
    val createdAt: String? = null,
)

@Serializable data class TrainingPlan(val id: String, val currentPhase: String, val createdAt: String? = null)
@Serializable data class PlanVersion(val id: String? = null, val versionNumber: Int, val reason: String, val summary: String)
@Serializable data class AthleteTrainingState(val fatigueRisk: String, val adherenceRate: Double, val consistencyScore: Double, val weeklyMinutes: Int, val weeklyDistanceMeters: Double)
@Serializable data class PlanAdjustment(val id: String? = null, val message: String, val eventType: String, val createdAt: String? = null)

@Serializable
data class PlanningState(
    val goal: TrainingGoal? = null,
    val plan: TrainingPlan? = null,
    val currentVersion: PlanVersion? = null,
    val today: PlannedWorkout? = null,
    val upcoming: List<PlannedWorkout> = emptyList(),
    val athleteState: AthleteTrainingState? = null,
    val latestAdjustment: PlanAdjustment? = null,
    val planningStatus: PlanningStatus,
)

@Serializable
data class ActivitySuggestion(
    val id: String,
    val title: String,
    val modality: Modality,
    val stimulus: TrainingStimulus,
    val durationMinutes: Int,
    val distanceMeters: Double? = null,
    val targetCalories: Int? = null,
    val effortLabel: String,
    val intensityModel: String,
    val intensityTarget: JsonObject? = null,
    val why: String,
    val steps: List<String>,
    val startLabel: String,
    val plannedWorkoutId: String? = null,
    val archetypeId: String? = null,
    val optional: Boolean,
)

@Serializable data class SuggestionPlanContext(val planId: String, val planVersionId: String? = null, val title: String? = null)
@Serializable data class ActivityWatermark(val lastActivityId: String? = null, val lastActivityStartedAt: String? = null)
@Serializable data class SuggestionDecision(val algorithmVersion: String, val reasons: List<String>, val safetyFlags: List<String>)
@Serializable
data class ActivitySuggestionEnvelope(
    val status: String,
    val source: String,
    val relationship: String,
    val primary: ActivitySuggestion? = null,
    val alternates: List<ActivitySuggestion> = emptyList(),
    val guideLine: String,
    val planningStatus: PlanningStatus,
    val generatedAt: String,
    val validForDate: String,
    val validUntil: String,
    val planVersionId: String? = null,
    val planContext: SuggestionPlanContext? = null,
    val activityWatermark: ActivityWatermark,
    val decision: SuggestionDecision,
)

@Serializable enum class CalibrationStatus { notStarted, inProgress, completed, skipped }
@Serializable enum class CalibrationSessionKind { comfortableRun, easyPickups, longerRelaxedRun }
@Serializable data class CalibrationSummary(val status: CalibrationStatus, val completedSessionCount: Int, val targetSessionCount: Int, val currentSession: CalibrationSessionKind? = null)
@Serializable data class CalibrationWorkoutStep(val id: String, val label: String, val durationSeconds: Int, val detail: String)
@Serializable data class CalibrationWorkout(val id: String, val kind: CalibrationSessionKind, val title: String, val purpose: String, val durationSeconds: Int, val steps: List<CalibrationWorkoutStep>)
@Serializable data class RunnerInsight(val id: String, val kind: String, val label: String, val value: String, val confidence: String, val evidenceCount: Int, val lastUpdatedAt: String)
@Serializable data class PlanChange(val workoutId: String, val beforeTitle: String, val afterTitle: String)
@Serializable data class AdjustmentProposal(val id: String, val reasonCode: String, val explanation: String, val requiresConfirmation: Boolean, val changes: List<PlanChange>)
@Serializable
data class PersonalizationSnapshot(
    val contractVersion: Int,
    val modelVersion: String,
    val generatedAt: String,
    val calibration: CalibrationSummary,
    val calibrationWorkouts: List<CalibrationWorkout>,
    val insights: List<RunnerInsight>,
    val pendingAdjustment: AdjustmentProposal? = null,
)

@Serializable
data class TrainingProfile(
    val sexAtBirth: String? = null,
    val birthDate: String? = null,
    val heightCentimeters: Double? = null,
    val weightKilograms: Double? = null,
    val primaryMotivation: PrimaryMotivation,
    val preferredRunGoalType: RunGoalType,
)

@Serializable data class CoachingPaceTarget(val reference: String, val targetSecondsPerKilometer: Double? = null, val athleteReferenceOffsetSeconds: Double, val fasterToleranceSeconds: Double, val slowerToleranceSeconds: Double? = null)
@Serializable data class CoachingTarget(val phase: String, val pace: CoachingPaceTarget? = null, val recognizesTargetLock: Boolean)
@Serializable data class StandaloneWorkoutStep(val id: String, val label: String, val durationSeconds: Int, val detail: String? = null, val coachingTarget: CoachingTarget? = null)
@Serializable data class GuideTrigger(val type: String, val startMeters: Double? = null, val endMeters: Double? = null, val startSeconds: Int? = null, val endSeconds: Int? = null)
@Serializable data class GuideEffort(val rpeMin: Int, val rpeMax: Int, val feel: String)
@Serializable data class GuideInstruction(val id: String, val trigger: GuideTrigger, val effort: GuideEffort, val instruction: String, val cue: String, val fallback: String)
@Serializable data class GuideInstructions(val objective: String, val beforeStart: List<String>, val segments: List<GuideInstruction>, val finish: List<String>, val stopConditions: List<String>)
@Serializable
data class StandaloneWorkout(
    val id: String,
    val title: String,
    val subtitle: String,
    val durationLabel: String,
    val systemImage: String,
    val sport: String,
    val category: String,
    val detail: String,
    val guideLine: String,
    val startLabel: String,
    val targetDistanceMeters: Double? = null,
    val targetDurationSeconds: Int? = null,
    val steps: List<StandaloneWorkoutStep>,
    val coachingTarget: CoachingTarget? = null,
    val prerequisites: List<String>,
    val guideInstructions: GuideInstructions,
    val sourceRefs: List<String>,
)
@Serializable data class StandaloneWorkoutCatalog(val version: Int, val locale: String, val measurementSystem: String, val workouts: List<StandaloneWorkout>)
