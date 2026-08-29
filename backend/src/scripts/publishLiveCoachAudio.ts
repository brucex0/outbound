import { readFile } from "node:fs/promises";
import { createHash, createSign } from "node:crypto";
import path from "node:path";
import { audioPackManifestSchema } from "../services/liveCoach/audioPackManifest.js";
import { publishLiveCoachAudioObject, publishLiveCoachManifest } from "../services/liveCoach/audioPackStorage.js";
import { validateLiveCoachWav } from "../services/aiProviders/audioValidation.js";

const manifestArgument = process.argv[process.argv.indexOf("--review-manifest") + 1];
if (!process.argv.includes("--approved") || !manifestArgument) {
  throw new Error("Usage: npm run live-coach:publish-audio -- --review-manifest <path> --approved");
}
const manifestPath = path.resolve(process.cwd(), manifestArgument);
const manifest = audioPackManifestSchema.parse(JSON.parse(await readFile(manifestPath, "utf8")));
if (manifest.entries.some((entry) => !entry.approved)) {
  throw new Error("Every audio entry must be listened to and marked approved=true before publication.");
}
const publicBaseUrl = process.env.LIVE_COACH_AUDIO_PUBLIC_BASE_URL?.replace(/\/+$/, "");
if (!publicBaseUrl) throw new Error("LIVE_COACH_AUDIO_PUBLIC_BASE_URL is required.");
if (new URL(publicBaseUrl).protocol !== "https:") {
  throw new Error("LIVE_COACH_AUDIO_PUBLIC_BASE_URL must use HTTPS.");
}
const directory = path.dirname(manifestPath);
const publishedEntries = [];
for (const entry of manifest.entries) {
  if (!entry.reviewFileName) throw new Error(`Review file is missing for ${entry.cueKey}.`);
  const filePath = path.join(directory, entry.reviewFileName);
  const audio = await readFile(filePath);
  const validated = validateLiveCoachWav(audio);
  const sha256 = createHash("sha256").update(audio).digest("hex");
  if (sha256 !== entry.sha256 || audio.byteLength !== entry.byteCount
      || validated.durationMilliseconds !== entry.durationMilliseconds) {
    throw new Error(`Reviewed audio no longer matches its manifest entry for ${entry.cueKey}.`);
  }
  const storageKey = `live-coach/${manifest.catalogVersion}/assets/${entry.sha256}.wav`;
  await publishLiveCoachAudioObject(storageKey, audio, entry.contentType);
  const { reviewFileName: _, ...publicEntry } = entry;
  publishedEntries.push({ ...publicEntry, url: `${publicBaseUrl}/${storageKey}` });
}
const published = { ...manifest, entries: publishedEntries };
const payload = Buffer.from(`${JSON.stringify(published)}\n`);
const payloadSha256 = createHash("sha256").update(payload).digest("hex");
const signedManifest = signManifest(payload);
const versionedKey = `live-coach/${manifest.catalogVersion}/manifest.json`;
await publishLiveCoachManifest(versionedKey, signedManifest, { immutable: true, payloadSha256 });
await publishLiveCoachManifest("live-coach/current/manifest.json", signedManifest, { immutable: false, payloadSha256 });
console.log(`Published ${publishedEntries.length} immutable assets and manifest ${versionedKey}.`);

function signManifest(payload: Buffer): Buffer {
  const keyId = process.env.LIVE_COACH_AUDIO_MANIFEST_SIGNING_KEY_ID?.trim();
  const privateKey = process.env.LIVE_COACH_AUDIO_MANIFEST_PRIVATE_KEY?.trim();
  if (!keyId || !privateKey) {
    throw new Error("LIVE_COACH_AUDIO_MANIFEST_SIGNING_KEY_ID and LIVE_COACH_AUDIO_MANIFEST_PRIVATE_KEY are required.");
  }
  const signer = createSign("SHA256");
  signer.update(payload);
  signer.end();
  return Buffer.from(`${JSON.stringify({
    contractVersion: 1,
    payload: payload.toString("base64url"),
    signature: {
      algorithm: "ES256",
      keyId,
      value: signer.sign(privateKey).toString("base64url"),
    },
  })}\n`);
}
