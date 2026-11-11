# Synthetic running-plan quality evaluation

Open to generate and inspect reproducible synthetic plans, compare revisions, or run an explicitly limited AI judging pilot. This is a local evaluation tool, not the app's test suite or a clinical safety certification.

## Reproduce offline

Build both actual checkouts; do not simulate the baseline with candidate flags. Then run from `backend/`:

```sh
npm run build
node dist/scripts/evaluateRunningPlans.js \
  --baseline-dist /absolute/baseline/backend/dist \
  --output /tmp/plainstride-planning-quality \
  --count 200 --supplement-count 36 --seed plainstride-running-2026-11-v1 \
  --now 2026-11-16T00:00:00.000Z --ai-limit 0
```

The candidate defaults to this build's `dist`; `--candidate-dist` can select another actual checkout. Manifest records source commits, tracked-diff status, seed, frozen UTC day, scenario/rubric versions and explicit assumptions. Use clean committed source for a final comparison. Bulk outputs stay outside Git.

## Scenario and evidence contract

- Original200 immutable versioned inputs (admission is evaluated separately): ten cohorts (new, returning, recreational, established, half/marathon experience and unknown history), goals, finish/perform intent, realistic preparation windows, one–six requested days where appropriate, 15–120-minute caps with explicit short-session opt-in, adherence, recent gaps and readiness.
- Histories are synthetic activity rows; each revision computes its own state through its real `computeAthleteTrainingState`. Unknown sensors are not negative evidence. Synthetic target times do not establish measured current fitness.
- Catalogue cases exercise actual source instantiation and rebuilding. A small six-episode self-fed rollout assumes completion of actual issued prescriptions except one missed episode; cumulative synthetic activities/completions pass through each engine’s actual state computation. No low-fatigue result or physiological improvement is assumed. These are declared simulations, not observed runner adaptation.
- Event goals include selected midpoint and taper checkpoint windows under an explicitly stable baseline assumption. Ordinary output is next 14 days, not a fully validated long-term programme. Do not judge longitudinal progression from a single window.
- Five separate feasibility guards cover confirmed new-runner marathon in four weeks, experienced/unknown alternatives and a later target. Expected ineligible inputs do not generate full plans or enter quality scores. The narrow gate helper is evaluated here; route enforcement and localized UI must be verified separately before claiming product enforcement.

## Deterministic findings

Rules inspect actual emitted rows independently of planner limit helpers. Exact workout/window IDs and observed values accompany every finding.

- Errors: phase/block sum mismatch, non-positive timed phases, cap breach, past/duplicate required slots, wrong requested day/frequency, beginner hard work or absent executable walking, active-pain near-term quality, lost catalogue source, and desired goal pace used as measured current fitness.
- Review warnings: possible repeat double-expansion, quality/long recovery spacing, weekly quality over 20% of baseline running time, and weekly volume over 140% of baseline. These thresholds are versioned product review heuristics; they do not identify an individual's injury risk or imply the percentages are scientifically optimal.
- Recovery substitutions are exempt from promised-run-count checks when fresh adverse readiness is present. Sparse volume does not create an invented volume baseline. Missing sensor data alone does not fail a scenario.
- Expected capacity/programme constraint rejections are separate admission outcomes. Unexpected generation exceptions are explicit hard findings; they are not silently omitted. Initial admission never changes because a later checkpoint rejects; successful earlier windows/findings remain, and each checkpoint has its own outcome/code. Hard errors cannot be overridden by an AI score.

## Limited AI pilot

AI is off by default. To explicitly judge up to 20 stratified pairs (plus three reversed-order repetitions):

```sh
node dist/scripts/evaluateRunningPlans.js \
  --baseline-dist /absolute/baseline/backend/dist \
  --output /tmp/plainstride-planning-quality \
  --ai-limit 20 --repeat 3 --concurrency 2 \
  --model gemini-3.8-flash --project outbound-494602 --location global \
  --timeout-ms 60000
```

