import { trainingPlanTemplates } from "../data/trainingPlanTemplates.js";

export type TrainingPlanFocus =
  | "consistency"
  | "comeback"
  | "fiveK"
  | "tenK"
  | "tenMile"
  | "halfMarathon";

export type TrainingPlanSport = "run" | "walk" | "bike" | "mixed";

export type TrainingPlanWorkoutKind =
  | "easy"
  | "recovery"
  | "walkRun"
  | "tempo"
  | "interval"
  | "fartlek"
  | "hill"
  | "longRun"
  | "crossTrain"
  | "racePrep"
  | "race";

export type TrainingPlanWorkoutStepKind =
  | "warmup"
  | "run"
  | "walk"
  | "tempo"
  | "interval"
  | "steady"
  | "recovery"
  | "crossTrain"
  | "cooldown"
  | "race";

type MotivationPhase = "firstSession" | "steady" | "comeback" | "momentum" | "completedToday";
type DailyReadiness = "Low energy" | "Okay" | "Ready" | "Stressed";

export interface TrainingPlanSource {
  name: string;
  license: string;
  attribution: string;
  url: string;
  importNotes: string;
}

export interface TrainingPlanWorkoutStep {
  id: string;
  kind: TrainingPlanWorkoutStepKind;
  label: string;
  durationSeconds: number;
  detail?: string | null;
}

export interface TrainingPlanWorkout {
  id: string;
  title: string;
  kind: TrainingPlanWorkoutKind;
  dayLabel: string;
  summary: string;
  purpose: string;
  coachCue: string;
  effortLabel: string;
  durationSeconds: number;
  distanceLabel?: string | null;
  steps: TrainingPlanWorkoutStep[];
  isOptional: boolean;
}

export interface TrainingPlanWeek {
  id: string;
  index: number;
  focus: string;
  summary: string;
  workouts: TrainingPlanWorkout[];
  notes: string[];
}

export interface TrainingPlanTemplate {
  id: string;
  focus: TrainingPlanFocus;
  sport: TrainingPlanSport;
  title: string;
  subtitle: string;
  defaultWeeks: number;
  minSessionsPerWeek: number;
  maxSessionsPerWeek: number;
  baseWeeklyMinutes: number;
  baseLongSessionMinutes: number;
  summary: string;
  highlights: string[];
  source?: TrainingPlanSource | null;
  weeks: TrainingPlanWeek[];
}

export interface TrainingPlanRecommendation {
  id: string;
  template: TrainingPlanTemplate;
  durationWeeks: number;
  sessionsPerWeek: number;
  targetWeeklyMinutes: number;
  longSessionMinutes: number;
  rationale: string;
  tradeoff: string;
}

export interface ActiveTrainingPlan {
  id: string;
  templateID: string;
  focus: TrainingPlanFocus;
  sport: TrainingPlanSport;
  title: string;
  subtitle: string;
  durationWeeks: number;
  sessionsPerWeek: number;
  targetWeeklyMinutes: number;
  longSessionMinutes: number;
  createdAt: Date;
}

export interface TrainingPlanWeekSnapshot {
  currentWeekIndex: number;
  totalWeeks: number;
  completedSessions: number;
  targetSessions: number;
  completedMinutes: number;
  targetMinutes: number;
  progressPercent: number;
  summaryLine: string;
  coachLine: string;
  focus: string;
  weekSummary: string;
  scheduledWorkouts: TrainingPlanWorkout[];
  notes: string[];
}

export interface SuggestedSession {
  id: string;
  sport: "run" | "bike";
  title: string;
  durationLabel: string;
  activityLabel: string;
  framing: string;
  coachLine: string;
  startLabel: string;
}

export interface TodayTrainingSuggestion {
  title: string;
  detail: string;
  coachLine: string;
  adjustmentLine?: string | null;
  suggestedSession: SuggestedSession;
  workout: TrainingPlanWorkout;
  stepSummary: string[];
}

export interface TrainingPlanState {
  activePlan: ActiveTrainingPlan | null;
  recommendations: TrainingPlanRecommendation[];
  currentWeek: TrainingPlanWeekSnapshot | null;
  todaySuggestion: TodayTrainingSuggestion | null;
}

