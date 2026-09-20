-- Server-owned trusted contacts, per docs/backend-architecture.md. One row per
-- marked trusted connection; the contact must be an accepted connection user.
CREATE TABLE "SafetyTrustedContact" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "contactId" TEXT NOT NULL,
    "isDefault" BOOLEAN NOT NULL DEFAULT false,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SafetyTrustedContact_pkey" PRIMARY KEY ("id")
);

CREATE UNIQUE INDEX "SafetyTrustedContact_userId_contactId_key" ON "SafetyTrustedContact"("userId", "contactId");
CREATE INDEX "SafetyTrustedContact_userId_createdAt_idx" ON "SafetyTrustedContact"("userId", "createdAt");

ALTER TABLE "SafetyTrustedContact" ADD CONSTRAINT "SafetyTrustedContact_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
ALTER TABLE "SafetyTrustedContact" ADD CONSTRAINT "SafetyTrustedContact_contactId_fkey" FOREIGN KEY ("contactId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
