import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import {
  getAuthenticatedAppUser,
  getAuthenticatedIdentity,
  resolveAuthenticatedAppUser,
} from "../services/currentUser.js";
import type { AppEnv } from "../types/hono.js";
import { deleteFirebaseUser } from "../services/firebaseAuth.js";
import { deleteAvatar, saveAvatar, signedAvatarURL } from "../services/avatarStorage.js";
import { deleteUserActivityPhotos } from "../services/activityPhotoStorage.js";
import { verifyAppleIdentityToken, revokeAppleAuthorization } from "../services/appleAuth.js";
import { issueSession, rotateSession, revokeRefreshToken, revokeSession } from "../services/authSessions.js";
import { Prisma } from "@prisma/client";

const router = new Hono<AppEnv>();

const sessionClient = z.object({ platform: z.enum(["ios", "android", "web"]), deviceLabel: z.string().trim().max(100).nullish() });

const gearItemSchema = z.object({
  id: z.string().uuid(),
  kind: z.literal("shoe"),
  purpose: z.enum(["dailyTrainer", "race", "trail", "recovery"]),
  name: z.string().max(100),
  brand: z.string().max(100),
  model: z.string().max(100),
  startedAt: z.string().datetime({ offset: true }),
  retiredAt: z.string().datetime({ offset: true }).nullable(),
  distanceLimitM: z.number().finite().min(0).max(2_000_000),
  notes: z.string().max(500),
}).strict();

const musicSelectionSchema = z.object({
  id: z.string().min(1).max(200),
  title: z.string().max(200),
  subtitle: z.string().max(300),
  category: z.enum(["songs", "albums", "playlists"]),
}).strict();

const preferencesSchema = z.object({
  schemaVersion: z.literal(1),
  measurementUnitSystem: z.enum(["metric", "imperial"]),
  temperatureUnit: z.enum(["celsius", "fahrenheit"]),
  voiceGuideEnabled: z.boolean(),
  appearanceMode: z.enum(["system", "light", "dark"]),
  guideSelection: z.object({
    coachPersonaId: z.string().min(1).max(100),
    voiceProfileId: z.string().min(1).max(100),
    theme: z.enum(["victoryGold", "indigo", "ocean", "forest", "rose", "aurora", "electricLime", "neonPulse"]),
    intensity: z.enum(["calm", "balanced", "driven"]),
    nudgeFrequency: z.enum(["low", "normal", "high"]),
    coachingContract: z.enum(["quiet", "responsive", "coach_me"]),
  }).strict(),
  shoes: z.array(gearItemSchema).max(50),
  defaultShoeId: z.string().uuid().nullable(),
  music: z.object({
    selectedQuickPickId: z.string().min(1).max(200).nullable(),
    selectedCustomItems: z.array(musicSelectionSchema).max(100),
    isDisabled: z.boolean(),
    repeatsQueue: z.boolean(),
    shufflesQueue: z.boolean(),
  }).strict(),
  preferredSessionPage: z.enum(["map", "camera"]),
  preferredLaunchGoalMode: z.string().max(32).nullable(),
}).strict();

router.post("/apple", zValidator("json", sessionClient.extend({
  identityToken: z.string().min(1), authorizationCode: z.string().min(1), rawNonce: z.string().min(16).max(256),
  givenName: z.string().trim().max(100).nullish(), familyName: z.string().trim().max(100).nullish(),
})), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const body = c.req.valid("json");
  try {
    const claims = await verifyAppleIdentityToken(body.identityToken, body.rawNonce);
    const displayName = [body.givenName, body.familyName].filter(Boolean).join(" ") || null;
    const user = await resolveAuthenticatedAppUser({ subject: claims.sub, authenticationKind: "provider", provider: "apple",
      providerSubject: claims.sub, internalUserId: null, sessionId: null, email: claims.email ?? null,
      emails: claims.email ? [claims.email] : [], emailVerified: claims.email_verified === true || claims.email_verified === "true",
      name: displayName, picture: null, phoneNumber: null, phoneNumbers: [] });
    if (!user) throw new Error("authentication_unavailable");
    return c.json(await issueSession(user, body.platform, body.deviceLabel));
  } catch (error) { return authError(c, error); }
});

