import { createMiddleware } from "hono/factory";
import { verifyBearerToken } from "../services/firebaseAuth.js";
import { verifyAccessToken } from "../services/accessTokens.js";
import type { AppEnv, AuthContext } from "../types/hono.js";

export const authMiddleware = createMiddleware<AppEnv>(async (c, next) => {
  c.set("auth", null);
  const authHeader = c.req.header("Authorization");
  if (!authHeader) return next();
  const [scheme, token] = authHeader.split(" ");
  if (scheme !== "Bearer" || !token) return c.json({ error: "Malformed Authorization header." }, 401);

  try {
    const claims = verifyAccessToken(token);
    c.set("auth", { subject: claims.sub, authenticationKind: "plainstride", provider: "plainstride",
      providerSubject: claims.sub, internalUserId: claims.sub, sessionId: claims.sid,
      email: null, emails: [], emailVerified: false, name: null, picture: null, phoneNumber: null, phoneNumbers: [] });
  } catch {
    if (process.env.AUTH_ACCEPT_LEGACY_FIREBASE !== "true") return c.json({ error: "Invalid auth token." }, 401);
    try {
      const decoded = await verifyBearerToken(token);
      const identities = decoded.firebase.identities ?? {};
      const emails = uniqueStrings([decoded.email, ...values(identities.email)]);
      const phones = uniqueStrings([decoded.phone_number, ...values(identities.phone_number ?? identities.phone)]);
      const context: AuthContext = { subject: decoded.uid, authenticationKind: "provider", provider: "firebase",
        providerSubject: decoded.uid, internalUserId: null, sessionId: null, email: decoded.email ?? null,
        emails, emailVerified: decoded.email_verified === true, name: decoded.name ?? null,
        picture: decoded.picture ?? null, phoneNumber: decoded.phone_number ?? null, phoneNumbers: phones };
      c.set("auth", context);
    } catch (error) {
      console.warn("[auth] bearer rejected", { path: c.req.path, code: "invalid_access_token" });
      return c.json({ error: "Invalid auth token." }, 401);
    }
  }
  await next();
});
function values(value: unknown): string[] { return typeof value === "string" ? [value] : Array.isArray(value) ? value.filter((v): v is string => typeof v === "string") : []; }
function uniqueStrings(values: Array<string | null | undefined>) { return [...new Set(values.filter((v): v is string => Boolean(v?.trim())))]; }
