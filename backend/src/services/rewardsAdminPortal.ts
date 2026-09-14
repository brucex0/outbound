import { configuredAdminEmails } from "./rewardsAdmin.js";
import { configuredGoogleClientIds } from "./googleAuth.js";

export function configuredRewardsAdminGoogleClientId(env: NodeJS.ProcessEnv = process.env): string | null {
  return env.REWARDS_ADMIN_GOOGLE_CLIENT_ID?.trim() || null;
}

export function assertRewardsAdminPortalConfiguration(env: NodeJS.ProcessEnv = process.env) {
  if (env.NODE_ENV !== "production" || configuredAdminEmails(env).size === 0) return;
  const clientId = configuredRewardsAdminGoogleClientId(env);
  if (!clientId) {
    throw new Error("REWARDS_ADMIN_GOOGLE_CLIENT_ID is required when rewards administration is enabled in production");
  }
  if (!configuredGoogleClientIds(env).includes(clientId)) {
    throw new Error("REWARDS_ADMIN_GOOGLE_CLIENT_ID must also appear in GOOGLE_AUTH_CLIENT_IDS");
  }
}
