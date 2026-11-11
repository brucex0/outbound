# Reported running benchmarks

Open when changing current-fitness benchmark validation, estimated pace targets or the optional benchmark editor. `guidance-plans.md` continues to own goal/session limits and race-goal editing; `workout-edits.md` owns explicit workout protections.

## Contract

- Optional explicit maximal running **race or time trial**, never an ordinary activity, incidental PR segment, easy calibration or desired race time. No automatic inference or transfer from prior goals.
- `POST /v1/planning/goals` accepts optional `runningBenchmark`; it is persisted only as `goal.constraints.runningBenchmark`. The existing freeform constraints path is validated equally. Conflicting top-level/nested values fail rather than silently taking precedence.
- `PATCH /v1/planning/goals/:id/running-benchmark` accepts `{ "runningBenchmark": <object or null> }` for the active generated or catalogue running goal. `null` removes the report. This does not replace the goal or change desired race time.
- Object: `{ "activity": "run", "source": "race", "maximalEffort": true, "distanceMeters": 5000, "durationSeconds": 1500, "date": "2026-11-01" }`. Source is `race` or `timeTrial`; no user text/identifier is needed. Date is strict UTC calendar `YYYY-MM-DD`, including rollover rejection.
- Supported distance is **1,500–30,000 metres**, matching the distance range used by the cited paper. First implementation excludes marathon benchmarks. Positive integral finish seconds, speed 60–450 m/min and performance estimate 5–100 bound the numerical domain; these are product validation heuristics, not physiological certification.
- Evidence must be dated today or within the preceding **84 UTC days**. The 12-week freshness window is a conservative product heuristic. Invalid/stale/future explicit requests return HTTP 422, stable `running_benchmark_invalid`, and guidance to correct the report or remove it for effort guidance. Absent, malformed, future or stale *persisted* metadata never makes reads fatal: use RPE fallback and a safe category diagnostic.
- A correction/removal holds the planning-user lock, updates constraints and regenerates atomically. Exact edited rows, original IDs/version membership, completed/skipped history, source cursor, schedule and caps remain protected. Eligible-to-eligible corrections force refresh; each refill checks current freshness, including the eligible-to-stale transition. Future catalogue weeks remain provisional.

## Estimate and phase targets

[The published Daniels/Gilbert equations, equations 7–9](https://pmc.ncbi.nlm.nih.gov/articles/PMC9701182/) specify `t` in minutes and `v` in metres/minute:

```text
cost(v) = -4.6 + 0.182258*v + 0.000104*v²
fraction(t) = 0.8 + 0.1894393*exp(-0.012778*t) + 0.2989558*exp(-0.1932605*t)
performanceEstimate = cost(v) / fraction(t)
```

This is a **performance estimate**, not measured laboratory VO2max. We invert the cost polynomial for estimated training pace. Plainstride's oxygen-cost fraction bands are **original policy**, not claimed published/validated ranges: easy/long 0.59–0.74, threshold 0.83–0.88, aerobic intervals 0.95–1.00. Output is bounded to 120–1,500 seconds/km; out-of-domain results fall back. These fractions are not percentages of speed or maximum heart rate. [Official training definitions](https://vdoto2.com/learn-more/training-definitions) inform the distinct training purposes, not validation of these exact bands.

- Only identified main running work receives pace. Warm-up, cooldown, walking/recovery and explicit beginner run/walk retain RPE. Existing quality eligibility, hard dose and progression are unchanged by the benchmark.
- Keep step RPE and instructions. Conditions/terrain can make the estimate unsuitable; pace is optional guidance. Each derived target has `paceEstimatePolicy=reported-maximal-running-v1`; original authored/user pace is preserved. Expiry/removal clears only this policy's derived target.
- Existing absolute coaching units are reused: midpoint `targetSecondsPerKilometer` and faster/slower tolerance seconds, `athleteReferenceOffsetSeconds=0`. Phase totals, distance/calorie semantics and step execution remain unchanged.
- `goal.currentRunningFitness` returns status/source, a schema-checked report for editor prefill, and eligible estimate/ranges; malformed metadata never enters this typed report. `workout.prescription.runningFitness` identifies estimate provenance/status. Existing clients ignore unknown optional fields and retain RPE; the typed editor models add only optional report/status fields. Derived pace provenance also travels on the authoritative effective `coachingTarget.paceEstimatePolicy`; presentation never guesses target identity by matching phase shape. Desired event pace stays separate.

## Verification and pending client work

Backend compile passed. Bounded synthetic output: `/tmp/plainstride-stage4-benchmark-demo.mjs` → `/tmp/plainstride-stage4-benchmark-output.jsonl`; real route state envelopes: `/tmp/plainstride-stage4-serialized-planning.json`. These run against isolated localhost PostgreSQL on port 55449, stopped after demonstration. They cover 5k/10k/half estimates, 84-day boundary, malformed/future/stale/unconfirmed evidence, authored/derived ownership, beginner/supporting phases, target-time independence, actual route validation/create/correction/removal/expiry, catalogue cursor and edited history protection. No test suite, production data or deployment.

Client implementation checkpoint (native QA pending): optional **Recent race or time trial** management row in active running Plan Details; reusable add/correct/remove editor with date/source and explicit maximal-effort confirmation. Clearly label estimated current-fitness pace and retain RPE; no measured-VO2 or desired-goal conflation. New copy is translated in EN/ES/ZH; validation retains inputs and successful save reloads canonical state. No mandatory intake question or Android page redesign is required. Failed Save retains inputs and immediately permits correction/retry; Cancel/dismiss discards unsaved input, and Cancel is disabled while saving. Logical report dates stay stable across timezone display; new reports default to the user's local Gregorian date, while backend freshness stays UTC. Client builds and pure input/encoding demonstrations pass; native QA remains pending.

### Native QA fixtures

- Existing DEBUG running-plan entry uses the production editor. Save serializes the actual request to private `benchmark-request.json`; a synthetic fail-next-save control returns the stable validation category without network. Success/removal loads a real isolated-service canonical envelope through the production DTO converter. No production request fallback exists in either debug callback.
- Copy `/tmp/plainstride-stage4-created-fixture.json` as `planning-fixture.json`, `/tmp/plainstride-stage4-corrected-fixture.json` as `planning-benchmark-corrected.json` and `/tmp/plainstride-stage4-removed-fixture.json` as `planning-benchmark-removed.json` into simulator Documents (iOS) or app files (Android). The corrected envelope reports the synthetic 5k in 23:20. A protected explicitly edited row deliberately retains its original phases/pace after correction/removal; unprotected rows regenerate.
- Pure inputs: `/tmp/plainstride-stage4-ios-input-output.txt` and `/tmp/plainstride-stage4-android-input-output.txt` use the actual platform helpers: Pacific evening Nov11UTC defaults to local Nov10, Spanish Nov1 stays Nov1, and malformed multi-part durations are rejected. `/tmp/plainstride-stage4-android-wire-output.txt` exercises the production Retrofit JSON instance/serializers, confirming explicit null removal and required run/maximal defaults. These do not replace native keyboard/accessibility/theme and save/retry checks.
