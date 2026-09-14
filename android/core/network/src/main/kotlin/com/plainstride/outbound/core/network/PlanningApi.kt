package com.plainstride.outbound.core.network

import kotlinx.serialization.Serializable
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import retrofit2.Response
import retrofit2.Retrofit
import retrofit2.converter.kotlinx.serialization.asConverterFactory
import retrofit2.http.Body
import retrofit2.http.DELETE
import retrofit2.http.GET
import retrofit2.http.Header
import retrofit2.http.PATCH
import retrofit2.http.POST
import retrofit2.http.PUT
import retrofit2.http.Path
import retrofit2.http.Query
import com.plainstride.outbound.core.model.ActivitySuggestionEnvelope
import com.plainstride.outbound.core.model.AdjustmentProposal
import com.plainstride.outbound.core.model.Modality
import com.plainstride.outbound.core.model.PersonalizationSnapshot
import com.plainstride.outbound.core.model.PlanningState
import com.plainstride.outbound.core.model.PrimaryMotivation
import com.plainstride.outbound.core.model.RunGoalType
import com.plainstride.outbound.core.model.StandaloneWorkoutCatalog
import com.plainstride.outbound.core.model.TrainingProfile

@Serializable
data class CreateTrainingGoalRequest(
    val type: String,
    val activities: List<Modality>,
    val baselineContext: String? = null,
    val targetDate: String? = null,
    val targetDistanceMeters: Double? = null,
    val targetEventName: String? = null,
    val eventIntent: String? = null,
    val targetTimeSeconds: Int? = null,
    val reviewHorizonWeeks: Int? = null,
    val successSignal: String? = null,
    val goalDescription: String? = null,
    val intakeContextVersion: String? = null,
    val priority: String? = null,
    val preferredDays: List<String>? = null,
    val daysPerWeekTarget: Int? = null,
    val maxSessionMinutes: Int? = null,
    val riskTolerance: String? = null,
    val primaryMotivation: PrimaryMotivation? = null,
    val preferredRunGoalType: RunGoalType? = null,
    val constraints: Map<String, String>? = null,
)

@Serializable data class PlanIntakeBodyProfile(val sexAtBirth:String?=null,val birthDate:String?=null,val heightCentimeters:Double?=null,val weightKilograms:Double?=null,val completeForPlanning:Boolean=false,val source:String="unknown")
@Serializable data class PlanIntakeObservedBaseline(val source:String,val confidence:String,val windowDays:Int,val sessionCount:Int,val activeWeekCount:Int,val sessionsPerWeek:Int,val comfortableMinutes:Int?=null,val longestSessionMinutes:Int?=null,val latestActivityAt:String?=null,val activityMix:List<String> = emptyList())
@Serializable data class PlanIntakePreviousSchedule(val source:String,val preferredDays:List<String>,val sessionsPerWeek:Int,val maxSessionMinutes:Int,val requiresConfirmation:Boolean)
@Serializable data class PlanIntakeContext(val contractVersion:Int,val policyVersion:String,val contextVersion:String,val dataTier:String,val evidenceState:String,val questions:List<String>,val bodyProfile:PlanIntakeBodyProfile,val observedBaseline:PlanIntakeObservedBaseline?=null,val previousSchedule:PlanIntakePreviousSchedule?=null,val requiredBodyFields:List<String>)
@Serializable data class PlanIntakeDraftRequest(val objective:String?=null,val activities:List<String> = emptyList(),val eventDate:String?=null,val eventDistanceMeters:Double?=null,val eventIntent:String?=null,val targetTimeSeconds:Int?=null,val reviewHorizonWeeks:Int?=null,val sessionsPerWeek:Int?=null,val maxSessionMinutes:Int?=null)
@Serializable data class PlanIntakeInterpretRequest(val message:String,val contextVersion:String,val draft:PlanIntakeDraftRequest)
@Serializable data class PlanIntakeInterpretation(val objective:String?=null,val activities:List<String> = emptyList(),val eventDate:String?=null,val eventDistanceMeters:Double?=null,val eventIntent:String?=null,val targetTimeSeconds:Int?=null,val reviewHorizonWeeks:Int?=null,val goalDescription:String?=null,val recognizedFields:List<String> = emptyList(),val assistantReply:String)

