import { z } from "zod";

export const confidenceLevelSchema = z.enum(["low", "medium", "high"]);
export type ConfidenceLevel = z.infer<typeof confidenceLevelSchema>;

export const calibrationStatusSchema = z.enum(["notStarted", "inProgress", "completed", "skipped"]);
export const calibrationSessionKindSchema = z.enum([
  "comfortableRun",
  "easyPickups",
  "longerRelaxedRun",
]);
export type CalibrationSessionKind = z.infer<typeof calibrationSessionKindSchema>;

export const calibrationWorkoutSchema = z.object({
  id: z.string().min(1),
  kind: calibrationSessionKindSchema,
  title: z.string().min(1),
  purpose: z.string().min(1),
  durationSeconds: z.number().int().positive(),
  steps: z.array(z.object({
    id: z.string().min(1),
    label: z.string().min(1),
    durationSeconds: z.number().int().positive(),
    detail: z.string().min(1),
  })).min(1),
});

export const calibrationSummarySchema = z.object({
  status: calibrationStatusSchema,
  completedSessionCount: z.number().int().nonnegative(),
  targetSessionCount: z.number().int().positive(),
  currentSession: calibrationSessionKindSchema.nullable(),
});
export type CalibrationSummary = z.infer<typeof calibrationSummarySchema>;

export const runnerInsightSchema = z.object({
  id: z.string().min(1),
  kind: z.enum(["effort", "endurance", "recovery", "schedule", "preference", "consistency"]),
  label: z.string().min(1),
  value: z.string().min(1),
  confidence: confidenceLevelSchema,
  evidenceCount: z.number().int().nonnegative(),
  lastUpdatedAt: z.string().datetime(),
});
export type RunnerInsight = z.infer<typeof runnerInsightSchema>;

export const planChangeSchema = z.object({
  workoutId: z.string().min(1),
  beforeTitle: z.string().min(1),
  afterTitle: z.string().min(1),
});

export const adjustmentProposalSchema = z.object({
  id: z.string().min(1),
  reasonCode: z.enum([
    "fatigue",
    "soreness",
    "timeConstraint",
    "harderThanExpected",
    "missedWorkout",
    "improving",
  ]),
  explanation: z.string().min(1),
  requiresConfirmation: z.boolean(),
  changes: z.array(planChangeSchema).min(1),
});
export type AdjustmentProposal = z.infer<typeof adjustmentProposalSchema>;

export const personalizationSnapshotSchema = z.object({
  contractVersion: z.literal(1),
  modelVersion: z.string().min(1),
  generatedAt: z.string().datetime(),
  calibration: calibrationSummarySchema,
  calibrationWorkouts: z.array(calibrationWorkoutSchema),
  insights: z.array(runnerInsightSchema),
  pendingAdjustment: adjustmentProposalSchema.nullable(),
});
export type PersonalizationSnapshot = z.infer<typeof personalizationSnapshotSchema>;

export const readinessChoiceSchema = z.enum(["good", "tired", "sore", "shortOnTime"]);
export const readinessCheckInRequestSchema = z.object({
  idempotencyKey: z.string().min(1),
  workoutId: z.string().min(1),
  recordedAt: z.string().datetime(),
  choice: readinessChoiceSchema,
  note: z.string().max(1000).nullable().optional(),
});
export type ReadinessCheckInRequest = z.infer<typeof readinessCheckInRequestSchema>;

export const workoutFeedbackRequestSchema = z.object({
  idempotencyKey: z.string().min(1),
  workoutId: z.string().min(1),
  activityId: z.string().min(1).nullable().optional(),
  recordedAt: z.string().datetime(),
  effort: z.enum(["easy", "aboutRight", "tooHard"]),
  continuationCapacity: z.enum(["none", "tenMinutes", "muchLonger"]).nullable().optional(),
  note: z.string().max(1000).nullable().optional(),
});
export type WorkoutFeedbackRequest = z.infer<typeof workoutFeedbackRequestSchema>;

export const runnerProfileInputSchema = z.object({
  goalSummary: z.string().min(1).max(500).nullable().optional(),
  scheduleSummary: z.string().min(1).max(500).nullable().optional(),
  comfortableDurationMinutes: z.number().int().min(5).max(360).nullable().optional(),
  recentSessionsPerWeek: z.number().int().min(0).max(14).nullable().optional(),
  targetSessionsPerWeek: z.number().int().min(1).max(7).optional(),
  preferredLongRunDay: z.string().min(1).max(16).nullable().optional(),
  coachingDetail: z.enum(["minimal", "balanced", "detailed"]).optional(),
  constraints: z.record(z.unknown()).optional(),
  complete: z.boolean().optional(),
});
export type RunnerProfileInput = z.infer<typeof runnerProfileInputSchema>;

export const adjustmentDecisionSchema = z.object({
  decision: z.enum(["accept", "reject"]),
});

export const personalizationContractSchemas = {
  snapshot: personalizationSnapshotSchema,
  readinessRequest: readinessCheckInRequestSchema,
  workoutFeedbackRequest: workoutFeedbackRequestSchema,
  runnerProfileInput: runnerProfileInputSchema,
  adjustmentDecision: adjustmentDecisionSchema,
} as const;
