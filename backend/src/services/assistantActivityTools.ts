import type { PrismaClient } from "@prisma/client/index.js";

export type AssistantActivitySummary = {
  id: string;
  title: string | null;
  type: string;
  startedAt: string;
  endedAt: string | null;
  durationSecs: number | null;
  distanceM: number | null;
  elevationM: number | null;
  avgPace: number | null;
  photoCount: number;
};

export type AssistantActivityToolContext = {
  generatedAt: string;
  timeZoneIdentifier: string;
  recentActivities: AssistantActivitySummary[];
};

type ActivityToolInput = {
  prisma: PrismaClient;
  userId: string;
  prompt: string;
  timeZoneIdentifier?: string | null;
  now?: Date;
};

type ActivityToolResult = {
  context: AssistantActivityToolContext;
  directAnswer: string | null;
};

const DEFAULT_TIME_ZONE = "UTC";

export async function runAssistantActivityTools({
  prisma,
  userId,
  prompt,
  timeZoneIdentifier,
  now = new Date(),
}: ActivityToolInput): Promise<ActivityToolResult> {
  const resolvedTimeZone = safeTimeZoneIdentifier(timeZoneIdentifier);
  const recentActivities = await prisma.activity.findMany({
    where: { userId },
    orderBy: { startedAt: "desc" },
    take: 20,
    select: {
      id: true,
      title: true,
      type: true,
      startedAt: true,
      endedAt: true,
      durationSecs: true,
      distanceM: true,
      elevationM: true,
      avgPace: true,
      photos: { select: { id: true } },
    },
  });

  const summaries = recentActivities.map((activity) => ({
    id: activity.id,
    title: activity.title,
    type: activity.type,
    startedAt: activity.startedAt.toISOString(),
    endedAt: activity.endedAt?.toISOString() ?? null,
    durationSecs: activity.durationSecs ?? null,
    distanceM: activity.distanceM ?? null,
    elevationM: activity.elevationM ?? null,
    avgPace: activity.avgPace ?? null,
    photoCount: activity.photos.length,
  }));

  return {
    context: {
      generatedAt: now.toISOString(),
      timeZoneIdentifier: resolvedTimeZone,
      recentActivities: summaries,
    },
    directAnswer: answerDirectActivityQuestion(prompt, summaries, resolvedTimeZone, now),
  };
}

export function answerDirectActivityQuestion(
  prompt: string,
  activities: AssistantActivitySummary[],
  timeZoneIdentifier: string = DEFAULT_TIME_ZONE,
  now: Date = new Date()
): string | null {
  const normalized = prompt.toLowerCase();
  if (!normalized.includes("yesterday")) {
    return null;
  }

  const asksAboutRun =
    /\b(run|running|ran)\b/.test(normalized) ||
    normalized.includes("did i run");
  const asksAboutActivity =
    asksAboutRun ||
    /\b(activity|activities|workout|workouts|exercise)\b/.test(normalized);

  if (!asksAboutActivity) {
    return null;
  }

  const { start, end } = relativeDayWindow(now, -1, timeZoneIdentifier);
  const yesterdayActivities = activities.filter((activity) => {
    const startedAt = new Date(activity.startedAt);
    return startedAt >= start && startedAt < end;
  });
  const matchingActivities = asksAboutRun
    ? yesterdayActivities.filter(isRunActivity)
    : yesterdayActivities;

  if (matchingActivities.length > 0) {
    const lead = asksAboutRun ? "Yes, you ran yesterday." : "Yes, you had activity yesterday.";
    const details = matchingActivities.map(formatActivityOneLine).join(" ");
    return `${lead} ${details}`;
  }

  if (asksAboutRun && yesterdayActivities.length > 0) {
    const details = yesterdayActivities.map(formatActivityOneLine).join(" ");
    return `I found activity yesterday, but not a run. ${details}`;
  }

  return asksAboutRun
    ? "I do not see a synced run from yesterday."
    : "I do not see a synced activity from yesterday.";
}

function isRunActivity(activity: AssistantActivitySummary): boolean {
  const type = activity.type.toLowerCase();
  return type === "run" || type === "running";
}

function formatActivityOneLine(activity: AssistantActivitySummary): string {
  const title = activity.title?.trim() || activity.type;
  const distance = activity.distanceM == null ? null : `${(activity.distanceM / 1000).toFixed(1)} km`;
  const duration = activity.durationSecs == null ? null : formatDuration(activity.durationSecs);
  const parts = [distance, duration].filter(Boolean).join(" in ");
  return parts ? `${title}: ${parts}.` : `${title}.`;
}

function formatDuration(totalSeconds: number): string {
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;
  if (hours > 0) {
    return `${hours}h ${minutes}m`;
  }
  if (minutes > 0) {
    return `${minutes}m ${seconds}s`;
  }
  return `${seconds}s`;
}

function safeTimeZoneIdentifier(timeZoneIdentifier: string | null | undefined): string {
  if (!timeZoneIdentifier) {
    return DEFAULT_TIME_ZONE;
  }
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: timeZoneIdentifier }).format(new Date());
    return timeZoneIdentifier;
  } catch {
    return DEFAULT_TIME_ZONE;
  }
}

function relativeDayWindow(now: Date, offsetDays: number, timeZoneIdentifier: string) {
  const parts = zonedDateParts(now, timeZoneIdentifier);
  const shifted = new Date(Date.UTC(parts.year, parts.month - 1, parts.day + offsetDays));
  const start = zonedLocalTimeToUtc(
    shifted.getUTCFullYear(),
    shifted.getUTCMonth() + 1,
    shifted.getUTCDate(),
    0,
    0,
    0,
    timeZoneIdentifier
  );
  const next = new Date(Date.UTC(shifted.getUTCFullYear(), shifted.getUTCMonth(), shifted.getUTCDate() + 1));
  const end = zonedLocalTimeToUtc(
    next.getUTCFullYear(),
    next.getUTCMonth() + 1,
    next.getUTCDate(),
    0,
    0,
    0,
    timeZoneIdentifier
  );
  return { start, end };
}

function zonedLocalTimeToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  timeZoneIdentifier: string
) {
  const utcGuess = new Date(Date.UTC(year, month - 1, day, hour, minute, second));
  const offset = timeZoneOffsetMilliseconds(utcGuess, timeZoneIdentifier);
  return new Date(utcGuess.getTime() - offset);
}

function timeZoneOffsetMilliseconds(date: Date, timeZoneIdentifier: string): number {
  const parts = zonedDateTimeParts(date, timeZoneIdentifier);
  const zonedAsUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
  );
  return zonedAsUtc - date.getTime();
}

function zonedDateParts(date: Date, timeZoneIdentifier: string) {
  const parts = zonedDateTimeParts(date, timeZoneIdentifier);
  return { year: parts.year, month: parts.month, day: parts.day };
}

function zonedDateTimeParts(date: Date, timeZoneIdentifier: string) {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone: timeZoneIdentifier,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
    hour12: false,
  });
  const parts = Object.fromEntries(formatter.formatToParts(date).map((part) => [part.type, part.value]));
  const hour = Number(parts.hour === "24" ? "0" : parts.hour);
  return {
    year: Number(parts.year),
    month: Number(parts.month),
    day: Number(parts.day),
    hour,
    minute: Number(parts.minute),
    second: Number(parts.second),
  };
}
