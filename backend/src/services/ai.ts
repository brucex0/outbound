import { generateStructuredAI, type AIOperation } from "./aiReliability/structuredGeneration.js";
import { ThinkingLevel } from "@google/genai";
import { gpt4oMiniTranscribe } from "./ai-transcribe.js";
import { parseUtteranceCommand } from "./commandParser.js";
import type { AssistantActivityToolContext } from "./assistantActivityTools.js";
import type { CompiledContext, CompanionActionProposal } from "./companion/types.js";
import { localeInstruction, type SupportedLocale } from "../middleware/locale.js";
// Final-pass transcription and command parsing for short recorded utterances
export async function runFinalTranscriptionAndParse({ audioUrl, language }: { audioUrl: string; language?: string }) {
  // 1. Run OpenAI gpt-4o-mini transcription
  const transcript = await gpt4oMiniTranscribe({ audioUrl, language });
  // 2. Run deterministic command parser
  const command = parseUtteranceCommand(transcript);
  return { transcript, command };
}

// Shared guide instruction across configured providers.
const GUIDE_SYSTEM_INSTRUCTION = `You are an expert running and endurance sports guide AI.
Your role is to analyze athlete data and produce actionable, personalized guidance insights.
Be specific, data-driven, and empathetic. Never give generic advice — always reference the athlete's actual numbers.`;

type AssistantCapability = "discover" | "navigate" | "support" | "brainstorm" | "plan";

type AssistantChatContext = {
  guideName: string;
  activityCount: number | null;
  weeklyDistanceKilometers: number | null;
  currentGoalSummary?: string | null;
  currentScreen?: string | null;
  isRecordingActive?: boolean;
  timeZoneIdentifier?: string | null;
};

type AssistantChatMessage = {
  role: "user" | "assistant";
  text: string;
  capability?: AssistantCapability;
};

type AssistantResponse = {
  message: string;
};

export async function analyzeActivity(
  activityData: object,
  guideContext: object,
  locale: SupportedLocale = "en"
): Promise<string> {
  const content = await generateMessageJSON(
    `${GUIDE_SYSTEM_INSTRUCTION}\n${localeInstruction(locale)}\nReturn JSON only as {"message":"..."}.`,
    `Analyze this activity and provide guidance insights.\n\nGuide context: ${JSON.stringify(guideContext)}\n\nActivity: ${JSON.stringify(activityData)}`,
    1024, 0.3, "activity_analysis"
  );
  return (JSON.parse(content) as AssistantResponse).message.trim();
}

export async function generateWeeklyReview(
  userId: string,
  activities: object[],
  guideProfile: object,
  locale: SupportedLocale = "en"
): Promise<string> {
  const content = await generateMessageJSON(
    `${GUIDE_SYSTEM_INSTRUCTION}\n${localeInstruction(locale)}\nReturn JSON only as {"message":"..."}.`,
    `Write a weekly training review for this athlete.
Include: what went well, what to improve, next week's focus, and one specific drill or workout recommendation.

Guide profile: ${JSON.stringify(guideProfile)}
This week's activities: ${JSON.stringify(activities)}`,
    2048, 0.3, "weekly_review"
  );
  return (JSON.parse(content) as AssistantResponse).message.trim();
}

export async function generateAssistantReply(input: {
  prompt: string;
  capability: AssistantCapability;
  context: AssistantChatContext;
  messages: AssistantChatMessage[];
  firebaseUid?: string;
  activityContext?: AssistantActivityToolContext | null;
  locale: SupportedLocale;
}): Promise<string> {
  const systemPrompt = `You are Plainstride's in-app assistant.
You help with product discovery, navigation, support, brainstorming, and planning.
Be concise, warm, and specific to Plainstride.
Do not mention internal implementation details.
You may answer from the provided backend activity context. Do not claim you lack access to activity history when the backend activity context contains the needed facts.
If the backend activity context is empty or unavailable, say what is missing in plain product terms.
Prefer short, practical answers with a clear next step when useful.
If the user is in an active recording flow, keep the answer extra brief and non-distracting.
${localeInstruction(input.locale)}
Return only valid JSON in the shape {"message":"..."} with no markdown fencing.`;

  const userPrompt = `Assistant capability: ${input.capability}
Current screen: ${input.context.currentScreen ?? "unknown"}
Recording active: ${input.context.isRecordingActive ? "yes" : "no"}
Companion style: ${input.context.guideName}
Saved activities: ${input.context.activityCount ?? "unavailable"}
Weekly distance: ${input.context.weeklyDistanceKilometers?.toFixed(1) ?? "unavailable"} km
Goal summary: ${input.context.currentGoalSummary ?? "No active goal"}
Time zone: ${input.context.timeZoneIdentifier ?? input.activityContext?.timeZoneIdentifier ?? "unknown"}
Firebase UID: ${input.firebaseUid ?? "not provided"}

Backend activity context:
${formatActivityContextForPrompt(input.activityContext)}

Recent conversation:
${input.messages.slice(-10).map((message) => `${message.role}: ${message.text}`).join("\n") || "No prior conversation."}

App map:
- Me: motivation, companion settings, activity history, settings
- Social: Groups, rivals
- Floating orange button: start or resume a live session
- Assistant: planning, navigation, support, brainstorming

User request:
${input.prompt}

Respond in 2 to 4 short paragraphs. Keep it compact and actionable.`;

  const content = await generateMessageJSON(systemPrompt, userPrompt, 700, 0.3);
  const parsed = JSON.parse(content) as AssistantResponse;
  return parsed.message?.trim() || "";
}

