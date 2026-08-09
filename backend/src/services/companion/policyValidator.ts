import type { CompiledContext, CompanionActionProposal, ValidationResult } from "./types.js";

const POLICY_VERSION = "companion-policy-v1";

export function validateCompanionProposal(
  proposal: CompanionActionProposal,
  context: CompiledContext
): ValidationResult & { policyVersion: string } {
  const reasonCodes: string[] = [];
  if (context.estimatedTokens > context.tokenBudget) reasonCodes.push("context_budget_exceeded");
  if (proposal.actionType === "communicate") {
    return { approved: true, disposition: "approved", reasonCodes, normalizedProposal: proposal, policyVersion: POLICY_VERSION };
  }
  if (!proposal.workoutId) reasonCodes.push("missing_workout_id");
  if (proposal.actionType === "shorten_workout") {
    if (!proposal.durationMinutes || proposal.durationMinutes < 15) reasonCodes.push("duration_below_reviewed_minimum");
    if (proposal.permissionTier < 2 || !proposal.requiresConfirmation) reasonCodes.push("meaningful_change_requires_confirmation");
  }
  if (proposal.evidenceIds.length === 0) reasonCodes.push("missing_evidence");
  const approved = reasonCodes.every((code) => code === "context_budget_exceeded");
  return {
    approved,
    disposition: approved ? (proposal.requiresConfirmation ? "confirmation_required" : "approved") : "rejected",
    reasonCodes,
    normalizedProposal: proposal,
    policyVersion: POLICY_VERSION,
  };
}

