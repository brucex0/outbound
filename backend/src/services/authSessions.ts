import { createHash, randomBytes, randomUUID, timingSafeEqual } from "node:crypto";
import type { Prisma, User } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import { issueAccessToken } from "./accessTokens.js";
import { CURRENT_TERMS_VERSION } from "./legal.js";
import { compactAvatarURL } from "./apiAssetURLs.js";

const refreshLifetimeMs = 30 * 24 * 60 * 60 * 1000;
// Window in which a replay of the previous refresh token is treated as a
// recoverable rotation race instead of a token-family theft. Concurrent app
// surfaces (widget/audio extensions, the Watch bridge) can hold a snapshot
// for tens of seconds, so the grace must comfortably exceed a request burst,
// not just a single in-flight call.
const refreshRotationGraceMs = 10 * 60 * 1000;
export type SessionUser = Pick<User, "id" | "username" | "displayName" | "avatarUrl" | "normalizedEmail" | "termsAcceptedVersion" | "onboardingStatus">;

export async function issueSession(user: SessionUser, platform: string, deviceLabel?: string | null) {
  const prisma = getPrismaClient();
  const token = randomBytes(32).toString("base64url");
  const expiresAt = new Date(Date.now() + refreshLifetimeMs);
  const session = await prisma.authSession.create({ data: {
      userId: user.id, familyId: randomUUID(), refreshTokenHash: hash(token), platform,
      deviceLabel: deviceLabel?.trim().slice(0, 100) || null, expiresAt,
    }});
  return response(session.id, user, token, expiresAt, user.onboardingStatus);
}

export async function rotateSession(refreshToken: string) {
  const prisma = getPrismaClient();
  const tokenHash = hash(refreshToken);
  return prisma.$transaction(async (tx) => {
    const previous = await tx.authSession.findFirst({
      where: { previousRefreshTokenHash: tokenHash },
      include: { user: true },
    });
    if (previous) {
      const now = new Date();
      const isRecoverableRotationRace = !previous.revokedAt
        && previous.expiresAt > now
        && now.getTime() - previous.lastUsedAt.getTime() <= refreshRotationGraceMs;
      if (isRecoverableRotationRace) {
        const recoveryToken = randomBytes(32).toString("base64url");
        const recoverySession = await tx.authSession.create({ data: {
            userId: previous.userId,
            familyId: previous.familyId,
            refreshTokenHash: hash(recoveryToken),
            platform: previous.platform,
            deviceLabel: previous.deviceLabel,
            expiresAt: previous.expiresAt,
          }});
        return response(
          recoverySession.id,
          previous.user,
          recoveryToken,
          previous.expiresAt,
          previous.user.onboardingStatus,
          true,
        );
      }
      await tx.authSession.updateMany({ where: { familyId: previous.familyId }, data: { revokedAt: new Date() } });
      throw new Error("invalid_refresh_token");
    }
    const session = await tx.authSession.findUnique({ where: { refreshTokenHash: tokenHash }, include: { user: true } });
    if (!session || session.revokedAt || session.expiresAt <= new Date() || !safeEqual(session.refreshTokenHash, tokenHash)) throw new Error("invalid_refresh_token");
    const replacement = randomBytes(32).toString("base64url");
    await tx.authSession.update({ where: { id: session.id }, data: {
      previousRefreshTokenHash: session.refreshTokenHash, refreshTokenHash: hash(replacement), lastUsedAt: new Date(),
    }});
    return response(
      session.id,
      session.user,
      replacement,
      session.expiresAt,
      session.user.onboardingStatus,
    );
  }, { isolationLevel: "Serializable" as Prisma.TransactionIsolationLevel });
}

export async function revokeSession(sessionId: string) {
  await getPrismaClient().authSession.updateMany({ where: { id: sessionId }, data: { revokedAt: new Date() } });
}
export async function revokeRefreshToken(token: string) {
  await getPrismaClient().authSession.updateMany({ where: { refreshTokenHash: hash(token) }, data: { revokedAt: new Date() } });
}
function response(
  sessionId: string,
  user: SessionUser,
  refreshToken: string,
  refreshTokenExpiresAt: Date,
  onboardingStatus: string,
  refreshRecovery = false,
) {
  const access = issueAccessToken(user.id, sessionId);
  return { accessToken: access.token, accessTokenExpiresAt: access.expiresAt, refreshToken, refreshTokenExpiresAt, refreshRecovery,
    currentTermsVersion: CURRENT_TERMS_VERSION,
    user: {
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      avatarUrl: compactAvatarURL(user.avatarUrl),
      email: user.normalizedEmail,
      onboardingStatus,
      onboardingCompleted: onboardingStatus !== "pending",
      termsAcceptedVersion: user.termsAcceptedVersion,
    } };
}

function hash(value: string) { return createHash("sha256").update(value).digest("hex"); }
function safeEqual(a: string, b: string) { const aa = Buffer.from(a); const bb = Buffer.from(b); return aa.length === bb.length && timingSafeEqual(aa, bb); }
