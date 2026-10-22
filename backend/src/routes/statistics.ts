import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import { accountStatistics } from "../services/statistics/service.js";
import type { AppEnv } from "../types/hono.js";
const router = new Hono<AppEnv>();
router.get("/", async c => {
  c.header("Cache-Control", "private, no-store");
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication is required." }, 401);
  const query = z.object({ timeZone: z.string().max(100).default("UTC").refine(value => { try { new Intl.DateTimeFormat("en-US", { timeZone: value }); return true; } catch { return false; } }), firstWeekday: z.coerce.number().int().min(1).max(7).default(1) }).safeParse(c.req.query());
  if (!query.success) { console.warn("[statistics] invalid_calendar status=400"); return c.json({ error: "Invalid statistics calendar." }, 400); }
  try { return c.json(await accountStatistics(user.id, query.data.timeZone, query.data.firstWeekday) as any); }
  catch (error) { console.error("[statistics] snapshot_failed", { category: error instanceof Error ? error.name : "unknown" }); return c.json({ error: "Statistics are temporarily unavailable." }, 503); }
});
// Exact candidate lookups avoid downloading the account's entire identity/history index.
router.post("/import-identities", zValidator("json", z.object({ sourceKind: z.enum(["strava", "appleHealth", "health_connect"]).default("strava"), externalIDs: z.array(z.string().max(512)).max(200), sessionIDs: z.array(z.string().uuid()).max(200).default([]) })), async c => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication is required." }, 401);
  const { externalIDs: ids, sessionIDs, sourceKind } = c.req.valid("json");
  if (!ids.length && !sessionIDs.length) return c.json({ externalIDs: [], sessionActivityIDs: [] });
  const rows = await getPrismaClient().activity.findMany({
    where: { userId: user.id, deletedAt: null, OR: [
      { importSourceKey: { in: ids.map(id => `${sourceKind}:${id}`) } },
      ...(sourceKind === "appleHealth" ? [{ healthWorkoutExternalID: { in: ids } }, { recordingSessionID: { in: sessionIDs.map(id => id.toLowerCase()) } }] : []),
    ] },
    select: { id: true, importSourceKey: true, healthWorkoutExternalID: true, recordingSessionID: true },
  });
  const known = rows.flatMap(r => [r.importSourceKey?.slice(sourceKind.length + 1), r.healthWorkoutExternalID].filter((x): x is string => typeof x === "string" && ids.includes(x)));
  return c.json({ externalIDs: [...new Set(known)], sessionActivityIDs: rows.filter(r => r.recordingSessionID && sessionIDs.some(id => id.toLowerCase() === r.recordingSessionID)).map(r => r.id) });
});
export default router;
