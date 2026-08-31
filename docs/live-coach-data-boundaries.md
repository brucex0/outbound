# Live Coach Data Boundaries

Open this when changing live-coach context, planner or speech providers, privacy behavior, or the data sent off device.

## Current Architecture

Gemini plans the workout once when the live-coach session starts. It does not run in the per-cue path. During the workout, the iPhone detects a semantic event, chooses an exact phrase from the signed-in runner's stored plan, and asks Plainstride to synthesize that phrase. Progress announcements are deterministic exact distance/time/pace sentences.

```text
iPhone session context
  -> authenticated Plainstride session creation
  -> bounded backend context compiler
  -> Gemini 3.1 Pro preview (one strict-JSON plan)
  -> plan returned to iPhone

iPhone moment detector + phrase ID + bounded live state
  -> authenticated Plainstride HTTP/2 request
  -> Google Cloud TTS gRPC streamingSynthesize(exact sentence)
  -> framed raw PCM HTTP response
  -> AVAudioEngine playback
  -> 1.5 s reviewed-pack/on-device speech fallback
```

There is no device-to-Google credential and no TTS WebSocket. The device keeps one ordinary HTTP/2 response open only for the duration of a cue; the backend keeps one Google gRPC stream open for that same cue.

## Device To Plainstride At Session Start

The authenticated request contains:

- opaque client session ID and optional internal workout ID;
- locale, metric/imperial preference, activity type, and goal type;
- product coach persona, product voice profile, and coaching contract;
- client workout title, detail, guide line, target duration/distance, typed phases, resolved pace targets, and route summary;
- route name/shape/direction, calculated distance/elevation gain, and approximate start coordinate/altitude when a route was selected;
- time-zone identifier, indoor flag, approximate place/coordinate/altitude, and the latest WeatherKit condition, temperature, apparent temperature, wind, precipitation chance, impact, headline, guidance, and best window.

The client never sends an account/user ID. Plainstride derives identity from the access token.

## Plainstride Context Compiler

The backend adds only data for the authenticated runner and bounds every list/string before calling Gemini:

- bio/survey: biography, age, sex at birth, height, weight, goal/schedule summaries, comfortable duration, recent/target frequency, preferred long-run day, guidance-detail preference, and declared constraints;
- coaching profile: fitness level, weekly volume, preferred pace, strengths, weaknesses, goals, records, and bounded recent memory summary;
- authoritative planned workout, blocks, and steps when present;
- latest readiness, including energy, soreness, sleep, stress, motivation, illness/pain, and bounded notes;
- derived survey summary, runner insights, confirmed/hypothesis beliefs, guidance priorities, and cue preferences;
- up to 50 activities from the prior 28 days, a seven-day detail/aggregate, 28-day aggregate/baseline, and up to 12 recent workout-feedback records;
- fresh situational signals and the client environment/weather described above.

The compiler omits name, username, email, login-provider IDs, access tokens, device IDs, contacts, photos, raw route geometry, raw GPS track, and user/session/cue IDs. Coordinates are rounded to two decimal places before serialization. Serialized context is capped at an estimated 20,000 tokens and stored with a SHA-256 hash.

## Plainstride To Gemini

Gemini receives:

- task and supported semantic-moment enum;
- the bounded compiled context above;
- selected coach-persona instructions in the system instruction;
- a strict JSON response schema.

The configured model is `gemini-3.1-pro-preview` with high thinking. Planning has a 20-second deadline and happens once per session. The response must contain a summary, progress cadence, and one to three exact short phrases for every supported moment, optionally specialized by workout phase. Invalid, timed-out, disabled, or unavailable planning produces a deterministic local plan; workout start is not failed solely because Gemini failed.

Gemini must not repeat private bio, health, location, survey, or weather facts in spoken phrases. Those fields may influence safety, tone, focus, timing, and advice only.

Vertex AI uses the Cloud Run runtime identity. `GEMINI_API_KEY` is supported for controlled non-Vertex environments but must never enter the app or repository.

## Device To Plainstride For Each Cue

Each request contains:

- opaque cue request ID, semantic moment, detection time, validity window, and selected server-issued phrase ID (not arbitrary text);
- elapsed time and distance;
- current, rolling, and target pace when available;
- grade, workout segment index/phase, and route-guidance-active flag when available.

The server resolves the phrase ID against the session's stored plan. Progress is formatted server-side from bounded live state. The device cannot ask the server to synthesize arbitrary text.

## Plainstride To Google Cloud TTS

Google TTS receives only:

- the finalized exact sentence;
- Google voice name and language code;
- PCM signed 16-bit little-endian, 24 kHz, mono settings;
- Google Cloud authentication/project metadata added by Application Default Credentials.

For progress cues, the sentence contains rounded distance, elapsed time, and pace as spoken words. Google does not receive the compiled context, semantic event, phrase ID, profile, structured telemetry, coordinates, route, or Plainstride identifiers.

The backend forwards Google audio chunks in a length-prefixed response with metadata, PCM, completion, and error frame types. It never exposes Google credentials to iOS.

## Planned Audio And Fallback

- After a generated plan arrives, iOS prewarms at most eight likely phrases through an authenticated phrase-ID endpoint. The server resolves the ID and returns a complete WAV; arbitrary text is not accepted.
- Planned WAVs are content-addressed by plan hash, voice profile, and phrase ID in the iOS cache and expire after 24 hours.
- Live raw PCM begins playback as chunks arrive. The initial server response and subsequent audio stream share one 1.5 second deadline measured from device request start. If no first audio arrives by then, iOS cancels the request and uses the reviewed local pack or `AVSpeechSynthesizer`; progress uses the already-finalized exact local distance/time/pace sentence.
- No Apple Foundation Model is used in this architecture. The on-device component selects phrases and provides the timeliness fallback; it does not invent coaching advice.

## Storage, Logs, And Analytics

- `LiveCoachSession` stores the bounded compiled context/hash/version, complete guidance plan/hash, planner status/model/prompt version, pinned TTS route, access reason, and coarse usage counts.
- `LiveCoachCue` stores moment, source/result category, context hash, and coarse latency/token/audio-size buckets. It does not store transcript or audio.
- Application logs and product analytics must not contain planner request bodies, profile/location fields, exact metrics, prompts, phrases, transcripts, audio, or identifiers.
- Product analytics records provider-neutral categories only. `live_guidance_audio_first_byte` measures device-request-to-first-audio with the existing coarse buckets.

## Change Checklist

1. Add fields to this allowlist and the bounded compiler together.
2. Keep cue TTS limited to a server-resolved exact sentence and synthesis settings.
3. Confirm planner text cannot disclose private context in spoken output.
4. Confirm logs/analytics still exclude raw context, transcript, audio, identifiers, and exact telemetry.
5. Re-review App Store privacy disclosures and current Google retention/region terms before production rollout.
