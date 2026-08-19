import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { getAuthenticatedIdentity } from "../services/currentUser.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

const feedbackSchema = z.object({
  kind: z.enum(["bug", "suggestion"]),
  message: z.string().trim().min(1).max(5_000),
  currentPage: z.string().trim().min(1).max(200),
  diagnostics: z.string().max(2_000).nullable().optional(),
  screenshotBase64: z.string().max(8_000_000).nullable().optional(),
  screenshotContentType: z.literal("image/jpeg").nullable().optional(),
});

router.post("/", zValidator("json", feedbackSchema), async (c) => {
  const identity = getAuthenticatedIdentity(c);
  if (!identity) return c.json({ error: "Authentication required." }, 401);

  const apiKey = process.env.RESEND_API_KEY;
  const from = process.env.FEEDBACK_EMAIL_FROM;
  if (!apiKey || !from) {
    return c.json({ error: "Feedback delivery is not configured." }, 503);
  }

  const body = c.req.valid("json");
  const screenshotBytes = body.screenshotBase64
    ? Buffer.from(body.screenshotBase64, "base64").byteLength
    : 0;
  if (screenshotBytes > 6_000_000) {
    return c.json({ error: "Screenshot is too large." }, 413);
  }

  const sections = [
    body.message,
    "",
    `Type: ${body.kind}`,
    `User ID: ${identity.firebaseUid}`,
    `User email: ${identity.email ?? "Unavailable"}`,
    `Current page: ${body.currentPage}`,
    ...(body.diagnostics ? ["", body.diagnostics] : []),
  ];
  const delivery = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: [process.env.FEEDBACK_EMAIL_TO ?? "info@plainstride.com"],
      subject: `Plainstride ${body.kind} report`,
      text: sections.join("\n"),
      ...(body.screenshotBase64
        ? {
            attachments: [
              {
                filename: "plainstride-feedback.jpg",
                content: body.screenshotBase64,
                content_type: body.screenshotContentType ?? "image/jpeg",
              },
            ],
          }
        : {}),
    }),
  });
  if (!delivery.ok) {
    console.error("Feedback email delivery failed", delivery.status, await delivery.text());
    return c.json({ error: "Could not deliver feedback." }, 502);
  }

  const result = (await delivery.json()) as { id?: string };
  return c.json({ id: result.id ?? "delivered", status: "sent" }, 201);
});

export default router;
