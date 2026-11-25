// Focused offline module checks; never uses credentials, network, or database.
import assert from 'node:assert/strict';
import { generateLoops } from '../dist/routePlanning/generateLoops.js';
import { OpenRouteService } from '../dist/routePlanning/openRouteService.js';
import { distance, RouteGenerationCancelled, RoutingProviderError } from '../dist/routePlanning/domain.js';
const request = { start: { latitude: 0, longitude: 0 }, targetDistanceM: 10000, activityType: 'running' };
const signal = () => new AbortController().signal;
function loop(heading = 0, length = 10000) {
  const radius = length / (2 * Math.PI) / 111195;
  const points = Array.from({ length: 81 }, (_, i) => {
    const angle = i * 2 * Math.PI / 80;
    const x = radius * (1 - Math.cos(angle)), y = radius * Math.sin(angle);
    return { longitude: x * Math.cos(heading) - y * Math.sin(heading), latitude: x * Math.sin(heading) + y * Math.cos(heading) };
  });
  return { points, distanceM: points.slice(1).reduce((sum, p, i) => sum + distance(points[i], p), 0), attribution: 'fixture' };
}
let calls = 0;
assert.equal((await generateLoops(request, { generate: async () => loop(calls++ * 2 * Math.PI / 3) }, signal())).length, 3);
assert.equal(calls, 3, 'stop after three useful diverse routes');
for (const category of ['authorization', 'quota']) {
  calls = 0;
  const routes = await generateLoops(request, { generate: async () => { if (calls++ === 0) return loop(); throw new RoutingProviderError(category, true, category === 'quota' ? 429 : 403); } }, signal());
  assert.equal(routes.length, 1, 'preserve validated partial result');
  assert.equal(calls, 2);
}
calls = 0;
await assert.rejects(generateLoops(request, { generate: async () => { calls++; throw new RoutingProviderError('upstream', false, 503); } }, signal()), e => e.category === 'upstream');
assert.equal(calls, 6, 'six-call ceiling');
assert.deepEqual(await generateLoops(request, { generate: async () => null }, signal()), []);
assert.deepEqual(await generateLoops(request, { generate: async () => loop(0, 12000) }, signal()), [], 'never widen distance tolerance');
assert.equal((await generateLoops(request, { generate: async () => loop() }, signal())).length, 1, 'duplicate candidates are rejected');
const invalid = loop(); invalid.points[1].latitude = NaN;
await assert.rejects(generateLoops(request, { generate: async () => invalid }, signal()), e => e.category === 'invalid_response');
const open = loop(); open.points[80] = { latitude: 1, longitude: 1 };
assert.deepEqual(await generateLoops(request, { generate: async () => open }, signal()), [], 'closure bound');
const shifted = loop(); shifted.points = shifted.points.map(p => ({ latitude: p.latitude + 1, longitude: p.longitude }));
assert.deepEqual(await generateLoops(request, { generate: async () => shifted }, signal()), [], 'start bound');
const via = { latitude: 0.01, longitude: -0.01 };
assert.deepEqual(await generateLoops({ ...request, via }, { generate: async () => loop() }, signal()), [], 'required via bound');
const outAndBack = loop(); outAndBack.points = [...outAndBack.points.slice(0, 40), ...outAndBack.points.slice(0, 40).reverse()];
assert.deepEqual(await generateLoops(request, { generate: async () => outAndBack }, signal()), [], 'backtracking bound');
// Caller cancellation is normal control flow; service and provider timeouts are failures.
const originalError = console.error, originalInfo = console.info, originalTimeout = AbortSignal.timeout;
const errors = [], outcomes = [];
console.error = (...args) => errors.push(args);
console.info = (...args) => outcomes.push(args[1]);
try {
  const controller = new AbortController(); calls = 0;
  await assert.rejects(generateLoops(request, { generate: async () => { calls++; if (calls === 2) { controller.abort(); throw new RoutingProviderError('timeout'); } return loop(); } }, controller.signal), e => e instanceof RouteGenerationCancelled);
  assert.equal(errors.length, 0);
  assert.equal(outcomes.at(-1).outcome, 'cancelled');
  assert.equal(outcomes.at(-1).providerFailures, 0);
  const aborted = new AbortController(); aborted.abort();
  await assert.rejects(generateLoops(request, { generate: async () => { throw new Error('must not call'); } }, aborted.signal), e => e instanceof RouteGenerationCancelled);
  assert.equal(errors.length, 0);
  assert.equal(outcomes.at(-1).calls, 0);
  let deadline = new AbortController();
  AbortSignal.timeout = ms => { assert.equal(ms, 25000); return deadline.signal; };
  await assert.rejects(generateLoops(request, { generate: async () => { deadline.abort(new DOMException('deadline', 'TimeoutError')); throw new RoutingProviderError('timeout'); } }, signal()), e => e.category === 'timeout');
  assert.equal(errors.length, 1);
  assert.equal(outcomes.at(-1).outcome, 'unavailable');
  assert.equal(outcomes.at(-1).providerFailures, 1);
  deadline = new AbortController(); calls = 0;
  assert.equal((await generateLoops(request, { generate: async () => { if (calls++ === 0) return loop(); deadline.abort(new DOMException('deadline', 'TimeoutError')); throw new RoutingProviderError('timeout'); } }, signal())).length, 1, 'service deadline retains partial routes');
  assert.equal(outcomes.at(-1).outcome, 'partial');
  assert.equal(outcomes.at(-1).providerFailures, 1);
  deadline = new AbortController();
  const lateCaller = new AbortController();
  await assert.rejects(generateLoops(request, { generate: async () => { deadline.abort(new DOMException('deadline', 'TimeoutError')); lateCaller.abort(); throw new RoutingProviderError('timeout'); } }, lateCaller.signal), e => e.category === 'timeout');
  assert.equal(outcomes.at(-1).outcome, 'unavailable', 'deadline winning before caller cancellation remains failure');
  deadline = new AbortController();
  const before = errors.length;
  await assert.rejects(generateLoops(request, { generate: async () => { throw new RoutingProviderError('timeout'); } }, signal()), e => e.category === 'timeout');
  assert.equal(errors.length - before, 6, 'per-call timeouts remain failures under call ceiling');
  assert.equal(outcomes.at(-1).providerFailures, 6);
} finally {
  console.error = originalError; console.info = originalInfo; AbortSignal.timeout = originalTimeout;
}
const originalFetch = globalThis.fetch;
try {
  for (const [status, code, category] of [[404, 2009, null], [400, 2010, null], [404, undefined, 'configuration'], [401, undefined, 'authorization'], [429, undefined, 'quota'], [503, undefined, 'upstream']]) {
    globalThis.fetch = async () => new Response(JSON.stringify({ error: { code } }), { status });
    const operation = new OpenRouteService('fake').generate(request, 0, signal());
    if (category) await assert.rejects(operation, e => e.category === category && e.status === status);
    else assert.equal(await operation, null);
  }
  globalThis.fetch = async () => { throw new TypeError('offline'); };
  await assert.rejects(new OpenRouteService('fake').generate(request, 0, signal()), e => e.category === 'transport');
  globalThis.fetch = async () => { throw new DOMException('timeout', 'TimeoutError'); };
  await assert.rejects(new OpenRouteService('fake').generate(request, 0, signal()), e => e.category === 'timeout');
  globalThis.fetch = async () => new Response('not json');
  await assert.rejects(new OpenRouteService('fake').generate(request, 0, signal()), e => e.category === 'invalid_response');
  const proposals = [];
  globalThis.fetch = async (_url, options) => {
    assert.equal(options.signal.aborted, false);
    proposals.push(JSON.parse(options.body).options.round_trip);
    const route = loop(0, proposals.length === 1 ? 12000 : 10000);
    return new Response(JSON.stringify({ features: [{ geometry: { coordinates: route.points.map(p => [p.longitude, p.latitude]) } }] }));
  };
  const provider = new OpenRouteService('fake');
  await provider.generate(request, 0, signal());
  await provider.generate(request, 1, signal());
  await provider.generate(request, 2, signal());
  assert.equal(proposals[0].seed, proposals[1].seed, 'correct same seed before changing geometry');
  assert.ok(proposals[1].length < 9000 && proposals[1].length > 8000);
  assert.equal(proposals[2].seed, proposals[0].seed + 1);
  assert.equal(proposals[2].length, request.targetDistanceM, 'new seed starts at original target');
} finally { globalThis.fetch = originalFetch; }
console.log('Focused route-generation checks passed.');
