import assert from "node:assert/strict";
import test, { type TestContext } from "node:test";
import { getPrismaClient } from "../prisma.js";
import { buildActivitySuggestion, buildBaseActivitySuggestion } from "../planning/activitySuggestion.js";
import { previewWorkoutAdjustment, decideAdjustment } from "./personalizationService.js";
import { workoutAdjustmentPreviewRequestSchema } from "./contracts.js";
import { applyDailyWorkoutAdjustment, WorkoutAdjustmentError } from "./workoutAdjustmentPolicy.js";

// Exercise the real service + suggestion engine against bounded in-memory Prisma delegates.
// Any accidental readiness/evidence write is counted; no database connection is used.
function fixture(context: TestContext, active: boolean) {
  const prisma = getPrismaClient();
  const proposals: any[] = [];
  let readiness: any = null;
  let readinessWrites = 0;
  let evidenceWrites = 0;
  const today = new Date(); today.setHours(0, 0, 0, 0);
  const workout: any = {
    id: "selected", userId: "runner", planVersionId: "version-1", scheduledDate: today,
    title: "Easy aerobic run", durationSeconds: 1500, modality: "run", stimulus: "easyAerobic",
    status: "planned", intensityModel: "rpe", intensityTarget: null, prescription: {}, isKeyWorkout: false,
    blocks: [
      { id: "warmup", blockType: "warmup", durationSeconds: 300, steps: [{ id: "warmup-step", label: "Warm up", durationSeconds: 300 }] },
      { id: "main", blockType: "main", durationSeconds: 900, steps: [{ id: "main-step", label: "Easy running", durationSeconds: 900 }] },
      { id: "cooldown", blockType: "cooldown", durationSeconds: 300, steps: [{ id: "cooldown-step", label: "Cool down", durationSeconds: 300 }] },
    ],
  };
  const plan: any = {
    id: "plan-1", userId: "runner", status: "active", createdAt: today,
    goal: { type: "eventPreparation", activities: ["run"], constraints: {}, baselineContext: "currentlyActive" },
    versions: [{ id: "version-1", versionNumber: 1, workouts: [workout] }],
  };
  workout.planVersion = { id: "version-1", plan };
  const patch = (owner: object, key: string, implementation: (...args: any[]) => any) => {
    const descriptor = Object.getOwnPropertyDescriptor(owner, key);
    Object.defineProperty(owner, key, { configurable: true, value: implementation });
    context.after(() => { if (descriptor) Object.defineProperty(owner, key, descriptor); else Reflect.deleteProperty(owner, key); });
  };
  patch(prisma, "$transaction", async (operation) => operation(prisma));
  patch(prisma.trainingPlan, "findFirst", async () => active ? plan : null);
  patch(prisma.activity, "findMany", async () => []);
  patch(prisma.readinessCheckIn, "findFirst", async () => readiness);
  patch(prisma.readinessCheckIn, "create", async () => { readinessWrites++; throw new Error("Preview wrote readiness"); });
  patch(prisma.runnerEvidence, "upsert", async () => { evidenceWrites++; throw new Error("Preview wrote runner evidence"); });
  patch(prisma.plannedWorkout, "findFirst", async ({ where }) => {
    if (!active || where.userId !== workout.userId || where.id !== workout.id || workout.status !== "planned") return null;
    if (where.scheduledDate && (workout.scheduledDate < where.scheduledDate.gte || workout.scheduledDate >= where.scheduledDate.lt)) return null;
    return workout;
  });
  patch(prisma.personalizationAdjustment, "findFirst", async ({ where }) => [...proposals].reverse().find((proposal) =>
    proposal.userId === where.userId && (!where.id || proposal.id === where.id)
    && (!where.status || proposal.status === where.status)
    && (!where.policyVersion || proposal.policyVersion === where.policyVersion)
    && (!where.decidedAt || proposal.decidedAt >= where.decidedAt.gte)
  ) ?? null);
  patch(prisma.personalizationAdjustment, "create", async ({ data }) => {
    const proposal = { ...data, id: `proposal-${proposals.length}`, status: "proposed", createdAt: new Date(), decidedAt: null };
    proposals.push(proposal); return proposal;
  });
  patch(prisma.personalizationAdjustment, "update", async ({ where, data }) => Object.assign(proposals.find((row) => row.id === where.id), data));
  patch(prisma.plannedWorkout, "update", async ({ where, data }) => { assert.equal(where.id, "selected"); return Object.assign(workout, data); });
  patch(prisma.workoutBlock, "update", async ({ where, data }) => Object.assign(workout.blocks.find((row: any) => row.id === where.id), data));
  patch(prisma.workoutStep, "update", async ({ where, data }) => Object.assign(workout.blocks.flatMap((row: any) => row.steps).find((row: any) => row.id === where.id), data));
  return {
    prisma, workout, plan, proposals,
    setReadiness: (value: any) => { readiness = value; },
    assertNoHealthWrites: () => { assert.equal(readinessWrites, 0); assert.equal(evidenceWrites, 0); },
  };
}

