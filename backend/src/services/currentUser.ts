import type { Context } from "hono";
import { Prisma, type User } from "@prisma/client";
import { getPrismaClient } from "./prisma.js";
import type { AppEnv, AuthContext } from "../types/hono.js";

type RegistrationProfile = {
  username?: string;
  displayName?: string;
};

export function getAuthenticatedIdentity(c: Context<AppEnv>): AuthContext | null {
  return c.get("auth");
}

export async function getAuthenticatedAppUser(
  c: Context<AppEnv>,
  profile: RegistrationProfile = {}
) {
  const auth = getAuthenticatedIdentity(c);
  if (!auth) {
    return null;
  }

  return resolveAuthenticatedAppUser(auth, profile);
}

export async function resolveAuthenticatedAppUser(
  auth: AuthContext,
  profile: RegistrationProfile = {}
) {
  const prisma = getPrismaClient();
  const normalizedEmails = normalizedEmailsForAuth(auth);
  const normalizedPhones = normalizedPhonesForAuth(auth, normalizedEmails);
  const primaryEmail = normalizedEmails[0] ?? null;
  const primaryPhone = normalizedPhones[0] ?? null;

  return prisma.$transaction(async (tx) => {
    const identity = await tx.authIdentity.findUnique({
      where: { firebaseUid: auth.firebaseUid },
      include: { user: true },
    });

    if (identity) {
      const user = await tx.user.update({
        where: { id: identity.userId },
        data: updateDataForExistingUser(identity.user, auth, profile, primaryEmail, primaryPhone),
      });
      await tx.authIdentity.update({
        where: { firebaseUid: auth.firebaseUid },
        data: identityDataForAuth(auth, primaryEmail, primaryPhone),
      });
      return user;
    }

    const user =
      (await tx.user.findUnique({ where: { firebaseUid: auth.firebaseUid } })) ??
      (await findUserByNormalizedEmails(tx, normalizedEmails)) ??
      (await findUserByNormalizedPhones(tx, normalizedPhones));

    if (user) {
      const updatedUser = await tx.user.update({
        where: { id: user.id },
        data: updateDataForExistingUser(user, auth, profile, primaryEmail, primaryPhone),
      });
      await tx.authIdentity.create({
        data: {
          userId: updatedUser.id,
          firebaseUid: auth.firebaseUid,
          ...identityDataForAuth(auth, primaryEmail, primaryPhone),
        },
      });
      return updatedUser;
    }

    const createdUser = await tx.user.create({
      data: {
        firebaseUid: auth.firebaseUid,
        normalizedEmail: primaryEmail,
        normalizedPhone: primaryPhone,
        username: profile.username ?? defaultUsernameForAuth(auth),
        displayName: profile.displayName ?? defaultDisplayNameForAuth(auth),
        avatarUrl: auth.picture,
      },
    });
    await tx.authIdentity.create({
      data: {
        userId: createdUser.id,
        firebaseUid: auth.firebaseUid,
        ...identityDataForAuth(auth, primaryEmail, primaryPhone),
      },
    });
    return createdUser;
  });
}

async function findUserByNormalizedEmails(
  tx: Prisma.TransactionClient,
  normalizedEmails: string[]
) {
  if (normalizedEmails.length === 0) {
    return null;
  }

  return tx.user.findFirst({
    where: { normalizedEmail: { in: normalizedEmails } },
    orderBy: { createdAt: "asc" },
  });
}

async function findUserByNormalizedPhones(
  tx: Prisma.TransactionClient,
  normalizedPhones: string[]
) {
  if (normalizedPhones.length === 0) {
    return null;
  }

  return tx.user.findFirst({
    where: { normalizedPhone: { in: normalizedPhones } },
    orderBy: { createdAt: "asc" },
  });
}

function updateDataForExistingUser(
  user: User,
  auth: AuthContext,
  profile: RegistrationProfile,
  normalizedEmail: string | null,
  normalizedPhone: string | null
) {
  return {
    ...(profile.username ? { username: profile.username } : {}),
    ...(profile.displayName ? { displayName: profile.displayName } : {}),
    ...(normalizedEmail && !user.normalizedEmail ? { normalizedEmail } : {}),
    ...(normalizedPhone && !user.normalizedPhone ? { normalizedPhone } : {}),
    ...(auth.picture && !user.avatarUrl ? { avatarUrl: auth.picture } : {}),
  };
}

function identityDataForAuth(
  auth: AuthContext,
  normalizedEmail: string | null,
  normalizedPhone: string | null
) {
  return {
    providerId: primaryProviderId(auth),
    signInProvider: auth.signInProvider,
    providerIds: normalizedProviderIds(auth),
    email: auth.email,
    normalizedEmail,
    emailVerified: auth.emailVerified,
    phoneNumber: auth.phoneNumber,
    normalizedPhone,
  };
}

function normalizedEmailsForAuth(auth: AuthContext): string[] {
  return uniqueStrings(
    auth.emails
      .map(normalizeEmail)
      .filter((email): email is string => Boolean(email))
      .filter((email) => phoneDigitsFromAliasEmail(email) === null)
  );
}

function normalizedPhonesForAuth(auth: AuthContext, normalizedEmails: string[]): string[] {
  const phones = auth.phoneNumbers.map(normalizePhone);
  const phoneAliases = auth.emails
    .map(normalizeEmail)
    .map((email) => (email ? phoneDigitsFromAliasEmail(email) : null));

  for (const email of normalizedEmails) {
    const aliasPhone = phoneDigitsFromAliasEmail(email);
    if (aliasPhone) {
      phoneAliases.push(aliasPhone);
    }
  }

  return uniqueStrings([...phones, ...phoneAliases]);
}

function normalizeEmail(value: string | null | undefined): string | null {
  const normalized = value?.trim().toLowerCase();
  return normalized || null;
}

function normalizePhone(value: string | null | undefined): string | null {
  const digits = value?.replace(/\D/g, "");
  return digits || null;
}

function phoneDigitsFromAliasEmail(value: string): string | null {
  const match = /^phone\.(\d+)@users\.outbound\.local$/.exec(value);
  return match?.[1] ?? null;
}

function normalizedProviderIds(auth: AuthContext): string[] {
  return uniqueStrings([auth.signInProvider, ...auth.providerIds]).sort();
}

function primaryProviderId(auth: AuthContext): string {
  return auth.signInProvider ?? auth.providerIds[0] ?? "firebase";
}

function uniqueStrings(values: Array<string | null | undefined>): string[] {
  return [...new Set(values.filter((value): value is string => Boolean(value)))];
}

function defaultUsernameForAuth(auth: AuthContext): string {
  const base = sanitizeUsername(
    auth.name ?? auth.email?.split("@")[0] ?? auth.phoneNumber ?? `runner-${auth.firebaseUid.slice(-8)}`
  );
  const suffix = auth.firebaseUid.slice(-6).toLowerCase();
  const trimmedBase = base.slice(0, Math.max(1, 30 - suffix.length - 1));
  return `${trimmedBase}-${suffix}`;
}

function defaultDisplayNameForAuth(auth: AuthContext): string {
  const raw = auth.name?.trim() ?? auth.email?.split("@")[0]?.trim();
  if (!raw) {
    return "Runner";
  }

  return raw.slice(0, 50);
}

function sanitizeUsername(value: string): string {
  const sanitized = value
    .toLowerCase()
    .replace(/[^a-z0-9_]+/g, "-")
    .replace(/^-+|-+$/g, "");

  return sanitized || "runner";
}
