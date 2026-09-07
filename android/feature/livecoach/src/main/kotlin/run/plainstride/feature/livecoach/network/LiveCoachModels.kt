package run.plainstride.feature.livecoach.network

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable enum class LiveCoachMode { @SerialName("disabled") Disabled, @SerialName("fixed_only") FixedOnly, @SerialName("dynamic") Dynamic }
@Serializable enum class CoachingContract { @SerialName("quiet") Quiet, @SerialName("responsive") Responsive, @SerialName("coach_me") CoachMe }
@Serializable enum class LiveCoachMoment {
    @SerialName("progress") Progress, @SerialName("early_overpace") EarlyOverpace,
    @SerialName("pace_above_target") PaceAboveTarget, @SerialName("pace_below_target") PaceBelowTarget,
    @SerialName("pace_instability") PaceInstability, @SerialName("target_locked") TargetLocked,
    @SerialName("pace_drift") PaceDrift, @SerialName("rhythm_recovery") RhythmRecovery,
    @SerialName("recovery_too_hard") RecoveryTooHard, @SerialName("unexpected_stop") UnexpectedStop,
    @SerialName("resume_after_break") ResumeAfterBreak, @SerialName("climb_start") ClimbStart,
    @SerialName("crest_recovery") CrestRecovery, @SerialName("segment_transition") SegmentTransition,
    @SerialName("finish_opportunity") FinishOpportunity, @SerialName("challenge_start") ChallengeStart,
    @SerialName("challenge_complete") ChallengeComplete, @SerialName("workout_instruction") WorkoutInstruction,
}
@Serializable enum class CueSource { @SerialName("dynamic_generation") Dynamic, @SerialName("planned_cache") Planned, @SerialName("fixed_pack") Fixed, @SerialName("cached_fallback") Cached }
@Serializable enum class CueResult { @SerialName("success") Success, @SerialName("offline") Offline, @SerialName("timeout") Timeout, @SerialName("stale") Stale, @SerialName("invalid") Invalid, @SerialName("unavailable") Unavailable, @SerialName("feature_disabled") FeatureDisabled, @SerialName("entitlement_required") EntitlementRequired, @SerialName("quota_exhausted") QuotaExhausted, @SerialName("budget_exhausted") BudgetExhausted }

@Serializable data class LiveCoachConfig(val contractVersion: Int, val configVersion: String, val mode: LiveCoachMode, val catalogVersion: String, val access: Access)
@Serializable data class Access(val dynamicCoaching: String, val reason: String, val paywallAvailable: Boolean)
@Serializable data class AudioPackRef(val manifestVersion: String, val manifestUrl: String)
@Serializable data class LiveCoachCatalog(val contractVersion: Int, val catalogVersion: String, val coachPersonas: List<CoachPersona>, val voices: List<VoiceProfile>, val audioPack: AudioPackRef? = null)
@Serializable data class CoachPersona(val id: String, val displayName: String, val description: String, val defaultVoiceProfileId: String, val allowedVoiceProfileIds: List<String>, val fixedScriptStyleId: String, val access: String)
@Serializable data class VoiceProfile(val id: String, val displayName: String, val description: String, val style: String, val presentation: String, val previewAssetId: String)

