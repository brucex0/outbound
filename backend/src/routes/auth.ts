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
import { verifyGoogleIdentityToken } from "../services/googleAuth.js";
import { issueSession, rotateSession, revokeRefreshToken, revokeSession } from "../services/authSessions.js";
import { Prisma } from "@prisma/client";
import { acceptCurrentTerms, CURRENT_TERMS_VERSION } from "../services/legal.js";
import { changeUsername, UsernameChangeError } from "../services/usernames.js";
import { consumeGoogleIdentityLinkIntent, createIdentityLinkIntent, IdentityLinkIntentError } from "../services/identityLinkIntents.js";

const router = new Hono<AppEnv>();

const sessionClient = z.object({
  platform: z.enum(["ios", "android", "web"]),
  deviceLabel: z.string().trim().max(100).nullish(),
  termsVersion: z.number().int().positive(),
});

const googleCredential = z.object({ identityToken: z.string().min(1) });

const gearItemSchema = z.object({
  id: z.string().uuid(),
  kind: z.literal("shoe"),
  purpose: z.enum(["dailyTrainer", "race", "trail", "recovery"]),
  name: z.string().max(100),
  brand: z.string().max(100),
  model: z.string().max(100),
  startedAt: z.string().datetime({ offset: true }),
  retiredAt: z.string().datetime({ offset: true }).nullable().default(null),
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
  defaultShoeId: z.string().uuid().nullable().default(null),
  music: z.object({
    selectedQuickPickId: z.string().min(1).max(200).nullable().default(null),
    selectedCustomItems: z.array(musicSelectionSchema).max(100),
    isDisabled: z.boolean(),
    repeatsQueue: z.boolean(),
    shufflesQueue: z.boolean(),
  }).strict(),
  preferredSessionPage: z.enum(["map", "camera"]),
  preferredLaunchGoalMode: z.string().max(32).nullable().default(null),
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
    const acceptedUser = body.termsVersion === CURRENT_TERMS_VERSION
      ? await acceptCurrentTerms(user, body.termsVersion)
      : user;
    if (body.termsVersion < CURRENT_TERMS_VERSION) {
      console.info("[auth] authenticated client requires terms reacceptance", {
        code: "terms_reacceptance_required",
        presentedTermsVersion: body.termsVersion,
        currentTermsVersion: CURRENT_TERMS_VERSION,
        provider: "apple",
      });
    }
    return c.json(await issueSession(acceptedUser, body.platform, body.deviceLabel));
  } catch (error) { return authError(c, error); }
});

router.post("/google", zValidator("json", sessionClient.extend(googleCredential.shape).strict()), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const body = c.req.valid("json");
  try {
    const claims = await verifyGoogleIdentityToken(body.identityToken);
    const user = await resolveAuthenticatedAppUser({
      subject: claims.sub,
      authenticationKind: "provider",
      provider: "google",
      providerSubject: claims.sub,
      internalUserId: null,
      sessionId: null,
      email: claims.email ?? null,
      emails: claims.email ? [claims.email] : [],
      emailVerified: claims.email_verified === true,
      name: claims.name ?? null,
      picture: claims.picture ?? null,
      phoneNumber: null,
      phoneNumbers: [],
    });
    if (!user) throw new Error("authentication_unavailable");
    const acceptedUser = body.termsVersion === CURRENT_TERMS_VERSION
      ? await acceptCurrentTerms(user, body.termsVersion)
      : user;
    if (body.termsVersion < CURRENT_TERMS_VERSION) {
      console.info("[auth] authenticated client requires terms reacceptance", {
        code: "terms_reacceptance_required",
        presentedTermsVersion: body.termsVersion,
        currentTermsVersion: CURRENT_TERMS_VERSION,
        provider: "google",
      });
    }
    return c.json(await issueSession(acceptedUser, body.platform, body.deviceLabel));
  } catch (error) { return authError(c, error); }
});

