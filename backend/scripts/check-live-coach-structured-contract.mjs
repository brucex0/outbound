// Focused local contract check. No provider calls, database, accounts or devices.
import assert from 'node:assert/strict';
import { createSessionSchema } from '../dist/services/liveCoach/liveCoachRequestContract.js';
import { compileLiveCoachContext } from '../dist/services/liveCoach/liveCoachContextCompiler.js';
import { standaloneWorkoutCatalog } from '../dist/data/standaloneWorkouts.js';
import { workoutStartInstructionCues } from '../dist/services/liveCoach/executionCoaching.js';

const base = { contractVersion: 2, clientSessionId: '00000000-0000-4000-8000-000000000001',
  locale: 'en', coachPersonaId: 'plainstride_supportive_v1', voiceProfileId: 'plainstride_clear_1',
  coachingContract: 'responsive', measurementUnitSystem: 'metric',
  sessionIntent: { activityType: 'running', goalType: 'time' },
  execution: { targetDurationSeconds: 1800, steps: [{ durationSeconds: 300, phase: 'warmup' }, { durationSeconds: 1500, phase: 'easy' }] },
  environment: { timeZoneIdentifier: 'America/Los_Angeles', indoor: false } };
const parse = value => createSessionSchema.parse(value);
const rejected = value => assert.equal(createSessionSchema.safeParse(value).success, false);
parse(base);
parse({ ...base, sessionIntent: { ...base.sessionIntent, goalType: 'distance' }, execution: { targetDistanceMeters: 10_000, steps: [] } });
rejected({ ...base, execution: { ...base.execution, guideLine: 'Display prose' } });
rejected({ ...base, execution: { ...base.execution, steps: [{ durationSeconds: 30, phase: 'invented' }] } });
rejected({ ...base, execution: { ...base.execution, steps: Array(81).fill({ durationSeconds: 30, phase: 'easy' }) } });
rejected({ ...base, execution: { ...base.execution, steps: [{ durationSeconds: 86_400, phase: 'easy' }, { durationSeconds: 1, phase: 'easy' }] } });
rejected({ ...base, execution: { steps: [] } });
rejected({ ...base, workoutId: 'saved', execution: base.execution });
rejected({ ...base, execution: { ...base.execution, route: { name: 'A private route' } } });
rejected({ ...base, environment: { indoor: false, approximateLocation: { placeName: 'A private place' } } });
const catalogWorkout = standaloneWorkoutCatalog.workouts.find(value => value.sport === 'run');
const catalogInput = parse({ ...base, workoutRef: { source: 'standalone_catalog', id: catalogWorkout.id, version: standaloneWorkoutCatalog.version }, execution: { targetDurationSeconds: 1800, steps: [] } });
const old = parse({ ...base, contractVersion: 1, execution: undefined, clientWorkout: {
  title: 'Long easy run', detail: 'x'.repeat(513), guideLine: 'x'.repeat(513), steps: [] } });
assert.equal(old.clientWorkout.detail, '');
assert.equal(old.clientWorkout.guideLine, '');
const nullRow = { findUnique: async () => null, findFirst: async () => null, findMany: async () => [] };
const db = Object.fromEntries(['user', 'runnerProfile', 'guideProfile', 'plannedWorkout', 'readinessCheckIn', 'activity',
  'workoutFeedback', 'runnerInsight', 'runnerBelief', 'runnerModelVersion', 'situationalSignal', 'workoutEdit', 'workoutPrescriptionRevision']
  .map(name => [name, { ...nullRow }]));
const catalog = await compileLiveCoachContext(db, 'synthetic', catalogInput);
assert.equal(catalog.context.workoutExecution.id, catalogWorkout.id);
assert.deepEqual(catalog.context.workoutExecution.segments.map(value => value.id), catalogWorkout.guideInstructions.segments.map(value => value.id));
const custom = await compileLiveCoachContext(db, 'synthetic', parse(base));
assert.equal(custom.context.clientWorkout.steps[0].phase, 'warmup');
assert.equal(custom.context.clientWorkout.targetDurationSeconds, 1800);
assert.equal('guideLine' in custom.context.clientWorkout, false);
assert.equal(workoutStartInstructionCues(custom.context)[0].instructionId, 'workout.phase.start');
const workout = { id: 'saved', title: 'Server prescription', stimulus: 'longEndurance', durationSeconds: 1800,
  targetCalories: null, prescription: {}, intensityTarget: {}, blocks: [{ blockType: 'warmup', durationSeconds: 300, steps: [] },
  { blockType: 'main', durationSeconds: 1500, steps: [{ kind: 'run', durationSeconds: 1500, target: null }] }] };
db.plannedWorkout.findFirst = async query => {
  assert.equal(query.where.userId, 'synthetic');
  return workout;
};
const savedInput = parse({ ...base, workoutId: 'saved', execution: { targetDurationSeconds: 1800, steps: [] } });
const saved = await compileLiveCoachContext(db, 'synthetic', savedInput);
assert.deepEqual(saved.context.clientWorkout.steps.map(step => step.phase), ['warmup', 'easy']);
assert.equal(saved.context.workout.title, 'Server prescription');
const issuance = { id: 'issued', revision: 'a'.repeat(64) };
await assert.rejects(() => compileLiveCoachContext(db, 'synthetic', { ...savedInput, workoutIssuance: issuance }), /issued workout revision/);
db.workoutPrescriptionRevision.findFirst = async () => ({ snapshot: {} });
await assert.rejects(() => compileLiveCoachContext(db, 'synthetic', { ...savedInput, workoutIssuance: issuance }), /issued execution snapshot/);
db.workoutPrescriptionRevision.findFirst = async query => {
  assert.deepEqual(query.where, { id: 'issued', revision: issuance.revision, plannedWorkoutId: 'saved', plannedWorkout: { userId: 'synthetic' } });
  return { snapshot: { effectiveWorkout: { id: 'issued-effective', title: 'Issued prescription', guideLine: 'Server-owned instruction', sport: 'run',
    steps: [{ id: 'warm', durationSeconds: 120, label: 'Warm up', coachingTarget: { phase: 'warmup' } }],
    guideInstructions: { objective: 'Warm up', beforeStart: [], segments: [], finish: [], stopConditions: [] } } } };
};
const issued = await compileLiveCoachContext(db, 'synthetic', { ...savedInput, workoutIssuance: issuance });
assert.equal(issued.context.workout.title, 'Issued prescription');
assert.equal(issued.context.clientWorkout.steps[0].durationSeconds, 120);
const legacy = await compileLiveCoachContext(db, 'synthetic', old);
assert.equal(legacy.serialized.includes('x'.repeat(100)), false);
console.log('Structured coaching contract checks passed: bounded inputs, goals, prose rejection, released iOS, owned and issued prescriptions, opening cue.');
