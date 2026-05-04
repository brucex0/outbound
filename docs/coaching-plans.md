# Coaching Plans

Open this when designing or building personalized plans, plan recommendations, adaptive coaching, or the backend/client architecture for progression features.

## Product Goal

Make Outbound useful before, during, and after activity by helping the user know:

- what they are working toward
- what this week should look like
- what to do today

The system should feel like a coach relationship, not a rigid training spreadsheet.

## Core Product Shape

Use three user-facing layers:

- `focus`: what the user wants, such as `Run a 10K`, `Get back into rhythm`, or `Build endurance`
- `plan`: the multi-week structure that turns the focus into a realistic progression
- `today`: the single best next action based on the plan, readiness, and recent behavior

This structure works for race preparation and for non-race use cases.

## Product Principles

- Start from a realistic baseline, not an aspirational fantasy.
- Short sessions count.
- Missed days should trigger re-entry, not failure language.
- Today should always surface a clear next step.
- A plan should adapt to real behavior, not only to a setup survey.
- AI should personalize and explain, but core progression rules should stay deterministic.
- The system must support sports beyond running.

## User Inputs

The recommendation engine should combine explicit inputs and observed behavior.

Explicit inputs:

- focus type
- event distance and event date when relevant
- preferred sports
- preferred days per week
- available time per day or week
- experience level
- confidence and motivation mode
- injury caution or recovery constraints

Observed inputs:

- recent activity count, time, distance, and frequency
- long-session pattern
- pace or speed profile when relevant
- adherence to prior suggestions
- readiness check-ins
- skipped-day patterns after hard sessions
- gaps in activity and comeback behavior

Future inputs:

- HealthKit and wearable recovery signals
- weather
- route or terrain preferences
- social commitments such as club runs

## Personalization Model

Do not let AI invent the full plan from scratch.

Recommended layering:

1. A structured plan template library defines the allowed progression patterns.
2. A personalization engine selects the right template and tunes its parameters.
3. An adaptation engine adjusts the week and the next workout using recent behavior.
4. AI explains the choice and rewrites the result in coach voice.

This keeps the system trustworthy while still feeling personalized.

## Why Backend Should Own Plans

Recommendation:
- make the backend the source of truth for plan definitions, active plan state, and adaptation logic

Why:

- recommendation logic can improve without an app release
- bugs in progression logic can be fixed centrally
- plans can sync across devices
- analytics and experimentation become possible
- AI orchestration is easier and safer on the server
- a multi-sport system is easier to evolve centrally than in per-client logic

The client should still cache plan data locally for fast rendering and offline access.

## Backend Versus Client Responsibilities

Backend should own:

- template library
- personalization rules
- progression and safety guardrails
- active plan state
- weekly and daily recomputation
- adherence tracking
- AI prompt orchestration
- explanation and coach copy generation
- experiments, versioning, and observability

Client should own:

- plan and Today UI
- local cache
- offline rendering of the last-known plan
- local completion capture before upload
- lightweight fallback suggestions if the network is unavailable
- readiness input and feedback collection

## Multi-Sport Domain Model

Avoid running-specific product primitives such as `5kPlan` or `longRun` at the top level.

Use generic concepts:

- `Goal`
- `Sport`
- `PlanTemplate`
- `ActivePlan`
- `PlanWeek`
- `PlannedSession`
- `CompletedSession`
- `PlanAdaptation`
- `ReadinessCheckIn`
- `CoachRecommendation`

Recommended high-level definitions:

- `Goal`: the user's intent, such as race prep, consistency, endurance, performance, recovery, or general fitness
- `Sport`: run, walk, ride, strength, mobility, mixed, and future types
- `PlanTemplate`: the versioned progression blueprint
- `ActivePlan`: one user's personalized plan instance
- `PlanWeek`: a generated week with targets and session slots
- `PlannedSession`: one suggested workout or recovery action
- `CompletedSession`: the normalized record of what actually happened
- `PlanAdaptation`: a record of what changed and why
- `ReadinessCheckIn`: user-reported daily state
- `CoachRecommendation`: the Today card content and rationale

