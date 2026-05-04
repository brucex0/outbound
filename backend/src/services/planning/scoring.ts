import type { AthleteTrainingStateSnapshot, PlannedWorkoutDraft } from "./types.js";

export interface PlanCandidate {
  id: string;
  workouts: PlannedWorkoutDraft[];
  summary: string;
}

export interface CandidateScore {
  total: number;
  safety: number;
  adherenceLikelihood: number;
  goalSpecificity: number;
  scheduleFit: number;
  fatigueRisk: number;
  progressionValue: number;
  reasons: string[];
}

export function scoreCandidate(
  candidate: PlanCandidate,
  athleteState: AthleteTrainingStateSnapshot
): CandidateScore {
  const weeklyMinutes = candidate.workouts.reduce((sum, workout) => sum + workout.durationSeconds / 60, 0) / 2;
  const target = Math.max(30, athleteState.fourWeekAvgMinutes || weeklyMinutes);
  const loadRatio = target > 0 ? weeklyMinutes / target : 1;
  const safety = loadRatio > 1.35 ? 0.25 : loadRatio > 1.2 ? 0.65 : 1;
  const fatigueRisk = athleteState.fatigueRisk === "high" ? 0.45 : athleteState.fatigueRisk === "medium" ? 0.75 : 1;
  const adherenceLikelihood = Math.min(1, athleteState.adherenceRate + 0.15);
  const goalSpecificity = candidate.workouts.some((workout) => workout.stimulus === "longEndurance") ? 0.9 : 0.75;
  const scheduleFit = candidate.workouts.length > 0 ? 1 : 0;
  const progressionValue = loadRatio < 0.7 ? 0.55 : loadRatio <= 1.2 ? 0.9 : 0.65;
  const total =
    safety * 0.28 +
    adherenceLikelihood * 0.18 +
    goalSpecificity * 0.16 +
    scheduleFit * 0.14 +
    fatigueRisk * 0.14 +
    progressionValue * 0.1;

  return {
    total,
    safety,
    adherenceLikelihood,
    goalSpecificity,
    scheduleFit,
    fatigueRisk,
    progressionValue,
    reasons: [
      `weekly load ratio ${loadRatio.toFixed(2)}`,
      `fatigue risk ${athleteState.fatigueRisk}`,
      `${candidate.workouts.length} planned workouts`,
    ],
  };
}

export function chooseBestCandidate(
  candidates: PlanCandidate[],
  athleteState: AthleteTrainingStateSnapshot
): PlanCandidate {
  if (candidates.length === 0) {
    throw new Error("No plan candidates were generated.");
  }

  return [...candidates].sort((a, b) =>
    scoreCandidate(b, athleteState).total - scoreCandidate(a, athleteState).total
  )[0];
}
