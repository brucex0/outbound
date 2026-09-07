import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { getRunningWeather } from "../services/weather.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const querySchema = z.object({
  latitude: z.coerce.number().min(-90).max(90),
  longitude: z.coerce.number().min(-180).max(180),
  altitudeMeters: z.coerce.number().min(-500).max(9_000).optional(),
  force: z.enum(["true", "false"]).optional().transform((value) => value === "true"),
});

router.get("/current", zValidator("query", querySchema), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required or user not registered." }, 401);

  const input = c.req.valid("query");
  try {
    const result = await getRunningWeather({
      userId: user.id,
      locale: c.get("locale"),
      latitude: input.latitude,
      longitude: input.longitude,
      altitudeMeters: input.altitudeMeters,
      force: input.force,
    });
    c.header("Cache-Control", "private, max-age=1800");
    c.header("X-Weather-Cache", result.cacheStatus);
    return c.json(result.snapshot);
  } catch (error) {
    console.warn("[weather] provider unavailable", {
      code: error instanceof Error ? error.message : "weather_provider_unknown",
    });
    return c.json({ error: "Local conditions are temporarily unavailable." }, 503);
  }
});

export default router;