router.post("/refresh", zValidator("json", z.object({ refreshToken: z.string().min(32) })), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  try {
    const session = await rotateSession(c.req.valid("json").refreshToken);
    if (session.refreshRecovery) console.warn("[auth] refresh rotation race recovered", { code: "refresh_rotation_race_recovered" });
    return c.json(session);
  }
  catch { return c.json({ error: "Authentication required.", code: "invalid_refresh_token" }, 401); }
});

router.post("/logout", zValidator("json", z.object({ refreshToken: z.string().min(32).optional() })), async (c) => {
  const auth = getAuthenticatedIdentity(c); const body = c.req.valid("json");
  if (auth?.sessionId) await revokeSession(auth.sessionId); else if (body.refreshToken) await revokeRefreshToken(body.refreshToken);
  return c.json({ loggedOut: true });
});

router.post("/debug/persona", zValidator("json", sessionClient.extend({ persona: z.enum(["new", "active", "social"]) })), async (c) => {
  if (process.env.NODE_ENV === "production" || process.env.AUTH_ENABLE_DEBUG_PERSONAS !== "true") return c.json({ error: "Not found." }, 404);
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const body = c.req.valid("json"); const email = `${body.persona}-runner@plainstride.test`;
  const user = await resolveAuthenticatedAppUser({ subject: `debug:${body.persona}`, authenticationKind: "provider", provider: "firebase",
    providerSubject: `debug:${body.persona}`, internalUserId: null, sessionId: null, email, emails: [email], emailVerified: true,
    name: `${body.persona[0]!.toUpperCase()}${body.persona.slice(1)} Runner`, picture: null, phoneNumber: null, phoneNumbers: [] });
  if (!user) return c.json({ error: "Authentication unavailable." }, 503);
  return c.json(await issueSession(user, body.platform, body.deviceLabel));
});

router.get("/avatars/:userId", async (c) => {
  try {
    const url = await signedAvatarURL(c.req.param("userId"));
    if (!url) return c.json({ error: "Avatar not found." }, 404);
    return c.redirect(url, 302);
  } catch (error) {
    console.error("[avatar] read failed", error);
    return c.json({ error: "Avatar is unavailable." }, 503);
  }
});

// Called after Firebase Auth sign-up to create or attach the app user record.
router.post(
  "/register",
  zValidator(
    "json",
    z.object({
      username: z.string().min(3).max(30),
      displayName: z.string().min(1).max(50),
    })
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;

    const auth = getAuthenticatedIdentity(c);
    if (!auth) {
      return c.json({ error: "Authentication required." }, 401);
    }

    const body = c.req.valid("json");
    const user = await getAuthenticatedAppUser(c, {
      username: body.username,
      displayName: body.displayName,
    });
    return c.json(user, 201);
  }
);

router.get("/me", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const auth = getAuthenticatedIdentity(c);
  if (!auth) {
    return c.json({ error: "Authentication required." }, 401);
  }

  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);
  if (!user) {
    return c.json({ error: "Authenticated user has not been registered yet." }, 404);
  }

  const userWithProfile = await prisma.user.findUnique({
    where: { id: user.id },
    include: { guideProfile: true },
  });
  if (!userWithProfile) {
    return c.json({ error: "Authenticated user has not been registered yet." }, 404);
  }
  return c.json(userWithProfile);
});

router.get("/me/preferences", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required." }, 401);
  const preferences = await getPrismaClient().userPreferences.findUnique({
    where: { userId: user.id },
  });
  return c.json({
    contractVersion: 1,
    preferences: preferences?.data ?? null,
    updatedAt: preferences?.updatedAt.toISOString() ?? null,
  });
});

router.put(
  "/me/preferences",
  zValidator("json", preferencesSchema),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;
    const user = await getAuthenticatedAppUser(c);
    if (!user) return c.json({ error: "Authentication required." }, 401);
    const data = c.req.valid("json");
    const preferences = await getPrismaClient().userPreferences.upsert({
      where: { userId: user.id },
      create: {
        userId: user.id,
        schemaVersion: data.schemaVersion,
        data: data as Prisma.InputJsonValue,
      },
      update: {
        schemaVersion: data.schemaVersion,
        data: data as Prisma.InputJsonValue,
      },
    });
    return c.json({
      contractVersion: 1,
      preferences: preferences.data,
      updatedAt: preferences.updatedAt.toISOString(),
    });
  }
);

