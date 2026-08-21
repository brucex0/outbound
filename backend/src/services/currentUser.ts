import type { Context } from "hono";
import { Prisma } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import type { AppEnv, AuthContext } from "../types/hono.js";

type RegistrationProfile = { username?: string; displayName?: string };

export function getAuthenticatedIdentity(c: Context<AppEnv>): AuthContext | null { return c.get("auth"); }

export async function getAuthenticatedAppUser(c: Context<AppEnv>, profile: RegistrationProfile = {}) {
  const auth = getAuthenticatedIdentity(c);
  return auth ? resolveAuthenticatedAppUser(auth, profile) : null;
}

export async function resolveAuthenticatedAppUser(auth: AuthContext, profile: RegistrationProfile = {}) {
  const prisma = getPrismaClient();
  if (auth.internalUserId) return prisma.user.findUnique({ where: { id: auth.internalUserId } });
  const normalizedEmail = auth.email?.trim().toLowerCase() || null;
  return prisma.$transaction(async (tx) => {
    const existing = await tx.authIdentity.findUnique({
      where: { provider_providerSubject: { provider: auth.provider, providerSubject: auth.providerSubject } },
      include: { user: true },
    });
    if (existing) {
      await tx.authIdentity.update({ where: { id: existing.id }, data: {
        email: auth.email, normalizedEmail, emailVerified: auth.emailVerified, displayName: auth.name,
      }});
      return existing.user;
    }
    const username = await uniqueUsername(tx, profile.username ?? auth.name ?? auth.email?.split("@")[0] ?? "runner");
    return tx.user.create({ data: {
      firebaseUid: auth.provider === "firebase" ? auth.providerSubject : null,
      normalizedEmail, username,
      displayName: (profile.displayName ?? auth.name ?? "Runner").trim().slice(0, 50) || "Runner",
      avatarUrl: auth.picture,
      authIdentities: { create: { provider: auth.provider, providerSubject: auth.providerSubject,
        email: auth.email, normalizedEmail, emailVerified: auth.emailVerified, displayName: auth.name } },
    }});
  }, { isolationLevel: Prisma.TransactionIsolationLevel.Serializable });
}

async function uniqueUsername(tx: Prisma.TransactionClient, proposed: string) {
  const base = proposed.toLowerCase().replace(/[^a-z0-9_]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 30) || "runner";
  if (!(await tx.user.findUnique({ where: { username: base } }))) return base;
  for (let suffix = 2; suffix < 10_000; suffix += 1) {
    const candidate = `${base.slice(0, 30 - String(suffix).length - 1)}-${suffix}`;
    if (!(await tx.user.findUnique({ where: { username: candidate } }))) return candidate;
  }
  return `runner-${crypto.randomUUID().slice(0, 8)}`;
}
