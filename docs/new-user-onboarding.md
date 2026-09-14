# New User Onboarding And Plan Setup

Open this when changing first-launch routing, onboarding persistence, plan creation, or the no-plan experience.

## Product Decision

Onboarding and plan setup are separate concepts:

- `onboarding`: a one-time first-launch choice after authentication
- `plan setup`: a reusable flow that creates a personalized training plan
- `active plan`: independent state owned by the planning domain

A person may skip onboarding and use Plainstride without a plan. Skipping permanently resolves onboarding for that account; the app must not present it again automatically on a later launch. The user can still open plan setup explicitly at any time.

## First-Launch Flow

After authentication, terms acceptance, and any identity fields required for the account:

1. Explain the product promise briefly.
2. Offer two actions:
   - `Create my plan`
   - `Explore first`
3. `Explore first` records onboarding as skipped and opens the main app immediately.
4. `Create my plan` opens the reusable plan-setup flow.

Do not show a feature tour, request unrelated permissions, or require a plan before the main app becomes useful.

## Onboarding State

Persist an account-scoped server-backed status with three semantic values:

- `pending`: the first-launch choice has not been resolved
- `skipped`: the user chose to explore without a plan
- `completed`: the user created a plan through setup

The status must survive reinstall, logout/login, and use on another device. A local account-scoped cache may accelerate startup, but it is not the source of truth.

Plan state remains independent:

- `activePlan == nil` means the user has no active plan.
- Neither `skipped` nor `completed` should be used as evidence that an active plan exists.
- Once resolved, onboarding status preserves what happened during first use. Creating a plan later does not rewrite an earlier `skipped` outcome.
- Ending or deleting a plan does not make onboarding pending again.

The current implementation derives `onboardingCompleted` from `RunnerProfile.completedAt`. That coupling cannot represent a durable skip and must be replaced by an explicit onboarding status.

## No-Plan Experience

When there is no active plan:

- Today defaults to `Run`, not a generated or fallback planned workout.
- The manual Run flow remains fully useful.
- The `Planned` control remains visible and acts as an explicit `Build a plan` entry point.
- Tapping `Planned` opens plan setup instead of showing an empty or syncing planned-workout state.
- Do not show plan-setup prompts automatically at startup or insert repeated nag cards.

The All Plans page should lead with:

1. `Build my plan` as the personalized path.
2. Recommended authored plans.
3. The complete browsable plan catalog.

Selecting an authored plan remains a valid shortcut and does not need to go through personalized setup.

## Plan-Setup Flow

Plan setup should feel like a short conversation, not a configuration form. It can be launched from first use, the Today `Planned` control, or All Plans.

The builder is evidence-aware:

- new accounts describe their baseline because Plainstride has no activity evidence;
- established accounts see one compact training-setup summary inferred from the last 28 days: activity mix, session frequency, an upper-typical session duration, and habitual weekdays;
- partial or historical evidence may provide context but never silently establishes current fitness;
- established accounts accept that setup in one tap or choose `Adjust it`; they do not repeat the activities, baseline, and weekly-schedule forms;
- the same confirmation asks only whether injury, illness, travel, or schedule constraints have changed, because activity history cannot establish those safely;
- every inferred value is visible, editable, and labeled by source.

The backend classifies a baseline as established only when it contains at least six supported activities across at least three of the last four weeks and includes an activity in the last 14 days. This combines coverage and recency instead of using a single arbitrary stale-after interval. Older history remains useful context, but the builder asks for a current baseline. The inferred weekly schedule is rounded from the 28-day activity count and capped to the builder's supported 1–6 sessions before it enters any client or request contract.

Plan setup uses one conversational shell backed by a deterministic state machine. The coach asks one bounded question, then presents quick replies, an appropriate structured control, or a text composer. Natural-language goal input and quick replies enter the same thread; neither silently mutates a separate form. AI receives the privacy-filtered intake context (data tier, evidence state, aggregate baseline, inferred setup, prior schedule, and remaining question IDs), extracts explicit facts, and maps them into the structured contract. Product code owns question order, validation, consent, and completion. If AI is unavailable, deterministic interpretation and the same quick replies keep the flow usable.

### 1. Objective

Ask `What do you want this plan to help you achieve?`

