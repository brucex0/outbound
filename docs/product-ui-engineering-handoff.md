# Product UI Engineering Handoff

Open this when implementing the simplified product, onboarding, cycle-aware guidance, or their shared SwiftUI components.

This document translates the target UX into implementation contracts. Product rationale remains in:

- `docs/simplified-product-ux.md`
- `docs/new-user-onboarding.md`
- `docs/cycle-aware-guidance.md`

Clickable references:

- `docs/prototypes/outbound-major-flow.html`
- `docs/prototypes/outbound-onboarding-flow.html`
- `docs/prototypes/outbound-cycle-aware-flow.html`

## Shared Design Foundation

### Layout

- Base horizontal screen inset: `20 pt`; allow `16 pt` at compact widths.
- Section spacing: `20 pt`.
- Related-element spacing: `8-12 pt`.
- Card content inset: `16 pt`; hero card: `20-24 pt`.
- Card corner radius: `20 pt`; compact controls: `12-14 pt`; pills: full capsule.
- Minimum control height: `44 pt`.
- Respect safe areas; no important content beneath the home indicator or Dynamic Island.
- Support Dynamic Type without truncating workout instructions or primary actions.

### Typography

Use semantic iOS text styles rather than fixed sizes:

- Screen title: `.title2`, semibold-equivalent emphasis.
- Hero statement: `.title2` or `.title3` depending on length.
- Card title: `.headline`.
- Primary metrics: `.title` with monospaced digits where useful.
- Body: `.body`.
- Metadata and eyebrow: `.caption`, uppercase only for short categories.

Limit custom weights to regular and medium/semibold. Preserve legibility over exact prototype wrapping.

### Color and appearance

- Support light and dark appearances.
- Use semantic asset colors for background, elevated surface, primary text, secondary text, border, brand green, warm action accent, success, warning, and destructive action.
- Do not encode workout intensity, selection, completion, or health state using color alone.
- Use the warm accent only for the main action, live route, and a small number of high-attention moments.
- Use green for selected navigation, AI explanation, compatibility, and successful completion.

### Motion and feedback

- Use standard iOS navigation and sheet transitions.
- Use light haptics for selection, medium haptic for workout start, success haptic for completion or saved Moment.
- Avoid looping or decorative animation during live activity.
- Honor Reduce Motion and Reduce Transparency.

### Selection and tap targets

- When tapping a list row selects or opens that row, make the whole available row area tappable rather than only its text or icon.
- Keep embedded controls such as preview, toggle, menu, disclosure, or secondary-action buttons as independent tap targets. The row's primary tap area should fill only the remaining space and must not overlap or intercept those controls.
- Preserve a minimum `44 pt` target for every independent control and expose each action separately to accessibility.

## Shared Components

Implement reusable components rather than screen-specific copies.

### `OutboundPrimaryButton`

- One high-emphasis action per action group.
- Full-width when it advances a setup flow or starts a workout.
- Loading state replaces label with progress while preserving width.
- Disabled state remains readable and explains missing requirements when tapped where appropriate.

### `OutboundCard`

- Supports standard and hero variants.
- Owns padding, surface, border, radius, and shadow.
- Does not own section spacing.

### `AIExplanationView`

Input:

- short explanation;
- optional source label such as `Adjusted from plan`;
- optional action such as `Why?`.

Rules:

- maximum two short sentences in collapsed form;
- never use generic praise;
- disclose material plan changes;
- no raw private health reason on social surfaces.

### `WorkoutPhaseSummary`

Input:

- ordered phase groups;
- duration or repeat count;
- label and effort;
- current/completed state when live.

Variants:

- horizontal proportional chain for Today;
- vertical phase flow for detail;
- compact progress rail for live sessions;
- completed rail for post-run.

Group repeated intervals into one expandable repeat block. Do not render every generated backend step as a peer row.

### `ActivityStatRow`

- Up to three context-relevant stats.
- Use monospaced digits.
- Units remain visible with accessibility labels.
- Social and Me variants may choose different metrics.

### `PersonOrClubRow`

- Avatar/mark, title, one context line, optional AI match line, one action.
- Relationship or club membership state must be accessible without color.

### `MomentView`

Variants:

- live camera action;
- focused capture;
- saved preview;
- social hero.

Moment media is private until explicit post-run approval.

## App Navigation

Primary tabs, left to right:

1. Together
2. Today
3. Me

Today is the initial tab after onboarding. Use icons with accessibility labels; the selected tab may reveal its text label. Persist the last selected tab for returning users only after they have completed onboarding.

Keep the primary Today action direct: `Start run` opens run setup without an intermediate detail or readiness screen. Today itself carries the essential workout summary. A single optional `Change` action asks for a short reason such as low energy, soreness, or limited time, then offers one clear alternative; readiness terminology must not appear in the primary UI or gate every start. Hide the primary tab bar during live activity, camera capture, and post-run completion. Restore it after saving or discarding.

## Today Screen Contract

Required order:

1. Compact inspirational quote.
2. One workout recommendation showing workout name, total duration, small header icons for Change and Why, an equal-weight interval preview, and Start as the only full-width card action.
3. One `Quick start` button into freestyle setup.
4. At most one compact social opportunity.

States:

- Loading: show stable skeleton geometry; no layout jump.
- Offline with cache: show cached recommendation and `Updated <time>`.
- Offline without cache: offer freestyle run; do not invent a plan workout.
- Completed today: replace start action with completion reflection and next planned action.
- No active plan: show one reviewed standalone recommendation and a secondary plan setup path.
- Active live session: replace Start with Return to run.