@Serializable data class PlanningReadinessRequest(val date: String? = null, val energy: Int? = null, val soreness: Int? = null, val sleepQuality: Int? = null, val stress: Int? = null, val motivation: Int? = null, val illnessOrPain: Boolean? = null, val notes: String? = null)
@Serializable data class PlannedWorkoutCompletionRequest(val activityId: String? = null, val completedAt: String? = null, val durationSeconds: Int? = null, val distanceMeters: Double? = null, val targetCalories: Int? = null, val energyKilocalories: Int? = null, val avgPace: Double? = null, val avgHeartRate: Int? = null, val avgPower: Double? = null, val perceivedEffort: Int? = null, val completionQuality: String? = null, val notes: String? = null)
@Serializable data class ReadinessCheckInRequest(val idempotencyKey: String, val workoutId: String, val recordedAt: String, val choice: String, val note: String? = null)
@Serializable data class WorkoutFeedbackRequest(val idempotencyKey: String, val workoutId: String, val activityId: String? = null, val recordedAt: String, val effort: String, val continuationCapacity: String? = null, val note: String? = null)
@Serializable data class RunnerProfileRequest(val goalSummary: String? = null, val scheduleSummary: String? = null, val comfortableDurationMinutes: Int? = null, val recentSessionsPerWeek: Int? = null, val targetSessionsPerWeek: Int? = null, val preferredLongRunDay: String? = null, val guidanceDetail: String? = null, val primaryMotivation: PrimaryMotivation? = null, val preferredRunGoalType: RunGoalType? = null, val constraints: Map<String, String>? = null, val complete: Boolean? = null)
@Serializable data class TrainingProfileRequest(val sexAtBirth: String? = null, val birthDate: String? = null, val heightCentimeters: Double? = null, val weightKilograms: Double? = null, val primaryMotivation: PrimaryMotivation, val preferredRunGoalType: RunGoalType)
@Serializable data class AdjustmentDecisionRequest(val decision: String)
@Serializable data class CycleTrainingSignalRequest(val signal:String,val workoutId:String?=null,val day:String,val idempotencyKey:String)
@Serializable data class CycleTrainingSignalResponse(val workoutId:String?=null,val day:String,val signal:String,val action:String,val explanation:String,val rawHealthDataStored:Boolean)
@Serializable data class PersonalizationMutationResponse(val accepted: Boolean? = null, val adjustment: AdjustmentProposal? = null, val personalization: PersonalizationSnapshot)

interface PlanningApiService {
    @GET("v1/planning/state") suspend fun state(@Header("Authorization") authorization: String): Response<PlanningState>
    @GET("v1/planning/activity-suggestion") suspend fun activitySuggestion(@Header("Authorization") authorization: String): Response<ActivitySuggestionEnvelope>
    @GET("v1/planning/standalone-workouts") suspend fun standaloneWorkouts(@Header("Authorization") authorization: String): Response<StandaloneWorkoutCatalog>
    @POST("v1/planning/goals") suspend fun createGoal(@Header("Authorization") authorization: String, @Body body: CreateTrainingGoalRequest): Response<PlanningState>
    @GET("v1/planning/intake-context") suspend fun planIntakeContext(@Header("Authorization") authorization: String, @Query("objective") objective: String? = null): Response<PlanIntakeContext>
    @POST("v1/planning/intake/interpret") suspend fun interpretPlanIntake(@Header("Authorization") authorization: String, @Body body: PlanIntakeInterpretRequest): Response<PlanIntakeInterpretation>
    @POST("v1/planning/readiness") suspend fun submitPlanningReadiness(@Header("Authorization") authorization: String, @Body body: PlanningReadinessRequest): Response<PlanningState>
    @POST("v1/planning/workouts/{id}/skip") suspend fun skipWorkout(@Header("Authorization") authorization: String, @Path("id") workoutId: String): Response<PlanningState>
    @POST("v1/planning/workouts/{id}/complete") suspend fun completeWorkout(@Header("Authorization") authorization: String, @Path("id") workoutId: String, @Body body: PlannedWorkoutCompletionRequest): Response<PlanningState>
    @DELETE("v1/planning/plan") suspend fun clearPlan(@Header("Authorization") authorization: String): Response<PlanningState>
    @GET("v1/personalization/snapshot") suspend fun personalization(@Header("Authorization") authorization: String): Response<PersonalizationSnapshot>
    @PUT("v1/personalization/profile") suspend fun updateProfile(@Header("Authorization") authorization: String, @Body body: RunnerProfileRequest): Response<PersonalizationMutationResponse>
    @GET("v1/personalization/profile/training") suspend fun trainingProfile(@Header("Authorization") authorization: String): Response<TrainingProfile>
    @PATCH("v1/personalization/profile/training") suspend fun updateTrainingProfile(@Header("Authorization") authorization: String, @Body body: TrainingProfileRequest): Response<TrainingProfile>
    @POST("v1/personalization/readiness") suspend fun submitReadiness(@Header("Authorization") authorization: String, @Body body: ReadinessCheckInRequest): Response<PersonalizationMutationResponse>
    @POST("v1/personalization/cycle-signal") suspend fun submitCycleSignal(@Header("Authorization") authorization:String,@Body body:CycleTrainingSignalRequest):Response<CycleTrainingSignalResponse>
    @POST("v1/personalization/workouts/{id}/feedback") suspend fun feedback(@Header("Authorization") authorization: String, @Path("id") workoutId: String, @Body body: WorkoutFeedbackRequest): Response<PersonalizationMutationResponse>
    @POST("v1/personalization/adjustments/{id}/decision") suspend fun adjustmentDecision(@Header("Authorization") authorization: String, @Path("id") adjustmentId: String, @Body body: AdjustmentDecisionRequest): Response<AdjustmentProposal>
}

fun createPlanningApi(baseUrl: String, client: OkHttpClient): PlanningApiService = Retrofit.Builder()
    .baseUrl(if (baseUrl.endsWith('/')) baseUrl else "$baseUrl/")
    .client(client)
    .addConverterFactory(PlainstrideJson.asConverterFactory("application/json".toMediaType()))
    .build()
    .create(PlanningApiService::class.java)