export async function generateCompanionMessage(input: {
  prompt: string;
  context: CompiledContext;
  proposal: CompanionActionProposal;
  actionStatus?: string | null;
  locale: SupportedLocale;
}): Promise<string> {
  const systemPrompt = `You are Plainstride's single running companion.
Use only the compiled, provenance-bearing context supplied below.
Never claim an action happened unless actionStatus is executed.
Distinguish facts from hypotheses and mention uncertainty when it matters.
Never diagnose pain or concerning symptoms. Recommend stopping or qualified care when appropriate.
Be warm, concise, and practical. ${localeInstruction(input.locale)} Return JSON only as {"message":"..."}.`;
  const payload = {
    task: input.context.task,
    rules: input.context.systemRules,
    runnerCore: input.context.runnerCore,
    currentState: input.context.currentState,
    beliefs: input.context.beliefs,
    episodes: input.context.episodes,
    situationalSignals: input.context.situationalSignals,
    conversation: input.context.conversation,
    proposal: input.proposal,
    actionStatus: input.actionStatus ?? null,
    userRequest: input.prompt,
  };
  const content = await generateMessageJSON(systemPrompt, JSON.stringify(payload), 600, 0.2);
  const parsed = JSON.parse(content) as { message?: string };
  if (!parsed.message?.trim()) throw new Error("Companion model returned an invalid message");
  return parsed.message.trim();
}

// Keep the message JSON contract identical across configured providers.
async function generateMessageJSON(systemInstruction: string, contents: string, maxOutputTokens: number, temperature: number, operation: AIOperation = "assistant"): Promise<string> {
  const result = await generateStructuredAI({
    operation, model: process.env.APP_AI_MODEL || "gemini-3.8-flash", deadlineMilliseconds: 20_000,
    parameters: {
      contents,
      config: {
        systemInstruction, responseMimeType: "application/json",
        responseJsonSchema: { type: "object", properties: { message: { type: "string" } }, required: ["message"] },
        thinkingConfig: { thinkingLevel: ThinkingLevel.LOW },
        maxOutputTokens: maxOutputTokens + 4_096, temperature,
      },
    },
    validate: (response) => {
      const content = response.text?.trim();
      if (!content) throw new Error("Empty assistant output");
      const parsed = JSON.parse(content) as AssistantResponse;
      if (typeof parsed.message !== "string" || !parsed.message.trim()) throw new Error("Invalid AI message");
      return content;
    },
  });
  return result.value;
}

function formatActivityContextForPrompt(context: AssistantActivityToolContext | null | undefined): string {
  if (!context) {
    return "No backend activity context was available for this request.";
  }

  if (context.recentActivities.length === 0) {
    return `Generated at ${context.generatedAt}. No synced activities found.`;
  }

  const activities = context.recentActivities
    .slice(0, 12)
    .map((activity) => {
      const distanceKm = activity.distanceM == null ? "unknown distance" : `${(activity.distanceM / 1000).toFixed(1)} km`;
      const duration = activity.durationSecs == null ? "unknown duration" : `${Math.round(activity.durationSecs / 60)} min`;
      const pace = activity.avgPace == null ? "unknown pace" : `${Math.round(activity.avgPace)} sec/km`;
      return [
        activity.startedAt,
        activity.type,
        activity.title ?? "Untitled activity",
        distanceKm,
        duration,
        pace,
        `${activity.photoCount} photos`,
      ].join(" | ");
    })
    .join("\n");

  return `Generated at ${context.generatedAt} for ${context.timeZoneIdentifier}. Recent synced activities:\n${activities}`;
}
