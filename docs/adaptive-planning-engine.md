# Adaptive Planning Engine

Open this when designing the smart training planner, adaptive plan tables, generated workouts, multi-sport support, or plan adjustment behavior.

## Goal

Move Outbound from static training plans to an adaptive planning engine.

Static plans should remain useful as seed content, examples, fallback behavior, and quality references. The product experience should become:

- goal-aware
- user-state-aware
- schedule-aware
- forgiving when users miss workouts
- scalable across modalities such as running, cycling, swimming, skating, strength, HIIT, mobility, and mixed training

The core product promise is:

> Given who you are, what you are working toward, and what happened recently, here is the best next training move.

## Core Principle

Plan training stimulus first. Translate stimulus into sport-specific workouts second.

Bad scalable path:

```text
RunPlan
SwimPlan
StrengthPlan
SkatePlan
```

Better scalable path:

```text
TrainingGoal
AdaptivePlan
PlannedWorkout
WorkoutBlock
WorkoutStep
ModalityAdapter
```

The shared planner should reason about load, recovery, adherence, and progression. Sport adapters should handle the details of what a workout looks like for a modality.

## Layering

The engine should be deterministic at the training-load layer and AI-assisted at the explanation layer.

Recommended layers:

1. `AthleteTrainingState` summarizes recent behavior and current risk.
2. `TrainingGoal` defines the north star.
3. The shared planner chooses phase, weekly load, session count, hard/easy balance, and target stimuli.
4. Modality adapters translate stimuli into concrete workout prescriptions.
5. The scoring layer compares candidate schedules.
6. The adaptation layer revises today and the next 7-14 days as new data arrives.
7. The activity suggestion layer selects the single best next action for the Home `Now` card.
8. AI explains the decision in coach voice, but does not invent unsafe load from scratch.

## Planning Horizon

The engine should not regenerate the entire future plan on every event.

Use different adaptation speeds:

```text
Goal stays stable.
Phase changes slowly.
Week adapts moderately.
Today adapts aggressively.
```

Practical behavior:

- Today can be shortened, softened, moved, or swapped immediately.
- The next 7-14 days can be regenerated after missed sessions, low readiness, travel, or strong progress.
- The current phase should change only when the goal or user state meaningfully changes.
- Historical plan versions should remain immutable for auditability.

## Implementation Architecture

Build planning as a backend domain that coach surfaces consume. The coach UI can explain and present the plan, but the planning service should own goals, generated workouts, adaptation, and event processing.

Target flow:

```text
API routes
  -> planning application service
    -> PlanningEvent queue
    -> AthleteTrainingState calculator
    -> plan generator
    -> adaptation engine
    -> modality adapters
    -> activity suggestion formatter
    -> Prisma persistence
```

### Route Layer

File:

- `backend/src/routes/planning.ts`

Responsibilities:

- validate request bodies
- resolve authenticated app user
- call `planningService`
- return typed planning responses

Routes should stay thin. They should not compute training load, mutate plan versions directly, or know sport-specific workout generation rules.

### Application Service

File:

- `backend/src/services/planning/planningService.ts`

Responsibilities:

- coordinate transactions
- create goals and plans
- enqueue planning events
- run immediate event processing for user-visible mutations
- assemble `PlanningState` responses

Interface shape:

```ts
export interface PlanningService {
  createGoal(userId: string, input: CreateTrainingGoalInput): Promise<PlanningState>;
  getState(userId: string): Promise<PlanningState>;
  getToday(userId: string): Promise<TodayPlanningResponse>;
  getActivitySuggestion(userId: string): Promise<ActivitySuggestionResponse>;
  submitReadiness(userId: string, input: SubmitReadinessInput): Promise<PlanningState>;
  skipWorkout(userId: string, workoutId: string): Promise<PlanningState>;
  completeWorkout(
    userId: string,
    workoutId: string,
    input: CompleteWorkoutInput
  ): Promise<PlanningState>;
  rebuildPlan(userId: string, input?: RebuildPlanInput): Promise<PlanningState>;
}
```

### Event Queue

File:

- `backend/src/services/planning/events.ts`

Responsibilities:

- create durable `PlanningEvent` rows
- dedupe events by `dedupeKey`
- claim pending events
- complete, ignore, or fail events
- expose a processing API that works synchronously now and as a worker later

Interface shape:

```ts
export interface PlanningEventService {
  enqueue(input: EnqueuePlanningEventInput): Promise<PlanningEventRecord>;
  enqueueMany(inputs: EnqueuePlanningEventInput[]): Promise<PlanningEventRecord[]>;
  claimDue(limit: number, now?: Date): Promise<PlanningEventRecord[]>;
  complete(eventId: string, result: PlanningEventResult): Promise<void>;
  ignore(eventId: string, reason: string): Promise<void>;
  fail(eventId: string, error: Error): Promise<void>;
}
```

### Event Processor

File:

- `backend/src/services/planning/processor.ts`

Responsibilities:

- process one or more claimed events
- load the current planning context
- refresh athlete state
- call adaptation engine
- persist new plan versions and adjustment events
- return a summary for request-driven processing

Interface shape:

```ts
export interface PlanningProcessor {
  processEvent(eventId: string): Promise<PlanningEventResult>;
  processDueForUser(userId: string, now?: Date): Promise<PlanningEventResult[]>;
}
```

### Athlete State Calculator

File:

- `backend/src/services/planning/athleteState.ts`

