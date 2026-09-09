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
  if (["shorten_workout", "set_workout_calories", "move_workout"].includes(proposal.actionType) && !proposal.workoutId) {
    reasonCodes.push("missing_workout_id");
  }
  if (proposal.actionType === "shorten_workout") {
    if (!proposal.durationMinutes || proposal.durationMinutes < 15) reasonCodes.push("duration_below_reviewed_minimum");
    if (proposal.permissionTier < 2 || !proposal.requiresConfirmation) reasonCodes.push("meaningful_change_requires_confirmation");
  }
  if (proposal.actionType === "set_workout_calories") {
    if (!proposal.targetCalories || proposal.targetCalories < 50 || proposal.targetCalories > 5_000) reasonCodes.push("calorie_target_out_of_range");
    if (proposal.permissionTier < 2 || !proposal.requiresConfirmation) reasonCodes.push("meaningful_change_requires_confirmation");
  }
  if (proposal.actionType === "update_run_goal_preference") {
    if (!proposal.goalType) reasonCodes.push("missing_goal_type");
    if (proposal.permissionTier < 2 || !proposal.requiresConfirmation) reasonCodes.push("meaningful_change_requires_confirmation");
  }
  if (proposal.actionType === "recalibrate_plan") {
    if (!proposal.adjustmentId) reasonCodes.push("missing_adjustment_id");
    if (proposal.permissionTier < 2 || !proposal.requiresConfirmation) reasonCodes.push("meaningful_change_requires_confirmation");
  }
  if (proposal.evidenceIds.length === 0 && !["set_workout_calories", "update_run_goal_preference", "recalibrate_plan"].includes(proposal.actionType)) {
    reasonCodes.push("missing_evidence");
  }
  const approved = reasonCodes.every((code) => code === "context_budget_exceeded");
  return {
    approved,
    disposition: approved ? (proposal.requiresConfirmation ? "confirmation_required" : "approved") : "rejected",
    reasonCodes,
    normalizedProposal: proposal,
    policyVersion: POLICY_VERSION,
  };
}
