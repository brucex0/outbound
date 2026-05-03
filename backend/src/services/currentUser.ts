import type { Context } from "hono";
import { getPrismaClient } from "./prisma.js";
import type { AppEnv, AuthContext } from "../types/hono.js";

export function getAuthenticatedIdentity(c: Context<AppEnv>): AuthContext | null {
  return c.get("auth");
}

export async function getAuthenticatedAppUser(c: Context<AppEnv>) {
  const auth = getAuthenticatedIdentity(c);
  if (!auth) {
    return null;
  }

  return getPrismaClient().user.upsert({
    where: { firebaseUid: auth.firebaseUid },
    update: {},
    create: {
      firebaseUid: auth.firebaseUid,
      username: defaultUsernameForAuth(auth),
      displayName: defaultDisplayNameForAuth(auth),
    },
  });
}

function defaultUsernameForAuth(auth: AuthContext): string {
  const base = sanitizeUsername(
    auth.email?.split("@")[0] ?? `runner-${auth.firebaseUid.slice(-8)}`
  );
  const suffix = auth.firebaseUid.slice(-6).toLowerCase();
  const trimmedBase = base.slice(0, Math.max(1, 30 - suffix.length - 1));
  return `${trimmedBase}-${suffix}`;
}

function defaultDisplayNameForAuth(auth: AuthContext): string {
  const raw = auth.email?.split("@")[0]?.trim();
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