router.patch(
  "/me",
  zValidator(
    "json",
    z.object({
      username: z.string().trim().min(3).max(30).regex(/^[a-zA-Z0-9_-]+$/).optional(),
      displayName: z.string().trim().min(1).max(50),
      bio: z.string().trim().max(160).nullish(),
      contactEmail: z.string().trim().email().max(254).nullish().or(z.literal("")),
      contactPhone: z.string().trim().min(7).max(30).nullish().or(z.literal("")),
    })
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;
    const user = await getAuthenticatedAppUser(c);
    if (!user) return c.json({ error: "Authentication required." }, 401);
    const body = c.req.valid("json");
    return c.json(await getPrismaClient().user.update({
      where: { id: user.id },
      data: {
        ...(body.username ? { username: body.username.toLowerCase() } : {}),
        displayName: body.displayName,
        bio: body.bio || null,
        contactEmail: body.contactEmail || null,
        contactPhone: body.contactPhone || null,
      },
    }));
  }
);

router.patch(
  "/me/avatar",
  zValidator(
    "json",
    z.object({
      base64: z.string().min(1).max(3_000_000),
      contentType: z.enum(["image/jpeg", "image/png"]),
    })
  ),
  async (c) => {
    const unavailable = requireDatabase(c);
    if (unavailable) return unavailable;
    const user = await getAuthenticatedAppUser(c);
    if (!user) return c.json({ error: "Authentication required." }, 401);
    const body = c.req.valid("json");
    const data = Buffer.from(body.base64, "base64");
    if (data.length === 0 || data.toString("base64").replace(/=+$/, "") !== body.base64.replace(/=+$/, "")) {
      return c.json({ error: "Avatar data is invalid." }, 400);
    }
    try {
      await saveAvatar(user.id, data, body.contentType);
      const origin = new URL(c.req.url).origin;
      const avatarUrl = `${origin}/v1/auth/avatars/${user.id}?v=${Date.now()}`;
      return c.json(await getPrismaClient().user.update({
        where: { id: user.id },
        data: { avatarUrl },
      }));
    } catch (error) {
      console.error("[avatar] upload failed", error);
      return c.json({ error: error instanceof Error ? error.message : "Avatar upload failed." }, 503);
    }
  }
);

router.delete("/me", zValidator("json", z.object({ identityToken: z.string().min(1), authorizationCode: z.string().min(1), rawNonce: z.string().min(16) })), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const auth = getAuthenticatedIdentity(c);
  if (!auth) {
    return c.json({ error: "Authentication required." }, 401);
  }

  const body = c.req.valid("json");
  let appleSubject: string;
  try { appleSubject = (await verifyAppleIdentityToken(body.identityToken, body.rawNonce)).sub; } catch (error) { return authError(c, error); }
  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);

  if (!user || !(await prisma.authIdentity.findFirst({ where: { userId: user.id, provider: "apple", providerSubject: appleSubject } }))) {
    return c.json({ error: "Recent Apple reauthorization is required.", code: "invalid_provider_credential" }, 401);
  }

  if (user) {
    try {
      await Promise.all([deleteAvatar(user.id), deleteUserActivityPhotos(user.id)]);
    } catch (error) {
      console.error("[user-media] cleanup failed", error);
    }
    await prisma.user.delete({ where: { id: user.id } });
  }

  let appleRevocationConfirmed = true;
  try { await revokeAppleAuthorization(body.authorizationCode); } catch { appleRevocationConfirmed = false; }
  if (auth.provider === "firebase") { try { await deleteFirebaseUser(auth.providerSubject); } catch { /* relational deletion remains final */ } }
  return c.json({ deleted: true, appleRevocationConfirmed });
});

function authError(c: any, error: unknown) {
  const code = error instanceof Error ? error.message : "authentication_unavailable";
  if (code === "invalid_provider_credential") {
    console.warn("[auth] request rejected", { code });
    return c.json({ error: "The provider credential is invalid.", code }, 401);
  }
  if (code === "provider_unavailable" || code === "authentication_unavailable") {
    console.warn("[auth] request rejected", { code });
    return c.json({ error: "Authentication is temporarily unavailable.", code }, 503);
  }
  console.error("[auth] unexpected authentication failure", error);
  return c.json({ error: "Authentication is temporarily unavailable.", code: "authentication_unavailable" }, 503);
}

export default router;
