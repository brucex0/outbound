import Anthropic from "@anthropic-ai/sdk";

const client = new Anthropic({ apiKey: process.env.ANTHROPIC_API_KEY });

// Shared cached system prompt prefix for all coach operations
const COACH_SYSTEM_CACHE_PREFIX = `You are an expert running and endurance sports coach AI.
Your role is to analyze athlete data and produce actionable, personalized coaching insights.
Be specific, data-driven, and empathetic. Never give generic advice — always reference the athlete's actual numbers.`;

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
        cache_control: { type: "ephemeral" },
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
        cache_control: { type: "ephemeral" },
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
        cache_control: { type: "ephemeral" },
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
