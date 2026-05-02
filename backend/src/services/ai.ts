import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// Shared cached system prompt prefix for all coach operations
const COACH_SYSTEM_CACHE_PREFIX = `You are an expert running and endurance sports coach AI.
Your role is to analyze athlete data and produce actionable, personalized coaching insights.
Be specific, data-driven, and empathetic. Never give generic advice — always reference the athlete's actual numbers.`;

type AssistantCapability = "discover" | "navigate" | "support" | "brainstorm" | "plan";

type AssistantChatContext = {
  coachName: string;
  activityCount: number;
  weeklyDistanceKilometers: number;
  currentGoalSummary?: string | null;
  currentScreen?: string | null;
  isRecordingActive?: boolean;
};

type AssistantChatMessage = {
  role: "user" | "assistant";
  text: string;
  capability?: AssistantCapability;
};

type DeepSeekAssistantResponse = {
  message: string;
};

export async function analyzeActivity(
  activityData: object,
  coachContext: object
): Promise<string> {
  const response = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 1024,
    system: [
      {
        type: "text",
        text: COACH_SYSTEM_CACHE_PREFIX,
      },
    ],
    messages: [
      {
        role: "user",
        content: `Analyze this activity and provide coaching insights.\n\nCoach context: ${JSON.stringify(coachContext)}\n\nActivity: ${JSON.stringify(activityData)}`,
      },
    ],
  });

  return response.content[0].type === "text" ? response.content[0].text : "";
}

export async function buildCoachSystemPrompt(
  athleteProfile: object
): Promise<string> {
  const response = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 512,
    system: [
      {
        type: "text",
        text: COACH_SYSTEM_CACHE_PREFIX,
      },
    ],
    messages: [
      {
        role: "user",
        content: `Generate a concise on-device system prompt (max 300 words) for a virtual coach with this athlete profile.
The prompt will run on a small on-device LLM for real-time coaching during runs.
Focus on: the athlete's current level, known weaknesses to watch, pacing guidance, and motivational style.

Athlete: ${JSON.stringify(athleteProfile)}`,
      },
    ],
  });

  return response.content[0].type === "text" ? response.content[0].text : "";
}

export async function generateWeeklyReview(
  userId: string,
  activities: object[],
  coachProfile: object
): Promise<string> {
  const response = await client.messages.create({
    model: "claude-sonnet-4-6",
    max_tokens: 2048,
    system: [
      {
        type: "text",
        text: COACH_SYSTEM_CACHE_PREFIX,
      },
    ],
    messages: [
      {
        role: "user",
        content: `Write a weekly training review for this athlete.
Include: what went well, what to improve, next week's focus, and one specific drill or workout recommendation.

Coach profile: ${JSON.stringify(coachProfile)}
This week's activities: ${JSON.stringify(activities)}`,
      },
    ],
  });

  return response.content[0].type === "text" ? response.content[0].text : "";
}

export async function generateAssistantReply(input: {
  prompt: string;
  capability: AssistantCapability;
  context: AssistantChatContext;
  messages: AssistantChatMessage[];
  firebaseUid?: string;
}): Promise<string> {
  const apiKey = process.env.APP_AI_KEY;
  const baseUrl = (process.env.APP_AI_BASE_URL || "https://api.deepseek.com").replace(/\/+$/, "");
  const model = process.env.APP_AI_MODEL || "deepseek-chat";

  if (!apiKey) {
    throw new Error("APP_AI_KEY is not configured");
  }

  const systemPrompt = `You are Outbound's in-app assistant.
You help with product discovery, navigation, support, brainstorming, and planning.
Be concise, warm, and specific to Outbound.
Do not mention internal implementation details.
Prefer short, practical answers with a clear next step when useful.
If the user is in an active recording flow, keep the answer extra brief and non-distracting.
Return only valid JSON in the shape {"message":"..."} with no markdown fencing.`;

  const userPrompt = `Assistant capability: ${input.capability}
Current screen: ${input.context.currentScreen ?? "unknown"}
Recording active: ${input.context.isRecordingActive ? "yes" : "no"}
Coach name: ${input.context.coachName}
Saved activities: ${input.context.activityCount}
Weekly distance: ${input.context.weeklyDistanceKilometers.toFixed(1)} km
Goal summary: ${input.context.currentGoalSummary ?? "No active goal"}
Firebase UID: ${input.firebaseUid ?? "not provided"}

Recent conversation:
${input.messages.slice(-10).map((message) => `${message.role}: ${message.text}`).join("\n") || "No prior conversation."}

App map:
- Me: motivation, coach settings, activity history, settings
- Social: squad, clubs, rivals
- Floating orange button: start or resume a live session
- Assistant: planning, navigation, support, brainstorming

User request:
${input.prompt}

Respond in 2 to 4 short paragraphs. Keep it compact and actionable.`;

  const response = await fetch(`${baseUrl}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      temperature: 0.3,
      max_tokens: 700,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
    }),
  });

  if (!response.ok) {
    const errorBody = await response.text();
    throw new Error(`DeepSeek assistant request failed: ${response.status} ${errorBody}`);
  }

  const payload = await response.json() as {
    choices?: Array<{ message?: { content?: string | null } }>;
  };
  const content = payload.choices?.[0]?.message?.content?.trim();
  if (!content) {
    throw new Error("DeepSeek assistant returned empty content");
  }

  const parsed = JSON.parse(content) as DeepSeekAssistantResponse;
  return parsed.message?.trim() || "";
}
