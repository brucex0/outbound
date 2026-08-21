import { createPrivateKey, createPublicKey, sign, verify, type JsonWebKey } from "node:crypto";

const issuer = "https://api.outbound.run";
const audience = "plainstride-api";
const lifetimeSeconds = 15 * 60;

type Header = { alg: "ES256"; kid: string; typ: "JWT" };
type Claims = { iss: string; aud: string; sub: string; sid: string; iat: number; exp: number };

export function issueAccessToken(userId: string, sessionId: string, now = new Date()) {
  const keyId = required("AUTH_ACCESS_KEY_ID");
  const privateKey = createPrivateKey(normalizePEM(required("AUTH_ACCESS_PRIVATE_KEY")));
  const issuedAt = Math.floor(now.getTime() / 1000);
  const expiresAt = issuedAt + lifetimeSeconds;
  const encodedHeader = encodeJSON<Header>({ alg: "ES256", kid: keyId, typ: "JWT" });
  const encodedClaims = encodeJSON<Claims>({ iss: issuer, aud: audience, sub: userId, sid: sessionId, iat: issuedAt, exp: expiresAt });
  const input = `${encodedHeader}.${encodedClaims}`;
  const signature = sign("sha256", Buffer.from(input), { key: privateKey, dsaEncoding: "ieee-p1363" });
  return { token: `${input}.${base64url(signature)}`, expiresAt: new Date(expiresAt * 1000) };
}

export function verifyAccessToken(token: string, now = new Date()): Claims {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("invalid_access_token");
  const header = decodeJSON<Header>(parts[0]!);
  if (header.alg !== "ES256" || !header.kid) throw new Error("invalid_access_token");
  const publicKeyPEM = publicKeyFor(header.kid);
  if (!publicKeyPEM) throw new Error("invalid_access_token");
  const valid = verify("sha256", Buffer.from(`${parts[0]}.${parts[1]}`),
    { key: createPublicKey(normalizePEM(publicKeyPEM)), dsaEncoding: "ieee-p1363" }, Buffer.from(parts[2]!, "base64url"));
  if (!valid) throw new Error("invalid_access_token");
  const claims = decodeJSON<Claims>(parts[1]!);
  const nowSeconds = Math.floor(now.getTime() / 1000);
  if (claims.iss !== issuer || claims.aud !== audience || !claims.sub || !claims.sid || claims.exp <= nowSeconds) {
    throw new Error("invalid_access_token");
  }
  return claims;
}

function publicKeyFor(kid: string) {
  const keys = JSON.parse(required("AUTH_ACCESS_PUBLIC_KEYS")) as Record<string, string>;
  return keys[kid];
}
function required(name: string) { const value = process.env[name]; if (!value) throw new Error(`Missing ${name}`); return value; }
function normalizePEM(value: string) { return value.replace(/\\n/g, "\n"); }
function base64url(value: Buffer | string) { return Buffer.from(value).toString("base64url"); }
function encodeJSON<T>(value: T) { return base64url(JSON.stringify(value)); }
function decodeJSON<T>(value: string) { return JSON.parse(Buffer.from(value, "base64url").toString("utf8")) as T; }

export function publicKeyFromJWK(jwk: JsonWebKey) { return createPublicKey({ key: jwk, format: "jwk" }); }
