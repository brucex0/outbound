import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { loadAIProviderConfiguration, assertAIProviderConfiguration } from "../services/aiProviders/config.js";
import { buildAIProviderRegistry } from "../services/aiProviders/registry.js";
import { resolveAIRoute } from "../services/aiProviders/router.js";
import type { SupportedAILocale, VoiceProfileId } from "../services/aiProviders/types.js";
import type { AudioPackManifest } from "../services/liveCoach/audioPackManifest.js";
import { stableLiveCoachInstructions } from "../services/liveCoach/liveCoachPrompt.js";
import { audioPackManifestSchema } from "../services/liveCoach/audioPackManifest.js";
import { validateLiveCoachWav } from "../services/aiProviders/audioValidation.js";
import { COACH_PERSONAS } from "../services/liveCoach/liveCoachCatalog.js";

type SourceCatalog = {
  catalogVersion: string;
  entries: Array<{
    cueKey: string;
    scriptStyleId: "standard" | "calm";
    texts: Record<SupportedAILocale, string>;
  }>;
};

const args = parseArgs(process.argv.slice(2));
if (args.provider !== "alibaba") throw new Error(`Unsupported live-coach provider: ${args.provider}.`);
const providerConfig = loadAIProviderConfiguration();
assertAIProviderConfiguration(providerConfig);
const catalogPath = path.resolve(process.cwd(), "resources/liveCoachAudio/catalog.v1.json");
const source = JSON.parse(await readFile(catalogPath, "utf8")) as SourceCatalog;
if (args.catalogVersion && args.catalogVersion !== source.catalogVersion) {
  throw new Error(`Catalog version mismatch: requested ${args.catalogVersion}, source is ${source.catalogVersion}.`);
}
const outputDirectory = path.resolve(process.cwd(), args.output ?? `.local/live-coach-review/${source.catalogVersion}`);
await mkdir(outputDirectory, { recursive: true });
const existingManifest = await loadExistingManifest(path.join(outputDirectory, "review-manifest.json"));
const registry = buildAIProviderRegistry(providerConfig);
const manifest: AudioPackManifest = {
  contractVersion: 1,
  catalogVersion: source.catalogVersion,
  generatedAt: new Date().toISOString(),
  entries: [],
};

for (const voiceProfileId of Object.keys(providerConfig.alibaba.voiceMap) as VoiceProfileId[]) {
  for (const locale of ["en", "es", "zh-Hans"] as const) {
    for (const entry of source.entries) {
      const text = entry.texts[locale];
      const resolved = resolveAIRoute(registry, {
        requestKind: "live_coach_fixed_asset",
        market: "global",
        locale,
        voiceProfileId,
        requiredCapabilities: ["audio_output", "combined_text_audio"],
        deploymentRegion: providerConfig.alibaba.deploymentRegion,
        latencyClass: "offline",
      }, providerConfig.routePolicyVersion);
      const hash = createHash("sha256").update(JSON.stringify({
        text: text.trim(), locale, voiceProfileId, scriptStyleId: entry.scriptStyleId,
        audio: "wav-pcm_s16le-24000-mono", route: resolved.route,
      })).digest("hex");
      const fileName = `${hash}.wav`;
      const filePath = path.join(outputDirectory, fileName);
      let audio: Buffer;
      try {
        audio = await readFile(filePath);
        validateLiveCoachWav(audio);
      } catch {
        const result = await resolved.provider.generateCue({
          requestId: crypto.randomUUID(),
          locale,
          coachPersonaId: "plainstride_supportive_v1",
          coachPersonaInstructions: "Speak naturally and clearly without changing the supplied fixed text.",
          voiceProfileId,
          providerVoice: resolved.route.providerVoice,
          semanticMoment: entry.cueKey,
          stableInstructions: stableLiveCoachInstructions(locale),
          compiledContext: {
            version: 1, runnerModelVersion: "fixed-asset", workout: null, readiness: null,
            guidancePriorities: [], cuePreferences: [], safetyRequiresFixedOnly: false,
          },
          liveState: { elapsedSeconds: 0, distanceMeters: 0, routeGuidanceActive: false },
          recentCueSummaries: [],
          maximumSpokenWordsEquivalent: 40,
          exactTranscript: text,
          deadline: new Date(Date.now() + 30_000),
        }, new AbortController().signal);
        audio = Buffer.from(result.audio);
        await writeFile(filePath, audio);
      }
      manifest.entries.push({
        cueKey: entry.cueKey,
        locale,
        voiceProfileId,
        scriptStyleId: entry.scriptStyleId,
        compatibleCoachPersonaIds: COACH_PERSONAS.filter((persona) =>
          persona.allowedVoiceProfileIds.includes(voiceProfileId)
          && (persona.fixedScriptStyleId === entry.scriptStyleId || entry.scriptStyleId === "standard")
        ).map((persona) => persona.id),
        transcript: text,
        sha256: createHash("sha256").update(audio).digest("hex"),
        byteCount: audio.byteLength,
        durationMilliseconds: wavDuration(audio),
        contentType: "audio/wav",
        reviewFileName: fileName,
        approved: existingManifest?.entries.some((existing) =>
          existing.cueKey === entry.cueKey
          && existing.locale === locale
          && existing.voiceProfileId === voiceProfileId
          && existing.scriptStyleId === entry.scriptStyleId
          && existing.sha256 === createHash("sha256").update(audio).digest("hex")
          && existing.approved
        ) ?? false,
      });
    }
  }
}
await writeFile(path.join(outputDirectory, "review-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Generated ${manifest.entries.length} review assets in ${outputDirectory}. Listen to every asset and mark approved=true before publishing.`);

function parseArgs(values: string[]) {
  const result: { catalogVersion?: string; output?: string; provider: string } = { provider: "alibaba" };
  for (let index = 0; index < values.length; index += 1) {
    if (values[index] === "--catalog-version") result.catalogVersion = values[++index];
    else if (values[index] === "--output") result.output = values[++index];
    else if (values[index] === "--provider") result.provider = values[++index];
  }
  return result;
}
async function loadExistingManifest(manifestPath: string): Promise<AudioPackManifest | null> {
  try {
    return audioPackManifestSchema.parse(JSON.parse(await readFile(manifestPath, "utf8")));
  } catch {
    return null;
  }
}
function wavDuration(audio: Buffer): number {
  for (let offset = 12; offset + 8 <= audio.length;) {
    const id = audio.toString("ascii", offset, offset + 4);
    const size = audio.readUInt32LE(offset + 4);
    if (id === "data") return Math.round((size / 48_000) * 1_000);
    offset += 8 + size + (size % 2);
  }
  throw new Error("Generated WAV is missing its data chunk.");
}
