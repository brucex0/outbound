# Live Coach Data Boundaries

Open this when changing live-coach context, planner or speech providers, privacy behavior, or the data sent off device.

## Current Architecture

The configured planner prepares a workout plan on selection when supported by the client, or at session start. Ready plans are reused only for the same runner and compiled context. It does not run in the per-cue path. During the workout, the iPhone detects a semantic event or crosses a selected-workout trigger, chooses an exact phrase from the signed-in runner's stored plan, and asks Plainstride to synthesize that phrase. Progress announcements are deterministic exact distance/time/pace sentences.

```text
iPhone session context
  -> authenticated Plainstride session creation
  -> bounded backend context compiler
  -> configured structured-JSON planner (see docs/ai-reliability.md)
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

Current iOS/Android builds send request contract **2**, shared by workout selection/preparation and session creation. The strict schema is `backend/src/services/liveCoach/liveCoachRequestContract.ts`.

| Field | Bound | Consumer/purpose |
| --- | --- | --- |
| Session/preparation/workout/edit IDs and revisions | UUID session; IDs 120–160 characters; revision 64 lowercase hex characters | Account-owned lookup, plan reuse, exact issued/edit snapshot resolution |
| Locale, units, sport, goal, persona, voice, coaching contract, race strategy/source | Closed enums/registered IDs | Planner language/style, eligibility, deterministic goal/race guidance |
| `execution` goal targets | Distance ≤1,000 km; duration ≤24 h; calories ≤20,000; positive values | Actual recording target, independent of saved prescription estimates; selected distance/time/calorie goal requires its numeric target |
| Custom `execution.steps` | ≤80; total ≤24 h; duration 0–24 h; closed phase enum; pace 60–3,600 s/km; lead 1–30 s; countdown enum | Phase-aware coaching and deterministic transition policy |
| Referenced workouts | No client steps; planned ID or catalog ID/version, optional issued ID/revision and edit ID/revision | Backend resolves authored phases/instructions; supplied issued references must match the exact runner and planned workout. Without an issuance reference, the current owned prescription is used. Invalid supplied references fail; they never silently select another workout. |
| Route summary | Direction enum; distance/elevation with numeric bounds; latitude/longitude/altitude with geographic bounds | Terrain/direction context; provider coordinates rounded to two decimals. No name, display description or geometry |
| Environment | Timezone identifier ≤100 characters, indoor boolean; optional approximate coordinates and timestamped numeric weather/impact enum | Freshness and safety gates; no place names, weather headlines/advice or best-window prose |

Contract 2 rejects `clientWorkout`, display titles/descriptions/guidelines, step labels/details/instruction prose, arbitrary training-signal suffixes and unknown keys. Client custom steps carry phase/target/policy; readable saved-workout instructions come from the backend's prescription/catalog. Full device UI text and local recording instructions are unchanged. Request body limit: 128 KiB; schema errors expose only bounded structural paths and error codes.

The backend still accepts request contract 1 for currently released iOS builds. Its obsolete `detail`/`guideLine` strings have a 16,000-unit ingress ceiling and are discarded before compilation; they are not passed to the planner. Version 1 display titles, step text and route names are also absent from the compiled client execution projection. This server ingress path is not an Android legacy-data reader or migration.

The client never sends an account/user ID. Plainstride derives identity from the access token.

## Plainstride Context Compiler

The backend adds only data for the authenticated runner and bounds every list/string before calling the planner (compiled context version 5):

- bio/survey: biography, age, sex at birth, height, weight, goal/schedule summaries, comfortable duration, recent/target frequency, preferred long-run day, guidance-detail preference, and declared constraints;
- coaching profile: fitness level, weekly volume, preferred pace, strengths, weaknesses, goals, records, and bounded recent memory summary;
- authoritative planned workout, blocks, and steps when present;
- for a selected standalone workout, the server-resolved execution projection: catalog ID/version, title, target, objective, preparation, distance/time segment triggers, effort range/feel, guide instruction/reference/adjustment cue, finish guidance, and stop conditions;
- latest readiness, including energy, soreness, sleep, stress, motivation, illness/pain, and bounded notes;
- derived survey summary, runner insights with confidence/evidence count/update age, runner beliefs with status/confidence/source/consequence and refresh age, guidance priorities, and cue preferences; expired beliefs are excluded;
- up to 50 activities from the prior 28 days, a seven-day detail/aggregate, 28-day aggregate/baseline, and up to 12 recent workout-feedback records;
- fresh situational signals and the client environment/weather described above.

The compiler omits name, username, email, login-provider IDs, access tokens, device IDs, contacts, photos, raw route geometry, raw GPS track, user/session/cue IDs, the standalone catalog wrapper, source bibliography, editorial metadata, and unrelated workouts. Coordinates are rounded to two decimal places before serialization. Serialized context is capped at an estimated 20,000 tokens and stored with a SHA-256 hash.

The one-time planner creates a session-specific phrase library. The phone later selects a planned phrase from a detected semantic moment and workout phase; live cue delivery does not ask an LLM to reason over telemetry again. The planner prioritizes safety, typed targets and workout prescription, fresh readiness/environment, recent measured training and reported feedback, then confidence-ranked runner insights, beliefs, and preferences. It treats context text as data, distinguishes confirmed beliefs from hypotheses, weighs insight confidence/evidence count/update age, and ignores stale readiness/weather rather than speaking as if old information is current. Effort/recovery beliefs older than 28 days are historical unless current evidence confirms them; preferences may guide style until contradicted. Each generated cue must give one grounded action or execution focus, not generic encouragement. Repeating a phrase across moments or alternatives invalidates the plan and selects the deterministic fallback. Workout-step instructions preserve actual purpose, effort, and work/recovery sequence; explicit prescribed pace and duration targets may be spoken in the selected measurement units. Live measurements still come from deterministic device announcements; the start planner must not invent them. Local GPS evidence timestamps used by the detector are not added to provider context or product analytics.


The structural request does not remove intentional runner-authored context from the authenticated backend: biography, constraints, readiness/feedback notes and bounded coaching memory remain deliberate planner inputs with their existing limits. Authored catalog instructions also remain text because their wording carries execution meaning. Display prose is not a substitute for those inputs; changing their privacy/retention scope is a separate product decision.

## Plainstride To The Planner

The configured Gemini or GPT planner receives:

- task, supported reactive semantic-moment enum, and the exact required instruction IDs for the selected workout;
- the bounded compiled context above;
- selected coach-persona instructions in the system instruction;
- a strict JSON response schema.

Production model status and qualification results are in `docs/ai-reliability.md`. Gemini uses low thinking; the GPT Responses adapter uses low reasoning with `store: false`. Planning has a 45-second deadline and happens once per session. The response must contain a summary, progress cadence, one short phrase for each requested workout-relevant reactive moment, with phase-specific entries when needed, and exactly one localized phrase for every required selected-workout instruction ID. Phrases should be distinct and grounded in the moment and workout; duplicates or unknown instruction IDs invalidate the response. Invalid, timed-out, disabled, or unavailable planning produces a deterministic local plan; workout start is not failed solely because the planner failed.

The planner must not repeat private bio, health, location, survey, or weather facts in spoken phrases. Those fields may influence safety, tone, focus, timing, and advice only. Readiness is current for planner purposes for 36 hours; weather must have been observed within three hours. A fresh illness/pain or unsafe-weather flag can force fixed-only audio; stale flags do not block dynamic planning.

The owner approved GPT-6 Luna for production coaching after the refined prompt passed cloud qualification. It receives the same bounded context described above. OpenAI credentials are mounted from Secret Manager, never from ordinary Cloud Run environment values; synthetic evaluations use no runner data.

Vertex AI uses the Cloud Run runtime identity. `GEMINI_API_KEY` is supported for controlled non-Vertex environments but must never enter the app or repository.

## Device To Plainstride For Each Cue

Each request contains:

- opaque cue request ID, semantic moment, detection time, validity window, and selected server-issued phrase ID (not arbitrary text);
- elapsed time and distance;
- current, rolling, and target pace when available;
- grade, workout segment index/phase, and route-guidance-active flag when available.

The server resolves the phrase ID against the session's stored plan. Progress is formatted server-side from bounded live state. The device cannot ask the server to synthesize arbitrary text. Live telemetry chooses the moment, but the current architecture does not run another language-model reasoning call at each cue.

## Plainstride To Google Cloud TTS

Google TTS receives only:

- the finalized exact sentence;
- Google voice name and language code;
- PCM signed 16-bit little-endian, 24 kHz, mono settings;
- Google Cloud authentication/project metadata added by Application Default Credentials.

For progress cues, the sentence contains rounded distance, elapsed time, and pace as spoken words. Google does not receive the compiled context, semantic event, phrase ID, profile, structured telemetry, coordinates, route, or Plainstride identifiers.

The backend forwards Google audio chunks in a length-prefixed response with metadata, PCM, completion, and error frame types. It never exposes Google credentials to iOS.

## Planned Audio And Fallback

- After a generated plan arrives, iOS prewarms at most eight likely phrases, prioritizing selected-workout instructions, through an authenticated phrase-ID endpoint. The server resolves the ID and returns a complete WAV; arbitrary text is not accepted.
- Planned WAVs are content-addressed by plan hash, voice profile, and phrase ID in the iOS cache and expire after 24 hours.
- Live raw PCM begins playback as chunks arrive. The initial server response and subsequent audio stream share one 1.5 second deadline measured from device request start. If no first audio arrives by then, the client cancels the request and uses the reviewed local pack; when no approved recording exists, it stays silent rather than invoking system TTS. Progress uses the already-finalized exact local distance/time/pace sentence.
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

- Planner response array counts are enforced after generation, rather than in the provider JSON schema: Gemini rejects the nested bounded-array schema with HTTP 400. Types, required fields, and enum IDs remain provider-constrained; all existing runtime bounds and semantic checks still apply.
- Chinese and Spanish guided half-marathon fallback instructions preserve each distance section’s pacing, practiced fueling, and conditional finish advice instead of repeating a generic segment announcement.
- Prompt version `2026-10-20.3` makes vague rhythm/posture wording bans explicit in the selected language and favors shorter concrete actions. The compact initial library asks for one phrase per supported moment and retains phase selection plus all output validation. Existing half-marathon fallback sessions resolve reviewed Chinese/Spanish instructions at playback using their unchanged instruction/phrase IDs; no session data is rewritten.

## Preparation Lifetime

The same bounded planner context may now be prepared on workout selection, before recording starts. Preparation does not add fields or send a second language. It stores an account-owned context/hash and validated result with a 15-minute expiry; fallback results expire after 30 seconds. Expired records cannot be attached or generated and are purged on account preparation or daily maintenance. Start recompiles context and applies current safety/access gates before reuse. Existing session retention remains unchanged.

## Contract Verification And Rollout

- Build: `cd backend && npm run build`; focused provider/database-free check: `node backend/scripts/check-live-coach-structured-contract.mjs`.
- Build iOS and Android; do not infer audibility, background execution or music mixing from compilation. No schema migration or account-data reset is required.
- Backend support was deployed on 2026-11-14 as `outbound-api-00199-8ml` before installing the contract-2 iOS build on Bruce main; see `backend-deploy.md` for actual evidence and remaining device checks. Deploy backend support before installing/releasing contract-2 app builds. The currently deployed contract-1 server rejects contract 2; installing a new app first would disable cloud coaching. Retain server contract 1 until the public iOS release policy explicitly retires it.
- Context version 5 changes preparation hashes, preventing old unstructured context from attaching to a new preparation. Existing active sessions retain their pinned plan.