Responsibilities:

- compute recent load from activities and completions
- compute adherence
- detect fatigue risk
- summarize modality mix
- optionally persist `AthleteTrainingState`

Interface shape:

```ts
export interface AthleteStateCalculator {
  compute(input: AthleteStateInput): AthleteTrainingStateSnapshot;
}

export type AthleteTrainingStateSnapshot = {
  asOfDate: Date;
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
};
```

### Plan Generator

Files:

- `backend/src/services/planning/goalPlanner.ts`
- `backend/src/services/planning/weekGenerator.ts`

Responsibilities:

- create the initial plan from a goal
- generate a 7-14 day window
- choose target stimuli
- ask modality adapters for concrete workouts
- create `PlannedWorkoutDraft` rows

Interface shape:

```ts
export interface PlanGenerator {
  generateInitialPlan(input: InitialPlanInput): Promise<PlanGenerationResult>;
  generateNextWindow(input: NextWindowInput): Promise<PlanGenerationResult>;
}

export type PlanGenerationResult = {
  summary: string;
  phase: TrainingPlanPhase;
  workouts: PlannedWorkoutDraft[];
  engineDecision: Record<string, unknown>;
};
```

### Adaptation Engine

File:

- `backend/src/services/planning/adaptationEngine.ts`

Responsibilities:

- classify the event situation
- decide whether a replan is needed
- generate candidate adjustments
- call scoring
- produce plan version and adjustment drafts

Interface shape:

```ts
export interface AdaptationEngine {
  adapt(input: AdaptationInput): Promise<AdaptationResult>;
}

export type AdaptationResult = {
  shouldCreateVersion: boolean;
  reason: PlanningEventType;
  summary: string;
  workouts: PlannedWorkoutDraft[];
  adjustmentEvents: PlanAdjustmentDraft[];
  engineDecision: Record<string, unknown>;
};
```

### Candidate Scoring

File:

- `backend/src/services/planning/scoring.ts`

Responsibilities:

- score generated candidate schedules
- reject unsafe plans
- choose the best candidate for this user's state and constraints

Interface shape:

```ts
export interface CandidateScorer {
  score(candidate: PlanCandidate, context: PlanningContext): CandidateScore;
  chooseBest(candidates: PlanCandidate[], context: PlanningContext): PlanCandidate;
}

export type CandidateScore = {
  total: number;
  safety: number;
  adherenceLikelihood: number;
  goalSpecificity: number;
  scheduleFit: number;
  fatigueRisk: number;
  progressionValue: number;
  reasons: string[];
};
```

### Modality Adapters

Directory:

- `backend/src/services/planning/adapters/`

Initial files:

- `runAdapter.ts`
- `walkAdapter.ts`
- `mobilityAdapter.ts`
- `strengthAdapter.ts`

Responsibilities:

- decide whether a modality can satisfy a stimulus
- generate sport-specific workout prescriptions
- estimate training stress
- evaluate whether completion matched prescription
- define progression behavior

Interface shape:

```ts
export interface ModalityAdapter {
  modality: Modality;
  canSatisfy(input: StimulusRequest): boolean;
  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft;
  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate;
  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality;
  progress(input: ProgressionInput): ModalityProgression;
}
```

### Shared Types

Put shared planning types in:

- `backend/src/services/planning/types.ts`

Core types:

```ts
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

export type PlannedWorkoutDraft = {
  scheduledDate: Date;
  modality: Modality;
  stimulus: TrainingStimulus;
  title: string;
  durationSeconds: number;
  distanceMeters?: number | null;
  intensityModel: string;
  intensityTarget?: unknown;
  prescription: unknown;
  isKeyWorkout: boolean;
  blocks: WorkoutBlockDraft[];
};
```

### Response Models

The client should not have to stitch together raw rows. The API should return app-shaped responses.

```ts
export type PlanningState = {
  goal: TrainingGoalDTO | null;
  plan: TrainingPlanDTO | null;
  currentVersion: TrainingPlanVersionDTO | null;
  today: PlannedWorkoutDTO | null;
  upcoming: PlannedWorkoutDTO[];
  athleteState: AthleteTrainingStateDTO | null;
  latestAdjustment: PlanAdjustmentEventDTO | null;
  planningStatus: "stable" | "reassessing" | "updated" | "needsAttention";
};

export type TodayPlanningResponse = {
  workout: PlannedWorkoutDTO | null;
  adjustment: PlanAdjustmentEventDTO | null;
  coachLine: string;
  planningStatus: PlanningState["planningStatus"];
};
```

### Activity Suggestion Engine

The Home `Now` card should be backed by a backend-owned suggestion endpoint, not local poetic labels such as vague short resets.

Route:

- `GET /v1/planning/activity-suggestion`

Service owner:

- `backend/src/services/planning/planningService.ts`

Suggested internal module:

- `backend/src/services/planning/activitySuggestion.ts`

Responsibilities:

- process due planning events before reading state
- load active plan, latest plan version, current week, today's planned workout, recent completions, latest readiness, and synced activities
- compute acute context from today and the last 7 days
- compute baseline context from the last 28 days
- coordinate plan-first recommendations with non-plan adaptive suggestions
- select from a small library of real coach-used workout archetypes
- return an app-shaped response with title, effort, reason, steps, plan relationship, cache metadata, and safer alternatives

The client should render this response. It should not recreate plan logic or generate its own training recommendation when online.

