const ABLY_REST_BASE = "https://rest.ably.io";

export type AblySessionKind = "group_run" | "live_share";

export function ablyChannel(kind: AblySessionKind, id: string) {
  return `plainstride:${kind}:${id}`;
}

export async function issueAblyToken(input: {
  channel: string;
  clientId: string;
  capabilities: string[];
}) {
  const apiKey = process.env.ABLY_API_KEY?.trim();
  if (!apiKey || !apiKey.includes(":")) throw new Error("Ably is not configured.");
  const keyName = apiKey.slice(0, apiKey.indexOf(":"));
  const response = await fetch(`${ABLY_REST_BASE}/keys/${encodeURIComponent(keyName)}/requestToken`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(apiKey).toString("base64")}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(5_000),
    body: JSON.stringify({
      keyName,
      clientId: input.clientId,
      capability: JSON.stringify({ [input.channel]: input.capabilities }),
      // Short expiry bounds access after leave/revoke; the SDK renews while the
      // session remains active and the authenticated user remains authorized.
      ttl: 2 * 60 * 1000,
      timestamp: Date.now(),
    }),
  });
  if (!response.ok) {
    // Never return provider response text: it can contain request details.
    throw new Error(`Ably token request failed (${response.status}).`);
  }
  return await response.json() as { token: string; expires: number; issued: number; capability: string; clientId: string };
}

export async function publishAbly(channel: string, name: string, data: unknown) {
  const apiKey = process.env.ABLY_API_KEY?.trim();
  if (!apiKey || !apiKey.includes(":")) return false;
  const response = await fetch(`${ABLY_REST_BASE}/channels/${encodeURIComponent(channel)}/messages`, {
    method: "POST",
    headers: {
      Authorization: `Basic ${Buffer.from(apiKey).toString("base64")}`,
      "Content-Type": "application/json",
    },
    signal: AbortSignal.timeout(3_000),
    body: JSON.stringify([{ name, data }]),
  });
  return response.ok;
}
