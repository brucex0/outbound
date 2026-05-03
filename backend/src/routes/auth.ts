import { Hono } from "hono";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";
import { requireDatabase } from "../services/database.js";
import { getPrismaClient } from "../services/prisma.js";
import { getAuthenticatedIdentity } from "../services/currentUser.js";
import type { AppEnv } from "../types/hono.js";

const router = new Hono<AppEnv>();

// Called after Firebase Auth sign-up to create the user record
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

    const prisma = getPrismaClient();
    const auth = getAuthenticatedIdentity(c);
    if (!auth) {
      return c.json({ error: "Authentication required." }, 401);
    }

    const body = c.req.valid("json");
    const existing = await prisma.user.findUnique({
      where: { firebaseUid: auth.firebaseUid },
    });
    if (existing) return c.json(existing);
    const user = await prisma.user.create({
      data: {
        firebaseUid: auth.firebaseUid,
        username: body.username,
        displayName: body.displayName,
      },
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
  const user = await prisma.user.findUnique({
    where: { firebaseUid: auth.firebaseUid },
    include: { coachProfile: true },
  });
  if (!user) {
    return c.json({ error: "Authenticated user has not been registered yet." }, 404);
  }
  return c.json(user);
});

router.get("/me/:firebaseUid", async (c) => {
  const unavailable = requireDatabase(c);
  if (unavailable) return unavailable;

  const prisma = getPrismaClient();
  const user = await prisma.user.findUnique({
    where: { firebaseUid: c.req.param("firebaseUid") },
    include: { coachProfile: true },
  });
  if (!user) return c.json({ error: "Not found" }, 404);
  return c.json(user);
});

export default router;