`Change` stays in a sheet: ask for the constraint, show one recommendation, and either apply it or keep the original. It must never inject a new card into Today. `Quick start` has no mode chooser on Today.

## Workout Detail and Live Session

Workout detail contains:

- title, total duration, effort;
- vertical phase flow;
- concise purpose;
- `Why this?` explanation;
- Start action.

Live session prioritizes:

- map or primary stats;
- current phase and remaining time;
- current pace/effort;
- next phase;
- Pause and Finish;
- subordinate Moment action.

Do not place camera, assistant, or social controls between Pause and Finish.

### Moment capture

- Tap camera to open the focused capture surface.
- Continue workout timing and GPS capture.
- Persist photo locally with activity elapsed time, phase identifier, and private coordinate metadata.
- Offer Retake and Keep; Keep returns to live session.
- If the active phase is hard or movement is unsafe, explain that capture is available during recovery or after pausing.
- Live tracking never includes photo/video content.

Post-run shows saved Moments as private. Sharing requires an explicit user action.

## Post-Run Contract

Order:

1. Completion reflection.
2. Core stats.
3. Moment preview when present.
4. AI social draft.
5. Share or Save privately.

AI drafts must remain editable and must never auto-publish. Saving the activity must not require social sharing.

## Together Contract

Prioritize actionable context:

1. Next compatible person or shared run.
2. Relevant club run.
3. One rich recent activity.
4. Compact subsequent activity rows.

A rich social activity contains person/time, title, photo-or-route hero, up to three stats, one factual AI highlight, and reaction actions.

Private plan or health causes never leave the owning user's planning domain. Together receives only compatibility and share-safe explanations.

## Me Contract

Order:

1. Current focus and plan week.
2. Weekly adherence and totals.
3. Precise guide observation.
4. Four-week trend.
5. Training-oriented recent activity.
6. History, records, predictions, and gear.

Settings live behind the gear action. Progress content must not require opening settings.

## Authentication and Onboarding

Authentication screen:

- Apple and Google provider buttons only.
- Both actions support signup and returning login.
- New account enters onboarding; returning account enters Today.
- Provider conflict shows a targeted recovery message after attempted authentication.

Onboarding steps:

1. Goal.
2. Starting point.
3. Realistic week.
4. Generated first week.
5. Optional person/club connection.
6. Today.

Persist the draft after every step. Back navigation preserves values. Resume interrupted onboarding at the last incomplete step.

Conditional fields:

- Race distance/date only for race goal.
- Preferred long-run day only when the generated plan needs it.
- Apple Health remains optional.

Do not request location, motion, notifications, camera, contacts, or live-location permissions as a batch. Follow the timing in `docs/new-user-onboarding.md`.

## Cycle-Aware Guidance Contract

Entry: `Me -> Health & body -> Cycle-aware guidance`.

Required V1 screens:

- privacy/setup explanation;
- Apple Health connection or manual logging;
- period and symptom logging;
- same-day adjustment choice;
- adjusted-week review;
- private learned-pattern preference.

Adaptation is based on reported training impact and existing safety rules, not cycle phase alone. Preserve `Keep planned workout` unless an independent safety condition prohibits it.

Raw cycle data must not enter:

- general assistant context;
- social/activity-post payloads;
- club or compatible-workout APIs;
- general product analytics.

Planning receives only the derived adjustment signal described in `docs/cycle-aware-guidance.md`.

## Accessibility Acceptance Criteria

- All icon-only controls have VoiceOver labels.
- Dynamic Type at accessibility sizes preserves all primary actions and workout instructions.
- Selection, workout state, intensity, and completion do not depend on color alone.
- Touch targets are at least `44 x 44 pt`.
- Live metrics use meaningful combined labels, for example `Current pace, 5 minutes 58 seconds per kilometer`.
- Reduce Motion removes nonessential transitions.
- Photos include user-authored alt text when shared; route fallback has a generated route summary.
- VoiceOver focus returns to the initiating control after dismissing sheets.

## Privacy and Safety Acceptance Criteria

- No social publication occurs without explicit confirmation.
- Moment location remains private unless the user chooses a location-inclusive share mode.
- Live-location recipients never receive Moment media automatically.
- Raw reproductive-health data never appears in logs, analytics, notifications, social payloads, or general AI prompts.
- Destructive actions such as Discard run or Delete cycle history require clear confirmation.

## Analytics Events

Use privacy-safe product events only. Do not attach free text, coordinates, health details, cycle state, or private adjustment reasons.

Recommended events:

- `onboarding_step_completed(step)`
- `first_week_accepted(adjusted: Bool)`
- `today_adjustment_selected(type)`
- `workout_started(source)`
- `moment_captured(phase_kind)`
- `moment_shared(destination_kind)`
- `compatible_run_opened(source_kind)`
- `club_run_joined(distance_group)`
- `cycle_guidance_enabled(source)` without cycle or symptom data
- `cycle_adjustment_accepted(adjustment_kind)` without private reason

## Definition of Done

- Implements every required state above using reusable components.
- Matches the information hierarchy and interaction flow in the clickable references.
- Supports light/dark appearance, Dynamic Type, VoiceOver, Reduce Motion, offline/cache states, and provider errors.
- Includes unit coverage for recommendation-state mapping, privacy-safe payload construction, plan rescheduling rules, and onboarding persistence.
- Includes UI previews for default, loading, empty, error, completed, and accessibility-size states.
- Does not introduce new primary navigation or a generic assistant destination.
