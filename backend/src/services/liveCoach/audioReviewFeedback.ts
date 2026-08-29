export const LIVE_COACH_REJECTION_REASON_CODES = [
  "pronunciation",
  "too_fast",
  "too_slow",
  "unnatural_pacing",
  "wrong_tone",
  "wrong_emphasis",
  "audio_artifact",
  "transcript_mismatch",
  "other",
] as const;

export type LiveCoachRejectionReasonCode = (typeof LIVE_COACH_REJECTION_REASON_CODES)[number];
export type LiveCoachRejectionReason = {
  code: LiveCoachRejectionReasonCode;
  detail?: string;
};
export type LiveCoachReviewStatus = "unreviewed" | "approved" | "rejected";
export type LiveCoachReviewProgress = {
  contractVersion: 1;
  catalogVersion: string;
  entries: Record<string, {
    sha256: string;
    status: LiveCoachReviewStatus;
    reviewedAt?: string;
    rejectionReason?: LiveCoachRejectionReason;
  }>;
};

type ReviewIdentity = {
  cueKey: string;
  locale: string;
  voiceProfileId: string;
  scriptStyleId: string;
};

export function liveCoachReviewEntryID(entry: ReviewIdentity): string {
  return [entry.cueKey, entry.locale, entry.voiceProfileId, entry.scriptStyleId].join("|");
}

export function isLiveCoachRejectionReasonCode(value: unknown): value is LiveCoachRejectionReasonCode {
  return LIVE_COACH_REJECTION_REASON_CODES.includes(value as LiveCoachRejectionReasonCode);
}

export function normalizeLiveCoachRejectionReason(value: unknown): LiveCoachRejectionReason | null {
  if (typeof value !== "object" || value === null) return null;
  const candidate = value as { code?: unknown; detail?: unknown };
  if (!isLiveCoachRejectionReasonCode(candidate.code)) return null;
  if (candidate.detail !== undefined && typeof candidate.detail !== "string") return null;
  const detail = typeof candidate.detail === "string" ? candidate.detail.trim() : "";
  if (detail.length > 500 || (candidate.code === "other" && !detail)) return null;
  return { code: candidate.code, ...(detail ? { detail } : {}) };
}

export function parseLiveCoachReviewProgress(
  value: unknown,
  expectedCatalogVersion: string
): LiveCoachReviewProgress | null {
  if (typeof value !== "object" || value === null) return null;
  const candidate = value as Partial<LiveCoachReviewProgress>;
  if (candidate.contractVersion !== 1
      || candidate.catalogVersion !== expectedCatalogVersion
      || typeof candidate.entries !== "object"
      || candidate.entries === null) return null;
  return candidate as LiveCoachReviewProgress;
}

export function liveCoachRegenerationInstruction(reason: LiveCoachRejectionReason): string {
  let correction: string;
  switch (reason.code) {
    case "pronunciation": correction = "Correct the pronunciation, with special attention to the reviewer's note."; break;
    case "too_fast": correction = "Speak more slowly while keeping the cue concise and natural."; break;
    case "too_slow": correction = "Speak more briskly without sounding rushed."; break;
    case "unnatural_pacing": correction = "Use smoother, more natural pacing and pauses."; break;
    case "wrong_tone": correction = "Use a natural, supportive running-coach tone appropriate to the cue."; break;
    case "wrong_emphasis": correction = "Use natural emphasis that matches the meaning of the cue."; break;
    case "audio_artifact": correction = "Produce clean speech without clipping, glitches, noise, or truncated words."; break;
    case "transcript_mismatch": correction = "Speak every supplied word exactly, with no substitutions, omissions, or additions."; break;
    case "other": correction = "Correct the issue described in the reviewer's note."; break;
  }
  const detail = reason.detail ? ` Reviewer note: ${reason.detail}` : "";
  return `The previous rendition was rejected. ${correction}${detail}`;
}
