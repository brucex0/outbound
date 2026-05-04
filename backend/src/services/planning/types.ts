export type Modality =
  | "run"
  | "walk"
  | "bike"
  | "swim"
  | "strength"
  | "hiit"
  | "skate"
  | "mobility";

export type TrainingStimulus =
  | "easyAerobic"
  | "longEndurance"
  | "threshold"
  | "speed"
  | "strength"
  | "hypertrophy"
  | "power"
  | "skill"
  | "recovery"
  | "mobility";

export type PlanningEventType =
  | "activityCompleted"
  | "workoutSkipped"
  | "readinessSubmitted"
  | "goalUpdated"
  | "scheduleUpdated"
  | "weeklyRollover"
  | "manualRebuild"
  | "healthImportCompleted"
  | "painFlagged";

export type PlanningStatus = "stable" | "reassessing" | "updated" | "needsAttention";

export type TrainingPlanPhase = "base" | "build" | "sharpen" | "taper" | "recovery" | "maintenance";

export interface CreateTrainingGoalInput {
  type: string;
  primaryModality?: Modality;
  targetDate?: string | null;
  targetDistanceMeters?: number | null;
  targetEventName?: string | null;
  priority?: string;
  preferredDays?: string[];
  daysPerWeekTarget?: number;
  maxSessionMinutes?: number;
  riskTolerance?: "conservative" | "balanced" | "stretch";
  constraints?: Record<string, unknown>;
}

export interface SubmitReadinessInput {
  date?: string;
  energy?: number;
  soreness?: number;
  sleepQuality?: number;
  stress?: number;
  motivation?: number;
  illnessOrPain?: boolean;
  notes?: string | null;
}

export interface CompleteWorkoutInput {
  activityId?: string | null;
  completedAt?: string;
  durationSeconds?: number | null;
  distanceMeters?: number | null;
  avgPace?: number | null;
  avgHeartRate?: number | null;
  avgPower?: number | null;
  perceivedEffort?: number | null;
  completionQuality?: string;
  notes?: string | null;
}

export interface RebuildPlanInput {
  reason?: PlanningEventType;
}

export interface ActivityForPlanning {
  id: string;
  type: string;
  startedAt: Date;
  durationSecs: number | null;
  distanceM: number | null;
  avgPace: number | null;
  avgHeartRate: number | null;
}

export interface ReadinessForPlanning {
  date: Date;
  energy: number;
  soreness: number;
  sleepQuality: number;
  stress: number;
  motivation: number;
  illnessOrPain: boolean;
}

export interface PlannedWorkoutForState {
  id: string;
  scheduledDate: Date;
  modality: string;
  stimulus: string;
  durationSeconds: number;
  distanceMeters: number | null;
  isKeyWorkout: boolean;
  status: string;
}

export interface AthleteTrainingStateSnapshot {
  asOfDate: Date;
  overallLoadScore: number;
  weeklyMinutes: number;
  weeklyDistanceMeters: number;
  fourWeekAvgMinutes: number;
  fourWeekAvgDistanceMeters: number;
  longestRecentSessionSeconds: number;
  adherenceRate: number;
  consistencyScore: number;
  fatigueRisk: "low" | "medium" | "high";
  lastHardWorkoutAt: Date | null;
  modalityBreakdown: Record<string, unknown>;
}

export interface WorkoutStepDraft {
  label: string;
  kind: string;
  durationSeconds?: number | null;
  distanceMeters?: number | null;
  target?: Record<string, unknown> | null;
  detail?: string | null;
}

export interface WorkoutBlockDraft {
  blockType: string;
  modality: Modality;
  stimulus: TrainingStimulus;
  durationSeconds?: number | null;
  distanceMeters?: number | null;
  repeats?: number | null;
  restSeconds?: number | null;
  metadata?: Record<string, unknown>;
  steps: WorkoutStepDraft[];
}

export interface PlannedWorkoutDraft {
  scheduledDate: Date;
  modality: Modality;
  stimulus: TrainingStimulus;
  title: string;
  durationSeconds: number;
  distanceMeters?: number | null;
  intensityModel: string;
  intensityTarget?: Record<string, unknown> | null;
  prescription: Record<string, unknown>;
  isKeyWorkout: boolean;
  blocks: WorkoutBlockDraft[];
}

export interface TrainingStressEstimate {
  score: number;
  hard: boolean;
}

export interface CompletionEvaluationInput {
  workout: PlannedWorkoutForState;
  completion: CompleteWorkoutInput;
}

export type CompletionQuality = "completed" | "partial" | "tooHard" | "feltEasy" | "differentWorkout";

export interface StimulusRequest {
  modality: Modality;
  stimulus: TrainingStimulus;
}

export interface WorkoutGenerationInput {
  scheduledDate: Date;
  modality: Modality;
  stimulus: TrainingStimulus;
  durationMinutes: number;
  isKeyWorkout?: boolean;
  athleteState: AthleteTrainingStateSnapshot;
}

export interface ProgressionInput {
  athleteState: AthleteTrainingStateSnapshot;
  previousWorkout?: PlannedWorkoutForState;
}

export interface ModalityProgression {
  durationMinutes: number;
}

export interface ModalityAdapter {
  modality: Modality;
  canSatisfy(input: StimulusRequest): boolean;
  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft;
  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate;
  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality;
  progress(input: ProgressionInput): ModalityProgression;
}

export interface PlanGenerationResult {
  summary: string;
  phase: TrainingPlanPhase;
  workouts: PlannedWorkoutDraft[];
  engineDecision: Record<string, unknown>;
}

export interface PlanningEventResult {
  eventId: string;
  status: "completed" | "ignored" | "failed";
  createdVersionId?: string;
  message: string;
}

export interface PlanningState {
  goal: unknown | null;
  plan: unknown | null;
  currentVersion: unknown | null;
  today: unknown | null;
  upcoming: unknown[];
  athleteState: unknown | null;
  latestAdjustment: unknown | null;
  planningStatus: PlanningStatus;
}

export interface TodayPlanningResponse {
  workout: unknown | null;
  adjustment: unknown | null;
  coachLine: string;
  planningStatus: PlanningStatus;
}