export interface TrainingPlanSelection {
  candidateID?: string;
  templateID?: string;
  durationWeeks?: number;
  sessionsPerWeek?: number;
  targetWeeklyMinutes?: number;
  longSessionMinutes?: number;
}

export interface ActiveTrainingPlanData {
  templateId: string;
  focus: TrainingPlanFocus;
  sport: TrainingPlanSport;
  title: string;
  subtitle: string;
  durationWeeks: number;
  sessionsPerWeek: number;
  targetWeeklyMinutes: number;
  longSessionMinutes: number;
  startedAt: Date;
}

interface StoredActiveTrainingPlan {
  id: string;
  templateId: string;
  focus: string;
  sport: string;
  title: string;
  subtitle: string;
  durationWeeks: number;
  sessionsPerWeek: number;
  targetWeeklyMinutes: number;
  longSessionMinutes: number;
  startedAt: Date;
}

interface ActivityForPlans {
  startedAt: Date | string;
  durationSecs?: number | null;
  distanceM?: number | null;
}

interface NormalizedActivity {
  startedAt: Date;
  durationSecs: number;
  distanceM: number;
}

interface RecentTrainingStats {
  recentSessionCount: number;
  recentDistanceKilometers: number;
  weeklySessionAverage: number;
  weeklyMinutesAverage: number;
  longestSessionMinutes: number;
}

const templates = trainingPlanTemplates as unknown as TrainingPlanTemplate[];
const templateLookup = new Map(templates.map((template) => [template.id, template]));

export function buildTrainingPlanState(params: {
  activePlan: StoredActiveTrainingPlan | null;
  activities: ActivityForPlans[];
  readiness?: string | null;
  now?: Date;
}): TrainingPlanState {
  const now = params.now ?? new Date();
  const activities = normalizeActivities(params.activities);
  const readiness = normalizeReadiness(params.readiness);

  if (params.activePlan) {
    const activePlan = activePlanFromRecord(params.activePlan);
    const currentWeek = makeWeekSnapshot(activePlan, activities, now);
    const todaySuggestion = makeTodaySuggestion(activePlan, currentWeek, readiness);

    return {
      activePlan,
      recommendations: [],
      currentWeek,
      todaySuggestion,
    };
  }

  return {
    activePlan: null,
    recommendations: makeRecommendations(activities, determinePhase(activities, now), now),
    currentWeek: null,
    todaySuggestion: null,
  };
}

export function makeActivePlanData(params: {
  selection: TrainingPlanSelection;
  activities: ActivityForPlans[];
  now?: Date;
}): ActiveTrainingPlanData {
  const now = params.now ?? new Date();
  const activities = normalizeActivities(params.activities);
  const phase = determinePhase(activities, now);
  const recommendations = makeRecommendations(activities, phase, now);
  const selectedRecommendation = params.selection.candidateID
    ? recommendations.find((recommendation) => recommendation.id === params.selection.candidateID)
    : undefined;
  const templateID =
    params.selection.templateID ?? selectedRecommendation?.template.id ?? recommendations[0]?.template.id;
  const template = templateID ? templateLookup.get(templateID) : undefined;

  if (!template) {
    throw new Error("Unknown training plan template.");
  }

  const durationWeeks = clampRounded(
    params.selection.durationWeeks ?? selectedRecommendation?.durationWeeks ?? template.defaultWeeks,
    1,
    Math.max(template.defaultWeeks, template.weeks.length)
  );
  const sessionsPerWeek = clampRounded(
    params.selection.sessionsPerWeek ?? selectedRecommendation?.sessionsPerWeek ?? template.minSessionsPerWeek,
    template.minSessionsPerWeek,
    template.maxSessionsPerWeek
  );
  const targetWeeklyMinutes = Math.max(
    template.baseWeeklyMinutes,
    Math.round(params.selection.targetWeeklyMinutes ?? selectedRecommendation?.targetWeeklyMinutes ?? template.baseWeeklyMinutes)
  );
  const longSessionMinutes = Math.min(
    Math.max(
      template.baseLongSessionMinutes,
      Math.round(params.selection.longSessionMinutes ?? selectedRecommendation?.longSessionMinutes ?? template.baseLongSessionMinutes)
    ),
    Math.max(15, targetWeeklyMinutes - 10)
  );

  return {
    templateId: template.id,
    focus: template.focus,
    sport: template.sport,
    title: template.title,
    subtitle: template.subtitle,
    durationWeeks,
    sessionsPerWeek,
    targetWeeklyMinutes,
    longSessionMinutes,
    startedAt: now,
  };
}

