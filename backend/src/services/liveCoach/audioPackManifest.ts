import { z } from "zod";
import { LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS, SUPPORTED_AI_LOCALES, VOICE_PROFILE_IDS } from "../aiProviders/types.js";

const coachPersonaIdSchema = z.enum([
  "plainstride_supportive_v1",
  "plainstride_focused_v1",
  "plainstride_calm_v1",
]);

export const audioPackManifestSchema = z.object({
  contractVersion: z.literal(1),
  catalogVersion: z.string().min(1).max(80),
  generatedAt: z.string().datetime(),
  entries: z.array(z.object({
    cueKey: z.string().min(1).max(100),
    locale: z.enum(SUPPORTED_AI_LOCALES),
    voiceProfileId: z.enum(VOICE_PROFILE_IDS),
    scriptStyleId: z.enum(["standard", "calm"]),
    compatibleCoachPersonaIds: z.array(coachPersonaIdSchema).min(1).max(3),
    transcript: z.string().min(1).max(240),
    sha256: z.string().length(64).regex(/^[a-f0-9]+$/),
    byteCount: z.number().int().positive().max(512 * 1024),
    durationMilliseconds: z.number().int().positive().max(LIVE_COACH_FIXED_AUDIO_MAX_DURATION_MILLISECONDS),
    contentType: z.literal("audio/wav"),
    url: z.string().url().optional(),
    reviewFileName: z.string().regex(/^[a-f0-9]{64}\.wav$/).optional(),
    approved: z.boolean(),
  }).strict()).min(1),
}).strict();

export type AudioPackManifest = z.infer<typeof audioPackManifestSchema>;
