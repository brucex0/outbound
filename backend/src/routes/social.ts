import { Hono } from "hono";
import { PrismaClient } from "@prisma/client";
import { z } from "zod";
import { zValidator } from "@hono/zod-validator";

const router = new Hono();
const prisma = new PrismaClient();

// Feed: posts from users you follow
router.get("/feed/:userId", async (c) => {
  const { userId } = c.req.param();
  const limit = Number(c.req.query("limit") ?? 20);
  const following = await prisma.follow.findMany({ where: { followerId: userId } });
  const followingIds = following.map((f) => f.followingId);
  const posts = await prisma.post.findMany({
    where: { userId: { in: [...followingIds, userId] } },
    orderBy: { createdAt: "desc" },
    take: limit,
    include: { user: true, activity: { include: { photos: true } }, reactions: true },
  });
  return c.json(posts);
});

router.post(
  "/follow",
  zValidator("json", z.object({ followerId: z.string(), followingId: z.string() })),
  async (c) => {
    const body = c.req.valid("json");
    await prisma.follow.upsert({
      where: { followerId_followingId: body },
      create: body,
      update: {},
    });
    return c.json({ ok: true });
  }
);

router.delete("/follow/:followerId/:followingId", async (c) => {
  await prisma.follow.delete({
    where: {
      followerId_followingId: {
        followerId: c.req.param("followerId"),
        followingId: c.req.param("followingId"),
      },
    },
  });
  return c.json({ ok: true });
});

router.post(
  "/react",
  zValidator(
    "json",
    z.object({
      userId: z.string(),
      postId: z.string(),
      type: z.enum(["fire", "clap", "heart", "strong"]),
    })
  ),
  async (c) => {
    const body = c.req.valid("json");
    await prisma.reaction.upsert({
      where: { userId_postId: { userId: body.userId, postId: body.postId } },
      create: body,
      update: { type: body.type },
    });
    return c.json({ ok: true });
  }
);

export default router;