export function makeRecommendations(
  activities: ActivityForPlans[],
  phase: MotivationPhase = "steady",
  now: Date = new Date()
): TrainingPlanRecommendation[] {
  const normalized = normalizeActivities(activities);
  const stats = recentTrainingStats(normalized, now);
  return recommendedTemplateIDs(stats, phase).flatMap((templateID) => {
    const template = templateLookup.get(templateID);
    return template ? [makeRecommendation(template, stats, phase)] : [];
  });
}

function activePlanFromRecord(record: StoredActiveTrainingPlan): ActiveTrainingPlan {
  const template = templateLookup.get(record.templateId);
  return {
    id: record.id,
    templateID: record.templateId,
    focus: (template?.focus ?? record.focus) as TrainingPlanFocus,
    sport: (template?.sport ?? record.sport) as TrainingPlanSport,
    title: template?.title ?? record.title,
    subtitle: template?.subtitle ?? record.subtitle,
    durationWeeks: record.durationWeeks,
    sessionsPerWeek: record.sessionsPerWeek,
    targetWeeklyMinutes: record.targetWeeklyMinutes,
    longSessionMinutes: record.longSessionMinutes,
    createdAt: record.startedAt,
  };
}

function makeWeekSnapshot(
  plan: ActiveTrainingPlan,
  activities: NormalizedActivity[],
  now: Date
): TrainingPlanWeekSnapshot {
  const weekStart = startOfWeek(now);
  const planWeekStart = startOfWeek(plan.createdAt);
  const weekEnd = addDays(weekStart, 7);
  const weekActivities = activities.filter(
    (activity) => activity.startedAt >= weekStart && activity.startedAt < weekEnd
  );
  const completedSessions = weekActivities.length;
  const completedMinutes = Math.ceil(
    weekActivities.reduce((total, activity) => total + activity.durationSecs, 0) / 60
  );
  const weekIndex = Math.max(
    1,
    Math.min(plan.durationWeeks, wholeWeeksBetween(planWeekStart, now) + 1)
  );
  const scheduledWeek = templateLookup.get(plan.templateID)?.weeks[weekIndex - 1];
  const targetSessions = scheduledWeek?.workouts.filter((workout) => !workout.isOptional).length ?? plan.sessionsPerWeek;
  const targetMinutes = scheduledWeek ? targetMinutesForWeek(scheduledWeek) : plan.targetWeeklyMinutes;
  const progressPercent = Math.min(
    1,
    Math.max(
      completedSessions / Math.max(1, targetSessions),
      completedMinutes / Math.max(1, targetMinutes)
    )
  );

  return {
    currentWeekIndex: weekIndex,
    totalWeeks: plan.durationWeeks,
    completedSessions,
    targetSessions,
    completedMinutes,
    targetMinutes,
    progressPercent,
    summaryLine: `${completedSessions} of ${targetSessions} sessions, ${completedMinutes} of ${targetMinutes} min this week`,
    coachLine: coachLine(plan, completedSessions, completedMinutes),
    focus: scheduledWeek?.focus ?? "Settle into the week",
    weekSummary: scheduledWeek?.summary ?? plan.subtitle,
    scheduledWorkouts: scheduledWeek?.workouts ?? [],
    notes: scheduledWeek?.notes ?? [],
  };
}

