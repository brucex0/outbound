import { getStorage } from "firebase-admin/storage";
import { createHash } from "node:crypto";
import { getFirebaseApp } from "../firebaseAuth.js";

function audioBucket() {
  const bucketName = process.env.LIVE_COACH_AUDIO_BUCKET;
  if (!bucketName) throw new Error("LIVE_COACH_AUDIO_BUCKET is not configured.");
  return getStorage(getFirebaseApp()).bucket(bucketName);
}

export async function publishLiveCoachAudioObject(storageKey: string, data: Buffer, contentType: string): Promise<void> {
  const file = audioBucket().file(storageKey);
  const sha256 = createHash("sha256").update(data).digest("hex");
  try {
    await file.save(data, {
      resumable: false,
      preconditionOpts: { ifGenerationMatch: 0 },
      metadata: {
        contentType,
        cacheControl: "public, max-age=31536000, immutable",
        metadata: { sha256 },
      },
    });
  } catch (error) {
    if (!isPreconditionFailure(error)) throw error;
    const [metadata] = await file.getMetadata();
    if (metadata.metadata?.sha256 !== sha256 || Number(metadata.size) !== data.byteLength) {
      throw new Error(`Immutable live-coach object collision at ${storageKey}.`);
    }
  }
}

export async function publishLiveCoachManifest(
  storageKey: string,
  data: Buffer,
  options: { immutable: boolean; payloadSha256: string }
): Promise<void> {
  const file = audioBucket().file(storageKey);
  try {
    await file.save(data, {
      resumable: false,
      ...(options.immutable ? { preconditionOpts: { ifGenerationMatch: 0 } } : {}),
      metadata: {
        contentType: "application/json",
        cacheControl: options.immutable ? "public, max-age=31536000, immutable" : "public, max-age=300",
        metadata: { payloadSha256: options.payloadSha256 },
      },
    });
  } catch (error) {
    if (!options.immutable || !isPreconditionFailure(error)) throw error;
    const [metadata] = await file.getMetadata();
    if (metadata.metadata?.payloadSha256 !== options.payloadSha256) {
      throw new Error(`Immutable live-coach manifest collision at ${storageKey}.`);
    }
  }
}

function isPreconditionFailure(error: unknown): boolean {
  return typeof error === "object" && error !== null
    && ("code" in error && (error.code === 412 || error.code === "412"));
}
