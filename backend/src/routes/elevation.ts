import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import type { AppEnv } from "../types/hono.js";
import { correctTerrainElevation } from "../services/terrainElevation.js";

const router = new Hono<AppEnv>();

const correctionSchema = z.object({
  points: z.array(z.object({
    latitude: z.number().finite().min(-85).max(85),
    longitude: z.number().finite().min(-180).max(180),
    startsNewSegment: z.boolean().default(false),
  }).strict()).min(2).max(512),
}).strict();

router.post("/correct", zValidator("json", correctionSchema), async (c) => {
  if (!c.get("auth")) return c.json({ error: "Authentication required." }, 401);
  try {
    const result = await correctTerrainElevation(c.req.valid("json").points);
    c.header("Cache-Control", "no-store");
    return c.json(result);
  } catch (error) {
    console.warn("[elevation] terrain provider unavailable", {
      code: error instanceof Error ? error.message : "terrain_provider_unknown",
    });
    return c.json({ error: "Terrain elevation is temporarily unavailable." }, 503);
  }
});

export default router;