#### Decision Priority

The suggestion engine should follow this order:

1. Process due planning events for the user.
2. If the user has an active plan and a planned workout today, use that workout as the primary suggestion unless safety rules require an adjustment.
3. If readiness, pain, illness, fatigue risk, or recent load makes the planned workout inappropriate, return an adjusted workout or plan fallback with `relationship: "adjustedFromPlan"` or `relationship: "planFallback"`.
4. If the user already completed the planned workout today, avoid suggesting a second workout as primary. Return rest or optional recovery.
5. If no active plan exists, choose a standalone suggestion from the canonical activity library based on recent synced activity.
6. If recent data is insufficient, return a conservative easy aerobic suggestion or no recommendation, not a hard workout.

Plans win over generic suggestions. The engine can soften, move, or replace a planned workout, but it should not silently ignore an active plan.

#### Input Windows

Assume activities are synced before the endpoint runs.

Use multiple time windows:

- `today`: did the user already train, and was it planned?
- `last7Days`: acute load, number of sessions, hard/easy spacing, comeback gaps, and recovery needs
- `last28Days`: baseline weekly minutes, longest recent session, normal frequency, and eligibility for progression or intensity

Do not use only the last 7 days. A user coming off a rest week may still have a stronger baseline than the last 7 days suggest, and a user with one big recent workout may not be ready for another hard session.

#### Guardrails

Standalone activity suggestions should be meaningful training actions:

- Do not suggest a standalone activity under 15 minutes.
- Prefer 20 minutes or more for run, walk, and bike suggestions.
- Allow under-15-minute work only as a warmup, cooldown, mobility add-on, or rehab-style add-on attached to a larger context.
- Do not prescribe hard work without enough recent consistency.
- Do not stack hard sessions on adjacent days unless the active plan explicitly supports it and readiness is good.
- Do not suggest a second workout after a completed same-day workout unless it is explicitly optional recovery.
- Do not cram missed workouts.
- Cap volume increases against the user's 28-day baseline.
- When pain or illness is flagged, return rest, mobility, or conservative walking, not intensity.

#### Response Shape

```ts
export type ActivitySuggestionStatus =
  | "suggested"
  | "restRecommended"
  | "noSuggestion";

export type ActivitySuggestionSource =
  | "plan"
  | "adaptive"
  | "recovery"
  | "offlineCache";

export type ActivitySuggestionRelationship =
  | "todayPlannedWorkout"
  | "adjustedFromPlan"
  | "planFallback"
  | "noPlanSuggestion"
  | "optionalRecovery"
  | "rest";

export type ActivitySuggestion = {
  id: string;
  title: string;
  modality: Modality;
  stimulus: TrainingStimulus;
  durationMinutes: number;
  effortLabel: string;
  intensityModel: "rpe" | "pace" | "heartRate" | "power" | "open";
  intensityTarget?: Record<string, unknown> | null;
  why: string;
  steps: string[];
  startLabel: string;
  plannedWorkoutId?: string | null;
  archetypeId?: string | null;
  optional: boolean;
};

export type ActivitySuggestionResponse = {
  status: ActivitySuggestionStatus;
  source: ActivitySuggestionSource;
  relationship: ActivitySuggestionRelationship;
  primary: ActivitySuggestion | null;
  alternates: ActivitySuggestion[];
  coachLine: string;
  planningStatus: PlanningStatus;
  generatedAt: string;
  validForDate: string;
  validUntil: string;
  planVersionId?: string | null;
  activityWatermark: {
    lastActivityId?: string | null;
    lastActivityStartedAt?: string | null;
  };
  decision: {
    algorithmVersion: string;
    reasons: string[];
    safetyFlags: string[];
  };
};
```

Example:

```json
{
  "status": "suggested",
  "source": "adaptive",
  "relationship": "noPlanSuggestion",
  "primary": {
    "id": "easy-run-30",
    "title": "30 min easy run",
    "modality": "run",
    "stimulus": "easyAerobic",
    "durationMinutes": 30,
    "effortLabel": "Conversational",
    "intensityModel": "rpe",
    "intensityTarget": { "rpe": 3 },
    "why": "You have not trained today and your recent week supports an easy aerobic session.",
    "steps": [
      "5 min easy warmup",
      "20 min relaxed run",
      "5 min easy cooldown"
    ],
    "startLabel": "Start run",
    "plannedWorkoutId": null,
    "archetypeId": "run_easy_aerobic",
    "optional": false
  },
  "alternates": [],
  "coachLine": "Keep this comfortably easy. The goal is aerobic time, not proving fitness today.",
  "planningStatus": "stable",
  "generatedAt": "2026-05-06T15:00:00.000Z",
  "validForDate": "2026-05-06",
  "validUntil": "2026-05-07T05:00:00.000Z",
  "planVersionId": null,
  "activityWatermark": {
    "lastActivityId": "activity_123",
    "lastActivityStartedAt": "2026-05-04T16:20:00.000Z"
  },
  "decision": {
    "algorithmVersion": "activity-suggestion-v1",
    "reasons": ["no_active_plan", "no_activity_today", "baseline_supports_30_min_easy"],
    "safetyFlags": []
  }
}
```

#### Canonical Activity Library

Suggestions should be selected from reviewed workout archetypes that coaches and athletes recognize.

Initial running and cycling archetypes:

