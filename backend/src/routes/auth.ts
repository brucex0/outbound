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

const router = new Hono<AppEnv>();

const sessionClient = z.object({ platform: z.enum(["ios", "android", "web"]), deviceLabel: z.string().trim().max(100).nullish() });

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
  try { return c.json(await rotateSession(c.req.valid("json").refreshToken)); }
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

router.patch(
  "/me",
  zValidator(
    "json",
    z.object({
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
  const status = code === "provider_unavailable" || code === "authentication_unavailable" ? 503 : 401;
  console.warn("[auth] request rejected", { code });
  return c.json({ error: status === 503 ? "Authentication is temporarily unavailable." : "The provider credential is invalid.", code }, status);
}

export default router;
