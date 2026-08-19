const baseURL = process.env.LOAD_TEST_BASE_URL;
const concurrency = Number(process.env.LOAD_TEST_CONCURRENCY ?? 40);
const requests = Number(process.env.LOAD_TEST_REQUESTS ?? 400);

if (!baseURL) throw new Error("LOAD_TEST_BASE_URL is required.");
if (!Number.isInteger(concurrency) || concurrency < 1 || concurrency > 500) {
  throw new Error("LOAD_TEST_CONCURRENCY must be an integer from 1 to 500.");
}

const durations = [];
let failures = 0;
let cursor = 0;

await Promise.all(Array.from({ length: Math.min(concurrency, requests) }, async () => {
  while (cursor < requests) {
    cursor += 1;
    const started = performance.now();
    try {
      const response = await fetch(new URL("/health", baseURL), { signal: AbortSignal.timeout(10_000) });
      if (!response.ok) failures += 1;
      await response.arrayBuffer();
    } catch {
      failures += 1;
    }
    durations.push(performance.now() - started);
  }
}));

durations.sort((a, b) => a - b);
const percentile = (p) => durations[Math.min(durations.length - 1, Math.ceil(durations.length * p) - 1)];
console.log(JSON.stringify({
  requests,
  concurrency,
  failures,
  p50Ms: Math.round(percentile(0.5)),
  p95Ms: Math.round(percentile(0.95)),
  p99Ms: Math.round(percentile(0.99)),
}, null, 2));

if (failures > 0) process.exitCode = 1;