Choose one objective—the outcome that matters most right now:

- prepare for an event
- build endurance or go farther
- improve speed
- lose weight
- improve health and energy

Keep strength hidden as both an objective and activity until Plainstride has dedicated recording, workout generation, launching, progress, and guidance for it.

Do not offer `Build consistency` or `Get active regularly` as objectives. Consistency is a means of achieving an objective and belongs in plan behavior and adherence guidance.

Ask for event distance and date only when event preparation is selected. Treat `starting out` and `returning after a break` as starting context, not objectives.

Event preparation also asks whether the runner wants to finish comfortably, perform strongly, or target a time. Non-event objectives ask for a 4-, 8-, or 12-week review horizon and an optional private description of what meaningful progress would feel like. The review horizon is a reassessment point, not an artificial end date.

After a typed goal is interpreted, keep the runner's message visible, acknowledge the understood goal, and reveal the next missing structured question in the same conversation. For example, `prepare for half marathon` establishes event preparation and half-marathon distance, then asks for the event date rather than closing a modal or returning to goal choices. Quick-reply goal selection follows the same path.

Only confirmed answers satisfy validation. A displayed suggestion may initialize a control, but Continue remains hidden or disabled until the runner confirms required event distance, date, intent, and target time when applicable. Confirmed answers remain tappable so the runner can revise them without restarting intake; revising an answer invalidates only that answer and any values that depend on it. On iOS, event date selection uses a dedicated calendar sheet that closes after a changed date is selected and retains a Done action to confirm the displayed date.

The objective controls progression and tradeoffs. Do not collect secondary objectives until the planner can genuinely reconcile multiple competing outcomes.

### 2. Activities

When recent evidence is not established, ask which activities the plan should use:

- choose one or more activities with no primary or supporting rank
- currently expose only `Run`, `Walk / Hike`, and `Bike`
- expose only activities for which recording, workout generation, launching, progress, and guidance are credible

Distribute selected activities evenly across the plan, moving to the next compatible selected activity when a workout stimulus is not supported by the current one. The planner should reason about training stimulus first, then use modality adapters to create sport-specific sessions. Do not silently map an unsupported modality to running.
Keep `Strength` and `Mobility` hidden until they meet that full support bar; their internal planner values may remain dormant for future implementation.

### 3. Starting Point

When recent evidence is not established or the runner chooses `Adjust it`, collect only the baseline needed for the selected activities:

- recent session frequency
- comfortable session duration
- `starting out`, `currently active`, or `returning after a break`

Use observed Health or activity data when the user explicitly connects it. Keep manual answers editable.

### 4. Realistic Week

When recent evidence is not established or the runner chooses `Adjust it`, ask what most weeks can reliably support:

- `1–6 sessions per week`
- typical time available
- preferred days when the user cares about scheduling
- let the planner place the long session automatically when the plan needs one
- optional injury, illness, travel, or schedule constraints

One session per week is valid. Create one meaningful anchor session and label any mobility or recovery additions as optional. Never inflate the commitment to make the plan look fuller.

### 5. Required Private Planning Details

Birth date, sex assigned at birth, and weight are required before a personalized plan can be created. Plainstride uses them as private planning inputs; weight also enables calorie calculations. Store birth date instead of a fixed age so age remains accurate. Height remains optional until a supported planning or calorie policy uses it.

Keep every body field manually editable. Apple Health or Health Connect is an optional autofill path, not a requirement or a way to skip confirmation. Explain the planning and calorie purpose before requesting the fields. Health authorization occurs only after the user taps the connection action. These values never appear in Together, generated social content, or analytics.

### 6. Create And Present The Plan

Use `Create my plan` as the creation CTA.

Creation establishes the overall objective, progression, activity mix, constraints, and adaptation policy. The product may concretely schedule only the next 7–14 days because later weeks adapt to actual behavior.

During a non-trivial request:

- replace the current content with an honest indeterminate loading state
- use copy such as `Building a plan around your week…`
- do not show fabricated percentages or artificial delays
- on failure, preserve the draft and show temporary toast-style failure feedback with Retry

The result should show:

