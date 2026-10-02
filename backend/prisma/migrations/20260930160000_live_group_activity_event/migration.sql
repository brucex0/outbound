ALTER TABLE "LiveGroupSession"
ADD COLUMN "activityEventId" TEXT;

CREATE UNIQUE INDEX "LiveGroupSession_activityEventId_key"
ON "LiveGroupSession"("activityEventId");

ALTER TABLE "LiveGroupSession"
ADD CONSTRAINT "LiveGroupSession_activityEventId_fkey"
FOREIGN KEY ("activityEventId") REFERENCES "ActivityEvent"("id")
ON DELETE CASCADE ON UPDATE CASCADE;
