import { z } from "zod";

export const companionTaskSchema = z.enum([
  "answer_training_question",
  "adapt_today",
  "prepare_week",
  "post_run_reflection",
  "live_coaching",
  "inspect_memory",
  "product_help",
]);

export const companionSurfaceSchema = z.enum([
  "assistant",
  "today",
  "post_run",
  "weekly_review",
  "live_session",
  "memory",
]);

export const companionMessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  text: z.string().min(1).max(4000),
});

export const situationalSignalInputSchema = z.object({
  idempotencyKey: z.string().min(1).max(160),
  type: z.string().min(1).max(100),
  value: z.unknown(),
  source: z.string().min(1).max(80),
  confidence: z.number().min(0).max(1).default(1),
  privacy: z.enum(["standard", "approximate_location", "sensitive"]).default("standard"),
  consequenceLevel: z.enum(["low", "medium", "high"]).default("low"),
  possibleEffects: z.array(z.string().min(1).max(80)).max(12).default([]),
  scope: z.record(z.unknown()).default({}),
  observedAt: z.string().datetime(),
  freshUntil: z.string().datetime(),
});

export const companionTurnRequestSchema = z.object({
  task: companionTaskSchema.default("answer_training_question"),
  surface: companionSurfaceSchema.default("assistant"),
  prompt: z.string().min(1).max(8000),
  conversationKey: z.string().min(1).max(160).default("default"),
  recentMessages: z.array(companionMessageSchema).max(12).default([]),
  currentEntityIds: z.array(z.string().min(1)).max(12).default([]),
  clientCapabilities: z.array(z.string().min(1)).max(24).default([]),
  isOffline: z.boolean().default(false),
  timeZoneIdentifier: z.string().max(100).nullable().optional(),
  signals: z.array(situationalSignalInputSchema).max(24).default([]),
});

export const memoryCorrectionSchema = z.object({
  value: z.unknown(),
  summary: z.string().min(1).max(1000),
  label: z.string().min(1).max(160).optional(),
  idempotencyKey: z.string().min(1).max(160),
});

export const memoryForgetSchema = z.object({
  idempotencyKey: z.string().min(1).max(160),
});

export const agentActionDecisionSchema = z.object({
  decision: z.enum(["accept", "reject"]),
});

export type CompanionTask = z.infer<typeof companionTaskSchema>;
export type CompanionSurface = z.infer<typeof companionSurfaceSchema>;
export type CompanionTurnRequest = z.infer<typeof companionTurnRequestSchema>;
export type SituationalSignalInput = z.infer<typeof situationalSignalInputSchema>;

