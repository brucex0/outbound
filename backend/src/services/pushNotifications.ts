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

export async function deliverPushNotification(notification: PushNotificationPayload) {
  const prisma = getPrismaClient();
  const devices = await prisma.pushDevice.findMany({
    where: { userId: notification.recipientId, enabled: true },
    select: { token: true },
  });
  if (devices.length === 0 || process.env.FIREBASE_AUTH_EMULATOR_HOST) return;

  const result = await getMessaging(getFirebaseApp()).sendEachForMulticast({
    tokens: devices.map((device) => device.token),
    notification: { title: "Plainstride", body: notification.message },
    data: {
      notificationId: notification.id,
      type: notification.type,
      objectId: notification.objectId ?? "",
      destination: "social.notifications",
    },
    apns: {
      payload: { aps: { sound: "default", badge: 1 } },
    },
  });

  const staleTokens = result.responses.flatMap((response, index) => {
    if (response.success) return [];
    const code = response.error?.code;
    return code === "messaging/registration-token-not-registered" || code === "messaging/invalid-registration-token"
      ? [devices[index]!.token]
      : [];
  });
  const failures = result.responses.flatMap((response, index) => {
    if (response.success) return [];
    return [{
      deviceIndex: index,
      code: response.error?.code ?? "unknown",
      message: response.error?.message ?? "Firebase did not provide an error message.",
      staleToken: staleTokens.includes(devices[index]!.token),
    }];
  });
  if (staleTokens.length > 0) {
    await prisma.pushDevice.deleteMany({ where: { token: { in: staleTokens } } });
  }
  if (failures.length > 0) {
    console.error("[push] delivery failures", {
      notificationId: notification.id,
      recipientId: notification.recipientId,
      failureCount: failures.length,
      failures,
    });
  }
}
