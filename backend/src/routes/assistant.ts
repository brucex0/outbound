import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { generateAssistantReply } from "../services/ai.js";
import { getAuthenticatedAppUser, getAuthenticatedIdentity } from "../services/currentUser.js";
import { getPrismaClient } from "../services/prisma.js";
import { runAssistantActivityTools } from "../services/assistantActivityTools.js";
import type { AppEnv } from "../types/hono.js";
import { runCompanionTurn } from "../services/companion/companionOrchestrator.js";

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
  guideName: z.string(),
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
    })
  ),
  async (c) => {
    const body = c.req.valid("json");
    const auth = getAuthenticatedIdentity(c);
    if (process.env.DATABASE_URL && auth) {
      const user = await getAuthenticatedAppUser(c).catch(() => null);
      if (user) {
        const task = body.context.isRecordingActive
          ? "live_guidance"
          : body.capability === "plan"
            ? "prepare_week"
            : body.capability === "support" || body.capability === "navigate" || body.capability === "discover"
              ? "product_help"
              : "answer_training_question";
        const companion = await runCompanionTurn(getPrismaClient(), user.id, {
          task,
          surface: body.context.isRecordingActive ? "live_session" : "assistant",
          prompt: body.prompt,
          conversationKey: "legacy-assistant",
          recentMessages: body.messages.map((message) => ({ role: message.role, text: message.text })),
          currentEntityIds: [],
          clientCapabilities: ["legacy-message"],
          isOffline: false,
          timeZoneIdentifier: body.context.timeZoneIdentifier,
          signals: [],
        }, c.get("locale")).catch((error) => {
          console.error("Companion adapter failed", error);
          return null;
        });
        if (companion) return c.json({ message: companion.message, locale: companion.locale });
      }
    }
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
      firebaseUid: auth?.internalUserId ?? auth?.providerSubject ?? undefined,
      activityContext: activityTools?.context,
      locale: c.get("locale"),
    });
    return c.json({ message: reply, locale: c.get("locale") });
  }
);

export default router;
