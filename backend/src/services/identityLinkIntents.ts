import { createHash, randomBytes } from "node:crypto";
import { Prisma } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";

const LINK_INTENT_LIFETIME_MS = 10 * 60 * 1_000;
const CODE_ALPHABET = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";

export class IdentityLinkIntentError extends Error {
  constructor(readonly code: "invalid_link_intent" | "provider_identity_in_use") { super(code); }
}

export async function createIdentityLinkIntent(userId: string) {
  const raw = randomBytes(16);
  const code = Array.from(raw, (byte) => CODE_ALPHABET[byte % CODE_ALPHABET.length]).join("");
  const expiresAt = new Date(Date.now() + LINK_INTENT_LIFETIME_MS);
  await getPrismaClient().$transaction(async (tx) => {
    await tx.identityLinkIntent.updateMany({ where: { userId, consumedAt: null }, data: { consumedAt: new Date() } });
    await tx.identityLinkIntent.create({ data: { userId, tokenHash: hash(code), expiresAt } });
  });
  return { code: formatCode(code), expiresAt: expiresAt.toISOString(),
    url: `https://plainstride.ai/account-link?code=${encodeURIComponent(formatCode(code))}` };
}

export async function consumeGoogleIdentityLinkIntent(input: {
  code: string; providerSubject: string; email: string | null; emailVerified: boolean; displayName: string | null;
}) {
  const normalizedCode = normalizeCode(input.code);
  if (normalizedCode.length !== 16) throw new IdentityLinkIntentError("invalid_link_intent");
  return getPrismaClient().$transaction(async (tx) => {
    const intent = await tx.identityLinkIntent.findUnique({ where: { tokenHash: hash(normalizedCode) } });
    if (!intent || intent.consumedAt || intent.expiresAt <= new Date()) throw new IdentityLinkIntentError("invalid_link_intent");
    const existing = await tx.authIdentity.findUnique({
      where: { provider_providerSubject: { provider: "google", providerSubject: input.providerSubject } },
    });
    if (existing && existing.userId !== intent.userId) throw new IdentityLinkIntentError("provider_identity_in_use");
    const identityData = { email: input.email, normalizedEmail: input.email?.trim().toLowerCase() || null,
      emailVerified: input.emailVerified, displayName: input.displayName };
    if (existing) await tx.authIdentity.update({ where: { id: existing.id }, data: identityData });
    else await tx.authIdentity.create({ data: { userId: intent.userId, provider: "google",
      providerSubject: input.providerSubject, ...identityData } });
    await tx.identityLinkIntent.update({ where: { id: intent.id }, data: { consumedAt: new Date() } });
    return tx.user.findUniqueOrThrow({ where: { id: intent.userId } });
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

function normalizeCode(value: string) { return value.toUpperCase().replace(/[^2-9A-Z]/g, ""); }
function formatCode(value: string) { return value.match(/.{1,4}/g)?.join("-") ?? value; }
function hash(value: string) { return createHash("sha256").update(normalizeCode(value)).digest("hex"); }
