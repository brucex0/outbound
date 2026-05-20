// Deterministic command parser for utterance transcripts

export function parseUtteranceCommand(transcript: string): { intent: string | null; details?: any } {
  // TODO: Replace with your actual deterministic parsing logic
  // Example: recognize simple "start run" or "start bike" commands
  const lower = transcript.trim().toLowerCase();
  if (lower.includes("start run")) {
    return { intent: "start_run" };
  }
  if (lower.includes("start bike")) {
    return { intent: "start_bike" };
  }
  // Add more rules as needed
  return { intent: null };
}
