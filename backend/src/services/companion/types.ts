import type { CompanionSurface, CompanionTask } from "./contracts.js";

export type ContextReference = {
  type: string;
  id: string;
  reason: string;
};

export type CompiledContext = {
  task: CompanionTask;
  surface: CompanionSurface;
  runnerModelVersion: string;
  manifestId: string;
  tokenBudget: number;
  estimatedTokens: number;
  systemRules: string[];
  runnerCore: Record<string, unknown>;
  currentState: Record<string, unknown>;
  beliefs: Array<Record<string, unknown>>;
  episodes: Array<Record<string, unknown>>;
  situationalSignals: Array<Record<string, unknown>>;
  conversation: Record<string, unknown>;
  includedRefs: ContextReference[];
};

export type CompanionActionProposal = {
  actionType: "communicate" | "shorten_workout" | "move_workout" | "update_memory";
  permissionTier: 0 | 1 | 2 | 3;
  requiresConfirmation: boolean;
  workoutId?: string;
  durationMinutes?: number;
  scheduledDate?: string;
  stableKey?: string;
  value?: unknown;
  evidenceIds: string[];
  rationale: string;
};

export type ValidationResult = {
  approved: boolean;
  disposition: "approved" | "confirmation_required" | "question_required" | "rejected";
  reasonCodes: string[];
  normalizedProposal: CompanionActionProposal;
};

