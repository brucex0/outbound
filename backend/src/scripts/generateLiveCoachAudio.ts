import { createHash } from "node:crypto";
import { mkdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";
import { loadAIProviderConfiguration, assertAIProviderConfiguration } from "../services/aiProviders/config.js";
import { buildAIProviderRegistry } from "../services/aiProviders/registry.js";
import { resolveAIRoute } from "../services/aiProviders/router.js";
import { LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS, VOICE_PROFILE_IDS, type SupportedAILocale, type VoiceProfileId } from "../services/aiProviders/types.js";
import type { AudioPackManifest } from "../services/liveCoach/audioPackManifest.js";
import { stableLiveCoachInstructions } from "../services/liveCoach/liveCoachPrompt.js";
import { audioPackManifestSchema } from "../services/liveCoach/audioPackManifest.js";
import { validateLiveCoachWav } from "../services/aiProviders/audioValidation.js";
import { AIProviderError } from "../services/aiProviders/errors.js";
import { COACH_PERSONAS } from "../services/liveCoach/liveCoachCatalog.js";
import {
  liveCoachRegenerationInstruction,
  liveCoachReviewEntryID,
  normalizeLiveCoachRejectionReason,
  parseLiveCoachReviewProgress,
  type LiveCoachReviewProgress,
} from "../services/liveCoach/audioReviewFeedback.js";

type SourceCatalog = {
  catalogVersion: string;
  entries: Array<{
    cueKey: string;
    scriptStyleId: "standard" | "calm";
    texts: Record<SupportedAILocale, string>;
  }>;
};

const GENERATION_MAX_ATTEMPTS = 3;
const GENERATION_RETRY_DELAY_MILLISECONDS = 1_000;

const args = parseArgs(process.argv.slice(2));
if (args.provider !== "alibaba") throw new Error(`Unsupported live-coach provider: ${args.provider}.`);
const catalogPath = path.resolve(process.cwd(), "resources/liveCoachAudio/catalog.v1.json");
const source = JSON.parse(await readFile(catalogPath, "utf8")) as SourceCatalog;
if (args.catalogVersion && args.catalogVersion !== source.catalogVersion) {
  throw new Error(`Catalog version mismatch: requested ${args.catalogVersion}, source is ${source.catalogVersion}.`);
}
if (args.list) {
  printCatalog(source);
  process.exit(0);
}
const providerConfig = loadAIProviderConfiguration();
assertAIProviderConfiguration(providerConfig);
const outputDirectory = path.resolve(process.cwd(), args.output ?? `.local/live-coach-review/${source.catalogVersion}`);
await mkdir(outputDirectory, { recursive: true });
const existingManifest = await loadExistingManifest(path.join(outputDirectory, "review-manifest.json"));
const reviewProgress = await loadReviewProgress(path.join(outputDirectory, "review-progress.json"), source.catalogVersion);
const registry = buildAIProviderRegistry(providerConfig);
const manifest: AudioPackManifest = {
  contractVersion: 1,
  catalogVersion: source.catalogVersion,
  generatedAt: new Date().toISOString(),
  entries: args.voiceProfileId || args.locale || args.cueKey || args.rejected
    ? [...(existingManifest?.entries ?? [])]
    : [],
};

const voiceProfileIds = args.voiceProfileId
  ? [args.voiceProfileId]
  : Object.keys(providerConfig.alibaba.voiceMap) as VoiceProfileId[];
const locales = args.locale
  ? [args.locale]
  : ["en", "es", "zh-Hans"] as SupportedAILocale[];
const entries = args.cueKey
  ? source.entries.filter((entry) => entry.cueKey === args.cueKey)
  : source.entries;
if (args.voiceProfileId && !providerConfig.alibaba.voiceMap[args.voiceProfileId]) {
  throw new Error(`Voice profile is not configured for Alibaba: ${args.voiceProfileId}.`);
}
if (entries.length === 0) {
  throw new Error(`Unknown live-coach cue: ${args.cueKey}.`);
}
const targetIDs = new Set<string>();
for (const voiceProfileId of voiceProfileIds) {
  for (const locale of locales) {
    for (const entry of entries) {
      const id = liveCoachReviewEntryID({
        cueKey: entry.cueKey,
        locale,
        voiceProfileId,
        scriptStyleId: entry.scriptStyleId,
      });
      const savedReview = reviewProgress?.entries[id];
      const existingEntry = existingManifest?.entries.find((existing) => liveCoachReviewEntryID(existing) === id);
      if (!args.rejected || (savedReview?.status === "rejected" && savedReview.sha256 === existingEntry?.sha256)) {
        targetIDs.add(id);
      }
    }
  }
}
if (targetIDs.size === 0) throw new Error("No current rejected live-coach assets match the selected filters.");
const forceGeneration = args.force || args.rejected;
const totalAssetCount = targetIDs.size;
let assetIndex = 0;
for (const voiceProfileId of voiceProfileIds) {
  for (const locale of locales) {
    for (const entry of entries) {
      const reviewEntryID = liveCoachReviewEntryID({
        cueKey: entry.cueKey,
        locale,
        voiceProfileId,
        scriptStyleId: entry.scriptStyleId,
      });
      if (!targetIDs.has(reviewEntryID)) continue;
      assetIndex += 1;
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
      const existingEntry = existingManifest?.entries.find((existing) =>
        existing.cueKey === entry.cueKey
        && existing.locale === locale
        && existing.voiceProfileId === voiceProfileId
        && existing.scriptStyleId === entry.scriptStyleId
      );
      const savedReview = reviewProgress?.entries[reviewEntryID];
      const rejectionReason = forceGeneration
        && existingEntry
        && savedReview?.status === "rejected"
        && savedReview.sha256 === existingEntry.sha256
        ? normalizeLiveCoachRejectionReason(savedReview.rejectionReason)
        : null;
      const regenerationInstruction = rejectionReason
        ? liveCoachRegenerationInstruction(rejectionReason)
        : "";
      let audio: Buffer;
      if (!forceGeneration) {
        try {
          audio = await readFile(filePath);
          validateLiveCoachWav(audio, {
            maximumDurationMilliseconds: LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS,
          });
          console.log(`[${assetIndex}/${totalAssetCount}] cached ${voiceProfileId}/${locale}/${entry.cueKey}`);
        } catch {
          audio = await generateAudio();
        }
      } else {
        audio = await generateAudio();
      }

      const manifestEntry: AudioPackManifest["entries"][number] = {
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
      };
      const existingIndex = manifest.entries.findIndex((existing) =>
        existing.cueKey === manifestEntry.cueKey
        && existing.locale === manifestEntry.locale
        && existing.voiceProfileId === manifestEntry.voiceProfileId
        && existing.scriptStyleId === manifestEntry.scriptStyleId
      );
      if (existingIndex >= 0) manifest.entries[existingIndex] = manifestEntry;
      else manifest.entries.push(manifestEntry);

      async function generateAudio(): Promise<Buffer> {
        console.log(`[${assetIndex}/${totalAssetCount}] generating ${voiceProfileId}/${locale}/${entry.cueKey}`);
        if (rejectionReason) console.log(`  applying rejection feedback: ${rejectionReason.code}`);
        const result = await generateWithRetry(
          () => resolved.provider.generateCue({
            requestId: crypto.randomUUID(),
            locale,
            coachPersonaId: "plainstride_supportive_v1",
            coachPersonaInstructions: [
              "Speak naturally and clearly without changing the supplied fixed text.",
              regenerationInstruction,
            ].filter(Boolean).join(" "),
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
          }, new AbortController().signal),
          `[${assetIndex}/${totalAssetCount}] ${voiceProfileId}/${locale}/${entry.cueKey}`
        );
        const generatedAudio = Buffer.from(result.audio);
        await writeFile(filePath, generatedAudio);
        return generatedAudio;
      }
    }
  }
}
await writeFile(path.join(outputDirectory, "review-manifest.json"), `${JSON.stringify(manifest, null, 2)}\n`);
console.log(`Generated ${manifest.entries.length} review assets in ${outputDirectory}. Listen to every asset and mark approved=true before publishing.`);

function parseArgs(values: string[]) {
  const result: {
    catalogVersion?: string;
    output?: string;
    provider: string;
    list: boolean;
    voiceProfileId?: VoiceProfileId;
    locale?: SupportedAILocale;
    cueKey?: string;
    force: boolean;
    rejected: boolean;
  } = {
    provider: "alibaba",
    list: false,
    force: false,
    rejected: false,
  };
  for (let index = 0; index < values.length; index += 1) {
    if (values[index] === "--catalog-version") result.catalogVersion = requiredValue(values, ++index, "--catalog-version");
    else if (values[index] === "--output") result.output = requiredValue(values, ++index, "--output");
    else if (values[index] === "--provider") result.provider = requiredValue(values, ++index, "--provider");
    else if (values[index] === "--voice-profile") {
      const value = requiredValue(values, ++index, "--voice-profile");
      if (!VOICE_PROFILE_IDS.includes(value as VoiceProfileId)) throw new Error(`Unknown voice profile: ${value}.`);
      result.voiceProfileId = value as VoiceProfileId;
    }
    else if (values[index] === "--locale") {
      const value = requiredValue(values, ++index, "--locale");
      if (!["en", "es", "zh-Hans"].includes(value)) throw new Error(`Unsupported locale: ${value}.`);
      result.locale = value as SupportedAILocale;
    }
    else if (values[index] === "--cue") result.cueKey = requiredValue(values, ++index, "--cue");
    else if (values[index] === "--force") result.force = true;
    else if (values[index] === "--rejected") result.rejected = true;
    else if (values[index] === "--list") result.list = true;
    else throw new Error(`Unknown argument: ${values[index]}.`);
  }
  return result;
}
function requiredValue(values: string[], index: number, flag: string): string {
  const value = values[index];
  if (!value || value.startsWith("--")) throw new Error(`${flag} requires a value.`);
  return value;
}
function printCatalog(source: SourceCatalog): void {
  console.log(`Catalog ${source.catalogVersion}: ${source.entries.length} cues, 3 locales, ${VOICE_PROFILE_IDS.length} voices, ${source.entries.length * 3 * VOICE_PROFILE_IDS.length} WAV assets.`);
  for (const entry of source.entries) {
    console.log(`\n${entry.cueKey} [${entry.scriptStyleId}]`);
    console.log(`  en: ${entry.texts.en}`);
    console.log(`  es: ${entry.texts.es}`);
    console.log(`  zh-Hans: ${entry.texts["zh-Hans"]}`);
  }
}
async function loadExistingManifest(manifestPath: string): Promise<AudioPackManifest | null> {
  try {
    return audioPackManifestSchema.parse(JSON.parse(await readFile(manifestPath, "utf8")));
  } catch {
    return null;
  }
}
async function loadReviewProgress(
  progressPath: string,
  catalogVersion: string
): Promise<LiveCoachReviewProgress | null> {
  try {
    return parseLiveCoachReviewProgress(JSON.parse(await readFile(progressPath, "utf8")), catalogVersion);
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

async function generateWithRetry<T>(generate: () => Promise<T>, assetLabel: string): Promise<T> {
  for (let attempt = 1; attempt <= GENERATION_MAX_ATTEMPTS; attempt += 1) {
    try {
      return await generate();
    } catch (error) {
      if (!isRetryableGenerationFailure(error) || attempt === GENERATION_MAX_ATTEMPTS) throw error;
      const delayMilliseconds = GENERATION_RETRY_DELAY_MILLISECONDS * attempt;
      console.warn(`${assetLabel} retrying after ${generationFailureSummary(error)} (attempt ${attempt + 1}/${GENERATION_MAX_ATTEMPTS})`);
      await delay(delayMilliseconds);
    }
  }
  throw new Error("Live-coach audio generation exhausted its retry attempts.");
}

function isRetryableGenerationFailure(error: unknown): error is AIProviderError {
  return error instanceof AIProviderError && (error.retryable || error.code === "invalid_provider_output");
}

function generationFailureSummary(error: AIProviderError): string {
  return `${error.code}: ${error.message}`;
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
