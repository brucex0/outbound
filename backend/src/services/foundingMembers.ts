import type { Prisma, PrismaClient } from "@prisma/client";

export const FOUNDING_ENTITLEMENT_SOURCE = "founding_beta_1000";
const DEFAULT_FOUNDING_USER_LIMIT = 1_000;

type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export async function isFoundingMember(
  prisma: DatabaseClient,
  userId: string,
  env: NodeJS.ProcessEnv = process.env,
): Promise<boolean> {
  const existing = await prisma.featureEntitlement.findFirst({
    where: {
      userId,
      source: FOUNDING_ENTITLEMENT_SOURCE,
      status: "active",
      expiresAt: null,
    },
    select: { id: true },
  });
  if (existing) return true;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, createdAt: true },
  });
  if (!user) return false;

  const configuredLimit = Number(env.LIVE_COACH_FOUNDING_USER_LIMIT);
  const limit = Number.isSafeInteger(configuredLimit) && configuredLimit > 0
    ? configuredLimit
    : DEFAULT_FOUNDING_USER_LIMIT;
  const ordinal = await prisma.user.count({
    where: { OR: [
      { createdAt: { lt: user.createdAt } },
      { createdAt: user.createdAt, id: { lte: user.id } },
    ] },
  });
  return ordinal <= limit;
}