function makeTodaySuggestion(
  plan: ActiveTrainingPlan,
  week: TrainingPlanWeekSnapshot | null,
  readiness?: DailyReadiness | null
): TodayTrainingSuggestion {
  const baseWorkout = nextWorkout(plan, week);
  const lowReadiness = readiness === "Low energy" || readiness === "Stressed";
  const workout = lowReadiness ? adjustedWorkout(baseWorkout) : baseWorkout;
  const detailPrefix = lowReadiness ? "Adjusted session" : "Planned session";
  const coachLineText = lowReadiness
    ? "We kept the shape of the workout, but softened the stress so the plan stays usable."
    : workout.coachCue;

  return {
    title: workout.title,
    detail: `${detailPrefix} • ${formatDuration(workout.durationSeconds)} • ${workout.effortLabel}`,
    coachLine: coachLineText,
    adjustmentLine: lowReadiness ? "Dialed back for today's readiness." : null,
    suggestedSession: {
      id: `plan-${plan.templateID}-${workout.id}`,
      sport: "run",
      title: workout.title,
      durationLabel: formatDuration(workout.durationSeconds),
      activityLabel: workoutKindDisplayName(workout.kind),
      framing: workout.purpose,
      coachLine: coachLineText,
      startLabel: "Start now",
    },
    workout,
    stepSummary: workout.steps.map(stepSummary),
  };
}

function makeRecommendation(
  template: TrainingPlanTemplate,
  stats: RecentTrainingStats,
  phase: MotivationPhase
): TrainingPlanRecommendation {
  const baselineSessions = Math.max(1, Math.round(stats.weeklySessionAverage));
  const baselineMinutes = Math.max(20, Math.round(stats.weeklyMinutesAverage));
  let suggestedSessions: number;

  switch (template.focus) {
    case "comeback":
      suggestedSessions = Math.min(
        template.maxSessionsPerWeek,
        Math.max(template.minSessionsPerWeek, baselineSessions <= 1 ? 2 : baselineSessions)
      );
      break;
    case "consistency":
      suggestedSessions = Math.min(
        template.maxSessionsPerWeek,
        Math.max(template.minSessionsPerWeek, baselineSessions + (phase === "momentum" ? 1 : 0))
      );
      break;
    case "fiveK":
    case "tenK":
    case "tenMile":
    case "halfMarathon":
      suggestedSessions = Math.min(
        template.maxSessionsPerWeek,
        Math.max(template.minSessionsPerWeek, baselineSessions)
      );
      break;
  }

  const targetWeeklyMinutes = Math.max(
    template.baseWeeklyMinutes,
    baselineMinutes + weeklyMinuteLift(template.focus, phase)
  );
  const longSessionMinutes = Math.min(
    Math.max(template.baseLongSessionMinutes, stats.longestSessionMinutes + longMinuteLift(template.focus)),
    Math.max(15, targetWeeklyMinutes - 10)
  );

  return {
    id: `${template.id}-${suggestedSessions}-${targetWeeklyMinutes}`,
    template,
    durationWeeks: template.defaultWeeks,
    sessionsPerWeek: suggestedSessions,
    targetWeeklyMinutes,
    longSessionMinutes,
    rationale: rationale(template.focus, stats, phase, suggestedSessions),
    tradeoff: tradeoff(template.focus, suggestedSessions),
  };
}

