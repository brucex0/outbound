ALTER TABLE "TrainingGoal"
ADD COLUMN "activities" TEXT[] NOT NULL DEFAULT ARRAY['run']::TEXT[];

UPDATE "TrainingGoal"
SET "activities" = ARRAY["primaryModality"] || "supportingModalities";

ALTER TABLE "TrainingGoal"
DROP COLUMN "supportingObjectives",
DROP COLUMN "primaryModality",
DROP COLUMN "supportingModalities";
