# Personalized Running Companion

Open this when implementing runner intake, calibration, feedback, athlete understanding, or adaptive training behavior.

## Product Promise

Outbound gets to know how a runner trains and plans around how they live.

Personalization is a continuous learning loop, not a one-time generated plan:

```text
understand -> prescribe -> observe -> ask -> learn -> adapt -> explain
```

The product must remain useful with little data, communicate uncertainty, and improve as evidence accumulates.

## First-Runner Experience

### Conversational intake

Collect only information needed for a safe, realistic first week:

- goal and relevant date;
- recent running frequency and comfortable duration;
- typical weekly availability and preferred long-run day;
- current pain, recent injury/illness, and material restrictions;
- optional Apple Health import;
- recurring family, friend, and club runs;
- preference for detailed or minimal coaching.

Before generating the week, show an editable companion summary. Separate runner-provided facts from starting estimates.

### Calibration period

Use the first 7-10 days to learn through normal training. Do not require an all-out test.

Default three-run sequence:

1. Comfortable run: estimate natural easy effort and sustainable duration.
2. Easy run with short pickups: observe controlled faster running.
3. Longer relaxed run: estimate endurance and recovery response.

Experienced runners may optionally use a recent race, imported benchmark, 20-minute controlled effort, or 5K time trial. Calibration must be skippable and must not block normal use.

### Lightweight feedback

Before a relevant workout, ask one readiness question: `Good`, `Tired`, `Sore`, or `Short on time`. Skip the prompt when no decision would change.

After a relevant workout, ask:

- `Easy`, `About right`, or `Too hard`;
- one context-sensitive follow-up, such as whether the runner could have continued;
- an optional voice or text note.

Do not ask the same generic questions after every run.

## Living Runner Model

Maintain a versioned runner model with provenance and confidence rather than an opaque free-text memory.

### Facts

- goals, dates, availability, preferences, and recurring social commitments;
- injury or restriction flags that the runner explicitly supplied;
- measurement units and coaching-detail preference.

### Observations

- recent volume, duration, distance, consistency, and adherence;
- easy-effort pace/heart-rate ranges when available;
- endurance, recovery time, intensity tolerance, and completion patterns;
- preferred times, terrain, run-goal modes, and social context.

### Inferences

Each inference has:

- typed value;
- confidence: `low`, `medium`, or `high`;
- evidence references;
- first and last observed timestamps;
- expiry or refresh policy where appropriate.

The companion may summarize these into natural language, but planning decisions use the structured model.

## Adaptation Speeds

- Immediate: shorten, soften, swap, or reschedule today's workout.
- Weekly: revise the next 7-14 days from adherence, feedback, and recovery.
- Long-term: update ability ranges, phase, and progression after sustained evidence.

Never regenerate the entire plan because one run was missed. Meaningful changes show the reason, expected effect, and `Keep original` action.

## Safety Boundary

- Pain or concerning symptoms do not trigger AI diagnosis.
- The companion may recommend stopping, resting, or seeking qualified care.
- Do not prescribe aggressive progression from a single benchmark.
- Sensor estimates never override explicit runner feedback without explanation.
- Raw cycle data stays within the boundary defined in `docs/cycle-aware-coaching.md`.

## Client Plan

### Slice C1: Contract and local states

- Add typed DTOs for onboarding summary, calibration status, readiness, feedback, runner-model insights, and plan adjustments.
- Add fixtures for empty, loading, offline, partial-data, and completed-calibration states.
- Keep the new shell behind `-OutboundSimplifiedShell` until the vertical slice is complete.

### Slice C2: Intake and editable understanding

- Replace the old onboarding intake with short structured choices plus optional natural-language context.
- Add `UnderstandingSummaryView` with per-section edit actions.
- Treat Apple Health as optional evidence, not a prerequisite.
- Persist an onboarding draft locally and resume after authentication or interruption.

### Slice C3: Calibration experience

- Add `CalibrationOverviewView` and a small progress banner on Today.
- Render calibration workouts through the shared workout block model.
- Reuse the retained recorder and activity store.
- Support recent-race/imported-benchmark entry without forcing a test.

