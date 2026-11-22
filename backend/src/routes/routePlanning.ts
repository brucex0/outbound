import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { bodyLimit } from "hono/body-limit";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { rateLimit } from "../middleware/rateLimit.js";
import type { AppEnv } from "../types/hono.js";
import { OpenRouteService } from "../routePlanning/openRouteService.js";
import { generateLoops } from "../routePlanning/generateLoops.js";
const coordinate = z.object({ latitude: z.number().finite().min(-85).max(85), longitude: z.number().finite().min(-180).max(180) }).strict();
const schema = z.object({ start: coordinate, via: coordinate.optional(), targetDistanceM: z.number().finite().min(1000).max(50000), activityType: z.enum(["running", "walking", "hiking", "cycling"]), variationSeed: z.number().int().min(0).max(1000000).optional(), preference: z.enum(["balanced", "less_climbing"]).optional() }).strict();
const router = new Hono<AppEnv>();
router.post("/generate", bodyLimit({ maxSize: 2048 }), rateLimit({ name: "route-generation", limit: 3, windowMs: 60000, key: "identity" }), zValidator("json", schema), async c => {
  if (!await getAuthenticatedAppUser(c)) return c.json({ error: "Authentication is required." }, 401);
  const request = c.req.valid("json"), key = process.env.ORS_API_KEY?.trim();
  if (!key || request.activityType === "cycling") return c.json({ code: "route_planning_unavailable", error: "Route planning is unavailable for this activity." }, 503);
  try {
    const signal = AbortSignal.any([c.req.raw.signal, AbortSignal.timeout(25000)]);
    const candidates = await generateLoops(request, new OpenRouteService(key, process.env.ORS_API_BASE_URL), signal);
    return c.json({ candidates, toleranceFraction: 0.1 });
  } catch (error) {
    console.error("route_planning generation_failed", { category: error instanceof Error ? error.name : "unknown" });
    return c.json({ code: "route_planning_unavailable", error: "Route planning is temporarily unavailable." }, 503);
  }
});
export default router;
