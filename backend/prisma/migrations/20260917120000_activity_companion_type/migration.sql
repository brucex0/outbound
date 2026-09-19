-- Optional dog-companion activity context. Null means no companion context;
-- historical rows are intentionally not backfilled.
ALTER TABLE "Activity" ADD COLUMN "companionType" TEXT;