async function requestFor(userId = "runner", choice: "tired" | "sore" | "shortOnTime" = "tired") {
  const response = await buildActivitySuggestion(userId);
  assert.ok(response.primary);
  return { workoutId: response.primary.plannedWorkoutId ?? response.primary.id, suggestionId: response.primary.id, validForDate: response.validForDate, choice };
}

test("planned preview + reject preserve the original workout and readiness", async (context) => {
  const state = fixture(context, true);
  const before = await buildActivitySuggestion("runner");
  const { adjustment } = await previewWorkoutAdjustment("runner", await requestFor());
  assert.ok(adjustment);
  assert.equal(state.workout.durationSeconds, 1500);
  await decideAdjustment("runner", adjustment.id, "reject");
  const after = await buildActivitySuggestion("runner");
  assert.deepEqual(after.primary, before.primary);
  assert.equal(state.proposals[0].status, "rejected");
  state.assertNoHealthWrites();
});

test("planned acceptance changes only selected row and preserves minimum running phase", async (context) => {
  const state = fixture(context, true);
  const { adjustment } = await previewWorkoutAdjustment("runner", await requestFor("runner", "shortOnTime"));
  assert.ok(adjustment);
  await decideAdjustment("runner", adjustment.id, "accept");
  assert.equal(state.workout.durationSeconds, 1200);
  assert.equal(state.workout.blocks.find((block: any) => block.blockType === "main").durationSeconds, 900);
  assert.equal(state.workout.blocks.reduce((sum: number, block: any) => sum + block.durationSeconds, 0), 1200);
  await decideAdjustment("runner", adjustment.id, "accept"); // Idempotent: no second resize.
  assert.equal(state.workout.durationSeconds, 1200);
  state.assertNoHealthWrites();
});

test("stale planned preview, foreign ownership, and wrong date cannot apply", async (context) => {
  const state = fixture(context, true);
  const request = await requestFor();
  const { adjustment } = await previewWorkoutAdjustment("runner", request);
  assert.ok(adjustment);
  state.workout.durationSeconds = 1800;
  await assert.rejects(decideAdjustment("runner", adjustment.id, "accept"), (error: unknown) => error instanceof WorkoutAdjustmentError && error.status === 409);
  await assert.rejects(decideAdjustment("other-runner", adjustment.id, "accept"));
  await assert.rejects(previewWorkoutAdjustment("runner", { ...request, validForDate: "2000-01-01" }));
  assert.equal(state.proposals[0].status, "proposed");
  state.assertNoHealthWrites();
});

test("daily preview + reject preserve recommendation; accept survives refresh only for same baseline/day", async (context) => {
  const state = fixture(context, false);
  const before = await buildActivitySuggestion("runner");
  const request = await requestFor();
  const first = await previewWorkoutAdjustment("runner", request);
  assert.ok(first.adjustment);
  await decideAdjustment("runner", first.adjustment.id, "reject");
  assert.deepEqual((await buildActivitySuggestion("runner")).primary, before.primary);
  const second = await previewWorkoutAdjustment("runner", request);
  assert.ok(second.adjustment);
  await decideAdjustment("runner", second.adjustment.id, "accept");
  const after = await buildActivitySuggestion("runner");
  assert.notDeepEqual(after.primary, before.primary);
  assert.ok(after.primary!.durationMinutes < before.primary!.durationMinutes);
  assert.equal(after.primary!.plannedWorkoutId, null);
  const applied = state.proposals.find((row) => row.status === "applied");
  applied.changes[0].date = "2000-01-01";
  assert.deepEqual((await buildActivitySuggestion("runner")).primary, before.primary);
  state.assertNoHealthWrites();
});

test("daily pending acceptance expires and genuine newer readiness/safety take precedence", async (context) => {
  const state = fixture(context, false);
  const pending = await previewWorkoutAdjustment("runner", await requestFor());
  assert.ok(pending.adjustment);
  state.proposals[0].changes[0].date = "2000-01-01";
  await assert.rejects(decideAdjustment("runner", pending.adjustment.id, "accept"));
  const next = await previewWorkoutAdjustment("runner", await requestFor());
  assert.ok(next.adjustment);
  await decideAdjustment("runner", next.adjustment.id, "accept");
  state.setReadiness({ id: "genuine-new-readiness", date: new Date(), energy: 3, soreness: 1, stress: 1, motivation: 3, sleepQuality: 3, illnessOrPain: false });
  const baseline = await buildBaseActivitySuggestion("runner");
  assert.deepEqual((await buildActivitySuggestion("runner")).primary, baseline.primary);
  const safety = { ...baseline, decision: { ...baseline.decision, safetyFlags: ["pain_or_illness"] } };
  assert.deepEqual(await applyDailyWorkoutAdjustment(state.prisma, "runner", safety), safety);
  state.assertNoHealthWrites();
});

test("Limited time uses canonical shortOnTime; old misspelling fails validation", () => {
  const request = { workoutId: "selected", suggestionId: "planned-selected", validForDate: "2026-11-09", choice: "shortOnTime" };
  assert.equal(workoutAdjustmentPreviewRequestSchema.safeParse(request).success, true);
  assert.equal(workoutAdjustmentPreviewRequestSchema.safeParse({ ...request, choice: "short_on_time" }).success, false);
});