| Archetype | Minimum | Typical | Eligibility | Notes |
| --- | ---: | ---: | --- | --- |
| Recovery run | 20 min | 20-35 min | Recent hard or long session, no pain flag | Very easy effort only |
| Recovery spin | 20 min | 20-40 min | Recent hard ride/run, bike preference | Very easy cadence, low pressure |
| Walk-run return | 20 min | 20-30 min | Beginner, comeback, low baseline, or gap in activity | Example: 5 min walk, then 1 min jog / 2 min walk repeats |
| Easy run | 20 min | 25-45 min | Default aerobic recommendation when baseline supports it | Conversational effort |
| Easy ride | 25 min | 30-60 min | Bike preference and aerobic baseline | Smooth, low to moderate effort |
| Easy run with strides | 25 min | 30-40 min | Consistent recent easy running and no high fatigue | Easy run plus 4-6 relaxed 20 sec strides |
| Progression run | 30 min | 35-50 min | Good readiness, stable baseline, no hard session yesterday | Easy start, steady finish |
| Fartlek | 30 min | 30-45 min | Recent consistency and readiness good | Informal speed play, not max effort |
| Threshold intervals | 35 min | 40-60 min | Plan-driven or strong baseline | Controlled comfortably-hard blocks |
| Hill repeats | 30 min | 35-50 min | Plan-driven or strong baseline, no injury risk | Short uphill efforts with easy recoveries |
| Long easy run | 45 min | 45-120 min | Plan-driven or demonstrated baseline | Should almost always come from an active plan |
| Mobility add-on | 5 min | 5-15 min | Add-on only, not standalone main suggestion | Useful after training, travel, soreness |

The engine should store the chosen `archetypeId` in the response and optionally in a future suggestion decision log. This makes product analytics and debugging possible.

#### Plan Coordination Examples

| Situation | Response |
| --- | --- |
| Active plan has easy run today, readiness normal | `source: "plan"`, `relationship: "todayPlannedWorkout"` |
| Active plan has intervals today, readiness low | `source: "plan"`, `relationship: "adjustedFromPlan"`, easier aerobic replacement |
| User completed today's plan workout | `source: "recovery"`, `relationship: "optionalRecovery"` or `status: "restRecommended"` |
| No active plan, no activity today, stable baseline | `source: "adaptive"`, `relationship: "noPlanSuggestion"` |
| No active plan, hard workout yesterday | recovery run, recovery spin, walk, or rest depending on baseline |
| Pain or illness flag | `status: "restRecommended"` with mobility or conservative walking only if appropriate |

#### Offline Cache Contract

The backend response should include enough metadata for safe offline rendering:

- `generatedAt`
- `validForDate`
- `validUntil`
- `planVersionId`
- `activityWatermark.lastActivityId`
- `activityWatermark.lastActivityStartedAt`

Client behavior:

- If offline and the cached suggestion is still valid for today, render it as the last-known suggestion.
- If the user recorded an offline activity after the cached watermark, invalidate the suggestion and show that recommendations will refresh after sync.
- If a cached active plan exists, show today's planned workout offline as plan content.
- If no valid cache exists, show freestyle start or a conservative offline fallback without adaptive recommendation language.

Offline fallback should never prescribe intensity, progression, tempo, fartlek, hill repeats, or plan changes. Backend remains canonical.

#### Build Order

Recommended implementation order:

1. Add activity suggestion types to `backend/src/services/planning/types.ts`.
2. Add `getActivitySuggestion(userId)` to `planningService.ts`.
3. Create `activitySuggestion.ts` to load context, classify the situation, select an archetype, and format the response.
4. Add `GET /activity-suggestion` to `backend/src/routes/planning.ts`.
5. Reuse existing `computeAthleteTrainingState` for 7-day and 28-day load facts.
6. Add a small canonical archetype library in code first; move to a `WorkoutArchetype` table only when product needs remote editing or analytics.
7. Update iOS `APIClient` to fetch the endpoint and cache the response.
8. Update the Home `Now` card to render backend fields: title, effort, why, plan relationship, and steps.
9. Keep local generic suggestions only as temporary offline fallback, then remove them once cache behavior is solid.
10. Add analytics for suggestion source, relationship, archetype, start taps, swaps, completions, and post-activity completion quality.

### Persistence Boundary

Keep direct Prisma calls inside planning services. Routes and adapters should operate on typed inputs/drafts, not raw Prisma records.

Recommended persistence functions:

- `loadPlanningContext(userId)`
- `createInitialPlan(tx, input)`
- `createPlanVersion(tx, input)`
- `replaceWorkoutWindow(tx, input)`
- `persistAthleteState(tx, input)`
- `createAdjustmentEvents(tx, input)`
- `assemblePlanningState(userId)`

## Primary Tables

### `TrainingGoal`

Stores what the user is working toward.

Important fields:

- `id`
- `userId`
- `type`: `consistency`, `comeback`, `race`, `strength`, `generalFitness`, `rehab`, `custom`
- `primaryModality`: `run`, `bike`, `swim`, `strength`, `hiit`, `skate`, `walk`, `mobility`, `mixed`
- `targetDate`
- `targetDistanceMeters`
- `targetEventName`
- `priority`: `finish`, `improvePace`, `buildHabit`, `returnSafely`, `increaseStrength`, `generalHealth`
- `preferredDays`
- `daysPerWeekTarget`
- `maxSessionMinutes`
- `riskTolerance`: `conservative`, `balanced`, `stretch`
- `constraints` JSON
- `status`: `active`, `paused`, `completed`, `archived`
- `createdAt`
- `updatedAt`

