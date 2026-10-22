import { Prisma, PrismaClient } from "@prisma/client";
import { activityFact, identityColumns, STATISTICS_VERSION } from "../services/statistics/facts.js";
const prisma = new PrismaClient();
// Additive, restartable backfill. Never changes canonical activity timestamps or facts.
async function main() {
  let cursor: string | undefined, rebuilt = 0;
  for (;;) {
    const rows = await prisma.activity.findMany({ where: { deletedAt: null }, orderBy: { id: "asc" }, take: 100, ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}) });
    if (!rows.length) break;
    for (const row of rows) {
      if ((row.statisticsFacts as { version?: number } | null)?.version === STATISTICS_VERSION) continue;
      const fact = activityFact(row);
      const result = await prisma.activity.updateMany({ where: { id: row.id, updatedAt: row.updatedAt }, data: { statisticsFacts: fact as unknown as Prisma.InputJsonValue, ...identityColumns(fact), updatedAt: row.updatedAt } });
      rebuilt += result.count;
    }
    cursor = rows.at(-1)!.id;
    console.log(`[statistics] backfill batch completed rebuilt_bucket=${rebuilt > 1000 ? "1000_plus" : rebuilt > 100 ? "101_1000" : "0_100"}`);
  }
  console.log("[statistics] backfill completed");
}
main().catch(error => { console.error("[statistics] backfill failed", { category: error instanceof Error ? error.name : "unknown" }); process.exitCode = 1; }).finally(() => prisma.$disconnect());
