import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { generateAssistantReply } from "../services/ai.js";

const router = new Hono();

const assistantCapabilitySchema = z.enum([
  "discover",
  "navigate",
  "support",
  "brainstorm",
  "plan",
]);

const assistantMessageSchema = z.object({
  role: z.enum(["user", "assistant"]),
  text: z.string().min(1),
  capability: assistantCapabilitySchema.optional(),
});

const assistantContextSchema = z.object({
  coachName: z.string(),
  activityCount: z.number().int().nonnegative(),
  weeklyDistanceKilometers: z.number().nonnegative(),
  currentGoalSummary: z.string().optional().nullable(),
  currentScreen: z.string().optional().nullable(),
  isRecordingActive: z.boolean().optional().default(false),
});

router.post(
  "/chat",
  zValidator(
    "json",
    z.object({
      prompt: z.string().min(1),
      capability: assistantCapabilitySchema,
      context: assistantContextSchema,
      messages: z.array(assistantMessageSchema).max(16).default([]),
      firebaseUid: z.string().optional(),
    })
  ),
  async (c) => {
    const body = c.req.valid("json");
    const reply = await generateAssistantReply({
      prompt: body.prompt,
      capability: body.capability,
      context: body.context,
      messages: body.messages,
      firebaseUid: body.firebaseUid,
    });
    return c.json({ message: reply });
  }
);

export default router;