This table should change rarely. It represents intent, not the current generated schedule.

### `TrainingPlan`

Represents the active adaptive plan container for a goal.

Important fields:

- `id`
- `userId`
- `goalId`
- `status`: `active`, `paused`, `completed`, `replaced`
- `currentPhase`: `base`, `build`, `sharpen`, `taper`, `recovery`, `maintenance`
- `source`: `generated`, `templateSeeded`, `coachAdjusted`
- `startedAt`
- `endedAt`
- `createdAt`
- `updatedAt`

This is the user's current plan identity. The detailed schedule lives in versions and planned workouts.

### `TrainingPlanVersion`

Immutable snapshot created whenever the engine materially replans.

Important fields:

- `id`
- `planId`
- `versionNumber`
- `reason`: `initial`, `missedWorkout`, `lowReadiness`, `loadSpike`, `scheduleChange`, `progressUpdate`, `manualEdit`
- `effectiveFrom`
- `effectiveUntil`
- `summary`
- `engineInputs` JSON
- `engineDecision` JSON
- `createdAt`

This gives the app an answer to: "Why did my plan change?"

### `PlannedWorkout`

Scheduled workout generated by a plan version.

Important fields:

- `id`
- `planVersionId`
- `userId`
- `scheduledDate`
- `modality`: `run`, `bike`, `swim`, `strength`, `hiit`, `skate`, `walk`, `mobility`
- `stimulus`: `easyAerobic`, `longEndurance`, `threshold`, `speed`, `strength`, `hypertrophy`, `power`, `skill`, `recovery`, `mobility`
- `title`
- `durationSeconds`
- `distanceMeters`
- `intensityModel`: `rpe`, `pace`, `heartRate`, `power`, `percentOneRepMax`, `repsInReserve`, `open`
- `intensityTarget` JSON
- `prescription` JSON
- `isKeyWorkout`
- `status`: `planned`, `completed`, `skipped`, `replaced`, `moved`
- `replacesWorkoutId`
- `createdAt`
- `updatedAt`

`prescription` should be flexible enough to represent sport-specific details while still keeping common query fields outside JSON.

### `WorkoutBlock`

Optional child table for structured prescriptions. Use this once JSON prescriptions need richer editing, analytics, or UI rendering.

Important fields:

- `id`
- `plannedWorkoutId`
- `sortOrder`
- `blockType`: `warmup`, `main`, `cooldown`, `interval`, `strength`, `skill`, `mobility`
- `modality`
- `stimulus`
- `durationSeconds`
- `distanceMeters`
- `repeats`
- `restSeconds`
- `metadata` JSON

### `WorkoutStep`

Optional child table under `WorkoutBlock` for highly structured workouts.

Important fields:

- `id`
- `blockId`
- `sortOrder`
- `label`
- `kind`
- `durationSeconds`
- `distanceMeters`
- `target` JSON
- `detail`

### `WorkoutCompletion`

Links real activity data back to a planned workout.

Important fields:

- `id`
- `plannedWorkoutId`
- `activityId`
- `completedAt`
- `durationSeconds`
- `distanceMeters`
- `avgPace`
- `avgHeartRate`
- `avgPower`
- `perceivedEffort`
- `completionQuality`: `completed`, `partial`, `tooHard`, `feltEasy`, `differentWorkout`
- `notes`
- `createdAt`

This tells the engine whether the prescription matched reality.

### `ReadinessCheckIn`

Stores daily subjective state.

Important fields:

- `id`
- `userId`
- `date`
- `energy`
- `soreness`
- `sleepQuality`
- `stress`
- `motivation`
- `illnessOrPain`
- `notes`
- `createdAt`

This powers same-day adaptation.

### `AthleteTrainingState`

Computed snapshot of current fitness, load, and adherence.

Important fields:

- `id`
- `userId`
- `asOfDate`
- `overallLoadScore`
- `fatigueRisk`: `low`, `medium`, `high`
- `consistencyScore`
- `adherenceRate`
- `weeklyMinutes`
- `weeklyDistanceMeters`
- `fourWeekAvgMinutes`
- `fourWeekAvgDistanceMeters`
- `longestRecentSessionSeconds`
- `lastHardWorkoutAt`
- `modalityBreakdown` JSON
- `createdAt`

This can be computed on demand at first, then stored once performance and explainability need it.

### `PlanningEvent`

Durable event queue for reassessment and replanning.

Important fields:

- `id`
- `userId`
- `planId`
- `type`: `activityCompleted`, `workoutSkipped`, `readinessSubmitted`, `goalUpdated`, `scheduleUpdated`, `weeklyRollover`, `manualRebuild`, `healthImportCompleted`, `painFlagged`
- `sourceId`
- `payload` JSON
- `status`: `pending`, `processing`, `completed`, `failed`, `ignored`
- `priority`
- `dedupeKey`
- `runAfter`
- `attemptCount`
- `lastError`
- `createdAt`
- `processedAt`

This table is the handoff between product events and the planning engine. Request handlers should enqueue events whenever user data changes, then either process immediately for MVP-critical paths or let a worker claim pending events.

### `PlanAdjustmentEvent`

Audit log for meaningful changes.

Important fields:

