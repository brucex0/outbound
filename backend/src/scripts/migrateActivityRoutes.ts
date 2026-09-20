import { PrismaClient } from "@prisma/client";
import { decodeStoredActivityRoute, encodeActivityRoute, legacyGeoJSONToRoute } from "../services/activityRouteCodec.js";

const prisma = new PrismaClient();

async function main() {
  const activities = await prisma.activity.findMany({
    where: { routeBlob: { not: null } },
    select: { id: true, routeBlob: true, routeMetadata: true },
  });
  let migrated = 0;
  let skipped = 0;
  for (const activity of activities) {
    if (!activity.routeBlob) continue;
    try {
      const decoded = decodeStoredActivityRoute(activity.routeBlob, activity.routeMetadata);
      if (!decoded || decoded.points.length < 2) {
        skipped += 1;
        continue;
      }
      const payload = encodeActivityRoute(decoded.points);
      await prisma.activity.update({
        where: { id: activity.id },
        data: {
          routeBlob: payload,
          routeMetadata: {
            visibility: decoded.visibility,
            elevationMetadata: decoded.elevationMetadata,
          },
        },
      });
      migrated += 1;
    } catch (error) {
      console.error(`Unable to migrate activity route ${activity.id}`, error);
      skipped += 1;
    }
  }
  console.log(`Migrated ${migrated} activity routes; skipped ${skipped}.`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  await prisma.$disconnect();
});