function recommendedTemplateIDs(stats: RecentTrainingStats, phase: MotivationPhase): string[] {
  switch (phase) {
    case "firstSession":
      return ["run-comeback-v1", "run-5k-v1", "run-consistency-v1", "run-base-30-v1"];
    case "comeback":
      return ["run-comeback-v1", "run-consistency-v1", "run-5k-v1", "run-base-30-v1"];
    case "momentum":
      if (
        stats.recentDistanceKilometers >= 65 ||
        stats.longestSessionMinutes >= 85 ||
        stats.weeklySessionAverage >= 4.5
      ) {
        return [
          "run-half-hansons-advanced-v1",
          "run-half-v1",
          "run-10mile-v1",
          "run-half-hansons-beginner-v1",
          "run-10k-v1",
          "run-base-30-v1",
        ];
      }
      if (
        stats.recentDistanceKilometers >= 35 ||
        stats.longestSessionMinutes >= 55 ||
        stats.weeklySessionAverage >= 3
      ) {
        return [
          "run-10k-v1",
          "run-half-hansons-beginner-v1",
          "run-10mile-v1",
          "run-half-v1",
          "run-base-30-v1",
          "run-5k-v1",
        ];
      }
      return ["run-5k-v1", "run-consistency-v1", "run-base-30-v1", "run-comeback-v1", "run-10k-v1"];
    case "steady":
    case "completedToday":
      if (
        stats.recentDistanceKilometers >= 60 ||
        stats.longestSessionMinutes >= 80 ||
        stats.weeklySessionAverage >= 4
      ) {
        return [
          "run-half-hansons-advanced-v1",
          "run-10mile-v1",
          "run-half-v1",
          "run-half-hansons-beginner-v1",
          "run-10k-v1",
          "run-base-30-v1",
        ];
      }
      if (
        stats.recentDistanceKilometers >= 28 ||
        stats.longestSessionMinutes >= 45 ||
        stats.weeklySessionAverage >= 2.5
      ) {
        return [
          "run-10k-v1",
          "run-base-30-v1",
          "run-half-hansons-beginner-v1",
          "run-half-v1",
          "run-5k-v1",
          "run-consistency-v1",
        ];
      }
      return ["run-5k-v1", "run-consistency-v1", "run-base-30-v1", "run-comeback-v1"];
  }
}

function recentTrainingStats(activities: NormalizedActivity[], now: Date): RecentTrainingStats {
  const start = addDays(now, -28);
  const recentActivities = activities.filter((activity) => activity.startedAt >= start);
  const totalSeconds = recentActivities.reduce((sum, activity) => sum + activity.durationSecs, 0);

  return {
    recentSessionCount: recentActivities.length,
    recentDistanceKilometers:
      recentActivities.reduce((sum, activity) => sum + activity.distanceM, 0) / 1000,
    weeklySessionAverage: recentActivities.length / 4,
    weeklyMinutesAverage: totalSeconds / 60 / 4,
    longestSessionMinutes:
      recentActivities.map((activity) => Math.ceil(activity.durationSecs / 60)).sort((a, b) => b - a)[0] ?? 0,
  };
}

function determinePhase(activities: NormalizedActivity[], now: Date): MotivationPhase {
  const latest = activities[0];
  if (!latest) return "firstSession";
  if (isSameDay(latest.startedAt, now)) return "completedToday";
  if (daysSince(latest.startedAt, now) >= 2) return "comeback";
  if (activitiesThisWeek(activities, now) >= 3) return "momentum";
  return "steady";
}

function weeklyMinuteLift(focus: TrainingPlanFocus, phase: MotivationPhase): number {
  switch (focus) {
    case "comeback":
      return 10;
    case "consistency":
      return phase === "momentum" ? 25 : 15;
    case "fiveK":
      return 20;
    case "tenK":
      return 30;
    case "tenMile":
      return 40;
    case "halfMarathon":
      return 50;
  }
}

function longMinuteLift(focus: TrainingPlanFocus): number {
  switch (focus) {
    case "comeback":
      return 0;
    case "consistency":
      return 5;
    case "fiveK":
      return 8;
    case "tenK":
      return 10;
    case "tenMile":
      return 12;
    case "halfMarathon":
      return 15;
  }
}

function rationale(
  focus: TrainingPlanFocus,
  stats: RecentTrainingStats,
  phase: MotivationPhase,
  suggestedSessions: number
): string {
  switch (focus) {
    case "comeback":
      return "You've had enough gap or variability that a softer re-entry will stick better than a harder block.";
    case "consistency":
      return `You've shown enough movement to support a simple weekly rhythm of ${suggestedSessions} runs without adding too much pressure.`;
    case "fiveK":
      return stats.recentSessionCount < 6
        ? "A 5K block is specific enough to feel motivating, but still realistic for your current base."
        : "You already have a base. A 5K block can sharpen it without needing a heavy schedule.";
    case "tenK":
      return "Your recent volume suggests you can handle a steadier endurance block that points toward a 10K.";
    case "tenMile":
      return "You've built enough baseline work that a longer endurance focus can be realistic if the week stays controlled.";
    case "halfMarathon":
      return phase === "momentum"
        ? "Your recent rhythm supports a half build, so long as the week keeps adapting around fatigue."
        : "You have enough baseline to start a half build, but the plan still needs to stay grounded in your current routine.";
  }
}

