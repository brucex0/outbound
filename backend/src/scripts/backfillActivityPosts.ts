import { PrismaClient } from "@prisma/client";

const prisma = new PrismaClient();

export async function backfillActivityPosts(client: PrismaClient = prisma) {
  const activities = await client.activity.findMany({
    where: {
      deletedAt: null,
      socialSharingInitializedAt: null,
    },
    select: { id: true, userId: true, posts: { select: { id: true }, take: 1 } },
    orderBy: { createdAt: "asc" },
  });

  if (!activities.length) return { createdCount: 0 };

  const unpublishedActivities = activities.filter((activity) => activity.posts.length === 0);
  const result = await client.$transaction(async (transaction) => {
    const created = unpublishedActivities.length
      ? await transaction.post.createMany({
          data: unpublishedActivities.map((activity) => ({
            userId: activity.userId,
            activityId: activity.id,
            visibility: "connections",
          })),
        })
      : { count: 0 };
    await transaction.activity.updateMany({
      where: { id: { in: activities.map((activity) => activity.id) } },
      data: { socialSharingInitializedAt: new Date() },
    });
    return created;
  });

  return { createdCount: result.count };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  try {
    const result = await backfillActivityPosts();
    console.log(`[backfill] Created ${result.createdCount} connection-visible activity posts.`);
  } finally {
    await prisma.$disconnect();
  }
}
