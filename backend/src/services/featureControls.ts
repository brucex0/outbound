import type { Prisma, PrismaClient } from "@prisma/client";

export const PAYWALL_FEATURE_CONTROL = "paywall_enabled";

type DatabaseClient = PrismaClient | Prisma.TransactionClient;

export async function isPaywallEnabled(prisma: DatabaseClient): Promise<boolean> {
  const control = await prisma.featureControl.findUnique({
    where: { key: PAYWALL_FEATURE_CONTROL },
    select: { enabled: true },
  });
  return control?.enabled ?? false;
}

export async function featureControlSummary(prisma: DatabaseClient) {
  return { paywallEnabled: await isPaywallEnabled(prisma) };
}