function tradeoff(focus: TrainingPlanFocus, sessionsPerWeek: number): string {
  switch (focus) {
    case "comeback":
      return "Best for re-entry, but slower if you want fast progression.";
    case "consistency":
      return "Best for habit, not race specificity.";
    case "fiveK":
      return `${sessionsPerWeek}x per week with one slightly more focused day.`;
    case "tenK":
      return "More steady work each week, but still manageable for a normal schedule.";
    case "tenMile":
      return "Needs honest recovery and a real long-run slot.";
    case "halfMarathon":
      return "Most demanding of the current options, with bigger long-run expectations.";
  }
}

function coachLine(plan: ActiveTrainingPlan, completedSessions: number, completedMinutes: number): string {
  if (completedSessions >= plan.sessionsPerWeek || completedMinutes >= plan.targetWeeklyMinutes) {
    return "You covered this week's core work. Anything extra can stay easy.";
  }

  const remainingSessions = Math.max(0, plan.sessionsPerWeek - completedSessions);
  return remainingSessions <= 1
    ? "One more honest session would round out this week well."
    : `${remainingSessions} more sessions would give this week the shape this plan is aiming for.`;
}

function nextWorkout(
  plan: ActiveTrainingPlan,
  week: TrainingPlanWeekSnapshot | null
): TrainingPlanWorkout {
  if (!week || week.scheduledWorkouts.length === 0) {
    return fallbackWorkout(plan.focus);
  }
  if (week.completedSessions >= week.targetSessions) {
    return completionWorkout(plan.focus);
  }
  const nextIndex = Math.min(week.completedSessions, week.scheduledWorkouts.length - 1);
  return week.scheduledWorkouts[nextIndex];
}

function adjustedWorkout(workout: TrainingPlanWorkout): TrainingPlanWorkout {
  const shortenedDuration = Math.max(12 * 60, Math.round(workout.durationSeconds * 0.7));
  const easyBlock = Math.max(4 * 60, shortenedDuration - 8 * 60);
  const steps = [
    step(`${workout.id}-adjusted-warmup`, "warmup", "Warm up walk", 4 * 60, "Start easy and settle your breathing."),
    step(
      `${workout.id}-adjusted-run`,
      workout.kind === "walkRun" ? "run" : "recovery",
      workout.kind === "walkRun" ? "Easy walk-run" : "Easy running",
      easyBlock,
      "Keep the effort conversational."
    ),
    step(`${workout.id}-adjusted-cooldown`, "cooldown", "Cooldown walk", 4 * 60, "Finish still feeling in control."),
  ];

  return {
    id: `${workout.id}-adjusted`,
    title: `Lighter ${workout.title}`,
    kind: workout.kind === "walkRun" ? "walkRun" : "recovery",
    dayLabel: workout.dayLabel,
    summary: "A softer version of the scheduled workout.",
    purpose: "Protect consistency without turning today into a grind.",
    coachCue: "Today still counts. Keep it easy and bank the routine.",
    effortLabel: "Easy",
    durationSeconds: shortenedDuration,
    distanceLabel: null,
    steps,
    isOptional: workout.isOptional,
  };
}

function fallbackWorkout(focus: TrainingPlanFocus): TrainingPlanWorkout {
  switch (focus) {
    case "comeback":
      return walkRun(
        "fallback-comeback",
        "Today",
        "Reset walk-run",
        20,
        "Short and low-pressure.",
        "Keep the first restart small enough that you'd do it again tomorrow.",
        60,
        90,
        6
      );
    case "consistency":
      return easyRun(
        "fallback-consistency",
        "Today",
        "Consistency run",
        25,
        "A simple aerobic run to keep the week moving.",
        "The goal is to protect rhythm, not squeeze out a big performance day."
      );
    case "fiveK":
      return easyRun(
        "fallback-5k",
        "Today",
        "Easy 5K support run",
        30,
        "A calm aerobic run that keeps the plan alive.",
        "Stay easy and leave something in the tank."
      );
    case "tenK":
      return easyRun(
        "fallback-10k",
        "Today",
        "Aerobic 10K support run",
        35,
        "Steady running without extra pressure.",
        "Smooth beats fast today."
      );
    case "tenMile":
    case "halfMarathon":
      return longRun(
        "fallback-endurance",
        "Today",
        60,
        "An easy long aerobic day.",
        "Let patience be the workout."
      );
  }
}

