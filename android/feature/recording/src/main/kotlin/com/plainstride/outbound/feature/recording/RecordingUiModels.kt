package com.plainstride.outbound.feature.recording

import kotlinx.serialization.Serializable

enum class RecordingGoalType { FREESTYLE, DISTANCE, TIME, CALORIES, WORKOUT }

@Serializable data class RecordingGoal(
    val type: RecordingGoalType = RecordingGoalType.FREESTYLE,
    val targetDistanceMeters: Double? = null,
    val targetDurationSeconds: Long? = null,
    val targetCalories: Int? = null,
)

@Serializable data class StructuredWorkoutStep(
    val title: String,
    val detail: String? = null,
    val durationSeconds:Int?=null,
    val phase:String?=null,
    val targetPaceSecondsPerKilometer:Double?=null,
)

@Serializable data class FollowedRouteConfiguration(val id:String,val name:String,val shape:String?=null,val distanceMeters:Double?=null,val elevationGainMeters:Double?=null,val reverse:Boolean=false,val points:List<RecordingRoutePoint> = emptyList())
@Serializable data class RecordingRoutePoint(val latitude:Double,val longitude:Double,val altitudeMeters:Double?=null)

@Serializable data class RecordingLaunchConfiguration(
    val activityKind: ActivityKind = ActivityKind.RUNNING,
    val title: String? = null,
    val goal: RecordingGoal = RecordingGoal(),
    val workoutSteps: List<StructuredWorkoutStep> = emptyList(),
    val entrySource: String = "quick_start",
    val suggestionId: String? = null,
    val plannedWorkoutId: String? = null,
    val gearId: String? = null,
    val workoutDetail: String? = null,
    val workoutGuideline: String? = null,
    val privateTrainingSignal: String? = null,
    val followedRoute:FollowedRouteConfiguration?=null,
    val indoor: Boolean = false,
    val voiceGuideEnabled: Boolean = true,
    val startImmediately: Boolean = false,
)

enum class RecordingSurfaceMode { MAP, CAMERA }

enum class ReflectionChoice { STRONG, STEADY, TOUGH }
