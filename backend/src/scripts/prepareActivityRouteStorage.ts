import { PrismaClient } from "@prisma/client";
import { decodeStoredActivityRoute, encodeActivityRoute, legacyGeoJSONToRoute } from "../services/activityRouteCodec.js";

const prisma = new PrismaClient();

type ColumnRow = { column_name: string };
type LegacyRow = { id: string; route_json: string | null };
type BlobRow = { id: string; route_blob: Uint8Array | null; route_metadata: unknown };

async function hasColumn(name: string): Promise<boolean> {
  const rows = await prisma.$queryRaw<ColumnRow[]>`
    SELECT column_name
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'Activity' AND column_name = ${name}
  `;
  return rows.length > 0;
}

async function main() {
  const hasRoute = await hasColumn("route");
  let hasRouteBlob = await hasColumn("routeBlob");
  let hasRouteMetadata = await hasColumn("routeMetadata");

  if (hasRoute) {
    if (!hasRouteBlob) {
      await prisma.$executeRaw`ALTER TABLE "Activity" ADD COLUMN "routeBlob" BYTEA`;
      hasRouteBlob = true;
    }
    if (!hasRouteMetadata) {
      await prisma.$executeRaw`ALTER TABLE "Activity" ADD COLUMN "routeMetadata" JSONB`;
      hasRouteMetadata = true;
    }
    const rows = await prisma.$queryRaw<LegacyRow[]>`
      SELECT id, "route"::text AS route_json
      FROM "Activity"
      WHERE "route" IS NOT NULL AND "routeBlob" IS NULL
    `;
    let migrated = 0;
    for (const row of rows) {
      const route = legacyGeoJSONToRoute(JSON.parse(row.route_json ?? "null"));
      if (!route) throw new Error(`Unable to prepare legacy activity route ${row.id}.`);
      await prisma.$executeRaw`
        UPDATE "Activity"
        SET "routeBlob" = ${encodeActivityRoute(route.points)},
            "routeMetadata" = ${JSON.stringify(route.metadata)}::jsonb
        WHERE id = ${row.id}
      `;
      migrated += 1;
    }
    if (migrated > 0) console.log(`Prepared ${migrated} legacy activity route rows before schema push.`);
  }

  if (hasRouteBlob && hasRouteMetadata) {
    const rows = await prisma.$queryRaw<BlobRow[]>`
      SELECT id, "routeBlob" AS route_blob, "routeMetadata" AS route_metadata
      FROM "Activity" WHERE "routeBlob" IS NOT NULL
    `;
    let canonicalized = 0;
    for (const row of rows) {
      if (!row.route_blob) continue;
      const route = decodeStoredActivityRoute(row.route_blob, row.route_metadata);
      if (!route) continue;
      const encoded = encodeActivityRoute(route.points);
      if (Buffer.from(row.route_blob).equals(encoded)) continue;
      await prisma.$executeRaw`
        UPDATE "Activity"
        SET "routeBlob" = ${encoded},
            "routeMetadata" = ${JSON.stringify({ visibility: route.visibility, elevationMetadata: route.elevationMetadata })}::jsonb
        WHERE id = ${row.id}
      `;
      canonicalized += 1;
    }
    if (canonicalized > 0) console.log(`Canonicalized ${canonicalized} temporary activity route blobs.`);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
}).finally(async () => {
  await prisma.$disconnect();
});