- Calls use the Google SDK directly with local ADC and synthetic input only, not the production planning route or its AI operation/analytics. No credentials are printed or persisted. Project/model are explicit options, not inferred production credentials.
- Sampling rotates across admitted cohorts and prioritizes additional goals, preparation lengths, frequencies and caps. It is not the first 20 nested-loop rows. Structurally flawed plans may receive diagnostic criticism; their hard-failure status remains authoritative and is included in results.
- Judge receives anonymous A/B outputs in seeded randomized order, with no revision/policy version labels. Input, actual phase rows, checkpoint assumptions and valid evaluation IDs are included. Raw private runner data is never used.
- Anchored 0–4 criteria: goal fit 25%, progression 25%, workout dose 20%, weekly balance 20%, clarity 10%. Code computes weighted scores. Unassessable criteria remain null; assessed-weight coverage is reported. Do not treat missing AI output as zero.
- Strict JSON/schema validation rejects invalid ratings, unknown fields and fabricated criticism references. Each call has a deadline, at most two attempts and concurrency at most three. Cache key includes full input/prompt, source identities, rubric version, model and repeat identity; reruns resume validated cached responses without mixing revisions.
- Three pairs reverse A/B order in separate calls. Report per-case score deltas; this small pilot checks gross instability/order sensitivity, not universal reliability. Provider/timeout/schema failures remain visible and unscored.

## Outputs and interpretation

`manifest.json` records reproducibility; `plans.json` retains actual inputs and both revisions' outputs/findings; `rollouts.json` and `eligibility-guards.json` retain focused demonstrations. `ai-results.json` and `judge-cache/` retain validated judgments, failures and cache identity. `report.json`/`report.md` summarize hard-failed cases, rule counts, per-cohort median/p10, judged/unscored/failure coverage, reversed-order differences and worst cases.

Use findings to guide the remaining implementation stages. Better synthetic scores or fewer rule violations do not establish better real-world race outcomes, personalized safety or medical validity. Final comparisons must name the exact committed revisions, evidence coverage and unresolved defects.

### Judge calibration v2

Holding duration, a run/walk ratio or a source week is not itself a defect when completion/readiness evidence remains unchanged or unknown. The v2 rubric distinguishes actual adaptive progression from calendar taper snapshots and forbids demanding invented fitness improvement. Cached v2 responses have a separate prompt/rubric identity. Provider status, attempt count, normalized failure category and available input/output/total/thinking token usage are retained; raw provider error bodies are excluded. Cached reuse reports zero new attempts while retaining the original response's usage for audit.

### Scenario matrix v2

Historical prescribed rows now share actual synthetic activity dates/durations; omitted sessions are skipped/missed without a corresponding activity. Zero-history cohorts have zero prior prescribed completions and explicitly unknown adherence evidence. Returning-established has a dated 14-day break with four coherent active weeks before it, rather than four uninterrupted recent weeks. Scenario IDs/cohorts and the returning catalogue failure remain visible; versioned inputs/cache keys prevent mixing the old and corrected matrix.

### Service-orchestration coverage

The original200 plus separately reported supplement batch exercises compiled generator/adaptation functions, not authenticated HTTP routing, transactional creation or client request composition. Smaller isolated local-Postgres demonstrations exercise real `createGoal`, catalogue resolution/refill, edited-row preservation and `decideAdjustment`.

Observed normal generation stored two requested days/week and a 30-minute cap, emitted four required sessions and never exceeded 1,800 seconds. Real catalogue activation recommended four days/65 minutes but preserved an explicit accepted three-day/30-minute request, retained template identity, and never exceeded 1,800 seconds. That historical pre-Stage5 revision rejected a source-incompatible one-day request. Current running C25K accepts lower frequency by carrying distinct pending source exposures across extended calendar weeks; it rejects an explicitly impossible deadline and never claims the nominal source duration is the calendar completion date. Resolving a selected marathon with omitted request distance still triggered the confirmed-novice short-timeline guard and created zero plans. These local demonstrations do not establish deployed/authenticated integration.

