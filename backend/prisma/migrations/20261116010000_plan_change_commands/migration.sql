CREATE TABLE "PlanChangeCommand" (
 "id" TEXT NOT NULL, "userId" TEXT NOT NULL, "planId" TEXT NOT NULL,
 "idempotencyKey" TEXT NOT NULL, "requestHash" TEXT NOT NULL, "operation" TEXT NOT NULL,
 "reason" TEXT, "baseRevision" TEXT NOT NULL, "resultRevision" TEXT,
 "validForDate" TEXT NOT NULL, "expiresAt" TIMESTAMP(3) NOT NULL,
 "before" JSONB NOT NULL, "after" JSONB NOT NULL,
 "appliedAt" TIMESTAMP(3), "undoneAt" TIMESTAMP(3), "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
 CONSTRAINT "PlanChangeCommand_pkey" PRIMARY KEY ("id"),
 CONSTRAINT "PlanChangeCommand_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE
);
CREATE UNIQUE INDEX "PlanChangeCommand_userId_idempotencyKey_key" ON "PlanChangeCommand"("userId", "idempotencyKey");
CREATE INDEX "PlanChangeCommand_userId_planId_createdAt_idx" ON "PlanChangeCommand"("userId", "planId", "createdAt");
