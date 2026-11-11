/** Local synthetic evaluation: no database, user records or production API. */
import { mkdirSync, writeFileSync, readFileSync } from "node:fs";
import { resolve, join, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { scenarios, orthogonalSupplement, SUPPLEMENT_VERSION, seeded, addDays, SCENARIO_VERSION, type Scenario } from "./planningQuality/scenarios.js";
import { CHECKS_VERSION, inspectWindow, type EvaluatedWindow, type Finding } from "./planningQuality/checks.js";
import { judge, score, RUBRIC_VERSION } from "./planningQuality/judge.js";
import { assessGoalFeasibility, GOAL_FEASIBILITY_POLICY } from "../services/planning/goalFeasibility.js";
process.env.TZ = "UTC";
const args = new Map<string, string>();
for (let index = 2; index < process.argv.length; index += 2) {
  if (!process.argv[index]?.startsWith("--") || process.argv[index + 1] == null) throw new Error("Use --name value arguments; see docs/running-plan-quality.md.");
  args.set(process.argv[index].slice(2), process.argv[index + 1]);
}
const number = (key: string, fallback: number, maximum: number) => { const value = Number(args.get(key) ?? fallback); if (!Number.isInteger(value) || value < 0 || value > maximum) throw new Error(`Invalid ${key}.`); return value; };
const count = number("count", 200, 2000); if (!count) throw new Error("count must be positive.");
const seed = args.get("seed") ?? "plainstride-running-2026-11-v1";
const clock = new Date(args.get("now") ?? "2026-11-16T00:00:00.000Z");
if (!Number.isFinite(clock.getTime()) || clock.toISOString().slice(11) !== "00:00:00.000Z") throw new Error("now must be UTC midnight.");
const baselineDist = args.get("baseline-dist"); if (!baselineDist) throw new Error("--baseline-dist must point to the compiled baseline checkout.");
const candidateDist = resolve(args.get("candidate-dist") ?? dirname(dirname(fileURLToPath(import.meta.url))));
const out = resolve(args.get("output") ?? "/tmp/plainstride-planning-quality"); mkdirSync(out, { recursive: true });
const aiLimit = number("ai-limit", 0, count), repeats = number("repeat", 3, 20), concurrency = Math.max(1, number("concurrency", 2, 3));
const model = args.get("model") ?? "gemini-3.8-flash", project = args.get("project") ?? "outbound-494602", location = args.get("location") ?? "global";
const timeoutMs = Math.max(1000, number("timeout-ms", 60_000, 120_000));
const save = (name: string, value: unknown) => writeFileSync(join(out, name), JSON.stringify(value, null, 2));
function revision(dist: string) { const root = resolve(dist, "../.."); const git = (commands: string[]) => execFileSync("git", ["-C", root, ...commands], { encoding: "utf8" }).trim(); return { commit: git(["rev-parse", "HEAD"]), dirty: git(["status", "--porcelain", "--untracked-files=no"]) !== "" }; }
async function engine(dist: string) {
  const load = (file: string) => import(pathToFileURL(join(resolve(dist), "services", file + ".js")).href);
  const [generator, athlete, adaptation, templates, catalogue] = await Promise.all([load("planning/generator"), load("planning/athleteState"), load("planning/adaptationEngine"), load("trainingPlans"), load("planning/catalogTemplate")]);
  let programme: any = null;
  try { programme = await load("planning/catalogProgramme"); } catch (error) { if ((error as NodeJS.ErrnoException).code !== "ERR_MODULE_NOT_FOUND") throw error; }
  return { generator, athlete, adaptation, templates, catalogue, programme };
}
const [baseline, candidate] = await Promise.all([engine(baselineDist), engine(candidateDist)]);
const baselineRevision = revision(baselineDist), candidateRevision = revision(candidateDist), original = scenarios(count, seed, clock);
const supplementCount = number("supplement-count", count >= 200 ? 36 : 0, 36);
const supplement = orthogonalSupplement(original, supplementCount), cases = [...original, ...supplement];
const groupFor = (scenario: Scenario) => scenario.id.startsWith("supp-") ? "supplement" : "original";
function windowFor(engine: any, scenario: Scenario, now: Date, id: string, rebuild = false): EvaluatedWindow {
  const shift = now.getTime() - scenario.now.getTime();
  const activities = scenario.activities.map((item) => ({ ...item, startedAt: new Date(item.startedAt.getTime() + shift) }));
  const planned = scenario.planned.map((item) => ({ ...item, scheduledDate: new Date(item.scheduledDate.getTime() + shift) }));
  const readiness = scenario.readiness.map((item) => ({ ...item, date: now }));
  const state = engine.athlete.computeAthleteTrainingState({ activities, plannedWorkouts: planned, readiness, now });
  const goal = engine.generator.normalizeGoalInput(scenario.goal);
  let generation: any;
  if (scenario.catalogue) {
    const template = engine.templates.fallbackTrainingPlanCatalog.templateLookup.get(scenario.goal.constraints?.templateID);
    generation = engine.programme ? engine.programme.generateCatalogWindow({ template, goal, now, createdAt: scenario.now, evidence: [], readyToAdvance: false, explicitDifficulty: false, athleteState: state })
      : { phase: "base", workouts: engine.catalogue.instantiateCatalogRecommendation({ template }, now), summary: template.summary, engineDecision: {} };
  } else generation = engine.generator.generateInitialPlan({ goal, athleteState: state, now, reason: "syntheticEvaluation" });
  const eventType = scenario.readiness.some((item) => item.illnessOrPain) ? "painFlagged" : scenario.readiness.some((item) => item.energy <= 2 || item.soreness >= 4) ? "readinessSubmitted" : rebuild ? "manualRebuild" : null;
  if (eventType) generation = engine.adaptation.adaptPlan({ goal, athleteState: state, latestReadiness: readiness[0], now, eventType, basePlan: generation });
  return { id, now: now.toISOString(), phase: generation.phase ?? generation.engineDecision?.phase ?? "unknown", programme: programmeNotice(generation.engineDecision), workouts: generation.workouts.map((item: any, index: number) => ({ ...item, evaluationId: `${id}-workout-${index + 1}` })) };
}
/** Anonymous user-visible progress, excluding source IDs/policy revisions/private engine state. */
function programmeNotice(decision: any): Record<string, unknown> | undefined {
  if (!decision?.programme && !decision?.runWalkProgramme) return undefined;
  return {
    sourceWeek: typeof decision.programme?.weekIndex === "number" ? decision.programme.weekIndex : null,
    sourceStatus: decision.programme?.status ?? null,
    completedSourceWorkouts: decision.completedSourceWorkouts ?? null,
    preparationOnly: decision.preparationOnly === true,
    nominalSourceWeeks: decision.nominalSourceWeeks ?? null,
    minimumRemainingCalendarWeeks: decision.minimumRemainingCalendarWeeks ?? null,
    calendarEstimateCondition: decision.minimumCalendarEstimateCondition ?? null,
    timelineStatus: decision.programmeTimelineStatus ?? null,
    doseStatus: decision.programmeDoseStatus ?? null,
    reviewReason: decision.programmeReviewReason ?? null,
    reviewAction: decision.programmeReviewAction ?? null,
    futureWeeksProvisional: decision.futureWeeksProvisional === true,
    runWalkStage: decision.runWalkProgramme?.stageIndex ?? null,
    runWalkStatus: decision.runWalkProgramme?.status ?? null,
  };
}
type Admission = "generated" | "rejected" | "failed";
interface CheckpointOutcome { id: string; now: string; outcome: Admission; code?: string; }
interface Output { admission: Admission; admissionCode?: string; windows: EvaluatedWindow[]; checkpointOutcomes: CheckpointOutcome[]; findings: Finding[]; generationFailure?: string; }
const expectedRejections = new Set(["running_schedule_conflict", "programme_timeline_conflict", "programme_constraints_conflict"]);
function outputFor(engine: any, scenario: Scenario): Output {
  const output: Output = { admission: "generated", windows: [], checkpointOutcomes: [], findings: [] };
  const checkpoints: [string, Date, boolean][] = [["initial", scenario.now, false]];
  if (scenario.catalogue) checkpoints.push(["rebuild", scenario.now, true]);
  if (scenario.goal.type === "eventPreparation" && scenario.horizonWeeks >= 8 && !scenario.readiness.some((item) => item.illnessOrPain || item.energy <= 2 || item.soreness >= 4)) {
    checkpoints.push(["midpoint", addDays(scenario.now, Math.floor(scenario.horizonWeeks / 2) * 7), false],
      ["taper_checkpoint", addDays(scenario.now, Math.max(0, scenario.horizonWeeks - 2) * 7), false]);
  }
  for (const [id, now, rebuild] of checkpoints) {
    try {
      const window = windowFor(engine, scenario, now, id, rebuild);
      output.windows.push(window);
      output.findings.push(...inspectWindow(scenario, window));
      output.checkpointOutcomes.push({ id, now: now.toISOString(), outcome: "generated" });
    } catch (error) {
      const code = (error as { code?: string }).code;
      const expected = code != null && expectedRejections.has(code);
      output.checkpointOutcomes.push({ id, now: now.toISOString(), outcome: expected ? "rejected" : "failed", code: expected ? code : "generation_failed" });
      if (!expected) output.findings.push({ rule: "GENERATION_FAILED", severity: "error", workoutIds: [], evidence: `${id} generation failed with ${error instanceof Error ? error.name : "unknown"}; inspect synthetic input.` });
      if (id === "initial") {
        output.admission = expected ? "rejected" : "failed";
        if (expected) output.admissionCode = code;
        else output.generationFailure = error instanceof Error ? error.name : "unknown";
        break;
      }
    }
  }
  return output;
}
const outputs = cases.map((scenario) => ({ scenario, dataset: groupFor(scenario), baseline: outputFor(baseline, scenario), candidate: outputFor(candidate, scenario) }));
function rollout(engine: any) {
  const scenario = original.find((item) => item.catalogue)!;
  const goal = engine.generator.normalizeGoalInput(scenario.goal), template = engine.templates.fallbackTrainingPlanCatalog.templateLookup.get(scenario.goal.constraints?.templateID);
  let decision: any; const episodes: any[] = [], evidence: any[] = [], activities: any[] = [...scenario.activities];
  for (let episode = 0; episode < 6; episode++) {
    const now = addDays(clock, episode * 7);
    const state = engine.athlete.computeAthleteTrainingState({ activities, plannedWorkouts: evidence, readiness: [], now });
    if (!engine.programme) { const workouts = engine.catalogue.instantiateCatalogRecommendation({ template }, now); episodes.push({ episode, sourceWeekIndices: [...new Set(workouts.map((workout: any) => workout.prescription.weekIndex))], outcome: "calendar_instantiation_no_cursor" }); continue; }
    let generation: any;
    try { generation = engine.programme.generateCatalogWindow({ template, goal, now, createdAt: clock, priorDecision: decision,
      evidence, readyToAdvance: state.fatigueRisk === "low", explicitDifficulty: false, athleteState: state }); }
    catch (error) { const code = (error as { code?: string }).code; episodes.push({ episode, admission: code != null && expectedRejections.has(code) ? "rejected" : "failed", code: code != null && expectedRejections.has(code) ? code : "generation_failed" }); break; }
    decision = generation.engineDecision;
    episodes.push({ episode, programme: decision.programme, outcome: decision.programmeOutcome, fatigue: state.fatigueRisk, workouts: generation.workouts });
    for (const [index, row] of generation.workouts.filter((workout: any) => workout.scheduledDate < addDays(now, 7)).entries()) {
      const completedAt = new Date(new Date(row.scheduledDate).getTime() + 3600000), id = `rollout-${episode}-${index}`;
      evidence.push({ ...row, id, status: episode === 3 ? "skipped" : "completed", edits: [],
        completions: episode === 3 ? [] : [{ completedAt, durationSeconds: row.durationSeconds, completionQuality: "completed", perceivedEffort: null }] });
      if (episode !== 3) activities.push({ id: `activity-${id}`, type: "run", startedAt: completedAt, durationSecs: row.durationSeconds,
        distanceM: null, avgPace: null, avgHeartRate: null });
    }
  }
  return { assumptions: "Synthetic issued prescriptions completed except episode3; actual computed state from cumulative synthetic duration/adherence, no ratings or physiological improvement invented.", episodes };
}
const rollouts = count >= 20 ? { baseline: rollout(baseline), candidate: rollout(candidate) } : null;
const guards = [
  { type: "eventPreparation", name: "new_marathon_4_weeks", baselineContext: "startingOut", days: 28, expected: false },
  { type: "eventPreparation", name: "experienced_marathon_4_weeks", baselineContext: "currentlyActive", days: 28, expected: true },
  { type: "eventPreparation", name: "unknown_marathon_4_weeks", baselineContext: undefined, days: 28, expected: true },
  { type: "eventPreparation", name: "new_marathon_later_no_safety_promise", baselineContext: "startingOut", days: 140, expected: true },
  { type: "endurance", name: "non_event_running_distance", baselineContext: "startingOut", days: 28, expected: true },
].map((guard) => ({ ...guard, result: assessGoalFeasibility({ type: guard.type, activities: ["run"], baselineContext: guard.baselineContext, targetDistanceMeters: 42_195, targetDate: addDays(clock, guard.days) }, clock) }));
const manifest = { version: "running-evaluation-v3", supplementVersion: SUPPLEMENT_VERSION, supplementCount: supplement.length, totalInputs: cases.length, scenarioVersion: SCENARIO_VERSION, checkerVersion: CHECKS_VERSION, rubricVersion: RUBRIC_VERSION, feasibilityPolicy: GOAL_FEASIBILITY_POLICY, seed, clock: clock.toISOString(), timezone: "UTC", count, baseline: baselineRevision, candidate: candidateRevision,
  ai: { limit: aiLimit, model, project: aiLimit ? project : "not_called", location, concurrency, timeoutMs, repeats }, limitations: ["Synthetic review is not clinical validation or injury-prevention certification.", "Ordinary outputs cover14days; checkpoint windows assume stable fitness rather than observed adaptation.", "Expected ineligible guards are separate from plan quality denominators.", "No production data, account, database or app analytics is used.", "AI cannot override hard findings; unassessable criteria report coverage."] };
save("manifest.json", manifest); save("plans.json", outputs); save("supplement-inputs.json", supplement); save("rollouts.json", rollouts); save("eligibility-guards.json", guards);
const aiResults: any[] = [], admissible = outputs.filter((item) => item.baseline.admission === "generated" && item.candidate.admission === "generated");
// Round-robin cohort sampling avoids a beginner-first convenience sample.
const buckets = [...new Set(cases.map((item) => item.cohort))].map((cohort) => admissible.filter((item) => item.scenario.cohort === cohort));
const selected: typeof outputs = [];
const sampling = seeded(seed + ":stratified");
for (let round = 0; selected.length < aiLimit && buckets.some((bucket) => bucket.some((item) => !selected.includes(item))); round++) {
  for (const bucket of buckets) {
    if (selected.length >= aiLimit) break;
    const coverage = (item: typeof outputs[number]) =>
      (selected.some((other) => other.scenario.goalLabel === item.scenario.goalLabel) ? 0 : 100)
      + (selected.some((other) => other.dataset === item.dataset) ? 0 : 20)
      + (selected.some((other) => other.scenario.horizonWeeks === item.scenario.horizonWeeks) ? 0 : 10)
      + (selected.some((other) => other.scenario.goal.daysPerWeekTarget === item.scenario.goal.daysPerWeekTarget) ? 0 : 3)
      + (selected.some((other) => other.scenario.goal.maxSessionMinutes === item.scenario.goal.maxSessionMinutes) ? 0 : 1);
    const pick = bucket.filter((item) => !selected.includes(item)).map((item) => ({ item, priority: coverage(item), tie: sampling() }))
      .sort((a, b) => b.priority - a.priority || a.tie - b.tie)[0];
    if (pick) selected.push(pick.item);
  }
}
const random = seeded(seed + ":blind");
const jobs = selected.map((item) => ({ item, flipped: random() < .5, repeat: 0 }));
for (let index = 0; index < Math.min(repeats, jobs.length); index++) jobs.push({ ...jobs[index], flipped: !jobs[index].flipped, repeat: 1 });
function anonymous(output: Output) {
  return { checkpointOutcomes: output.checkpointOutcomes, windows: output.windows.map((window) => ({
    id: window.id, now: window.now, phase: window.phase, programme: window.programme,
    workouts: window.workouts.map((workout) => ({ evaluationId: workout.evaluationId, scheduledDate: workout.scheduledDate,
      modality: workout.modality, stimulus: workout.stimulus, title: workout.title, durationSeconds: workout.durationSeconds,
      distanceMeters: workout.distanceMeters, targetCalories: workout.targetCalories,
      provisional: workout.prescription?.provisional === true,
      blocks: workout.blocks.map((block: any) => ({ blockType: block.blockType, durationSeconds: block.durationSeconds, repeats: block.repeats,
        steps: block.steps.map((step: any) => ({ label: step.label, kind: step.kind,
          durationSeconds: step.durationSeconds, distanceMeters: step.distanceMeters, detail: step.detail,
          target: step.target ? Object.fromEntries(Object.entries(step.target).filter(([key]) => !["paceEstimatePolicy", "policyVersion"].includes(key))) : null })) }))
    }))
  })) };
}
let cursor = 0;
await Promise.all(Array.from({ length: Math.min(concurrency, jobs.length) }, async () => {
  while (cursor < jobs.length) {
    const job = jobs[cursor++], A = job.flipped ? job.item.candidate : job.item.baseline, B = job.flipped ? job.item.baseline : job.item.candidate;
    const ids = (output: Output) => new Set(output.windows.flatMap((window) => window.workouts.map((workout) => workout.evaluationId)));
    try {
      const judged = await judge({ payload: { inputs: job.item.scenario, checkpointAssumptions: "Stable synthetic baseline, no observed fitness improvement. Windows are alternative snapshots, not additive schedules. Same-date initial/rebuild snapshots share evidence; identical output is correct stable/idempotent re-evaluation.", A: anonymous(A), B: anonymous(B) }, allowedA: ids(A), allowedB: ids(B), identity: { caseId: job.item.scenario.id, baseline: baselineRevision, candidate: candidateRevision, scenarioVersion: SCENARIO_VERSION, supplementVersion: SUPPLEMENT_VERSION, evaluationVersion: manifest.version, checkerVersion: CHECKS_VERSION, flipped: job.flipped }, cache: join(out, "judge-cache"), model, project, location, timeoutMs, repeat: job.repeat });
      const baselinePlan = judged.result[job.flipped ? "B" : "A"], candidatePlan = judged.result[job.flipped ? "A" : "B"];
      const shared = Object.keys(baselinePlan.criteria).filter((key) => baselinePlan.criteria[key as keyof typeof baselinePlan.criteria].rating != null && candidatePlan.criteria[key as keyof typeof candidatePlan.criteria].rating != null);
      aiResults.push({ caseId: job.item.scenario.id, dataset: job.item.dataset, cohort: job.item.scenario.cohort, repeat: job.repeat, flipped: job.flipped, ...judged, baseline: { ...score(baselinePlan, shared), ownCoverage: score(baselinePlan).coverage, criterionMask: shared, hardEligible: !job.item.baseline.findings.some((finding) => finding.severity === "error") }, candidate: { ...score(candidatePlan, shared), ownCoverage: score(candidatePlan).coverage, criterionMask: shared, hardEligible: !job.item.candidate.findings.some((finding) => finding.severity === "error") } });
    } catch (error) { aiResults.push({ caseId: job.item.scenario.id, dataset: job.item.dataset, cohort: job.item.scenario.cohort, repeat: job.repeat, failure: error instanceof Error ? error.message : "judge_failed", providerStatus: "failure", usage: (error as { usage?: unknown }).usage ?? null, attempts: (error as { attempts?: number }).attempts ?? null, validationFailures: (error as { validationFailures?: unknown[] }).validationFailures ?? [] }); }
    save("ai-results.json", aiResults);
  }
}));
function quantile(values: number[], q: number) { if (!values.length) return null; const sorted = [...values].sort((a, b) => a - b); const index = (sorted.length - 1) * q, lower = Math.floor(index), fraction = index - lower; return sorted[lower] + fraction * (sorted[Math.ceil(index)] - sorted[lower]); }
const labels = ["baseline", "candidate"] as const;
const ruleCounts: Record<string, number> = {};
for (const label of labels) for (const item of outputs) for (const finding of item[label].findings) { const key = `${label}:${finding.severity}:${finding.rule}`; ruleCounts[key] = (ruleCounts[key] ?? 0) + 1; }
const cohorts = [...new Set(cases.map((item) => item.cohort))].map((cohort) => ({ cohort, ...Object.fromEntries(labels.map((label) => {
  const rows = outputs.filter((item) => item.scenario.cohort === cohort), scored = aiResults.filter((item) => item.cohort === cohort && item.repeat === 0 && item[label]?.score != null), values = scored.map((item) => item[label].score);
  return [label, { cases: rows.length, generated: rows.filter((row) => row[label].admission === "generated").length, rejected: rows.filter((row) => row[label].admission === "rejected").length, failed: rows.filter((row) => row[label].admission === "failed").length, hardFailedCases: rows.filter((item) => item[label].findings.some((finding) => finding.severity === "error")).length, median: quantile(values, .5), p10: quantile(values, .1), scored: values.length, unscored: rows.length - values.length,
    judgeFailures: aiResults.filter((item) => item.cohort === cohort && item.repeat === 0 && item.failure).length, coverage: scored.map((item) => item[label].coverage) }];
})) }));
const reliability = aiResults.filter((item) => item.repeat === 1 && !item.failure).map((item) => { const original = aiResults.find((other) => other.caseId === item.caseId && other.repeat === 0); return { caseId: item.caseId, baselineDelta: original?.baseline?.score == null || item.baseline.score == null ? null : item.baseline.score - original.baseline.score, candidateDelta: original?.candidate?.score == null || item.candidate.score == null ? null : item.candidate.score - original.candidate.score, orderFlipped: true }; });
const admissions = (rows: typeof outputs) => ({ inputs: rows.length,
  engines: Object.fromEntries(labels.map((label) => [label, { generated: rows.filter((row) => row[label].admission === "generated").length,
    rejected: rows.filter((row) => row[label].admission === "rejected").length, failed: rows.filter((row) => row[label].admission === "failed").length,
    checkpointOutcomes: rows.flatMap((row) => row[label].checkpointOutcomes).reduce((counts, outcome) => { const key = `${outcome.id}:${outcome.outcome}:${outcome.code ?? "none"}`; counts[key] = (counts[key] ?? 0) + 1; return counts; }, {} as Record<string, number>),
    rejectionCodes: rows.filter((row) => row[label].admission === "rejected").reduce((counts, row) => { const code = row[label].admissionCode!; counts[code] = (counts[code] ?? 0) + 1; return counts; }, {} as Record<string, number>) }])),
  commonGenerated: rows.filter((row) => row.baseline.admission === "generated" && row.candidate.admission === "generated").length,
  commonGeneratedHardFailedCases: Object.fromEntries(labels.map((label) => [label, rows.filter((row) => row.baseline.admission === "generated" && row.candidate.admission === "generated" && row[label].findings.some((finding) => finding.severity === "error")).length])) });
const summary = { manifest, originalInputs: original.length, admissions: { original: admissions(outputs.filter((row) => row.dataset === "original")),
  supplement: admissions(outputs.filter((row) => row.dataset === "supplement")), all: admissions(outputs) },
 guardCorrect: guards.every((guard) => guard.result.eligible === guard.expected), hardFailedCases: Object.fromEntries(labels.map((label) => [label, outputs.filter((item) => item[label].findings.some((finding) => finding.severity === "error")).length])), ruleCounts, cohorts,
  ai: { coverageByDataset: ["original", "supplement"].map((dataset) => {
    const eligible = admissible.filter((row) => row.dataset === dataset).length;
    const attempted = aiResults.filter((row) => row.dataset === dataset && row.repeat === 0);
    return { dataset, eligiblePairs: eligible, attemptedPairs: attempted.length, scoredPairs: attempted.filter((row) => !row.failure).length,
      unscoredPairs: eligible - attempted.filter((row) => !row.failure).length, failures: attempted.filter((row) => row.failure).length };
  }), eligiblePairedCases: admissible.length, attemptedCalls: jobs.length, completedCalls: aiResults.filter((item) => !item.failure).length, failures: aiResults.filter((item) => item.failure), reliability },
  worstCases: outputs.map((item) => ({ caseId: item.scenario.id, cohort: item.scenario.cohort, findings: item.candidate.findings, hardErrors: item.candidate.findings.filter((finding) => finding.severity === "error").length })).sort((a, b) => b.hardErrors - a.hardErrors || b.findings.length - a.findings.length).slice(0, 12) };
save("report.json", summary);
const lines = ["# Synthetic running-plan quality report", "", `Seed: ${seed}; frozen UTC clock: ${clock.toISOString()}.`, `Baseline: ${baselineRevision.commit}; candidate: ${candidateRevision.commit}.`, "", `${original.length} original inputs plus ${supplement.length} separately reported orthogonal inputs; ${guards.length} separate eligibility guards. Guard expectations matched: ${summary.guardCorrect}.`, "", `Hard-failed cases: baseline ${summary.hardFailedCases.baseline}; candidate ${summary.hardFailedCases.candidate}. AI cannot override these findings.`, `AI: ${summary.ai.completedCalls}/${summary.ai.attemptedCalls} calls completed; ${admissible.length} common initial-generated pairs. Scores are diagnostic and cannot override hard findings. Missing scores remain unknown.`, "", "| Cohort | Cases | Baseline hard failures | Candidate hard failures | Baseline AI median/p10 | Candidate AI median/p10 |", "| --- | ---: | ---: | ---: | --- | --- |", ...cohorts.map((item: any) => `| ${item.cohort} | ${item.baseline.cases} | ${item.baseline.hardFailedCases} | ${item.candidate.hardFailedCases} | ${item.baseline.median ?? "unscored"}/${item.baseline.p10 ?? "unscored"} (n=${item.baseline.scored}) | ${item.candidate.median ?? "unscored"}/${item.candidate.p10 ?? "unscored"} (n=${item.candidate.scored}) |`), "", "## Admission outcomes", "", ...Object.entries(summary.admissions).map(([group, value]) => `- ${group}: ${JSON.stringify(value)}`), "", "## Worst candidate cases", "", ...summary.worstCases.map((item) => `- ${item.caseId} (${item.cohort}): ${item.hardErrors} hard findings; ${[...new Set(item.findings.map((finding) => finding.rule))].join(", ") || "none"}. Exact evidence and IDs: report.json/plans.json.`), "", "## Limits", "", ...manifest.limitations.map((item) => `- ${item}`), "- Numeric hard-rule thresholds are product review heuristics; warnings require review, not an injury-risk diagnosis.", "- See cohort judged/unscored/failure coverage and order-flipped repeat differences in report.json; a pilot does not establish universal judge reliability.", ""];
writeFileSync(join(out, "report.md"), lines.join("\n"));
console.log(JSON.stringify({ output: out, count, hardFailedCases: summary.hardFailedCases, guardCorrect: summary.guardCorrect, aiCompleted: summary.ai.completedCalls, artifactHash: createHash("sha256").update(readFileSync(join(out, "plans.json"))).digest("hex") }, null, 2));
