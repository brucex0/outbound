import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { runFinalTranscriptionAndParse } from "../services/ai.js";

const router = new Hono();

const transcribeSchema = z.object({
  audioUrl: z.string().url(),
  language: z.string().optional(),
});

router.post(
  "/final-pass",
  zValidator("json", transcribeSchema),
  async (c) => {
    const { audioUrl, language } = c.req.valid("json");
    const result = await runFinalTranscriptionAndParse({ audioUrl, language });
    return c.json(result);
  }
);

export default router;
