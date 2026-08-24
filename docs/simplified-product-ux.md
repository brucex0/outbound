# Simplified Product UX Direction

Open this when changing primary navigation, Today, Together, Me, training-plan presentation, social activity cards, or the role of AI across the product.

This is the target product direction. `docs/INDEX.md` continues to describe the currently implemented app shape.

## Product Promise

Outbound should help a runner:

1. Know what to do today.
2. Complete it with clear guidance.
3. Run with or stay connected to people who matter.
4. Understand progress and what comes next.

Positioning:

> An AI running companion that learns how you train and helps you stay consistent with people who matter.

AI should be visible through useful decisions, adaptations, explanations, coordination, and reflections. It should not require a chatbot-centric UI.

## Primary Navigation

Use three primary destinations in this order:

- `Together`: people, family, private circles, clubs, compatible runs, and recent social activity.
- `Today`: the default center tab and primary action surface.
- `Me`: plan, progress, history, records, gear, and settings.

Use icon-forward tabs with accessible labels. The selected tab may show its text label; never rely on an unlabeled icon for meaning.

Do not use a separate Progress tab. Show immediate progress context on Today and post-run, with detailed progress under Me.

## Today

Keep the inspirational quote as the emotional opening. Pair it with a factual, personalized line that proves Outbound understands the runner.

### Planned workout and quick start

Keep two clear paths:

- `Start workout` launches the companion-prescribed session with its existing time, distance, and interval structure.
- `Quick start` launches freestyle run setup immediately. Open, distance, and time goals remain available on that setup screen rather than competing for space on Today.

Workout type (`easy`, `long`, `tempo`, `intervals`, or `recovery`) and recording goal (`open`, `distance`, or `time`) are separate concepts. The companion recommends the workout type; the runner may choose the recording goal.

### Personalization loop

Today participates in the learning loop defined in `docs/personalized-running-companion.md`:

- keep readiness and calibration state out of the default Today hierarchy;
- place constraint-driven changes in one self-contained sheet and preserve `Keep original`;
- explain meaningful adaptations only when the runner opens `Change` or `Why?`;
- avoid claiming a new insight until supported by observable evidence and confidence.

Information order:

1. Compact inspirational quote.
2. One concrete workout recommendation with total duration and a brief equal-weight interval preview.
3. Direct Start plus small `Change` and `Why?` actions.
4. One `Quick start` button.
5. At most one compact social opportunity.

The workout must answer:

- What am I doing?
- How hard should it feel?
- What are the phases?
- Why is this appropriate today?

Avoid multiple competing recommendation cards, generic AI chat prompts, and motivational copy that does not lead to action.

## AI Guide

Treat the guide as the intelligence connecting the experience, not necessarily as a separate destination or character-customization product.

Before a run, the guide:

- selects or adjusts the workout;
- explains why;
- responds to time, fatigue, soreness, travel, and schedule constraints;
- finds compatible people or club runs.

During a run, the guide:

- announces the current step and what comes next;
- answers concise workout questions;
- avoids repetitive stat narration.

After a run, the guide:

- gives a precise private reflection;
- updates plan and weekly progress;
- drafts, but never automatically publishes, a social recap.

Prefer structured outcomes such as shorten, move, soften, replace, explain, or coordinate over long free-form answers.

## Training Plans and Workouts

Start with a small, reviewed plan library rather than a large AI-generated catalog:

- start running / walk-to-run;
- return after a break;
- run consistently;
- first 5K;
- improve 5K;
- first 10K;
- first half marathon.

Defer marathon plans until progression and adaptation are demonstrably trustworthy.

Use recognizable workout names such as `Easy run`, `Progression run`, and `Threshold intervals`. Guide flavor belongs in supporting copy, not the workout title.

### Workout presentation

- Today preview: horizontal chained phases with widths roughly proportional to duration.
- Workout detail: vertical flow with full instructions.
- Repeated intervals: one grouped repeat block; expand only on demand.
- Live run: current step, remaining time, next step, and a compact phase rail.
- Post-run: show the same structure as completed progress.

Do not render every backend step with equal prominence. Group steps by the runner's mental model: phase, repeat block, and current interval.

### Camera moments

Treat the camera as optional `Moment` capture, not the default live-run surface.

- Keep map, workout phase, current guidance, Pause, and Finish primary.
- Place a small camera action over the map or in the stats toolbar.
- Open the camera only after an explicit tap; do not run a persistent preview.
- Continue activity recording while the focused capture surface is open.
- Attach elapsed time, workout phase, and private location metadata to the moment.
- Return to the live workout immediately after Keep or Retake.
- During a hard interval or unsafe movement, ask the runner to wait for recovery, slow down, or pause before capturing.
- Never stream camera content through live location sharing.

After the run, let the user keep a moment private or approve it for the social recap. Prefer a user-selected moment as the activity-card hero; fall back to the route map, then clean stats for indoor activities.

AI may draft a caption from the workout and an optional user note. Do not analyze image contents without explicit opt-in, and never publish automatically.

V1 supports front/rear still photos, Retake, Keep, and post-run sharing choice. Defer continuous video, automatic capture, filters, live camera streaming, and public posting during a run.

### Adaptation

Keep early adaptation narrow and explain every material change:

- skip a missed easy run rather than forcing catch-up;
- move a key session only when recovery spacing remains safe;
- reduce the next week after several missed runs;
- replace intensity when fatigue or soreness is reported;
- rearrange the week around real availability or a compatible club run.

## Together

`Together` is the destination. It includes:

- people, including spouse, family, friends, and running partners;
- circles for small private groups;
- clubs for organized communities such as Seattle United Runners;
- group runs and one-to-one run invitations;
- recent social activity.

Do not use `Crew` as a primary product term.

AI should connect personal training with social opportunity:

- identify compatible workouts and availability;
- match a planned workout to a club pace or distance group;
- adapt two workouts so people can share a start, route, and finish;
- rearrange a week safely around a chosen group run;
- preserve private reasons such as fatigue, injury, or missed training.

### Social activity cards

A featured recent card should include:

1. Person and recency.
2. Activity title.
3. Photo or route preview.
4. Up to three useful stats.
5. One factual AI highlight.
6. Cheer and comment actions.

Use precise highlights such as `First run back after two weeks` or `Fastest final kilometer this month`. Avoid generic praise.

Show one rich featured card followed by compact rows to prevent the feed from becoming visually heavy.

## Me

Me answers `How am I doing?`

Prioritize:

1. Current focus and plan week.
2. This week's adherence and totals.
3. One precise guide observation.
4. Four-week trend.
5. Recent activity.
6. History, personal records, predictions, and gear.

Recent activity in Me is training-oriented rather than social: workout completion, core stats, route when useful, and one precise training insight.

Keep settings behind a gear button so account and preference controls do not compete with progress.

## Core Flow

The primary loop is:

`Inspiration -> AI recommendation -> Workout detail -> Guided run -> Reflection/share -> Progress`

Together intersects before the run through coordination and after the run through approved sharing.

The clickable reference is `docs/prototypes/outbound-major-flow.html`.

## Scope Discipline

Deprioritize until the core loop is excellent:

- a generic assistant destination;
- prominent guide-face customization;
- a generic public social feed;
- badges and broad reward systems;
- broad multi-sport positioning;
- AI-generated plans without reviewed progression rules;
- multiple overlapping home recommendations.
