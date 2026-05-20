import fetch from "node-fetch";

export async function gpt4oMiniTranscribe({ audioUrl, language }: { audioUrl: string; language?: string }) {
  // Replace with your OpenAI API key and endpoint
  const apiKey = process.env.OPENAI_API_KEY;
  if (!apiKey) throw new Error("OPENAI_API_KEY not set");

  const endpoint = "https://api.openai.com/v1/audio/transcriptions";
  const formData = new URLSearchParams();
  formData.append("model", "gpt-4o-mini");
  formData.append("file", audioUrl); // In real use, fetch and upload the file buffer
  if (language) formData.append("language", language);

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      // 'Content-Type' will be set automatically by fetch for FormData
    },
    body: formData,
  });

  if (!response.ok) {
    throw new Error(`OpenAI transcription failed: ${response.status} ${await response.text()}`);
  }

  const data = await response.json();
  return data.text as string;
}
