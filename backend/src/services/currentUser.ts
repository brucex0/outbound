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

  return getPrismaClient().user.findUnique({
    where: { firebaseUid: auth.firebaseUid },
  });
}