- `id`
- `planId`
- `fromVersionId`
- `toVersionId`
- `eventType`: `missedWorkout`, `lowReadiness`, `loadSpike`, `completedKeyWorkout`, `scheduleChange`, `manualOverride`
- `message`
- `changedWorkoutIds`
- `engineInputs` JSON
- `engineDecision` JSON
- `createdAt`

This makes adaptation understandable instead of mysterious.

### `WorkoutArchetype`

Reusable workout pattern selected by the planner and filled by adapters.

Important fields:

- `id`
- `modality`
- `stimulus`
- `name`
- `description`
- `minDurationSeconds`
- `maxDurationSeconds`
- `difficulty`
- `constraints` JSON
- `templatePrescription` JSON
- `createdAt`
- `updatedAt`

Examples:

- `easy_aerobic_30`
- `long_endurance`
- `threshold_intervals`
- `full_body_strength`
- `upper_body_strength`
- `swim_technique`
- `hiit_power`
- `skate_skill_endurance`

## Modality Adapters

The shared planner should call modality adapters instead of embedding sport-specific rules everywhere.

Adapter responsibilities:

- determine whether the modality can satisfy a target stimulus
- generate a concrete workout prescription
- estimate training stress
- evaluate completion quality
- define progression rules
- define contraindications or safety checks

Initial adapters:

- `RunAdapter`
- `BikeAdapter`
- `SwimAdapter`
- `StrengthAdapter`
- `HIITAdapter`
- `SkateAdapter`
- `WalkAdapter`
- `MobilityAdapter`

Adapter interface shape:

```ts
interface ModalityAdapter {
  modality: string;
  canSatisfy(stimulus: TrainingStimulus, athlete: AthleteTrainingState): boolean;
  generateWorkout(input: WorkoutGenerationInput): PlannedWorkoutDraft;
  estimateStress(workout: PlannedWorkoutDraft): TrainingStressEstimate;
  evaluateCompletion(input: CompletionEvaluationInput): CompletionQuality;
  progress(input: ProgressionInput): ModalityProgression;
}
```

## Prescription Examples

### Running

```json
{
  "blocks": [
    { "type": "warmup", "durationSeconds": 300 },
    { "type": "steady", "durationSeconds": 1800, "target": { "rpe": 4 } },
    { "type": "cooldown", "durationSeconds": 300 }
  ]
}
```

### Strength

```json
{
  "blocks": [
    {
      "type": "strength",
      "exercises": [
        { "name": "Back squat", "sets": 4, "reps": 5, "target": { "rpe": 7 } },
        { "name": "Romanian deadlift", "sets": 3, "reps": 8, "target": { "rpe": 7 } }
      ]
    }
  ]
}
```

### Swimming

```json
{
  "blocks": [
    { "type": "warmup", "distanceMeters": 300 },
    { "type": "interval", "repeats": 8, "distanceMeters": 100, "restSeconds": 20, "stroke": "freestyle" },
    { "type": "cooldown", "distanceMeters": 200 }
  ]
}
```

### HIIT

```json
{
  "blocks": [
    { "type": "warmup", "durationSeconds": 300 },
    { "type": "interval", "workSeconds": 40, "restSeconds": 20, "repeats": 10 },
    { "type": "cooldown", "durationSeconds": 300 }
  ]
}
```

## Adaptation Loop

The engine should use event-triggered reassessment. Product actions create `PlanningEvent` rows; the planner processes those events and decides whether a new plan version is needed.

Trigger events after:

- activity completion
- health import completion
- skipped workout
- readiness check-in
- schedule change
- goal change
- weekly rollover
- manual rebuild
- pain, illness, or injury flag

## Event Trigger Matrix

| Trigger | Event type | Timing | Expected behavior |
| --- | --- | --- | --- |
| User completes planned workout | `activityCompleted` | Debounced by 2 minutes | Recompute state, update completion, replan only if load or quality changed materially |
| User completes unplanned activity | `activityCompleted` | Debounced by 2 minutes | Recompute state and account for extra load |
| Health import finishes | `healthImportCompleted` | Debounced by 10 minutes | Batch imported activities into one reassessment |
| User skips workout | `workoutSkipped` | Immediate | Replan near-term schedule without cramming the missed work |
| User submits low readiness | `readinessSubmitted` | Immediate | Adapt today aggressively, optionally regenerate next 7 days |
| User submits normal readiness | `readinessSubmitted` | Immediate but low priority | Usually reassess without replanning |
| User changes goal | `goalUpdated` | Immediate | Create a new plan version from the new north star |
| User changes available days/time | `scheduleUpdated` | Immediate | Regenerate the next 7-14 days |
| Weekly rollover | `weeklyRollover` | Scheduled | Generate the next week and close out prior-week state |
| User taps rebuild | `manualRebuild` | Immediate | Force a full near-term replan |
| User flags pain/illness | `painFlagged` | Immediate, high priority | Replace risky workouts with rest, mobility, or conservative movement |

Use `dedupeKey` to prevent duplicate replans:

```text
user:{userId}:plan:{planId}:near_term_replan
user:{userId}:plan:{planId}:today_readiness
user:{userId}:plan:{planId}:weekly_rollover:{yyyy-mm-dd}
```

If five imported activities arrive together, they should become one near-term replan. If readiness changes today, it should be able to preempt a lower-priority import event.

## Reassess Versus Replan

The engine should reassess often and replan only when needed.

Always reassess:

- recompute `AthleteTrainingState`
- update completion/adherence facts
- evaluate fatigue and load
- classify the latest event