Checker v2 independently filters the synthetic running baseline to the frozen inclusive28-day window before dividing by four. Checkpoint comparisons shift each activity date by the declared stable-history checkpoint offset before applying the same independent window arithmetic; older pre-break history is not accidentally counted as current load.

### Judge calibration v3 and interpretation

Same-date rebuilds with unchanged evidence should be stable/idempotent. Windows are alternative snapshots, not additive schedules; v3 explicitly states both relationships in the rubric/input. Scores for A/B use only their common assessed-criterion mask, retaining each plan's own coverage for audit. Median and p10 use conventional linear interpolation at `(n−1)×q` (Type7), so a two-score median is their average; sample counts remain visible.

The earlier pinned v2 pilot remains immutable. It completed22/23 calls (19/20 primary pairs plus three reversed-order repeats), and one failed schema response stayed unscored. A reversed-order repeat moved a candidate score by21.7points. Thus preference/score results remain advisory; do not silently retrofit the old report's quantiles or treat this small pilot as reliable model validation. Final-stage scoring should use the corrected version and disclose coverage/variance.

Final-pass judging also sends the strict response JSON schema to the provider. Schema/generation configuration is part of cache identity. Safe diagnostics retain bounded schema paths/codes, attempt number, normalized category and numeric HTTP status when available; no response/error body is logged. The completed v2 pilot remains unchanged.

The fifth eligibility guard verifies that a non-event running goal carrying an aggregate distance/date is not classified as a marathon race. The narrow timeline gate applies only to explicit event/marathon intent.

## Final-pass evaluator v3 / checker v4

- The original200 matrix inputs/IDs remain unchanged. The separate versioned36-input orthogonal supplement crosses one/three/six days against15/60-minute caps across low-volume cohorts, plus viable no-date/long-horizon source cases and mixed run/walk schedules. `--supplement-count 0` reproduces only the original matrix; `supplement-inputs.json` records the addition separately.
- Admission is initial `generated`, expected `rejected` or unexpected `failed`, per engine and original/supplement/all groups. Reports also show the common initially-generated paired denominator and hard failures within it. A rejected input is never a zero-error generated plan; AI compares only genuinely generated pairs, while hard-failing baseline plans remain eligible for diagnostic AI review.
- Later midpoint/taper or same-day rebuild outcomes are explicit, preserving the initial plan and its findings. Stable-history catalogue checkpoints may legitimately reject a deadline after no earned source advancement. Anonymous judge payloads include bounded programme status, review reason/action, nullable conditional calendar estimate, earned stage/completion/provisional state and checkpoint outcomes. Policy/revision identifiers and private engine data are excluded.
- Independent actual-phase quality checks include literal `fartlek` and `racePrep`, regardless of the workout’s top-level stimulus. Derived pace verification requires fresh explicit maximal benchmark input plus matching current `runningFitness` and phase provenance; desired-goal pace metadata alone is insufficient.
- Preliminary offline236-input observation (dirty development build, not final frozen provenance): baseline generated236; candidate generated213/rejected23/failed0; common-generated213. Original group candidate181/19/0, supplement32/4/0. Common-generated hard-failed cases were baseline80/candidate0; candidate still has42 volume-review warnings, including starter floors/re-entry references exceeding the checker’s advisory140% history threshold. Zero hard findings is not a safety or quality certification. Clean committed-source outputs must be regenerated for the final report; no AI was called in this preliminary pass.
- Evidence: `/tmp/plainstride-evaluation-v3-preliminary/{manifest,plans,report,rollouts,supplement-inputs}.json`; build `/tmp/plainstride-evaluator-v3-build.log`. Historical pilot outputs remain unchanged.
