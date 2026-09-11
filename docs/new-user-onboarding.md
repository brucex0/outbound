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

### 1. Objective

Ask `What do you want this plan to help you achieve?`

Choose one primary objective and optionally up to two supporting objectives:

- prepare for an event
- build endurance or go farther
- improve speed
- lose weight
- maintain fitness
- improve health and energy
- something else

Keep strength hidden as both an objective and activity until Plainstride has dedicated recording, workout generation, launching, progress, and guidance for it.

Do not offer `Build consistency` or `Get active regularly` as objectives. Consistency is a means of achieving an objective and belongs in plan behavior and adherence guidance.

Ask for event distance and date only when event preparation is selected. Treat `starting out` and `returning after a break` as starting context, not objectives.

The primary objective controls progression and tradeoffs. Supporting objectives influence activity mix, session selection, and the explanation without creating independent competing plans.

### 2. Activities

Ask which activities the plan should use:

- choose one primary activity
- optionally choose supporting activities
- currently expose only `Run`, `Walk / Hike`, and `Bike`
- expose only activities for which recording, workout generation, launching, progress, and guidance are credible

The planner should reason about training stimulus first, then use modality adapters to create sport-specific sessions. Do not silently map an unsupported modality to running.
Keep `Strength` and `Mobility` hidden until they meet that full support bar; their internal planner values may remain dormant for future implementation.

### 3. Starting Point

Collect only the baseline needed for the selected primary activity:

- recent session frequency
- comfortable session duration
- `starting out`, `currently active`, or `returning after a break`

Use observed Health or activity data when the user explicitly connects it. Keep manual answers editable.

### 4. Realistic Week

Ask what most weeks can reliably support:

- `1–6 sessions per week`
- typical time available
- preferred days when the user cares about scheduling
- preferred long-session day only when the plan needs one
- optional injury, illness, travel, or schedule constraints

One session per week is valid. Create one meaningful anchor session and label any mobility or recovery additions as optional. Never inflate the commitment to make the plan look fuller.

### 5. Optional Private Details

Birthday, height, weight, sex assigned at birth, and Apple Health remain optional and private. Keep the body fields manually editable; Apple Health is an optional autofill path, not a replacement for manual entry. Explain why a field helps before requesting it. Apple Health authorization occurs only after the user taps the connection action.

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
- Optional profile and Health sections have a direct `Skip` action.
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
- `plan_creation_completed`, with success/failure and a coarse latency bucket

Objective and activity categories may be bounded enum values. Never send free text, body details, dates, exact measurements, constraints, workout details, or account identifiers through analytics.

## Implementation Map

- Backend account state: `backend/prisma/schema.prisma`, `backend/src/services/authSessions.ts`, and `backend/src/routes/auth.ts` own the durable `pending` / `skipped` / `completed` contract and skip mutation.
- Backend plan creation: `backend/src/routes/planning.ts` and `backend/src/services/planning/` own structured objectives, modality mix, weekly capacity, scheduling preferences, and the adaptive 14-day starting window.
- iOS routing and persistence: `App/OutboundApp.swift`, `App/AuthStore.swift`, `Core/AuthSession.swift`, and `App/OnboardingStore.swift` use the server status as the authority and keep account-scoped builder drafts locally.
- Reusable iOS builder: `Features/Onboarding/SimplifiedOnboardingFlow.swift` is shared by first use, Today's `Planned` control, and the All Plans entry.
- No-plan behavior: `App/MainTabView.swift` keeps Today in manual Run mode while `Features/Planning/TrainingPlanViews.swift` leads All Plans with `Build my plan`.

Use `docs/onboarding-plan-setup-implementation-prompt.md` when revisiting the full acceptance contract.

## Debugging

Debug builds should continue to expose a replay action. Replay opens plan setup without clearing activity history, account identity, guide settings, prior onboarding resolution, or an existing plan unless the developer explicitly chooses a destructive reset action.
