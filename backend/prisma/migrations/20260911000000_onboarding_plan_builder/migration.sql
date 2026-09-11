ALTER TABLE "User"
ADD COLUMN "onboardingStatus" TEXT NOT NULL DEFAULT 'pending';

UPDATE "User" AS u
SET "onboardingStatus" = 'completed'
WHERE EXISTS (
  SELECT 1 FROM "RunnerProfile" AS rp
  WHERE rp."userId" = u.id AND rp."completedAt" IS NOT NULL
)
OR EXISTS (
  SELECT 1 FROM "TrainingPlan" AS tp
  WHERE tp."userId" = u.id
);

ALTER TABLE "TrainingGoal"
ADD COLUMN "supportingObjectives" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "supportingModalities" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN "baselineContext" TEXT NOT NULL DEFAULT 'currentlyActive',
ADD COLUMN "preferredLongSessionDay" TEXT;
