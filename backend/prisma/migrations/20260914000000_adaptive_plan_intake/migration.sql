ALTER TABLE "TrainingGoal"
ADD COLUMN "eventIntent" TEXT,
ADD COLUMN "targetTimeSeconds" INTEGER,
ADD COLUMN "reviewHorizonWeeks" INTEGER,
ADD COLUMN "successSignal" TEXT,
ADD COLUMN "goalDescription" TEXT,
ADD COLUMN "intakeContextVersion" TEXT;
