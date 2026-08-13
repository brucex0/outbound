import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import {
  getAuthenticatedAppUser,
  getAuthenticatedIdentity,
} from "../services/currentUser.js";
import type { AppEnv } from "../types/hono.js";
import { deleteFirebaseUser } from "../services/firebaseAuth.js";
import { deleteAvatar, readAvatar, saveAvatar } from "../services/avatarStorage.js";
import { deleteUserActivityPhotos } from "../services/activityPhotoStorage.js";

const router = new Hono<AppEnv>();

router.get("/avatars/:userId", async (c) => {
  try {
    const avatar = await readAvatar(c.req.param("userId"));
    if (!avatar) return c.json({ error: "Avatar not found." }, 404);
    return new Response(new Uint8Array(avatar.data), {
      headers: {
        "Content-Type": avatar.contentType,
        "Cache-Control": "public, max-age=31536000, immutable",
      },
    });
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
    include: { coachProfile: true },
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
      data: { displayName: body.displayName, bio: body.bio || null },
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

router.delete("/me", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const auth = getAuthenticatedIdentity(c);
  if (!auth) {
    return c.json({ error: "Authentication required." }, 401);
  }

  const prisma = getPrismaClient();
  const user = await prisma.user.findFirst({
    where: {
      OR: [
        { firebaseUid: auth.firebaseUid },
        { authIdentities: { some: { firebaseUid: auth.firebaseUid } } },
      ],
    },
    select: { id: true },
  });

  if (user) {
    try {
      await Promise.all([deleteAvatar(user.id), deleteUserActivityPhotos(user.id)]);
    } catch (error) {
      console.error("[user-media] cleanup failed", error);
    }
    await prisma.user.delete({ where: { id: user.id } });
  }

  await deleteFirebaseUser(auth.firebaseUid);
  return c.json({ deleted: true });
});

router.get("/me/:firebaseUid", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const firebaseUid = c.req.param("firebaseUid");
  const user = await prisma.user.findFirst({
    where: {
      OR: [
        { firebaseUid },
        { authIdentities: { some: { firebaseUid } } },
      ],
    },
    include: { coachProfile: true },
  });
  if (!user) return c.json({ error: "Not found" }, 404);
  return c.json(user);
});

export default router;
