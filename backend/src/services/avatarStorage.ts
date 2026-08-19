import { getStorage } from "firebase-admin/storage";
import { getFirebaseApp } from "./firebaseAuth.js";

const maximumAvatarBytes = 2 * 1024 * 1024;

function bucket() {
  const projectId =
    process.env.FIREBASE_PROJECT_ID ??
    process.env.GOOGLE_CLOUD_PROJECT ??
    process.env.GCLOUD_PROJECT;
  const bucketName = process.env.AVATAR_STORAGE_BUCKET ?? (projectId ? `${projectId}.firebasestorage.app` : undefined);
  if (!bucketName) throw new Error("AVATAR_STORAGE_BUCKET is not configured.");
  return getStorage(getFirebaseApp()).bucket(bucketName);
}

export function avatarStorageKey(userId: string) {
  return `avatars/${userId}/profile.jpg`;
}

export async function saveAvatar(userId: string, data: Buffer, contentType: string) {
  if (data.length === 0 || data.length > maximumAvatarBytes) {
    throw new Error("Avatar must be between 1 byte and 2 MB.");
  }
  await bucket().file(avatarStorageKey(userId)).save(data, {
    resumable: false,
    metadata: { contentType, cacheControl: "private, max-age=0, no-store" },
  });
}

export async function readAvatar(userId: string) {
  const file = bucket().file(avatarStorageKey(userId));
  const [exists] = await file.exists();
  if (!exists) return null;
  const [[data], [metadata]] = await Promise.all([file.download(), file.getMetadata()]);
  return { data, contentType: metadata.contentType ?? "image/jpeg" };
}

export async function signedAvatarURL(userId: string) {
  const file = bucket().file(avatarStorageKey(userId));
  const [exists] = await file.exists();
  if (!exists) return null;
  const [url] = await file.getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + 15 * 60 * 1_000,
  });
  return url;
}

export async function deleteAvatar(userId: string) {
  await bucket().file(avatarStorageKey(userId)).delete({ ignoreNotFound: true });
}