### Slice C4: Readiness and post-run feedback

- Add a pre-run check-in only when the response can change the workout.
- Add the three-choice effort prompt and one conditional follow-up after completion.
- Queue submissions locally when offline and make them idempotent.
- Do not block activity saving or leaving the post-run screen.

### Slice C5: Explainable adaptation

- Add an adaptation sheet showing before/after, concise reason, and affected schedule.
- Require explicit confirmation for schedule-wide changes; allow safe same-day reductions immediately with undo.
- Show `What I learned` only for evidence-backed changes and include confidence language.

### Target client modules

```text
Features/Onboarding/
  IntakeScreenModel
  UnderstandingSummaryView
Features/Calibration/
  CalibrationOverviewView
  CalibrationScreenModel
Features/Today/
  ReadinessCheckInView
  AdaptationExplanationView
Features/PostRun/
  RunFeedbackView
Domains/Athlete/
  RunnerModelDTO
  CalibrationDTO
  FeedbackDTO
Services/API/
  AthleteAPI
  TrainingAPI
```

## Backend Plan

### Slice B1: Identity, onboarding, and runner facts

- Replace `CoachProfile` as the primary athlete record with `RunnerProfile` and structured preferences.
- Add authenticated `GET/PUT /v1/onboarding` and `GET/PUT /v1/me` routes.
- Store runner-provided facts separately from derived observations and inferences.

### Slice B2: Evidence and versioned runner model

- Add `RunnerObservation`, `RunnerInference`, and immutable `RunnerModelVersion` records.
- Build a deterministic runner-model projector from activities, workout completions, readiness, and feedback.
- Store evidence references and confidence; never make the language model the source of truth.
- Emit durable, idempotent projection events after relevant writes.

### Slice B3: Calibration orchestration

- Add calibration state and three reviewed calibration workout templates.
- Assign calibration as the first plan block when appropriate.
- Accept recent race or benchmark evidence with source and date.
- Complete calibration from sufficient evidence, not merely three button taps.

### Slice B4: Feedback and readiness APIs

Add authenticated, idempotent endpoints:

```text
GET  /v1/me/runner-model
GET  /v1/calibration
POST /v1/calibration/benchmark
POST /v1/check-ins/readiness
POST /v1/workouts/:id/feedback
GET  /v1/runner-model/insights
```

Feedback writes must return the accepted record and any immediate proposed adjustment. Repeated client requests use a client-generated idempotency key.

### Slice B5: Adaptation policy and explanations

- Extend `AthleteTrainingState` with calibrated effort, endurance, recovery, preference, and confidence fields.
- Keep load and progression decisions deterministic and bounded.
- Generate candidate adjustments, score them, persist the selected proposal, then use AI only to explain it.
- Record input model version, policy version, before/after workout IDs, reason codes, and runner decision.
- Reproject and adapt at three speeds: immediate, weekly, and long-term.

### Proposed data shape

```text
RunnerProfile
RunnerPreference
RunnerObservation
RunnerInference
RunnerModelVersion
CalibrationProgram
CalibrationEvidence
ReadinessCheckIn
WorkoutFeedback
PlanAdjustment
PlanningEvent
```

## Shared Contract First

Before client or backend implementation proceeds beyond fixtures, freeze:

- runner summary and confidence enums;
- calibration status and evidence types;
- readiness and feedback request/response DTOs;
- adjustment reason codes and before/after representation;
- idempotency and offline retry behavior;
- privacy classification for every field.

Use checked-in JSON fixtures in both backend contract checks and Swift previews so both sides can work independently.

## Delivery Order

1. Contracts and fixtures.
2. Onboarding summary plus runner facts.
3. Calibration status and reviewed workouts.
4. Today readiness and post-run feedback.
5. Runner-model projection and `What I learned`.
6. Explainable immediate adaptations.
7. Weekly and long-term adaptation.
8. Social schedule awareness without exposing private coaching evidence.

The first shippable learning loop is complete when a new runner can finish intake, see an editable understanding, complete calibration runs, submit lightweight feedback, and receive one safe, explained plan adjustment grounded in visible evidence.