@Serializable data class CreateSessionRequest(
    val contractVersion: Int = 1, val clientSessionId: String, val workoutId: String? = null,
    val workoutRef: WorkoutReference? = null, val locale: String, val coachPersonaId: String,
    val voiceProfileId: String, val coachingContract: CoachingContract, val measurementUnitSystem: String,
    val sessionIntent: SessionIntent, val clientWorkout: ClientWorkout? = null,
    val environment: Environment? = null, val appDistributionHint: String = "global",
)
@Serializable data class WorkoutReference(val source: String = "standalone_catalog", val id: String, val version: Int? = null)
@Serializable data class SessionIntent(val activityType: String, val goalType: String)
@Serializable data class ClientWorkout(val title: String, val detail: String, val guideLine: String, val targetDistanceMeters: Double? = null, val targetDurationSeconds: Int? = null, val targetCalories: Int? = null, val steps: List<WorkoutStep>, val route: WorkoutRoute? = null)
@Serializable data class WorkoutStep(val label: String, val durationSeconds: Int, val detail: String? = null, val phase: String? = null, val targetPaceSecondsPerKilometer: Double? = null)
@Serializable data class WorkoutRoute(val name: String? = null, val shape: String? = null, val direction: String? = null, val distanceMeters: Double? = null, val elevationGainMeters: Double? = null, val approximateStartLatitude: Double? = null, val approximateStartLongitude: Double? = null, val approximateStartAltitudeMeters: Double? = null)
@Serializable data class Environment(val timeZoneIdentifier: String? = null, val indoor: Boolean, val approximateLocation: ApproximateLocation? = null, val weather: Weather? = null)
@Serializable data class ApproximateLocation(val placeName: String? = null, val latitude: Double? = null, val longitude: Double? = null, val altitudeMeters: Double? = null)
@Serializable data class Weather(val observedAt: String, val condition: String, val temperatureCelsius: Double, val apparentTemperatureCelsius: Double, val windKilometersPerHour: Double, val precipitationChance: Double, val impact: String, val headline: String, val guidance: String? = null, val bestWindow: String? = null)

@Serializable data class CreateSessionResponse(val contractVersion: Int, val sessionId: String, val contextVersion: Int, val expiresAt: String, val effectiveMode: LiveCoachMode, val dynamicCoachingAvailable: Boolean, val access: Access, val audioPack: AudioPackRef, val limits: Limits, val guidancePlan: GuidancePlan, val guidancePlanHash: String, val planner: Planner)
@Serializable data class Limits(val cueValidityMilliseconds: Int, val maximumDynamicCues: Int)
@Serializable data class Planner(val status: String, val model: String? = null, val promptVersion: String)
@Serializable data class GuidancePlan(val contractVersion: Int, val planVersion: String, val locale: String, val summary: String, val progressPolicy: ProgressPolicy, val cues: List<PlanCue>)
@Serializable data class ProgressPolicy(val announceEverySeconds: Int, val announceEveryMeters: Double, val includePace: Boolean)
@Serializable data class PlanCue(val id: String, val moment: LiveCoachMoment, val instructionId: String? = null, val trigger: CueTrigger? = null, val phases: List<String>, val priority: String, val cooldownSeconds: Int, val phrases: List<Phrase>)
@Serializable data class CueTrigger(val type: String, val startMeters: Double? = null, val endMeters: Double? = null, val startSeconds: Int? = null, val endSeconds: Int? = null)
@Serializable data class Phrase(val id: String, val text: String)

@Serializable data class CueRequest(val contractVersion: Int = 1, val cueRequestId: String, val moment: LiveCoachMoment, val detectedAtElapsedSeconds: Int, val validForMilliseconds: Int, val selectedPhraseId: String? = null, val liveState: LiveState)
@Serializable data class LiveState(val elapsedSeconds: Int, val distanceMeters: Double, val currentPaceSecondsPerKilometer: Double? = null, val rollingPaceSecondsPerKilometer: Double? = null, val targetPaceSecondsPerKilometer: Double? = null, val gradePercent: Double? = null, val workoutSegmentIndex: Int? = null, val workoutSegmentPhase: String? = null, val routeGuidanceActive: Boolean)
@Serializable data class CueEnvelope(val contractVersion: Int, val cueRequestId: String, val source: CueSource, val result: CueResult, val moment: LiveCoachMoment, val urgency: String, val transcript: String, val fixedCueKey: String? = null, val audio: InlineAudio? = null, val generatedAt: String, val expiresAt: String)
@Serializable data class InlineAudio(val contentType: String, val base64: String, val durationMilliseconds: Int)
@Serializable data class EndSessionRequest(val contractVersion: Int = 1, val spokenCueCount: Int, val helpfulCueCount: Int, val outcome: String)
@Serializable data class Ack(val contractVersion: Int, val recorded: Boolean? = null, val ended: Boolean? = null)
