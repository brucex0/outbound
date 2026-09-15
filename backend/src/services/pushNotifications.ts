import { getMessaging } from "firebase-admin/messaging";
import { getFirebaseApp } from "./firebaseAuth.js";
import { getPrismaClient } from "./prisma.js";

export type PushNotificationPayload = {
  id: string;
  recipientId: string;
  type: string;
  objectId: string | null;
  message: string;
};

type PushPlatform = "ios" | "android";
type DeliveryErrorCategory = "invalid_token" | "credentials" | "rate_limited" | "provider_unavailable" | "invalid_payload" | "unknown";

const ACTIONABLE_NOTIFICATION_TYPES = new Set([
  "liveCheerInvitation",
  "connectionRequest",
  "runInvitation",
  "circleInvitation",
  "groupRunInvitation",
]);

export async function deliverPushNotification(notification: PushNotificationPayload) {
  const prisma = getPrismaClient();
  const devices = await prisma.pushDevice.findMany({
    where: { userId: notification.recipientId, enabled: true, platform: { in: ["ios", "android"] } },
    select: { token: true, platform: true },
  });
  if (devices.length === 0 || process.env.FIREBASE_AUTH_EMULATOR_HOST) return;
  const staleTokens: string[] = [];
  const failures: Array<{ platform: PushPlatform; category: DeliveryErrorCategory; retryable: boolean }> = [];
  for (const platform of ["ios", "android"] as const) {
    const platformDevices = devices.filter((device) => device.platform === platform);
    if (platformDevices.length === 0) continue;
    const result = await getMessaging(getFirebaseApp()).sendEachForMulticast({
      tokens: platformDevices.map((device) => device.token),
      // Social notification copy is intentionally share-safe when the durable
      // inbox record is created, so the push can identify the actor and action.
      notification: { title: "Plainstride", body: notification.message },
      data: {
        notificationId: notification.id,
        type: notification.type,
        objectId: notification.objectId ?? "",
        targetType: notification.type === "runInvitation" ? "invitation" : notification.type.startsWith("activityEvent") || notification.type === "invitationAccepted" ? "event" : "notification",
        destination: "social.notifications",
      },
      ...(platform === "ios"
        ? {
            apns: {
              payload: {
                aps: {
                  sound: "default",
                  ...(ACTIONABLE_NOTIFICATION_TYPES.has(notification.type) ? { badge: 1 } : {}),
                },
              },
            },
          }
        : { android: { priority: "high", notification: { channelId: "social", sound: "default" } } }),
    });
    result.responses.forEach((response, index) => {
      if (response.success) return;
      const error = classifyDeliveryError(response.error?.code);
      if (error.category === "invalid_token") staleTokens.push(platformDevices[index]!.token);
      failures.push({ platform, ...error });
    });
  }
  if (staleTokens.length > 0) {
    await prisma.pushDevice.deleteMany({ where: { token: { in: staleTokens } } });
  }
  if (failures.length > 0) {
    const summary = failures.reduce<Record<string, number>>((counts, failure) => {
      const key = `${failure.platform}:${failure.category}:${failure.retryable ? "retryable" : "terminal"}`;
      counts[key] = (counts[key] ?? 0) + 1;
      return counts;
    }, {});
    console.error("[push] delivery failures", {
      notificationId: notification.id,
      failureCount: failures.length,
      summary,
    });
  }
}

function classifyDeliveryError(code?: string): { category: DeliveryErrorCategory; retryable: boolean } {
  switch (code) {
    case "messaging/registration-token-not-registered":
    case "messaging/invalid-registration-token":
      return { category: "invalid_token", retryable: false };
    case "messaging/authentication-error":
    case "messaging/mismatched-credential":
      return { category: "credentials", retryable: false };
    case "messaging/message-rate-exceeded":
    case "messaging/device-message-rate-exceeded":
      return { category: "rate_limited", retryable: true };
    case "messaging/server-unavailable":
    case "messaging/internal-error":
      return { category: "provider_unavailable", retryable: true };
    case "messaging/invalid-argument":
    case "messaging/invalid-payload":
      return { category: "invalid_payload", retryable: false };
    default:
      return { category: "unknown", retryable: true };
  }
}
