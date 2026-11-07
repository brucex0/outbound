import { Prisma } from "@prisma/client";

// Invitation admissions, join requests and series changes share a row lock. Reading or
// extending a schedule must not change Group.updatedAt or directory ordering.
export async function lockedGroup(db: Prisma.TransactionClient, groupId: string) {
  await db.$queryRaw(Prisma.sql`SELECT "id" FROM "SocialGroup" WHERE "id" = ${groupId} FOR UPDATE`);
  return db.socialGroup.findUniqueOrThrow({ where: { id: groupId } });
}

export function isRetryableGroupTransaction(error: unknown) {
  return error instanceof Prisma.PrismaClientKnownRequestError && (
    error.code === "P2034" || (error.code === "P2010" && ["40001", "40P01"].includes(String(error.meta?.code)))
  );
}
