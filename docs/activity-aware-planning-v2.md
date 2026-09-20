# Activity-Aware Planning v2

## Purpose

The planner must respond to what the runner actually did, not only replay the workout that was generated when the plan was created. A user who runs 10 km on four consecutive days should not continue receiving a generic 20-minute walk-run prescription without an explicit recovery or progression explanation.

## Decision Contract

Every Today recommendation has two layers:

1. **Plan fit** — a deterministic assessment of recent load, running streak, observed running capacity, readiness, and the scheduled workout.
2. **Recommendation** — the safe next action selected from the active plan or the reviewed adaptive archetype library.

The activity suggestion response remains the client contract. Its `why` and `decision.reasons` fields must cite the evidence used for the decision.

## Plan-fit signals

The current implementation computes these additional rolling signals:

- run sessions in the last 3 days;
- run sessions and running distance in the last 7 days;
- consecutive active days;
- recent run distance compared with the four-week weekly distance baseline;
- observed average duration of recent runs;
- whether a recent run streak is a recovery concern;
- whether an active plan's short walk-run prescription is stale compared with observed running.

These are intentionally deterministic and inspectable. AI is not allowed to invent load, override pain/illness safeguards, or author an unconstrained workout.

## Current decision policy

- Pain or illness remains the highest-priority safety override.
- A completed activity today suppresses another primary workout and returns optional recovery.
- Three or more consecutive active days, or a material recent running-load spike, makes the next planned workout recovery-biased.
- A stale walk-run prescription is replaced by an easy aerobic run when the runner has demonstrated repeated, sufficiently long recent runs and there is no elevated fatigue signal.
- Otherwise, the active planned workout remains the primary recommendation.
- The recommendation includes the exact recent minutes, distance, run streak, baseline comparison, and fatigue state where available.

This is a near-term recommendation policy. It does not silently change the user's multi-week plan. Material multi-day changes remain adjustment proposals requiring confirmation.

## AI boundary

The deterministic planner owns:

- activity aggregation;
- readiness and safety classification;
- plan-fit classification;
- candidate safety limits;
- workout construction;
- database mutations.

Gemini may rank a bounded near-term candidate (`maintain`, `recover`, `reduce`, or eligible `progress`) and write a concise evidence-based explanation. It receives aggregate athlete state, upcoming workouts, completion quality, and feedback. Its strict JSON output is validated before use.

The in-app companion model may explain an already validated proposal and handle conversational requests. It must not claim that a plan changed until the action executor confirms it.

## Client experience contract

After an activity is saved, Today should refresh the suggestion and present one of these states:

- **Plan still fits:** show the next workout and the evidence supporting it.
- **Recovery recommended:** explain the recent streak/load and offer rest or recovery as the primary action.
- **Adjustment proposed:** show before/after workouts, why the change is needed, and `Apply adjustment` / `Keep original`.
- **Need readiness:** ask a targeted question when the load is unusual but current physical state is unknown.

The client should render the backend `why`, `guideLine`, `decision.reasons`, and `decision.safetyFlags`; it should not recreate planner logic locally except for a clearly labelled offline cache fallback.

## Example

For four 10 km runs in four days, the backend should expose evidence similar to:

```text
You have run 40.0 km across the last 4 days. That is 4 consecutive running days and above your recent weekly distance baseline. Recovery is the useful next step, so today's planned run has been softened rather than adding another progression session.
```

If the runner has normal readiness and the scheduled workout is an obsolete 25-minute walk-run, the recommendation can instead say:

```text
Your recent running shows a stable aerobic baseline: 3 runs in the last 14 days, with an average run longer than this walk-run prescription. I am using an easy continuous run today, while keeping intensity conversational.
```

## Verification scenarios

1. Four consecutive 10 km runs produce a recovery-biased next recommendation and cite distance plus streak.
2. A same-day completed activity produces optional recovery, not a duplicate primary workout.
3. A returning runner with no meaningful recent run evidence still receives walk-run return guidance.
4. A stale walk-run plan is not used after repeated demonstrated running unless fatigue/readiness requires recovery.
5. Pain or illness prevents progression and returns the safety path.
6. A normal, stable active-plan runner still receives the planned workout with a plan-specific explanation.
7. Gemini failure or unavailable capability leaves deterministic behavior intact.

## Replanning and confirmation flow

Activity completion always recomputes athlete state and runs the plan-fit assessment. A same-day recommendation can change immediately without changing the multi-week plan. A material multi-workout change is persisted as a `PersonalizationAdjustment` proposal with the evidence explanation and requires confirmation.

For activity-driven load changes, the planner now reassesses instead of silently creating a new plan version. The client refreshes the pending adjustment after activity sync and presents the existing confirmation sheet proactively. The sheet shows before/after workout titles and offers `Apply update` or `Keep original plan`. Pain/illness and explicit low-readiness safety adaptations remain automatic conservative paths; user confirmation is retained for non-emergency multi-workout load changes.

The Gemini evaluator now receives:

- deterministic athlete state, including run streak and recent run distance;
- a bounded plan-fit assessment;
- the latest twelve activity summaries with date, modality, duration, distance, pace, and heart rate;
- upcoming workouts;
- completion ratios, perceived effort, and feedback counts.

Gemini can only select the validated near-term candidates and cannot directly mutate plans. Missing credentials, timeout, invalid JSON, or disabled capability falls back to the deterministic policy.

## Health and physical-state behavior

Readiness and health remain higher priority than progression:

- pain or illness returns the rest path;
- low energy, high soreness, or high stress softens hard planned work;
- high acute load or four consecutive active days creates recovery-biased recommendations;
- stale short walk-run prescriptions are replaced by continuous easy running only when repeated recent running supports it and safety signals are normal.

The stored `AthleteTrainingState` now persists the rolling run-session, run-distance, and active-day signals so the decision can be audited after the request has completed.
