import { Hono } from "hono";
import { PrismaClient } from "@prisma/client";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";

const router = new Hono();
const prisma = new PrismaClient();

// Called after Firebase Auth sign-up to create the user record
router.post(
  "/register",
  zValidator(
    "json",
    z.object({
      firebaseUid: z.string(),
      username: z.string().min(3).max(30),
      displayName: z.string().min(1).max(50),
    })
  ),
  async (c) => {
    const body = c.req.valid("json");
    const existing = await prisma.user.findUnique({
      where: { firebaseUid: body.firebaseUid },
    });
    if (existing) return c.json(existing);
    const user = await prisma.user.create({ data: body });
    return c.json(user, 201);
  }
);

router.get("/me/:firebaseUid", async (c) => {
  const user = await prisma.user.findUnique({
    where: { firebaseUid: c.req.param("firebaseUid") },
    include: { coachProfile: true },
  });
  if (!user) return c.json({ error: "Not found" }, 404);
  return c.json(user);
});

export default router;
