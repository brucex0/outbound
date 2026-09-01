import type { User } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";

// Increment with the iOS constant whenever a material update requires reacceptance.
export const CURRENT_TERMS_VERSION = 1;
export const CURRENT_TERMS_EFFECTIVE_DATE = "August 31, 2026";

export async function acceptCurrentTerms(user: User, version: number): Promise<User> {
  if (version !== CURRENT_TERMS_VERSION) throw new Error("terms_version_outdated");
  if (user.termsAcceptedVersion === version && user.termsAcceptedAt) return user;

  return getPrismaClient().user.update({
    where: { id: user.id },
    data: {
      termsAcceptedVersion: version,
      termsAcceptedAt: new Date(),
    },
  });
}