## Plan Template Design

Templates should be structured and versioned.

Each template should define:

- supported sports
- supported goal types
- baseline duration in weeks
- recommended sessions per week range
- progression pattern
- recovery week cadence
- workout type mix
- parameter bounds
- eligibility rules

Example template families:

- `run_5k_beginner`
- `run_10k_improver`
- `run_half_beginner`
- `run_comeback`
- `walk_consistency`
- `walk_to_run`
- `ride_endurance`
- `strength_consistency`
- `hybrid_endurance_strength`

Current iOS MVP note:

- the app now ships a local plan library with structured `weeks -> workouts -> steps`
- the `5K` plan is directly imported from the MIT-licensed [`lmorchard/c25k-web`](https://github.com/lmorchard/c25k-web) Couch-to-5K data
- the local `consistency`, `comeback`, `10K`, `10 mile`, and `half marathon` plans are authored in-app but use open-source MIT workout taxonomy cues from [`danielcoats/training-planner`](https://github.com/danielcoats/training-planner) for realistic workout types such as `intervals`, `fartlek`, `long run`, `cross-train`, and `time trial`
- the library now also imports larger week-by-week plans from MIT-licensed [`hoovercj/time-to-run`](https://github.com/hoovercj/time-to-run), including a `base 30 mpw` phase plus `half marathon beginner` and `half marathon advanced` variants
- imported plain-text plans are normalized into Outbound workout kinds and step lists so the same detail UI and Today adaptation logic can still work across authored and imported plans
- the same catalog has been exported into `backend/src/data/trainingPlanTemplates.ts` for seeding and fallback; deployed backends load the active catalog from Prisma `TrainingPlanTemplate`, `TrainingPlanWeek`, `TrainingPlanWorkout`, and `TrainingPlanWorkoutStep` tables
- the backend is now the source of truth for recommendation candidates, active-plan state, current-week progress, and Today adaptation
- iOS still keeps `TrainingPlanLibrary.swift` as an offline fallback and compatibility cache, but the normal authenticated flow calls the plan API through `APIClient`

## Personalization Parameters

Templates should be tuned with structured parameters rather than free-form AI output.

Recommended parameters:

- total plan length
- sessions per week
- target weekly minutes
- target weekly distance when relevant
- long-session starting point and progression
- pace or effort bands when relevant
- workout intensity mix
- recovery emphasis
- optional versus required sessions
- hard day spacing

Important rule:
- do not auto-prescribe load that materially exceeds the user's demonstrated recent baseline unless they explicitly choose a stretch goal

## Today Recommendation Model

Even with a multi-week plan, the most important output is today's best next action.

The recommendation engine should consider:

- today's planned session
- readiness state
- recent completed sessions
- missed sessions
- recovery spacing
- available time
- focus urgency, such as event countdown

Potential outcomes:

- do the planned session as written
- shorten it
- swap it with a lighter alternative
- move intensity later in the week
- recommend recovery, mobility, or rest
- suggest a catch-up only when it is safe and helpful

The coach voice should explain the recommendation in human language.

## Adaptation Rules

Adaptation should happen at two levels:

- daily adaptation for today's best next step
- weekly adaptation for the shape of the upcoming week

Daily adaptation examples:

- low readiness turns `40 min easy` into `20 min easy`
- missed yesterday moves a workout instead of stacking intensity
- a hard session yesterday makes today recovery-first

Weekly adaptation examples:

- poor adherence lowers next week's volume or number of required sessions
- stable adherence increases load gradually within safe bounds
- repeated low readiness adds a lighter week
- steady over-performance can unlock a higher-volume branch

## AI Role

Use AI for:

- mapping survey answers and messy history into structured plan inputs
- producing candidate-plan explanations
- rewriting plan summaries in coach voice
- generating weekly and daily rationale
- suggesting alternatives when the user deviates from plan

Do not rely on AI alone for:

- progression ceilings
- injury-risk safeguards
- event countdown structure
- recovery spacing
- hard constraints by sport

Recommended system pattern:
- rules engine for plan correctness
- AI layer for personalization, summarization, and communication

## API Shape

The client should not need to recreate plan logic locally.

Recommended endpoints:

- `GET /coach/plans/state`
- `POST /coach/plans/recommendation`
- `POST /coach/plans`
- `GET /coach/plans/active`
- `GET /coach/plans/active/week`
- `GET /coach/today`
- `DELETE /coach/plans/active`
- `POST /coach/checkins/readiness`
- `POST /coach/sessions`
- `POST /coach/plans/active/adapt`

Suggested responsibilities:

- `GET /coach/plans/state`: return the app-shaped training plan state for the current authenticated user, including either active plan/week/today or recommendation candidates
- `GET /coach/plans/templates`: return the database-backed template catalog for the current authenticated app session
- `POST /coach/plans/recommendation`: return one or more recommended plan candidates with rationale
- `POST /coach/plans`: accept a candidate or create a personalized active plan
- `GET /coach/plans/active`: fetch the active plan summary and metadata
- `GET /coach/plans/active/week`: fetch the current or requested week structure
- `GET /coach/today`: fetch today's best recommendation and explanation
- `DELETE /coach/plans/active`: clear the current user's active plan and return fresh recommendation state
- `POST /coach/checkins/readiness`: record readiness and optionally trigger recomputation
- `POST /coach/sessions`: ingest a completed session summary and trigger plan updates
- `POST /coach/plans/active/adapt`: force a re-plan when preferences or constraints change

Current implementation notes:

- `ActiveTrainingPlan` in Prisma stores one active plan per user with template id, tuned weekly targets, and start date.
- `TrainingPlanTemplate` and its week/workout/step child tables store the reusable template catalog. The seed script rebuilds these rows from `backend/src/data/trainingPlanTemplates.ts`.
- Recommendation and Today logic lives in `backend/src/services/trainingPlans.ts` and derives recent training stats from synced `Activity` rows.
- Readiness is currently passed as request context from the iOS daily check-in and is not yet persisted as a `ReadinessCheckIn` row.
- iOS caches the last active plan/week/today response for offline rendering, then falls back to local deterministic rules if the API is unavailable.

## Suggested Response Shapes

Keep responses structured and typed.

`Plan recommendation` should include:

- candidate id
- focus summary
- sport set
- duration in weeks
- sessions per week
- rough week shape
- why this fits
- tradeoffs

`Active plan summary` should include:

- active plan id
- focus
- current phase
- start and target dates
- sports involved
- plan status
- current week progress
- next key session

`Today` should include:

- recommendation type
- title
- duration or effort target
- sport
- structured workout payload when relevant
- coach explanation
- fallback easier option
- confidence or rationale metadata for internal use

## Session Modeling

Planned and completed sessions should share common normalized fields.

Recommended fields:

- sport
- session category
- planned duration
- planned distance when relevant
- effort target or pace band when relevant
- structured steps when relevant
- optionality
- completion status
- completion deltas

Session categories should be cross-sport friendly:

- easy
- long
- interval
- tempo
- recovery
- walk
- strength
- mobility
- rest

## Data and Storage Guidance

Keep template definitions versioned and reviewable.

Recommended storage split:

- template catalog in versioned backend config or database
- active plans and generated weeks in database
- adaptations and user feedback in database
- coach explanation text stored with generation metadata when useful for debugging

Version important objects:

- template version
- personalization algorithm version
- adaptation engine version
- AI prompt or strategy version

This makes retrospective analysis and migrations much easier.

## Observability

Plan quality should be measured, not guessed.

Track:

- recommendation acceptance rate
- plan completion rate
- week-over-week adherence
- plan abandonment rate
- frequency of plan adaptations
- how often easier alternatives are chosen
- retention impact by plan type

Useful breakdowns:

- by sport
- by goal type
- by onboarding recommendation path
- by low-readiness versus high-readiness users

## UX Flow Recommendation

Recommended product flow:

1. User chooses a focus.
2. User answers a short setup survey.
3. Backend recommends 1-3 plan options.
4. Coach explains the best-fit option in human language.
5. User accepts or tunes difficulty.
6. Today starts reflecting the active plan immediately.
7. Daily and weekly check-ins adapt the plan over time.

Avoid:

- forcing users into a dense calendar first
- showing failure-heavy copy for missed days
- making users manually rebuild the week after every miss

## V1 Scope

Ship first:

- backend-owned plan templates
- one active plan at a time
- running and walking only
- focus types for consistency, comeback, 5K, 10K, 10 mile, and half marathon
- deterministic personalization from survey plus recent history
- daily Today recommendation from active plan plus readiness
- weekly plan view with simple adaptation
- AI explanation and coach voice, not full free-form planning

Defer:

- full multi-sport hybrid plans
- advanced pace targeting
- strength block periodization
- shared coach plans between users
- heavy calendar editing
- complex wearables-first recovery models

## Current Implementation Status

Implemented locally in the iOS app now:

- predefined running templates for consistency, comeback, 5K, 10K, 10 mile, and half marathon
- local-first recommendation logic based on recent saved activity history and current motivation phase
- one active plan at a time
- weekly plan-progress summary on Today
- adaptive today's plan suggestion that softens the recommendation when readiness is low or stressed

Still deferred:

- backend-owned plan catalog and active plan state
- plan APIs and cross-device sync
- non-running plan templates exposed in product UI
- richer weekly adaptation and rescheduling
- AI-generated explanations backed by plan-specific server context

## Phase Plan

### Phase 1: Structured Plan Foundation

Goal:
- prove that users want Outbound to tell them what to do today and this week

Build:

- backend plan template catalog
- onboarding survey additions
- recommendation endpoint
- active plan creation
- current week generation
- Today recommendation endpoint
- client plan summary and week UI

Success signals:

- users accept plans
- daily recommendation taps increase
- plan users return more often than non-plan users

### Phase 2: Adaptive Weekly Coaching

Goal:
- make plans feel responsive rather than static

Build:

- readiness-driven daily adjustments
- adherence-based weekly adaptation
- adaptation history and reasoning
- weekly review summary
- better explanation copy

Success signals:

- fewer abandoned plans
- better completion of weekly sessions
- more recovery-option acceptance without churn

### Phase 3: Expand Beyond Running

Goal:
- evolve from race-plan support into a broader coaching platform

Build:

- walking-first and return-to-movement plans
- cycling templates
- strength and mobility session support
- mixed-sport goal definitions

Success signals:

- meaningful adoption outside pure running plans
- similar adherence quality across sports

### Phase 4: Deeper Intelligence

Goal:
- make the system feel increasingly personal without losing trust

Build:

- richer historical modeling
- better performance estimation
- HealthKit and wearable-informed adaptation
- smarter alternative workout generation
- more autonomous re-planning with strong guardrails

## Implementation Notes For Outbound

Near-term fit with current product:

- Today remains the primary surface for plan output
- the existing focus language from `docs/goals-progress.md` should remain the user-facing framing
- readiness input from `docs/motivation-ux.md` should feed daily adaptation
- the assistant from `docs/assistant.md` can explain plans, answer `why this today?`, and help the user change focus

Recommended first visible surfaces:

- focus setup card on Today
- plan recommendation card stack
- active focus and week-progress card
- today's planned session card
- post-activity reflection that references plan progress

## Open Questions

- Should V1 allow one active plan only, or one primary plan plus optional side routines such as mobility?
- How much plan editing should users get before backend adaptation becomes the main mechanism?
- Should the first non-running expansion be walking, strength, or a simple mixed consistency plan?
- Should coach personas only rewrite explanations, or should they slightly alter recommendation framing too?
