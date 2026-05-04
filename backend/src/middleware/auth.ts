import { createMiddleware } from "hono/factory";
import { verifyBearerToken } from "../services/firebaseAuth.js";
import type { AppEnv } from "../types/hono.js";

export const authMiddleware = createMiddleware<AppEnv>(async (c, next) => {
  c.set("auth", null);

  const authHeader = c.req.header("Authorization");
  if (!authHeader) {
    await next();
    return;
  }

  const [scheme, token] = authHeader.split(" ");
  if (scheme !== "Bearer" || !token) {
    return c.json({ error: "Malformed Authorization header." }, 401);
  }

  try {
    const decoded = await verifyBearerToken(token);
    const identities = decoded.firebase.identities ?? {};
    const identityEmails = valuesForIdentity(identities.email);
    const identityPhones = valuesForIdentity(identities.phone_number ?? identities.phone);

    c.set("auth", {
      firebaseUid: decoded.uid,
      email: decoded.email ?? null,
      emails: uniqueStrings([decoded.email, ...identityEmails]),
      emailVerified: decoded.email_verified === true,
      name: decoded.name ?? null,
      picture: decoded.picture ?? null,
      phoneNumber: decoded.phone_number ?? null,
      phoneNumbers: uniqueStrings([decoded.phone_number, ...identityPhones]),
      providerIds: Object.keys(identities).sort(),
      signInProvider: decoded.firebase.sign_in_provider ?? null,
    });
  } catch (error) {
    console.error("[auth] token verification failed", error);
    return c.json({ error: "Invalid auth token." }, 401);
  }

  await next();
});

function valuesForIdentity(value: unknown): string[] {
  if (typeof value === "string") {
    return [value];
  }

  if (!Array.isArray(value)) {
    return [];
  }

  return value.filter((entry): entry is string => typeof entry === "string");
}

function uniqueStrings(values: Array<string | null | undefined>): string[] {
  const normalized = values
    .map((value) => value?.trim())
    .filter((value): value is string => Boolean(value));

  return [...new Set(normalized)];
}
