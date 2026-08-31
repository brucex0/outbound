import type { LiveCoachCueEnvelope } from "./liveCoachTypes.js";

type CachedResult = { value: LiveCoachCueEnvelope; expiresAt: number };
type RateBucket = { count: number; resetAt: number };

export class LiveCoachCueRepository {
  private readonly inFlight = new Map<string, Promise<LiveCoachCueEnvelope>>();
  private readonly completed = new Map<string, CachedResult>();
  private readonly recentSummaries = new Map<string, string[]>();
  private readonly sessionAbortControllers = new Map<string, Set<AbortController>>();
  private readonly activeGeneration = new Map<string, string>();
  private readonly sessionRateBuckets = new Map<string, RateBucket>();
  private readonly sessionPrefetchBuckets = new Map<string, RateBucket>();

  allowSessionRequest(sessionId: string, now = Date.now()): boolean {
    this.sweep(now);
    const current = this.sessionRateBuckets.get(sessionId);
    const bucket = !current || current.resetAt <= now
      ? { count: 1, resetAt: now + 60_000 }
      : { count: current.count + 1, resetAt: current.resetAt };
    this.sessionRateBuckets.set(sessionId, bucket);
    return bucket.count <= 20;
  }

  allowSessionPrefetch(sessionId: string, now = Date.now()): boolean {
    this.sweep(now);
    const current = this.sessionPrefetchBuckets.get(sessionId);
    const bucket = !current || current.resetAt <= now
      ? { count: 1, resetAt: now + 4 * 60 * 60 * 1_000 }
      : { count: current.count + 1, resetAt: current.resetAt };
    this.sessionPrefetchBuckets.set(sessionId, bucket);
    return bucket.count <= 8;
  }

  tryBeginGeneration(sessionId: string, cueRequestId: string): boolean {
    if (this.activeGeneration.has(sessionId)) return false;
    this.activeGeneration.set(sessionId, cueRequestId);
    return true;
  }

  endGeneration(sessionId: string, cueRequestId: string): void {
    if (this.activeGeneration.get(sessionId) === cueRequestId) {
      this.activeGeneration.delete(sessionId);
    }
  }

  runIdempotent(
    sessionId: string,
    cueRequestId: string,
    work: (controller: AbortController) => Promise<LiveCoachCueEnvelope>
  ): Promise<LiveCoachCueEnvelope> {
    this.sweep();
    const key = `${sessionId}:${cueRequestId}`;
    const cached = this.completed.get(key);
    if (cached) return Promise.resolve(cached.value);
    const existing = this.inFlight.get(key);
    if (existing) return existing;

    const controller = new AbortController();
    const controllers = this.sessionAbortControllers.get(sessionId) ?? new Set<AbortController>();
    controllers.add(controller);
    this.sessionAbortControllers.set(sessionId, controllers);
    const promise = work(controller).then((value) => {
      this.completed.set(key, { value, expiresAt: Date.parse(value.expiresAt) });
      return value;
    }).finally(() => {
      this.inFlight.delete(key);
      controllers.delete(controller);
      if (controllers.size === 0) this.sessionAbortControllers.delete(sessionId);
    });
    this.inFlight.set(key, promise);
    return promise;
  }

  recentCueSummariesForSession(sessionId: string): string[] {
    return [...(this.recentSummaries.get(sessionId) ?? [])];
  }

  appendCueSummary(sessionId: string, summary: string): void {
    const current = this.recentSummaries.get(sessionId) ?? [];
    current.push(summary.slice(0, 160));
    this.recentSummaries.set(sessionId, current.slice(-3));
  }

  abortSession(sessionId: string): void {
    for (const controller of this.sessionAbortControllers.get(sessionId) ?? []) controller.abort();
    this.sessionAbortControllers.delete(sessionId);
    this.recentSummaries.delete(sessionId);
    this.activeGeneration.delete(sessionId);
    this.sessionRateBuckets.delete(sessionId);
    this.sessionPrefetchBuckets.delete(sessionId);
    for (const key of this.completed.keys()) {
      if (key.startsWith(`${sessionId}:`)) this.completed.delete(key);
    }
  }

  private sweep(now = Date.now()): void {
    for (const [key, item] of this.completed) {
      if (item.expiresAt <= now) this.completed.delete(key);
    }
    for (const [sessionId, bucket] of this.sessionRateBuckets) {
      if (bucket.resetAt <= now) this.sessionRateBuckets.delete(sessionId);
    }
    for (const [sessionId, bucket] of this.sessionPrefetchBuckets) {
      if (bucket.resetAt <= now) this.sessionPrefetchBuckets.delete(sessionId);
    }
  }
}

export const liveCoachCueRepository = new LiveCoachCueRepository();