function completionWorkout(focus: TrainingPlanFocus): TrainingPlanWorkout {
  return {
    id: `completion-${focus}`,
    title: "Optional recovery shakeout",
    kind: "recovery",
    dayLabel: "Optional",
    summary: "You already covered the core week.",
    purpose: "Keep moving lightly if you want a little extra freshness.",
    coachCue: "The plan is already intact. Anything here should feel restorative.",
    effortLabel: "Very easy",
    durationSeconds: 20 * 60,
    distanceLabel: null,
    steps: [
      step("completion-warmup", "warmup", "Warm up walk", 4 * 60, "Relax your shoulders."),
      step("completion-run", "recovery", "Easy jog or brisk walk", 12 * 60, "Stay well below strain."),
      step("completion-cooldown", "cooldown", "Cooldown walk", 4 * 60, "Finish feeling fresh."),
    ],
    isOptional: true,
  };
}

function easyRun(
  id: string,
  dayLabel: string,
  title: string,
  durationMinutes: number,
  summary: string,
  coachCue: string
): TrainingPlanWorkout {
  return {
    id,
    title,
    kind: "easy",
    dayLabel,
    summary,
    purpose: "Build aerobic support while keeping recovery intact.",
    coachCue,
    effortLabel: "Conversational",
    durationSeconds: durationMinutes * 60,
    distanceLabel: null,
    steps: [
      step(`${id}-warmup`, "warmup", "Warm up walk or jog", 5 * 60, "Ease into the session."),
      step(
        `${id}-main`,
        "steady",
        "Easy run",
        Math.max(1, durationMinutes - 10) * 60,
        "You should be able to speak in short sentences."
      ),
      step(`${id}-cooldown`, "cooldown", "Cooldown walk", 5 * 60, "Let your breathing settle."),
    ],
    isOptional: false,
  };
}

function longRun(
  id: string,
  dayLabel: string,
  durationMinutes: number,
  summary: string,
  coachCue: string
): TrainingPlanWorkout {
  return {
    id,
    title: "Long run",
    kind: "longRun",
    dayLabel,
    summary,
    purpose: "Build durable endurance with low drama and steady effort.",
    coachCue,
    effortLabel: "Easy-steady",
    durationSeconds: durationMinutes * 60,
    distanceLabel: null,
    steps: [
      step(`${id}-warmup`, "warmup", "Warm up jog", 8 * 60, "Start more gently than you think you need to."),
      step(
        `${id}-main`,
        "steady",
        "Long aerobic running",
        Math.max(1, durationMinutes - 16) * 60,
        "Stay under control for the whole middle."
      ),
      step(`${id}-cooldown`, "cooldown", "Cooldown walk", 8 * 60, "Walk a bit before you stop completely."),
    ],
    isOptional: false,
  };
}

function walkRun(
  id: string,
  dayLabel: string,
  title: string,
  durationMinutes: number,
  summary: string,
  coachCue: string,
  runSeconds: number,
  walkSeconds: number,
  repeats: number
): TrainingPlanWorkout {
  const mainSteps = Array.from({ length: repeats }, (_, index) => index + 1).flatMap((rep) => [
    step(`${id}-run-${rep}`, "run", `Run ${rep}`, runSeconds, "Relax the pace."),
    step(`${id}-walk-${rep}`, "walk", `Walk ${rep}`, walkSeconds, "Recover fully."),
  ]);
  const totalSeconds = 5 * 60 + mainSteps.reduce((total, item) => total + item.durationSeconds, 0) + 5 * 60;

  return {
    id,
    title,
    kind: "walkRun",
    dayLabel,
    summary,
    purpose: "Rebuild impact tolerance and confidence with controlled run segments.",
    coachCue,
    effortLabel: "Gentle",
    durationSeconds: Math.max(durationMinutes * 60, totalSeconds),
    distanceLabel: null,
    steps: [
      step(`${id}-warmup`, "warmup", "Warm up walk", 5 * 60, "Get loose before the first run segment."),
      ...mainSteps,
      step(`${id}-cooldown`, "cooldown", "Cooldown walk", 5 * 60, "Let the session settle."),
    ],
    isOptional: false,
  };
}

