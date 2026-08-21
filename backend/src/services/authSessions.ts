import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import type { Prisma, User } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import { issueAccessToken } from "./accessTokens.js";

const refreshLifetimeMs = 30 * 24 * 60 * 60 * 1000;
export type SessionUser = Pick<User, "id" | "username" | "displayName" | "avatarUrl" | "normalizedEmail">;

export async function issueSession(user: SessionUser, platform: string, deviceLabel?: string | null) {
  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + refreshLifetimeMs);
  const session = await getPrismaClient().authSession.create({ data: {
    userId: user.id, familyId: randomUUID(), refreshTokenHash: hash(token), platform,
    deviceLabel: deviceLabel?.trim().slice(0, 100) || null, expiresAt,
  }});
  return response(session.id, user, token, expiresAt);
}

export async function rotateSession(refreshToken: string) {
  const prisma = getPrismaClient();
  const tokenHash = hash(refreshToken);
  return prisma.$transaction(async (tx) => {
    const previous = await tx.authSession.findFirst({ where: { previousRefreshTokenHash: tokenHash } });
    if (previous) {
      await tx.authSession.updateMany({ where: { familyId: previous.familyId }, data: { revokedAt: new Date() } });
      throw new Error("invalid_refresh_token");
    }
    const session = await tx.authSession.findUnique({ where: { refreshTokenHash: tokenHash }, include: { user: true } });
    if (!session || session.revokedAt || session.expiresAt <= new Date() || !safeEqual(session.refreshTokenHash, tokenHash)) throw new Error("invalid_refresh_token");
    const replacement = randomBytes(32).toString("base64url");
    await tx.authSession.update({ where: { id: session.id }, data: {
      previousRefreshTokenHash: session.refreshTokenHash, refreshTokenHash: hash(replacement), lastUsedAt: new Date(),
    }});
    return response(session.id, session.user, replacement, session.expiresAt);
  }, { isolationLevel: "Serializable" as Prisma.TransactionIsolationLevel });
}

export async function revokeSession(sessionId: string) {
  await getPrismaClient().authSession.updateMany({ where: { id: sessionId }, data: { revokedAt: new Date() } });
}
export async function revokeRefreshToken(token: string) {
  await getPrismaClient().authSession.updateMany({ where: { refreshTokenHash: hash(token) }, data: { revokedAt: new Date() } });
}
function response(sessionId: string, user: SessionUser, refreshToken: string, refreshTokenExpiresAt: Date) {
  const access = issueAccessToken(user.id, sessionId);
  return { accessToken: access.token, accessTokenExpiresAt: access.expiresAt, refreshToken, refreshTokenExpiresAt,
    user: { id: user.id, username: user.username, displayName: user.displayName, avatarUrl: user.avatarUrl, email: user.normalizedEmail } };
}
function hash(value: string) { return createHash("sha256").update(value).digest("hex"); }
function safeEqual(a: string, b: string) { const aa = Buffer.from(a); const bb = Buffer.from(b); return aa.length === bb.length && timingSafeEqual(aa, bb); }