router.post("/link/google", zValidator("json", googleCredential.strict()), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  try {
    const claims = await verifyGoogleIdentityToken(c.req.valid("json").identityToken);
    const normalizedEmail = claims.email?.trim().toLowerCase() || null;
    const identity = await getPrismaClient().$transaction(async (tx) => {
      const existing = await tx.authIdentity.findUnique({
        where: { provider_providerSubject: { provider: "google", providerSubject: claims.sub } },
      });
      if (existing && existing.userId !== user.id) throw new Error("provider_identity_in_use");
      return existing
        ? tx.authIdentity.update({ where: { id: existing.id }, data: {
          email: claims.email ?? null, normalizedEmail, emailVerified: claims.email_verified === true,
          displayName: claims.name ?? null,
        } })
        : tx.authIdentity.create({ data: {
          userId: user.id, provider: "google", providerSubject: claims.sub,
          email: claims.email ?? null, normalizedEmail, emailVerified: claims.email_verified === true,
          displayName: claims.name ?? null,
        } });
    }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
    return c.json({ linked: true, identity: { provider: identity.provider, email: identity.email } });
  } catch (error) {
    if (error instanceof Error && error.message === "provider_identity_in_use") {
      return c.json({ error: "That Google identity is already linked to another account.", code: error.message }, 409);
    }
    return authError(c, error);
  }
});

router.post("/link-intents", async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  return c.json(await createIdentityLinkIntent(user.id), 201);
});

router.post("/link-intents/redeem/google", zValidator("json", sessionClient.extend({
  ...googleCredential.shape,
  code: z.string().trim().min(16).max(32),
}).strict()), async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const body = c.req.valid("json");
  try {
    const claims = await verifyGoogleIdentityToken(body.identityToken);
    const user = await consumeGoogleIdentityLinkIntent({
      code: body.code, providerSubject: claims.sub, email: claims.email ?? null,
      emailVerified: claims.email_verified === true, displayName: claims.name ?? null,
    });
    const acceptedUser = body.termsVersion === CURRENT_TERMS_VERSION
      ? await acceptCurrentTerms(user, body.termsVersion)
      : user;
    return c.json(await issueSession(acceptedUser, body.platform, body.deviceLabel));
  } catch (error) {
    if (error instanceof IdentityLinkIntentError) {
      const message = error.code === "provider_identity_in_use"
        ? "That Google identity is already linked to another account."
        : "That transfer code is invalid or expired.";
      return c.json({ error: message, code: error.code }, error.code === "provider_identity_in_use" ? 409 : 401);
    }
    return authError(c, error);
  }
});

router.get("/me/identities", async (c) => {
  const unavailable = requireDatabase(c); if (unavailable) return unavailable;
  const user = await getAuthenticatedAppUser(c);
  if (!user) return c.json({ error: "Authentication required.", code: "authentication_required" }, 401);
  const identities = await getPrismaClient().authIdentity.findMany({
    where: { userId: user.id },
    select: { provider: true, email: true, createdAt: true },
    orderBy: { createdAt: "asc" },
  });
  return c.json({ identities: identities.map((identity) => ({
    provider: identity.provider,
    email: identity.email,
    linkedAt: identity.createdAt.toISOString(),
  })) });
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
  const acceptedUser = body.termsVersion === CURRENT_TERMS_VERSION
    ? await acceptCurrentTerms(user, body.termsVersion)
    : user;
  if (body.termsVersion < CURRENT_TERMS_VERSION) {
    console.info("[auth] authenticated client requires terms reacceptance", {
      code: "terms_reacceptance_required",
      presentedTermsVersion: body.termsVersion,
      currentTermsVersion: CURRENT_TERMS_VERSION,
      provider: "debug_persona",
    });
  }
  return c.json(await issueSession(acceptedUser, body.platform, body.deviceLabel));
});

