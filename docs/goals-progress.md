# Goals And Progress

Open this when designing or building goal setting, weekly progress, milestones, or coach-led planning.

## Product Goal

Make progress feel like part of the coach relationship, not a separate analytics dashboard.

The user should feel like the coach is helping them choose a realistic focus, track it gently, and turn it into today's next step.

## Positioning

Use `focus` as the main user-facing language.

Why:
- it sounds more human than `goal`
- it matches the app's motivation-first tone
- it lets the coach frame progress softly on comeback days and more directly on momentum weeks

Use `goal` as the structured internal concept that powers progress logic.

Example mapping:
- user sees: `This week's focus`
- app tracks: `3 sessions this week`

## UX Principles

- Think conversation, not configuration.
- Bias toward realistic weekly commitments over ambitious targets.
- Short sessions count.
- Missed days should lead to re-entry, not failure language.
- Progress should appear inside the Today loop before it grows into a separate progress surface.
- Adjusting a goal should feel easy and stigma-free.

## V1 Scope

Ship:
- one active weekly goal at a time
- coach-led setup inside Today
- local-first persistence
- progress derived from saved activities
- goal-aware Today copy and post-run reflection

Defer:
- race-date plans
- pace targets
- multiple simultaneous goals
- heavy charts
- backend sync as a requirement
- open-ended natural-language parsing

## Current Implementation

Implemented in the app:

- one active weekly focus at a time
- `weeklySessions` and `weeklyMinutes`
- coach-led setup in Today with reply-chip cards
- progress card and progress chip on Today
- post-run reflection note that references goal progress

Still deferred:

- race-date goals
- multiple simultaneous goals
- backend sync
- natural-language goal entry

## Recommended Goal Types

Start with only a few structured goal types:

- `weeklySessions`
- `weeklyMinutes`
- `comebackSessions`

Recommended defaults:
- first-session or comeback users: 2 sessions this week
- steady users: 3 sessions this week
- momentum users: 3 sessions or a light minutes target, depending on final product feel

Do not auto-suggest targets that exceed the user's recent pattern unless they explicitly choose a harder goal.

## Conversation Model

The setup flow should feel like a coach-thread card stack with reply chips, not a generic form and not a full chatbot.

Suggested flow:

1. Coach offers help at the right moment.
2. User picks a direction from chips.
3. Coach proposes a realistic target.
4. User confirms, eases, or changes it.
5. Today immediately starts reflecting the new goal.

Example:

```text
Coach:
Want a focus for this week?

[ Build consistency ] [ Get back into rhythm ] [ Move by time ] [ Not now ]
```

```text
Coach:
What feels realistic right now?

[ 2 sessions ] [ 3 sessions ] [ 4 sessions ] [ Help me choose ]
```

```text
Coach:
Let's keep it simple: 3 sessions this week. Short ones count. Lock that in?

[ Lock it in ] [ Make it easier ] [ Change it ]
```

## Best Trigger Moments

- no active goal and at least one saved activity
- comeback phase
- momentum phase
- post-run save flow when the user has no active goal

Avoid interrupting the user with setup during a live activity.

## Surface Placement

Primary surface:
- Today, between the spark and suggestion layers

Recommended Today order:
1. spark
2. focus / goal conversation card
3. readiness
4. suggested actions
5. momentum
6. recent activity

Secondary surfaces:
- post-run reflection card
- future coach tab if coaching gets promoted out of Me

Do not start with a standalone progress dashboard.

## Progress Surfaces

Progress should show up as lightweight, emotionally framed context:

- spark copy: `Two sessions this week would get you back into rhythm`
- Today focus card: `1 of 3 sessions this week`
- momentum chip: `15 min left on your weekly focus`
- post-run reflection: `That moved you to 2 of 3 this week`

Avoid streak-heavy or guilt-heavy framing such as:
- `behind goal`
- `missed target`
- `failed week`

## Local Architecture

Recommended files:

- `Goals/GoalModels.swift`
- `Goals/GoalStore.swift`
- `Goals/GoalProgressEngine.swift`
- optional `Goals/GoalConversationCard.swift`

Recommended store responsibilities:

- persist one active goal locally
- persist lightweight conversation state locally
- compute progress from `ActivityStore.activities`
- expose goal-aware Today state

Recommended app integration:

- create `GoalStore` in `App/OutboundApp.swift`
- inject it into `MainTabView`
- refresh progress when Today appears and after activities save

## Suggested Models

Suggested core model split:

- `GoalDefinition`: structured active goal
- `GoalDraft`: in-progress proposal during the conversation
- `GoalConversationState`: current setup step plus dismissal state
- `GoalProgressSnapshot`: computed progress view model

V1 should allow only one active goal at a time.

## Post-Run Reflection

Extend the finish reflection model with an optional progress note.

Examples:
- `That moved you to 2 of 3 sessions this week.`
- `You completed this week's focus.`
- `15 more minutes would finish your weekly target.`

This is one of the strongest places to reinforce progress because it connects effort to meaning rather than just showing a stat.

## Copy Guidance

Prefer:
- `focus`
- `simple`
- `doable`
- `short sessions count`
- `want to lock that in?`

Avoid:
- `target configuration`
- `goal failed`
- `you are behind`
- `increase difficulty`