Only create a new `TrainingPlanVersion` when the chosen action materially changes the next 7-14 days.

Do not replan for noise:

- expected easy workout completed normally
- normal readiness with no other change
- small pace variance
- imported activity already linked to a planned workout

Do replan for material signals:

- missed key workout
- low readiness before a hard session
- high fatigue risk
- extra workout caused a load spike
- goal or schedule changed
- pain, illness, or injury flag
- repeated missed sessions
- weekly rollover needs fresh sessions

The API can expose a compact status:

```text
planningStatus: stable | reassessing | updated | needsAttention
```

This lets the client show a calm "Updating today's plan" state without making the plan feel random.

## Event Processing Flow

MVP can process events synchronously after request handlers enqueue them. The service boundary should still look like a queue processor so it can become a background worker later.

Loop:

1. Claim pending `PlanningEvent` rows where `runAfter <= now`.
2. Load `TrainingGoal`, active `TrainingPlan`, latest `TrainingPlanVersion`, recent `Activity`, recent `WorkoutCompletion`, and latest `ReadinessCheckIn`.
3. Compute or refresh `AthleteTrainingState`.
4. Classify the situation.
5. Generate candidate adjustments.
6. Reject unsafe candidates.
7. Score remaining candidates.
8. Create a new `TrainingPlanVersion` if the chosen candidate materially changes the next 7-14 days.
9. Create or update `PlannedWorkout`, `WorkoutBlock`, and `WorkoutStep` rows for the affected horizon.
10. Create `PlanAdjustmentEvent`.
11. Mark `PlanningEvent` rows as `completed` or `ignored`.
12. Return explanation and updated `PlannedWorkout` rows to the client when processing was request-driven.

Situation classes:

- `missedEasyWorkout`
- `missedKeyWorkout`
- `lowReadinessToday`
- `highFatigueRisk`
- `loadSpike`
- `aheadOfPlan`
- `behindPlan`
- `scheduleCompressed`
- `goalDateChanged`
- `strongProgress`

## Adaptation Policy

Rules should feel like a good coach:

- Do not cram missed work.
- Preserve the workout intent when possible.
- Reduce stress before reducing identity: "lighter tempo" is better than "you failed tempo day."
- Keep hard sessions separated by enough recovery.
- Cap load increases.
- De-load after high fatigue or repeated missed sessions.
- Protect consistency for new or returning users.
- Preserve specificity near a race or event.
- Explain what changed and why.

Examples:

| Signal | Adaptation |
| --- | --- |
| Missed easy workout | Drop it or make it optional recovery |
| Missed long workout | Hold long-session progression next week |
| Low readiness today | Shorten by 25-40% or swap hard stimulus to easy aerobic |
| High fatigue risk | De-load next 7 days |
| Completed everything and readiness is good | Progress slightly within ramp limits |
| User only has 20 minutes | Preserve stimulus in miniature |
| Pain or illness flag | Replace with rest, mobility, or conservative walk |

## Candidate Scoring

The engine should generate several candidate weeks and score them.

Candidate types:

- conservative
- balanced
- stretch
- recovery-biased
- schedule-optimized

Scoring dimensions:

- goal specificity
- progression value
- fatigue risk
- adherence likelihood
- schedule fit
- modality preference fit
- novelty and enjoyment
- safety constraints

The highest score should not automatically mean the hardest week. The best plan is the one the user can complete and recover from.

## Relationship To Current Template Tables

Current database-backed template tables remain useful:

- `TrainingPlanTemplate`
- `TrainingPlanWeek`
- `TrainingPlanWorkout`
- `TrainingPlanWorkoutStep`

Long-term role:

- seed the first version of a plan
- provide safe examples for generated workouts
- provide fallback plans when adaptive generation cannot run
- preserve imported/open-source workout structures
- support QA comparisons against known-good progressions

They should not be the only source of truth for future adaptive plans. Generated `PlannedWorkout` rows should become the user's actual plan.

## API Direction

Suggested authenticated endpoints:

- `GET /v1/planning/goals`
- `POST /v1/planning/goals`
- `GET /v1/planning/state`
- `GET /v1/planning/plan`
- `POST /v1/planning/plan/rebuild`
- `GET /v1/planning/today`
- `GET /v1/planning/activity-suggestion`
- `POST /v1/planning/readiness`
- `POST /v1/planning/workouts/:id/skip`
- `POST /v1/planning/workouts/:id/complete`
- `POST /v1/planning/schedule/constraints`
- `GET /v1/planning/adjustments`

Because there are no live users yet, prefer a clean replacement: move the client to `/v1/planning/*`, then remove the old `/v1/coach/plans/*` routes instead of maintaining compatibility wrappers.

## Implementation Plan

There are no live users yet, so prefer a clean replacement over migration compatibility.

### Phase 1: Schema And Domain Split

- Add `TrainingGoal`, `TrainingPlan`, `TrainingPlanVersion`, `PlannedWorkout`, `WorkoutBlock`, `WorkoutStep`, `WorkoutCompletion`, `ReadinessCheckIn`, `AthleteTrainingState`, `PlanningEvent`, and `PlanAdjustmentEvent`.
- Remove `ActiveTrainingPlan` once the new flow is wired.
- Keep `TrainingPlanTemplate`, `TrainingPlanWeek`, `TrainingPlanWorkout`, and `TrainingPlanWorkoutStep` as seed/reference tables.
- Create `backend/src/services/planning/`.
- Move planning-specific types out of `coach` route code.

