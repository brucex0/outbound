-- Route payloads are now stored independently from activity metadata.
-- The initial blob contains the old JSON text so the application migration can
-- canonicalize it with the versioned binary codec without losing data.
ALTER TABLE "Activity" ADD COLUMN "routeBlob" BYTEA;
ALTER TABLE "Activity" ADD COLUMN "routeMetadata" JSONB;
UPDATE "Activity"
SET "routeBlob" = convert_to("route"::text, 'UTF8')
WHERE "route" IS NOT NULL;
ALTER TABLE "Activity" DROP COLUMN "route";
