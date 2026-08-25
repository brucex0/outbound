import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const requestSchema = z.object({
  model: z.string().min(1).max(120).regex(/^[A-Za-z0-9._:/-]+$/),
  packet: z.record(z.string(), z.unknown()),
});

router.post("/analyze", zValidator("json", requestSchema), async (c) => {
  const { model, packet } = c.req.valid("json");
  const apiKey = process.env.APP_AI_KEY;
  const baseUrl = (process.env.APP_AI_BASE_URL || "https://api.deepseek.com").replace(/\/+$/, "");
  if (!apiKey) return c.json({ error: "Live coach AI is not configured" }, 503);

  const allowedModels = (process.env.LIVE_COACH_ALLOWED_MODELS || process.env.APP_AI_MODEL || "deepseek-chat")
    .split(",").map((value) => value.trim()).filter(Boolean);
  if (!allowedModels.includes(model)) return c.json({ error: "Model is not enabled" }, 400);

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
    body: JSON.stringify({
      model,
      temperature: 0.45,
      max_tokens: 100,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "You are Plainstride's live running coach. Use only the supplied workout packet. Be safe, specific, non-medical, and under 24 spoken words. Return JSON only as {\"message\":\"...\",\"urgency\":\"steady|opportunity|caution\",\"shouldSpeak\":true}." },
        { role: "user", content: JSON.stringify(packet) },
      ],
    }),
  });
  if (!response.ok) return c.json({ error: "Model request failed" }, 502);
  const payload = await response.json() as { choices?: Array<{ message?: { content?: string } }> };
  const content = payload.choices?.[0]?.message?.content;
  if (!content) return c.json({ error: "Model returned no result" }, 502);
  try {
    const result = JSON.parse(content) as { message?: string; urgency?: string; shouldSpeak?: boolean };
    const message = result.message?.trim();
    if (!message || message.length > 240) throw new Error("invalid message");
    const urgency = ["steady", "opportunity", "caution"].includes(result.urgency ?? "") ? result.urgency : "steady";
    return c.json({ message, urgency, shouldSpeak: result.shouldSpeak !== false, model });
  } catch {
    return c.json({ error: "Model returned an invalid result" }, 502);
  }
});

export default router;
