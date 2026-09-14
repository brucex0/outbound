import { OAuth2Client, type TokenPayload } from "google-auth-library";

const verifier = new OAuth2Client();

export type GoogleClaims = Pick<TokenPayload, "sub" | "email" | "email_verified" | "name" | "picture">;

export async function verifyGoogleIdentityToken(identityToken: string): Promise<GoogleClaims> {
  const audiences = configuredGoogleClientIds();
  if (audiences.length === 0) throw new Error("authentication_unavailable");

  try {
    const ticket = await verifier.verifyIdToken({ idToken: identityToken, audience: audiences });
    const claims = ticket.getPayload();
    if (!claims?.sub || !claims.iss || !["accounts.google.com", "https://accounts.google.com"].includes(claims.iss)) {
      throw new Error("invalid_provider_credential");
    }
    return claims;
  } catch (error) {
    if (error instanceof Error && error.message === "invalid_provider_credential") throw error;
    if (isProviderTransportFailure(error)) throw new Error("provider_unavailable");
    throw new Error("invalid_provider_credential");
  }
}

export function assertGoogleAuthConfiguration(env: NodeJS.ProcessEnv = process.env) {
  if (env.NODE_ENV !== "production") return;
  const ids = configuredGoogleClientIds(env);
  if (ids.length === 0) throw new Error("GOOGLE_AUTH_CLIENT_IDS must contain at least one OAuth client ID in production");
}

export function configuredGoogleClientIds(env: NodeJS.ProcessEnv = process.env) {
  return (env.GOOGLE_AUTH_CLIENT_IDS ?? env.GOOGLE_ANDROID_CLIENT_ID ?? "")
    .split(",")
    .map((value) => value.trim())
    .filter(Boolean);
}

function isProviderTransportFailure(error: unknown) {
  if (!(error instanceof Error)) return false;
  const code = (error as NodeJS.ErrnoException).code;
  return Boolean(code && ["ECONNABORTED", "ECONNREFUSED", "ECONNRESET", "ENETUNREACH", "ETIMEDOUT"].includes(code));
}
