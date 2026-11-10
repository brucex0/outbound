-- AlterTable
ALTER TABLE "WorkoutCompletion" ADD COLUMN     "workoutEditId" TEXT,
ADD COLUMN     "workoutRevision" TEXT;

-- CreateTable
CREATE TABLE "WorkoutEdit" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "validForDate" TEXT NOT NULL,
    "plannedWorkoutId" TEXT,
    "suggestionId" TEXT NOT NULL,
    "operation" TEXT NOT NULL,
    "reason" TEXT,
    "idempotencyKey" TEXT NOT NULL,
    "requestHash" TEXT NOT NULL,
    "baseRevision" TEXT NOT NULL,
    "resultRevision" TEXT NOT NULL,
    "beforeWorkout" JSONB NOT NULL,
    "afterWorkout" JSONB NOT NULL,
    "validationContext" JSONB NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WorkoutEdit_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "WorkoutEdit_userId_validForDate_createdAt_idx" ON "WorkoutEdit"("userId", "validForDate", "createdAt");

-- CreateIndex
CREATE UNIQUE INDEX "WorkoutEdit_userId_idempotencyKey_key" ON "WorkoutEdit"("userId", "idempotencyKey");

-- AddForeignKey
ALTER TABLE "WorkoutEdit" ADD CONSTRAINT "WorkoutEdit_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkoutEdit" ADD CONSTRAINT "WorkoutEdit_plannedWorkoutId_fkey" FOREIGN KEY ("plannedWorkoutId") REFERENCES "PlannedWorkout"("id") ON DELETE SET NULL ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "WorkoutCompletion" ADD CONSTRAINT "WorkoutCompletion_workoutEditId_fkey" FOREIGN KEY ("workoutEditId") REFERENCES "WorkoutEdit"("id") ON DELETE SET NULL ON UPDATE CASCADE;
