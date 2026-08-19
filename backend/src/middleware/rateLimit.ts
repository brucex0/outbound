import { createMiddleware } from "hono/factory";
import type { AppEnv } from "../types/hono.js";

type Bucket = { count: number; resetAt: number };

const buckets = new Map<string, Bucket>();
let lastSweep = Date.now();

export function rateLimit(options: {
  name: string;
  limit: number;
  windowMs: number;
  key?: "identity" | "ip";
}) {
  return createMiddleware<AppEnv>(async (c, next) => {
    const now = Date.now();
    sweepExpiredBuckets(now, options.windowMs);

    const auth = c.get("auth");
    const forwardedFor = c.req.header("X-Forwarded-For")?.split(",")[0]?.trim();
    const clientIP = forwardedFor || "unknown";
    const principal = options.key === "ip" ? clientIP : auth?.firebaseUid || clientIP;
    const key = `${options.name}:${principal}`;
    const current = buckets.get(key);
    const bucket = !current || current.resetAt <= now
      ? { count: 1, resetAt: now + options.windowMs }
      : { count: current.count + 1, resetAt: current.resetAt };
    buckets.set(key, bucket);

    const remaining = Math.max(0, options.limit - bucket.count);
    c.header("RateLimit-Limit", String(options.limit));
    c.header("RateLimit-Remaining", String(remaining));
    c.header("RateLimit-Reset", String(Math.ceil(bucket.resetAt / 1_000)));

    if (bucket.count > options.limit) {
      const retryAfter = Math.max(1, Math.ceil((bucket.resetAt - now) / 1_000));
      c.header("Retry-After", String(retryAfter));
      return c.json({ error: "Too many requests. Please try again shortly." }, 429);
    }

    await next();
  });
}

function sweepExpiredBuckets(now: number, windowMs: number) {
  if (now - lastSweep < windowMs) return;
  lastSweep = now;
  for (const [key, bucket] of buckets) {
    if (bucket.resetAt <= now) buckets.delete(key);
  }
}
