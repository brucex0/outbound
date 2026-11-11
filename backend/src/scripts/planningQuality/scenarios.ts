import type { ActivityForPlanning, CreateTrainingGoalInput, PlannedWorkoutForState, ReadinessForPlanning } from "../../services/planning/types.js";

export interface Scenario {
  id: string;
  cohort: string;
  goalLabel: string;
  goal: CreateTrainingGoalInput;
  activities: ActivityForPlanning[];
  planned: PlannedWorkoutForState[];
  readiness: ReadinessForPlanning[];
  now: Date;
  horizonWeeks: number;
  catalogue: boolean;
  assumptions: string[];
  adherenceEvidence: "synthetic_prescribed_history" | "unknown";
}
export const SCENARIO_VERSION = "realistic-running-matrix-v2";
const profiles = [
  { name: "new_runner", context: "startingOut", minutes: 0, runs: 0, longest: 0 },
  { name: "returning_low", context: "returningAfterBreak", minutes: 40, runs: 2, longest: 25 },
  { name: "active_short", context: "currentlyActive", minutes: 60, runs: 3, longest: 25 },
  { name: "active_recreational", context: "currentlyActive", minutes: 100, runs: 3, longest: 45 },
  { name: "active_consistent", context: "currentlyActive", minutes: 150, runs: 4, longest: 60 },
  { name: "experienced_half", context: "currentlyActive", minutes: 210, runs: 4, longest: 80 },
  { name: "experienced_marathon", context: "currentlyActive", minutes: 300, runs: 5, longest: 110 },
  { name: "experienced_high_volume", context: "currentlyActive", minutes: 400, runs: 6, longest: 130 },
  { name: "unknown_history", context: "currentlyActive", minutes: 0, runs: 0, longest: 0 },
  { name: "returning_established", context: "returningAfterBreak", minutes: 120, runs: 3, longest: 55 },
] as const;
export function scenarios(count: number, seed: string, clock: Date): Scenario[] {
  const random = seeded(seed);
  return Array.from({ length: count }, (_, index) => {
    const profile = profiles[Math.floor(index / 20) % profiles.length];
    const variation = index % 20;
    const race = variation % 5 >= 2;
    const marathon = profile.minutes >= 300 && variation % 5 === 4;
    const half = profile.minutes >= 150 && variation % 5 === 3;
    const distance = marathon ? 42_195 : half ? 21_097.5 : profile.minutes >= 60 && variation % 5 === 3 ? 10_000 : 5_000;
    const weeks = marathon ? [12, 16, 20][variation % 3] : profile.context === "startingOut" ? [12, 16, 20][variation % 3] : [4, 6, 8, 12, 16, 20][variation % 6];
    const catalogue = variation === 19;
    const catalogueTemplate = profile.minutes >= 150 ? "run-half-v1" : profile.minutes >= 60 ? "run-10k-v1" : "run-5k-v1";
    const days = catalogue ? 3 : profile.context === "startingOut" ? 2 + variation % 2 : profile.context === "returningAfterBreak" ? 2 + variation % 3 : 1 + variation % 6;
    const caps = profile.minutes >= 210 ? [30, 45, 60, 90, 120] : [15, 20, 25, 30, 45, 60];
    const cap = catalogue ? profile.minutes >= 150 ? 90 : 60 : caps[variation % caps.length];
    const preferredDays = Array.from({ length: days }, (_, day) => ["mon", "tue", "wed", "thu", "fri", "sat", "sun"][Math.floor(day * 7 / days)]);
    const gap = variation === 14;
    const activities: ActivityForPlanning[] = [];
    const planned: PlannedWorkoutForState[] = [];
    const returningBreak = profile.name === "returning_established";
    const adherence = variation === 11 ? .5 : variation === 12 ? .75 : 1;
    for (let week = 0; week < (returningBreak ? 6 : 4); week++) for (let run = 0; run < profile.runs; run++) {
      // The declared break has no scheduled commitments or completed activities.
      // Four coherent active weeks precede it; only two remain inside28days.
      if (returningBreak && week < 2) continue;
      const minutes = run === 0 ? profile.longest : (profile.minutes - profile.longest) / Math.max(profile.runs - 1, 1);
      const seconds = Math.round(minutes * 60);
      const pace = 330 + Math.round(random() * 120);
      const date = addDays(clock, -(week * 7 + 1 + Math.floor(run * 7 / Math.max(profile.runs, 1))));
      const slot = week * Math.max(profile.runs, 1) + run;
      const completed = !(gap && week === 0) && (adherence === .5 ? slot % 2 === 0 : adherence === .75 ? slot % 4 !== 0 : true);
      planned.push({ id: `synthetic-prescription-${index}-${week}-${run}`, scheduledDate: date, modality: "run", stimulus: "easyAerobic",
        durationSeconds: seconds, distanceMeters: null, targetCalories: null, isKeyWorkout: false,
        status: completed ? "completed" : gap && week === 0 ? "missed" : "skipped", prescription: {} });
      if (completed) activities.push({ id: `synthetic-${index}-${week}-${run}`, type: "run", startedAt: date,
        durationSecs: seconds, distanceM: seconds / pace * 1000, avgPace: pace, avgHeartRate: null });
    }
    const pain = variation === 13;
    const readiness: ReadinessForPlanning[] = variation === 15 ? [] : [{ date: clock, energy: variation === 16 ? 2 : 4,
      soreness: variation === 16 ? 4 : 1, sleepQuality: 4, stress: 1, motivation: 4, illnessOrPain: pain }];
    return { id: `case-${String(index + 1).padStart(4, "0")}`, cohort: profile.name, goalLabel: catalogue ? `catalogue_${catalogueTemplate}` : race ? marathon ? "marathon" : half ? "half" : distance === 10_000 ? "10k" : "5k" : variation % 5 === 1 ? "speed" : "endurance",
      now: clock, horizonWeeks: weeks, catalogue, activities, planned, readiness,
      adherenceEvidence: planned.length ? "synthetic_prescribed_history" : "unknown",
      goal: { type: race ? "eventPreparation" : variation % 5 === 1 ? "speed" : "endurance", activities: ["run"],
        baselineContext: profile.context, daysPerWeekTarget: days, maxSessionMinutes: cap, preferredDays,
        targetDate: race ? addDays(clock, weeks * 7).toISOString() : null, targetDistanceMeters: catalogue ? profile.minutes >= 150 ? 21_097.5 : profile.minutes >= 60 ? 10_000 : 5_000 : race ? distance : null,
        eventIntent: race ? variation % 2 === 0 ? "finish" : "perform" : null,
        targetTimeSeconds: null, riskTolerance: profile.context === "currentlyActive" ? "balanced" : "conservative",
        constraints: { shortRunSessions: String(cap < 25), templateID: catalogue ? catalogueTemplate : undefined } },
      assumptions: ["All activities, completions, readiness and goals are synthetic; no sensor data is assumed.",
        `Historical scheduled running is ${profile.minutes} minutes/week before explicit skipped sessions/breaks; completed activity rows match completed prescribed dates and durations. This is an input assumption, not observed fitness.`,
        ...(planned.length ? [] : ["No prior prescribed completions exist. Adherence evidence is unknown; any engine default is not observed adherence."]),
        ...(returningBreak ? ["The last14days contain no activities or prescribed commitments; four coherent active weeks precede that declared break."] : []),
        "Phase checkpoints independently assume stable baseline volume/adherence; they do not model physiological improvement.",
        ...(pain ? ["Active pain is assumed to remain relevant for the first seven days for this conservative review rule."] : [])],
    };
  });
}
export function addDays(date: Date, count: number): Date { return new Date(date.getTime() + count * 86_400_000); }
export function seeded(seed: string) { let value = 2166136261; for (const char of seed) value = Math.imul(value ^ char.charCodeAt(0), 16777619); return () => { value ^= value << 13; value ^= value >>> 17; value ^= value << 5; return (value >>> 0) / 4294967296; }; }