router.post(
  "/terms/accept",
  zValidator("json", z.object({ termsVersion: z.number().int().positive() }).strict()),
  async (c) => {
    const unavailable = requireDatabase(c); if (unavailable) return unavailable;
    const user = await getAuthenticatedAppUser(c);
    if (!user) return c.json({ error: "Authentication required." }, 401);
    const version = c.req.valid("json").termsVersion;
    if (version !== CURRENT_TERMS_VERSION) return termsVersionError(c);
    const acceptedUser = await acceptCurrentTerms(user, version);
    return c.json({ termsVersion: acceptedUser.termsAcceptedVersion, acceptedAt: acceptedUser.termsAcceptedAt });
  },
);

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
    include: {
      guideProfile: true,
      runnerProfile: { select: { completedAt: true } },
    },
  });
  if (!userWithProfile) {
    return c.json({ error: "Authenticated user has not been registered yet." }, 404);
  }
  const { runnerProfile, ...account } = userWithProfile;
  return c.json({
    ...account,
    onboardingCompleted: runnerProfile?.completedAt != null,
  });
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
    try {
      const updated = await getPrismaClient().$transaction(async (tx) => {
        const usernameChange = body.username ? await changeUsername(tx, user, body.username) : null;
        return tx.user.update({
          where: { id: user.id },
          data: {
            ...(usernameChange ?? {}),
            displayName: body.displayName,
            bio: body.bio || null,
            contactEmail: body.contactEmail || null,
            contactPhone: body.contactPhone || null,
          },
        });
      }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
      return c.json(updated);
    } catch (error) {
      if (error instanceof UsernameChangeError) {
        const message = error.code === "username_taken"
          ? "That username is already taken."
          : error.code === "username_reserved"
            ? "That username is reserved."
            : "You can change your username once every 30 days.";
        return c.json({ error: message, code: error.code, retryAt: error.retryAt?.toISOString() }, 409);
      }
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === "P2002") {
        return c.json({ error: "That username is already taken.", code: "username_taken" }, 409);
      }
      throw error;
    }
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
      const requestURL = new URL(c.req.url);
      const forwardedProtocol = c.req.header("x-forwarded-proto")?.split(",", 1)[0]?.trim();
      if (forwardedProtocol === "http" || forwardedProtocol === "https") {
        requestURL.protocol = `${forwardedProtocol}:`;
      }
      const origin = requestURL.origin;
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

const appleDeletionCredential = z.object({
  provider: z.literal("apple").optional(), identityToken: z.string().min(1), authorizationCode: z.string().min(1), rawNonce: z.string().min(16),
}).strict();
const googleDeletionCredential = googleCredential.extend({ provider: z.literal("google") }).strict();

router.delete("/me", zValidator("json", z.union([googleDeletionCredential, appleDeletionCredential])), async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const auth = getAuthenticatedIdentity(c);
  if (!auth) {
    return c.json({ error: "Authentication required." }, 401);
  }

  const body = c.req.valid("json");
  const provider = body.provider === "google" ? "google" : "apple";
  let providerSubject: string;
  try {
    if (body.provider === "google") {
      providerSubject = (await verifyGoogleIdentityToken(body.identityToken)).sub;
    } else {
      providerSubject = (await verifyAppleIdentityToken(body.identityToken, body.rawNonce)).sub;
    }
  } catch (error) { return authError(c, error); }
  const prisma = getPrismaClient();
  const user = await getAuthenticatedAppUser(c);

  if (!user || !(await prisma.authIdentity.findFirst({ where: { userId: user.id, provider, providerSubject } }))) {
    return c.json({ error: "Recent provider reauthorization is required.", code: "invalid_provider_credential" }, 401);
  }

  if (user) {
    try {
      await Promise.all([deleteAvatar(user.id), deleteUserActivityPhotos(user.id)]);
    } catch (error) {
      console.error("[user-media] cleanup failed", error);
    }
    await prisma.user.delete({ where: { id: user.id } });
  }

  let appleRevocationConfirmed: boolean | null = null;
  if (body.provider !== "google") {
    appleRevocationConfirmed = true;
    try { await revokeAppleAuthorization(body.authorizationCode); } catch { appleRevocationConfirmed = false; }
  }
  if (auth.provider === "firebase") { try { await deleteFirebaseUser(auth.providerSubject); } catch { /* relational deletion remains final */ } }
  return c.json({
    deleted: true,
    provider,
    providerRevocationConfirmed: appleRevocationConfirmed,
    appleRevocationConfirmed,
  });
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

function termsVersionError(c: any) {
  return c.json({
    error: "Please update Plainstride to review the current Terms of Service.",
    code: "terms_version_outdated",
    currentTermsVersion: CURRENT_TERMS_VERSION,
  }, 409);
}

export default router;