- `Your plan`: objective, overall direction, activity mix, and expected duration when applicable
- `Your starting week`: concrete sessions, days, total time, and optional sessions
- one concise explanation of why the plan fits
- actions to make it easier, change days, or change activity mix
- `Go to Today` as the final action

Do not describe the CTA as `Build my first week`. The plan is broader than one week even though only the starting week is committed in detail.

## Calibration

Calibration means the first three relevant completed sessions, not three mandatory runs in the first calendar week. Show progress lightly and allow calibration to span as many weeks as needed for a low-frequency user.

## Exit And Resume

- First launch offers the explicit `Explore first` resolution.
- After plan setup has begun, closing it uses `Finish later` semantics and preserves the account-scoped draft locally.
- Apple Health or Health Connect remains optional. The required private planning fields do not have a `Skip` action.
- Exiting an explicitly launched plan setup never changes onboarding back to pending and never creates a partial active plan.

## Permission Timing

- Apple Health: only from its optional plan-setup action.
- Location and motion: when the first relevant outdoor activity starts.
- Notifications: after a plan is created or later from Settings.
- Camera and photos: on first use.
- Contacts: avoid when link-based invitations are sufficient.
- Live location: only when explicitly enabling sharing.

Do not request multiple system permissions during first use.

## Analytics And Privacy

Add typed, bounded events for:

- `onboarding_resolved`, emitted once with result `skipped` or `completed`
- `plan_builder_opened`, with entry source `onboarding`, `planned_button`, or `all_plans`
- `plan_builder_exited`, with a bounded step name
- `plan_creation_completed`, with success/failure, a coarse latency bucket, and a bounded error category on failure
- `plan_intake_context_loaded`, with the bounded data tier
- `plan_intake_goal_interpreted`, with success/failure, bounded source `conversation_text` or `quick_reply`, and a bounded error category on failure
- `plan_intake_answer_edited`, with a bounded field name and source `conversation`
- `plan_intake_baseline_confirmed`, with accepted/corrected and bounded source `recent_activities` or `recent_activity_setup`

Objective and activity categories may be bounded enum values. Never send free text, body details, dates, exact measurements, constraints, workout details, or account identifiers through analytics.
`plan_creation_completed` may include the single bounded goal type and a coarse selected-activity count bucket; it must not include profile measurements or free text.

## Implementation Map

- Backend account state: `backend/prisma/schema.prisma`, `backend/src/services/authSessions.ts`, and `backend/src/routes/auth.ts` own the durable `pending` / `skipped` / `completed` contract and skip mutation.
- Backend plan creation: `backend/src/routes/planning.ts` and `backend/src/services/planning/` own structured objectives, modality mix, weekly capacity, scheduling preferences, and the adaptive 14-day starting window.
- Adaptive intake: `GET /v1/planning/intake-context` returns the privacy-filtered evidence summary, inferred setup, and required questions. It derives habitual weekdays in the request's time zone and never sends raw activity records to the intake AI. `POST /v1/planning/intake/interpret` receives that aggregate context and extracts structured facts from one user message. `planIntake.ts` owns confidence, recency, strict AI output, and deterministic fallback behavior.
- iOS routing and persistence: `App/OutboundApp.swift`, `App/AuthStore.swift`, `Core/AuthSession.swift`, and `App/OnboardingStore.swift` use the server status as the authority and keep account-scoped builder drafts locally.
- Reusable iOS builder: `Features/Onboarding/SimplifiedOnboardingFlow.swift` is shared by first use, Today's `Planned` control, and the All Plans entry.
- No-plan behavior: `App/MainTabView.swift` keeps Today in manual Run mode while `Features/Planning/TrainingPlanViews.swift` leads All Plans with `Build my plan`.

The flat-activity migration combines each existing primary and supporting modality into `TrainingGoal.activities` and removes stored supporting objectives. Apply it with `cd backend && npx prisma migrate deploy`; no database rebuild is required. For a disposable local database, `cd backend && npm run db:rebuild` remains the clean reset path.

Use `docs/onboarding-plan-setup-implementation-prompt.md` when revisiting the full acceptance contract.

## Debugging

Debug builds should continue to expose a replay action. Replay opens plan setup without clearing activity history, account identity, guide settings, prior onboarding resolution, or an existing plan unless the developer explicitly chooses a destructive reset action.
