import { createHmac, timingSafeEqual } from "node:crypto";
import type { PrismaClient } from "@prisma/client";
import { setRevenueCatPlusEntitlement } from "./entitlements.js";

const REVENUECAT_API_BASE_URL = "https://api.revenuecat.com/v1";
const WEBHOOK_TOLERANCE_SECONDS = 300;
const REQUEST_TIMEOUT_MILLISECONDS = 7_500;

type RevenueCatEntitlement = {
  expires_date?: string | null;
  grace_period_expires_date?: string | null;
  purchase_date?: string | null;
};

type RevenueCatCustomerResponse = {
  subscriber?: {
    entitlements?: Record<string, RevenueCatEntitlement>;
  };
};

export function verifyRevenueCatWebhookSignature(
  rawBody: string,
  signatureHeader: string | undefined,
  nowSeconds = Math.floor(Date.now() / 1_000),
  env: NodeJS.ProcessEnv = process.env,
): boolean {
  const secret = env.REVENUECAT_WEBHOOK_SIGNING_SECRET?.trim();
  if (!secret || !signatureHeader) return false;
  const parts = Object.fromEntries(signatureHeader.split(",").map((part) => {
    const separator = part.indexOf("=");
    return separator < 0 ? [part.trim(), ""] : [part.slice(0, separator).trim(), part.slice(separator + 1).trim()];
  }));
  const timestamp = Number(parts.t);
  const signature = parts.v1;
  if (!Number.isSafeInteger(timestamp) || Math.abs(nowSeconds - timestamp) > WEBHOOK_TOLERANCE_SECONDS) return false;
  if (!/^[a-f0-9]{64}$/i.test(signature ?? "")) return false;
  const expected = createHmac("sha256", secret).update(`${parts.t}.${rawBody}`).digest();
  const received = Buffer.from(signature, "hex");
  return received.length === expected.length && timingSafeEqual(received, expected);
}

export async function reconcileRevenueCatPlus(
  prisma: PrismaClient,
  userId: string,
  env: NodeJS.ProcessEnv = process.env,
  now = new Date(),
): Promise<{ active: boolean; expiresAt: Date | null }> {
  const apiKey = env.REVENUECAT_SECRET_API_KEY?.trim();
  if (!apiKey) throw new RevenueCatConfigurationError();
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MILLISECONDS);
  let response: Response;
  try {
    response = await fetch(`${REVENUECAT_API_BASE_URL}/subscribers/${encodeURIComponent(userId)}`, {
      headers: { Accept: "application/json", Authorization: `Bearer ${apiKey}` },
      signal: controller.signal,
    });
  } finally {
    clearTimeout(timeout);
  }
  if (!response.ok) throw new RevenueCatUpstreamError(response.status);
  const customer = await response.json() as RevenueCatCustomerResponse;
  const entitlementId = env.REVENUECAT_PLUS_ENTITLEMENT_ID?.trim() || "plainstride_pro";
  const entitlement = customer.subscriber?.entitlements?.[entitlementId];
  const expiration = latestDate(entitlement?.expires_date, entitlement?.grace_period_expires_date);
  const active = Boolean(entitlement) && (expiration == null || expiration > now);
  const startsAt = parsedDate(entitlement?.purchase_date) ?? now;
  const expiresAt = active ? expiration : now;
  await setRevenueCatPlusEntitlement(prisma, userId, { active, startsAt, expiresAt });
  return { active, expiresAt };
}

function latestDate(...values: Array<string | null | undefined>): Date | null {
  const dates = values.map(parsedDate).filter((value): value is Date => value != null);
  return dates.length === 0 ? null : new Date(Math.max(...dates.map((value) => value.getTime())));
}

function parsedDate(value: string | null | undefined): Date | null {
  if (!value) return null;
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export class RevenueCatConfigurationError extends Error {
  constructor() { super("revenuecat_not_configured"); }
}

export class RevenueCatUpstreamError extends Error {
  constructor(readonly status: number) { super("revenuecat_upstream_failed"); }
}
