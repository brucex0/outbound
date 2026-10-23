import { createHash } from "node:crypto";
import { copyFile, mkdir, readFile, readdir, unlink, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { audioPackManifestSchema } from "../dist/services/liveCoach/audioPackManifest.js";
import { validateLiveCoachWav } from "../dist/services/aiProviders/audioValidation.js";

const args = process.argv.slice(2);
const manifestArgument = args[args.indexOf("--review-manifest") + 1];
if (!args.includes("--review-manifest") || !manifestArgument) {
  throw new Error("Usage: node scripts/export-bundled-live-coach-audio.mjs --review-manifest <path> [--unreviewed-test-fixture]");
}
const manifestPath = path.resolve(manifestArgument);
const manifest = audioPackManifestSchema.parse(JSON.parse(await readFile(manifestPath, "utf8")));
const pending = manifest.entries.filter(entry => !entry.approved).length;
if (pending && !args.includes("--unreviewed-test-fixture")) {
  throw new Error(`${pending} entries still require listening review. No production bundle was exported.`);
}
const destination = fileURLToPath(new URL("../../ios/Outbound/Outbound/LiveCoachAudio/", import.meta.url));
await mkdir(destination, { recursive: true });
const entries = [];
for (const entry of manifest.entries) {
  if (!entry.reviewFileName) throw new Error(`Missing review file for ${entry.cueKey}.`);
  const source = path.join(path.dirname(manifestPath), entry.reviewFileName);
  const audio = await readFile(source);
  const sha = createHash("sha256").update(audio).digest("hex");
  const validated = validateLiveCoachWav(audio, { maximumDurationMilliseconds: 8000 });
  if (sha !== entry.sha256 || audio.length !== entry.byteCount || validated.durationMilliseconds !== entry.durationMilliseconds) {
    throw new Error(`Audio changed after review: ${entry.cueKey}/${entry.locale}/${entry.voiceProfileId}.`);
  }
  await copyFile(source, path.join(destination, `${sha}.wav`));
  const { reviewFileName: _, url: __, ...metadata } = entry;
  entries.push({ ...metadata, bundledResourceName: sha });
}
const active = new Set(entries.map(entry => `${entry.sha256}.wav`));
for (const name of await readdir(destination)) {
  if (/^[a-f0-9]{64}\.wav$/.test(name) && !active.has(name)) await unlink(path.join(destination, name));
}
await writeFile(path.join(destination, "manifest.json"), `${JSON.stringify({ ...manifest, entries }, null, 2)}\n`);
console.log(`Exported ${entries.length} entries; pending=${pending}. ${pending ? "Test fixture only; production playback rejects this manifest." : "Approved bundle ready."}`);
