import { getPrismaClient } from "../services/prisma.js";
import { entitlementCodeDigest, generateEntitlementCode } from "../services/entitlements.js";

const label = process.argv[2]?.trim();
const durationDays = Number(process.argv[3] ?? 90);
const maxRedemptions = Number(process.argv[4] ?? 1);
if (!label || !Number.isInteger(durationDays) || durationDays < 1 || !Number.isInteger(maxRedemptions) || maxRedemptions < 1) {
  throw new Error("Usage: npm run rewards:issue-code -- <label> [durationDays] [maxRedemptions]");
}
const code = generateEntitlementCode();
await getPrismaClient().entitlementCode.create({ data: {
  codeDigest: entitlementCodeDigest(code), label: label.slice(0, 100), durationDays, maxRedemptions,
} });
console.log(code);
await getPrismaClient().$disconnect();
