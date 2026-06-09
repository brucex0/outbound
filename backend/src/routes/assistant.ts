import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { generateAssistantReply } from "../services/ai.js";
import { getAuthenticatedAppUser, getAuthenticatedIdentity } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import { runAssistantActivityTools } from "../services/assistantActivityTools.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

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
  timeZoneIdentifier: z.string().optional().nullable(),
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
    const auth = getAuthenticatedIdentity(c);
    const activityTools =
      process.env.DATABASE_URL && auth
        ? await (async () => {
            const user = await getAuthenticatedAppUser(c);
            if (!user) return null;
            return runAssistantActivityTools({
              prisma: getPrismaClient(),
              userId: user.id,
              prompt: body.prompt,
              timeZoneIdentifier: body.context.timeZoneIdentifier,
            });
          })().catch((error) => {
            console.error("Assistant activity tools failed", error);
            return null;
          })
        : null;

    if (activityTools?.directAnswer) {
      return c.json({ message: activityTools.directAnswer });
    }

    const reply = await generateAssistantReply({
      prompt: body.prompt,
      capability: body.capability,
      context: body.context,
      messages: body.messages,
      firebaseUid: auth?.firebaseUid ?? body.firebaseUid,
      activityContext: activityTools?.context,
    });
    return c.json({ message: reply });
  }
);

export default router;