export const SUPPLEMENT_VERSION = "orthogonal-running-supplement-v1";
/** Separate inputs; the original matrix and case IDs remain unchanged. */
export function orthogonalSupplement(original: Scenario[], maximum = 36): Scenario[] {
  const result: Scenario[] = [];
  const sourceFor = (cohort: string) => original.find((row) => row.cohort === cohort);
  const add = (source: Scenario | undefined, goal: CreateTrainingGoalInput, label: string, weeks = 0, catalogue = false) => {
    if (!source) return;
    result.push({ ...structuredClone(source), id: `supp-${String(result.length + 1).padStart(3, "0")}`, goalLabel: label,
      catalogue, horizonWeeks: weeks, goal, assumptions: [...source.assumptions,
        "Separately versioned orthogonal supplement: schedule/cap are crossed independently; history is unchanged."] });
  };
  for (const cohort of ["new_runner", "active_short", "unknown_history", "returning_established"]) {
    const source = sourceFor(cohort); if (!source) continue;
    for (const days of [1, 3, 6]) for (const cap of [15, 60]) add(source, { ...source.goal, type: "endurance", targetDate: null,
      targetDistanceMeters: null, eventIntent: null, daysPerWeekTarget: days, maxSessionMinutes: cap,
      preferredDays: Array.from({ length: days }, (_, index) => ["mon", "tue", "wed", "thu", "fri", "sat", "sun"][Math.floor(index * 7 / days)]),
      constraints: { shortRunSessions: String(cap < 25) } }, "orthogonal_endurance");
  }
  const beginner = sourceFor("new_runner");
  if (beginner) for (const days of [1, 2, 3]) for (const dated of [false, true]) {
    const weeks = days === 1 ? 30 : days === 2 ? 20 : 12;
    add(beginner, { ...beginner.goal, type: "eventPreparation", targetDistanceMeters: 5000, eventIntent: "finish",
      targetDate: dated ? addDays(beginner.now, weeks * 7).toISOString() : null, daysPerWeekTarget: days, maxSessionMinutes: 30,
      preferredDays: days === 1 ? ["mon"] : days === 2 ? ["mon", "thu"] : ["mon", "wed", "fri"],
      constraints: { templateID: "run-5k-v1", shortRunSessions: "false" } }, dated ? "c25k_viable_deadline" : "c25k_no_date", weeks, true);
  }
  const returning = sourceFor("returning_established");
  if (returning) for (const days of [3, 4]) for (const dated of [false, true]) add(returning, { ...returning.goal,
    type: "endurance", targetDate: dated ? addDays(returning.now, 140).toISOString() : null,
    daysPerWeekTarget: days, maxSessionMinutes: 45, preferredDays: days === 3 ? ["mon", "wed", "fri"] : ["mon", "wed", "fri", "sun"],
    constraints: { templateID: "run-consistency-v1", shortRunSessions: "false" } }, dated ? "returning_source_long_horizon" : "returning_source_no_date", 20, true);
  const active = sourceFor("active_short");
  if (active) for (const short of [false, true]) add(active, { ...active.goal, type: "eventPreparation", activities: ["run", "walk"],
    targetDate: addDays(active.now, 84).toISOString(), targetDistanceMeters: 5000, eventIntent: "perform", daysPerWeekTarget: 6,
    maxSessionMinutes: 45, preferredDays: ["mon", "tue", "wed", "thu", "fri", "sat"], constraints: { shortRunSessions: String(short) } }, "mixed_run_walk", 12);
  return result.slice(0, maximum);
}
