import { createHash } from "node:crypto";
import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { getStorage } from "firebase-admin/storage";
import { getFirebaseApp } from "./firebaseAuth.js";

export const maximumActivityPhotoBytes = 5 * 1024 * 1024;

function bucket() {
  const projectId =
    process.env.FIREBASE_PROJECT_ID ??
    process.env.GOOGLE_CLOUD_PROJECT ??
    process.env.GCLOUD_PROJECT;
  const bucketName =
    process.env.MEDIA_STORAGE_BUCKET ??
    process.env.AVATAR_STORAGE_BUCKET ??
    (projectId ? `${projectId}.firebasestorage.app` : undefined);
  if (!bucketName) throw new Error("MEDIA_STORAGE_BUCKET is not configured.");
  return getStorage(getFirebaseApp()).bucket(bucketName);
}

function localMediaPath(storageKey: string) {
  if (!process.env.FIREBASE_AUTH_EMULATOR_HOST) return null;
  const root = process.env.OUTBOUND_LOCAL_MEDIA_DIR ?? path.resolve(process.cwd(), ".local", "media");
  return path.join(root, ...storageKey.split("/"));
}

export function activityPhotoStorageKey(userId: string, activityId: string, clientPhotoId: string) {
  return `activity-photos/${userId}/${activityId}/${clientPhotoId}.jpg`;
}

export function activityPhotoSHA256(data: Buffer) {
  return createHash("sha256").update(data).digest("hex");
}

export async function saveActivityPhoto(storageKey: string, data: Buffer) {
  if (data.length === 0 || data.length > maximumActivityPhotoBytes) {
    throw new Error("Activity photo must be between 1 byte and 5 MB.");
  }
  if (data[0] !== 0xff || data[1] !== 0xd8 || data[data.length - 2] !== 0xff || data[data.length - 1] !== 0xd9) {
    throw new Error("Activity photo must be a valid JPEG.");
  }
  const localPath = localMediaPath(storageKey);
  if (localPath) {
    await mkdir(path.dirname(localPath), { recursive: true });
    await writeFile(localPath, data);
    return;
  }
  await bucket().file(storageKey).save(data, {
    resumable: false,
    metadata: { contentType: "image/jpeg", cacheControl: "private, max-age=3600" },
  });
}

export async function readActivityPhoto(storageKey: string) {
  const localPath = localMediaPath(storageKey);
  if (localPath) {
    try {
      return await readFile(localPath);
    } catch (error: any) {
      if (error?.code === "ENOENT") return null;
      throw error;
    }
  }
  const file = bucket().file(storageKey);
  const [exists] = await file.exists();
  if (!exists) return null;
  const [data] = await file.download();
  return data;
}

export async function signedActivityPhotoURL(storageKey: string) {
  if (localMediaPath(storageKey)) return null;
  const file = bucket().file(storageKey);
  const [exists] = await file.exists();
  if (!exists) return null;
  const [url] = await file.getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + 15 * 60 * 1_000,
  });
  return url;
}

export async function deleteActivityPhoto(storageKey: string) {
  const localPath = localMediaPath(storageKey);
  if (localPath) {
    await rm(localPath, { force: true });
    return;
  }
  await bucket().file(storageKey).delete({ ignoreNotFound: true });
}

export async function deleteActivityPhotos(storageKeys: string[]) {
  await Promise.all(storageKeys.map(deleteActivityPhoto));
}

export async function deleteUserActivityPhotos(userId: string) {
  const localPath = localMediaPath(`activity-photos/${userId}`);
  if (localPath) {
    await rm(localPath, { recursive: true, force: true });
    return;
  }
  await bucket().deleteFiles({ prefix: `activity-photos/${userId}/` });
}