Suggested service files:

- `planning/events.ts`: enqueue, dedupe, claim, complete, fail
- `planning/athleteState.ts`: compute recent load, adherence, fatigue risk, modality breakdown
- `planning/goalPlanner.ts`: create the initial plan from a goal
- `planning/weekGenerator.ts`: generate the next 7-14 days
- `planning/adapters/runAdapter.ts`
- `planning/adapters/walkAdapter.ts`
- `planning/adapters/mobilityAdapter.ts`
- `planning/adapters/strengthAdapter.ts`
- `planning/adaptationEngine.ts`: missed workout, low readiness, load spike, pain flag
- `planning/scoring.ts`: conservative, balanced, stretch, recovery-biased candidate scoring
- `planning/explain.ts`: deterministic explanations first, AI later
- `planning/processor.ts`: process `PlanningEvent` rows end to end

### Phase 2: Clean Planning API

Add `/v1/planning/*` routes:

- `POST /v1/planning/goals`
- `GET /v1/planning/state`
- `GET /v1/planning/today`
- `GET /v1/planning/activity-suggestion`
- `POST /v1/planning/readiness`
- `POST /v1/planning/workouts/:id/skip`
- `POST /v1/planning/workouts/:id/complete`
- `POST /v1/planning/plan/rebuild`
- `GET /v1/planning/adjustments`

Each mutating endpoint should write the domain record and enqueue a `PlanningEvent` in the same transaction.

MVP route behavior:

- `POST /goals`: create goal, plan, version, planned workouts, and an initial adjustment event.
- `POST /readiness`: create check-in, enqueue `readinessSubmitted`, process immediately, return updated today.
- `POST /workouts/:id/skip`: mark skipped, enqueue `workoutSkipped`, process immediately, return updated state.
- `POST /workouts/:id/complete`: link completion/activity, enqueue `activityCompleted`, process immediately or with short debounce.
- `POST /plan/rebuild`: enqueue `manualRebuild`, process immediately.

### Phase 3: First Engine Behavior

Implement deterministic MVP rules:

- initial 14-day generation for run/walk goals
- backend-owned Home activity suggestion from canonical archetypes
- low-readiness same-day softening
- missed-workout handling without cramming
- pain/illness replacement with rest, walk, or mobility
- weekly rollover generation
- simple adherence and fatigue state
- `PlanAdjustmentEvent` explanations

Do not implement complex race periodization or AI-authored workouts in this phase.

### Phase 4: Client Integration

Replace `TrainingPlanStore` API usage with `/v1/planning/*`.

Client responsibilities:

- create or edit a `TrainingGoal`
- render `PlannedWorkout` for Today and upcoming days
- render `ActivitySuggestionResponse` for the Home `Now` card
- submit readiness
- mark planned workout skipped
- link completed activity to planned workout when started from a suggestion
- render plan adjustment explanations
- cache the latest planning state and activity suggestion for offline display

Because there are no live users, old `/v1/coach/plans/*` client calls can be removed once the new screens compile.

### Phase 5: Worker And Scheduling

After the synchronous MVP works:

- add a worker entrypoint for `PlanningEvent` processing
- add a scheduled weekly rollover job
- add retry handling for failed events
- add metrics around event volume, replan count, and failed adaptations
- keep request-driven immediate processing only for user-visible events such as readiness and manual rebuild

### Phase 6: Multi-Sport Expansion

Add adapters in order of product value:

1. run/walk
2. mobility/recovery
3. simple strength
4. bike
5. HIIT
6. swim
7. skate

Each adapter must define generation, stress estimate, completion evaluation, and progression behavior before it can be used for primary planning.

## MVP Sequence

1. Add the new adaptive schema and remove `ActiveTrainingPlan`.
2. Add `PlanningEvent` enqueue/process helpers.
3. Add initial `TrainingGoal` creation and 14-day `PlannedWorkout` generation.
4. Add deterministic `AthleteTrainingState` computation from activities and completions.
5. Add `ReadinessCheckIn` and same-day low-readiness adaptation.
6. Add skipped-workout adaptation without cramming.
7. Add `TrainingPlanVersion` and `PlanAdjustmentEvent`.
8. Add `GET /v1/planning/activity-suggestion` with plan-first selection, real workout archetypes, and offline cache metadata.
9. Replace iOS training-plan API calls with `/v1/planning/*`.
10. Add candidate generation and scoring.
11. Add first sport adapter split: run/walk versus strength/mobility.
12. Add background worker and scheduled weekly rollover.
13. Add multi-sport adapters after the generic workout shape is stable.

## Non-Goals For V1

- LLM-authored raw training load.
- Perfect fitness modeling.
- Full periodization for every sport.
- Complex wearable recovery science before basic adherence adaptation works.
- Throwing away the template catalog before generated workouts have enough QA coverage.

## Open Questions

- Should `TrainingPlan` live under `coach` routes or a separate `planning` domain?
- How much generated history should the client cache offline?
- Should `WorkoutBlock` and `WorkoutStep` be tables immediately, or stay JSON until editing/analytics require relational data?
- What is the first non-running modality: strength, walking, cycling, or mobility?
- Should social/group workouts constrain planning in V1 or come later?
- Should `PlanningEvent` processing start synchronous-only, or should the first backend pass include a Cloud Run job worker entrypoint?
