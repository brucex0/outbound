import { createHash, createPrivateKey, createPublicKey, sign, verify, type JsonWebKey } from "node:crypto";

type AppleClaims = { iss: string; aud: string; sub: string; exp: number; nonce?: string; email?: string; email_verified?: boolean | string };
type AppleKey = JsonWebKey & { kid: string; alg: string };
let cachedKeys: { expiresAt: number; keys: AppleKey[] } | null = null;

export async function verifyAppleIdentityToken(identityToken: string, rawNonce: string): Promise<AppleClaims> {
  const [encodedHeader, encodedClaims, encodedSignature] = identityToken.split(".");
  if (!encodedHeader || !encodedClaims || !encodedSignature) throw new Error("invalid_provider_credential");
  const header = decode<{ alg: string; kid: string }>(encodedHeader);
  if (header.alg !== "RS256" || !header.kid) throw new Error("invalid_provider_credential");
  const key = (await appleKeys()).find((candidate) => candidate.kid === header.kid && candidate.alg === "RS256");
  if (!key || !verify("RSA-SHA256", Buffer.from(`${encodedHeader}.${encodedClaims}`), createPublicKey({ key, format: "jwk" }), Buffer.from(encodedSignature, "base64url"))) {
    throw new Error("invalid_provider_credential");
  }
  const claims = decode<AppleClaims>(encodedClaims);
  const clientId = process.env.APPLE_CLIENT_ID;
  const nonce = createHash("sha256").update(rawNonce).digest("hex");
  if (!clientId) throw new Error("authentication_unavailable");
  if (claims.iss !== "https://appleid.apple.com" || claims.aud !== clientId || claims.exp <= Date.now() / 1000 || !claims.sub || claims.nonce !== nonce) {
    throw new Error("invalid_provider_credential");
  }
  return claims;
}

async function appleKeys() {
  if (cachedKeys && cachedKeys.expiresAt > Date.now()) return cachedKeys.keys;
  let response: Response;
  try { response = await fetch("https://appleid.apple.com/auth/keys", { signal: AbortSignal.timeout(5_000) }); }
  catch { throw new Error("provider_unavailable"); }
  if (!response.ok) throw new Error("provider_unavailable");
  const body = await response.json() as { keys?: AppleKey[] };
  if (!body.keys?.length) throw new Error("provider_unavailable");
  cachedKeys = { keys: body.keys, expiresAt: Date.now() + 60 * 60 * 1000 };
  return body.keys;
}
function decode<T>(value: string) { return JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as T; }

export async function revokeAppleAuthorization(authorizationCode: string) {
  if (!authorizationCode) throw new Error("invalid_provider_credential");
  const clientId = required("APPLE_CLIENT_ID");
  const clientSecret = appleClientSecret(clientId);
  const exchange = await fetch("https://appleid.apple.com/auth/token", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, code: authorizationCode, grant_type: "authorization_code" }),
    signal: AbortSignal.timeout(5_000) });
  if (!exchange.ok) throw new Error(exchange.status >= 500 ? "provider_unavailable" : "invalid_provider_credential");
  const tokens = await exchange.json() as { refresh_token?: string; access_token?: string };
  const token = tokens.refresh_token ?? tokens.access_token;
  if (!token) throw new Error("provider_unavailable");
  const revoke = await fetch("https://appleid.apple.com/auth/revoke", { method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ client_id: clientId, client_secret: clientSecret, token, token_type_hint: tokens.refresh_token ? "refresh_token" : "access_token" }),
    signal: AbortSignal.timeout(5_000) });
  if (!revoke.ok) throw new Error(revoke.status >= 500 ? "provider_unavailable" : "invalid_provider_credential");
}

function appleClientSecret(clientId: string) {
  const now = Math.floor(Date.now() / 1000); const keyId = required("APPLE_KEY_ID"); const teamId = required("APPLE_TEAM_ID");
  const header = Buffer.from(JSON.stringify({ alg: "ES256", kid: keyId })).toString("base64url");
  const payload = Buffer.from(JSON.stringify({ iss: teamId, iat: now, exp: now + 300, aud: "https://appleid.apple.com", sub: clientId })).toString("base64url");
  const input = `${header}.${payload}`;
  const signature = sign("sha256", Buffer.from(input), { key: createPrivateKey(required("APPLE_PRIVATE_KEY").replace(/\\n/g, "\n")), dsaEncoding: "ieee-p1363" });
  return `${input}.${signature.toString("base64url")}`;
}
function required(name: string) { const value = process.env[name]; if (!value) throw new Error("authentication_unavailable"); return value; }