function step(
  id: string,
  kind: TrainingPlanWorkoutStepKind,
  label: string,
  durationSeconds: number,
  detail?: string
): TrainingPlanWorkoutStep {
  return { id, kind, label, durationSeconds, detail: detail ?? null };
}

function normalizeActivities(activities: ActivityForPlans[]): NormalizedActivity[] {
  return activities
    .map((activity) => ({
      startedAt: activity.startedAt instanceof Date ? activity.startedAt : new Date(activity.startedAt),
      durationSecs: activity.durationSecs ?? 0,
      distanceM: activity.distanceM ?? 0,
    }))
    .filter((activity) => !Number.isNaN(activity.startedAt.getTime()))
    .sort((a, b) => b.startedAt.getTime() - a.startedAt.getTime());
}

function normalizeReadiness(value?: string | null): DailyReadiness | null {
  switch (value) {
    case "lowEnergy":
    case "Low energy":
      return "Low energy";
    case "okay":
    case "Okay":
      return "Okay";
    case "ready":
    case "Ready":
      return "Ready";
    case "stressed":
    case "Stressed":
      return "Stressed";
    default:
      return null;
  }
}

function activitiesThisWeek(activities: NormalizedActivity[], now: Date): number {
  const start = startOfWeek(now);
  const end = addDays(start, 7);
  return activities.filter((activity) => activity.startedAt >= start && activity.startedAt < end).length;
}

function targetMinutesForWeek(week: TrainingPlanWeek): number {
  return Math.ceil(week.workouts.reduce((total, workout) => total + workout.durationSeconds, 0) / 60);
}

function wholeWeeksBetween(start: Date, end: Date): number {
  return Math.floor((end.getTime() - start.getTime()) / (7 * 24 * 60 * 60 * 1000));
}

function daysSince(date: Date, now: Date): number {
  return Math.floor((startOfDay(now).getTime() - startOfDay(date).getTime()) / (24 * 60 * 60 * 1000));
}

function isSameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}

function startOfDay(date: Date): Date {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function startOfWeek(date: Date): Date {
  const start = startOfDay(date);
  start.setUTCDate(start.getUTCDate() - start.getUTCDay());
  return start;
}

function addDays(date: Date, days: number): Date {
  const next = new Date(date);
  next.setUTCDate(next.getUTCDate() + days);
  return next;
}

function clampRounded(value: number, min: number, max: number): number {
  return Math.min(max, Math.max(min, Math.round(value)));
}

function formatDuration(seconds: number): string {
  if (seconds % 60 === 0) {
    return `${seconds / 60} min`;
  }
  return `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

function stepSummary(step: TrainingPlanWorkoutStep): string {
  if (step.detail && step.detail.length > 0) {
    return `${step.label} • ${formatDuration(step.durationSeconds)} • ${step.detail}`;
  }
  return `${step.label} • ${formatDuration(step.durationSeconds)}`;
}

function workoutKindDisplayName(kind: TrainingPlanWorkoutKind): string {
  switch (kind) {
    case "easy":
      return "Easy run";
    case "recovery":
      return "Recovery run";
    case "walkRun":
      return "Walk-run";
    case "tempo":
      return "Tempo";
    case "interval":
      return "Intervals";
    case "fartlek":
      return "Fartlek";
    case "hill":
      return "Hills";
    case "longRun":
      return "Long run";
    case "crossTrain":
      return "Cross-train";
    case "racePrep":
      return "Race prep";
    case "race":
      return "Race day";
  }
}
