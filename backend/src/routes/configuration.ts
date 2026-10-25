import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { Prisma } from "@prisma/client";
import { getAuthenticatedAppUser } from "../services/currentUser.js";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import { stretchMovementModes, stretchTemplateModes } from "../services/liveCoach/stretchCatalogModes.js";
import type { AppEnv } from "../types/hono.js";

const mode = z.enum(["freestyle", "distance", "time", "calories"]);
const identifier = z.string().regex(/^[a-z][a-z0-9_]{0,63}$/);
const launch = z.object({
  preferredGoalModeRawValue: mode.nullish(),
  goalModeStartHistory: z.array(mode).max(3).default([]),
  distanceMeters: z.number().finite().positive().nullish(),
  timeSeconds: z.number().int().positive().max(2147483647).nullish(),
  calories: z.number().int().positive().max(2147483647).nullish(),
}).strict();
const entry = z.object({ movementID: identifier, seconds: z.union([z.literal(15), z.literal(20), z.literal(25), z.literal(30)]) }).strict();
const value = z.object({
  selection: identifier.optional(),
  launch: launch.optional(),
  entries: z.array(entry).min(1).max(20).optional(),
}).strict();
const mutation = z.object({
  key: z.string().regex(/^(stretch\/(last|standing)|stretch\/custom\/[a-z][a-z0-9_]{0,63}|launch\/[a-z][a-z0-9_]{0,63}|launch\/lastSport)$/),
  expectedRevision: z.number().int().min(0),
  value: value.nullable(),
}).strict().superRefine((body, ctx) => {
  const sports = ["run", "walk", "hike", "bike", "swim", "strength", "mobility"];
  const templateID = body.key.startsWith("stretch/custom/") ? body.key.slice("stretch/custom/".length) : null;
  if ((templateID !== null && !Object.hasOwn(stretchTemplateModes, templateID)) ||
      (body.key.startsWith("launch/") && body.key !== "launch/lastSport" && !sports.includes(body.key.slice(7)))) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Unknown configuration key" });
  }
  if (body.value === null) return;
  if (body.value.selection && !(body.key === "launch/lastSport" ? sports.includes(body.value.selection) : Object.hasOwn(stretchTemplateModes, body.value.selection))) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Unknown selection" });
  }
  const v = body.value;
  const custom = body.key.startsWith("stretch/custom/");
  const sport = body.key.startsWith("launch/") && body.key !== "launch/lastSport";
  if (Object.keys(v).length !== 1 || (custom ? !v.entries : sport ? !v.launch : !v.selection)) {
    ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Value does not match configuration key" });
  }
  if (v.entries) {
    const definitions = v.entries.map(e => stretchMovementModes[e.movementID as keyof typeof stretchMovementModes]);
    if (new Set(v.entries.map(e => e.movementID)).size !== v.entries.length || definitions.some(d => !d) || new Set(definitions.filter(Boolean).map(d => d.dynamic)).size !== 1 || (templateID !== null && definitions.some(d => d && d.dynamic !== stretchTemplateModes[templateID as keyof typeof stretchTemplateModes]))) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Invalid stretch movement sequence" });
    }
  }
});

export const configurationRouter = new Hono<AppEnv>();
configurationRouter.get("/", async c => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication required." }, 401);
  try {
    const records = await getPrismaClient().userConfiguration.findMany({ where: { userId: user.id }, select: { key: true, revision: true, value: true } });
    return c.json({ records });
  } catch (error) {
    console.error("[configuration] fetch failed", { operation: "get", code: error instanceof Prisma.PrismaClientKnownRequestError ? error.code : "unexpected" });
    return c.json({ error: "Configuration fetch failed." }, 500);
  }
});
configurationRouter.patch("/", zValidator("json", mutation), async c => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c); if (!user) return c.json({ error: "Authentication required." }, 401);
  const body = c.req.valid("json");
  try {
    // Lock the parent even when this key has no row yet; concurrent first writes must
    // observe one another. Each account's small configuration writes serialize.
    const result = await getPrismaClient().$transaction(async tx => {
      await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${user.id} FOR UPDATE`;
      const existing = await tx.userConfiguration.findUnique({ where: { userId_key: { userId: user.id, key: body.key } } });
      if ((existing?.revision ?? 0) !== body.expectedRevision) return { conflict: true as const, record: existing ?? { key: body.key, revision: 0, value: null } };
      const record = await tx.userConfiguration.upsert({
        where: { userId_key: { userId: user.id, key: body.key } },
        create: { userId: user.id, key: body.key, value: body.value ?? Prisma.JsonNull },
        update: { revision: { increment: 1 }, value: body.value ?? Prisma.JsonNull },
      });
      return { conflict: false as const, record };
    });
    const record = { key: result.record.key, revision: result.record.revision, value: result.record.value };
    if (result.conflict) {
      console.info("[configuration] write conflict", { operation: "patch", status: 409 });
      return c.json({ record }, 409);
    }
    return c.json({ record });
  } catch (error) {
    console.error("[configuration] write failed", { operation: "patch", code: error instanceof Prisma.PrismaClientKnownRequestError ? error.code : "unexpected" });
    return c.json({ error: "Configuration save failed." }, 500);
  }
});
