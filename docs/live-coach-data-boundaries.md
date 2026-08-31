# Live Coach Data Boundaries

Open this when changing live-coach context, adding an AI or speech provider, reviewing privacy, or answering what leaves the device/backend.

## Current Decision

Live coaching does **not** call an LLM during a workout. The server chooses a product-authored exact coaching sentence or deterministically formats a progress sentence, then sends only that sentence and speech settings to Google Cloud Text-to-Speech.

The prior Alibaba combined text-and-audio path could send context to a conversational model for every dynamic cue. The current orchestrator always supplies an exact transcript, so that combined LLM path is no longer used even if Alibaba is re-enabled as a TTS fallback.

## Data Flow

```text
iPhone moment detector
  -> Plainstride API (authenticated live state)
  -> server-authored exact sentence
  -> Google Cloud TTS (sentence + voice/audio settings only)
  -> complete validated WAV response
  -> iPhone playback or reviewed fixed-pack fallback
```

This remains a request/response path. The API returns one complete Base64-encoded WAV; it does not maintain a TTS WebSocket to the phone.

## Device To Plainstride At Session Start

The authenticated session-creation request contains:

- opaque client session ID and optional internal workout ID;
- locale and metric/imperial preference;
- selected product coach persona and product voice profile IDs;
- coaching contract (`quiet`, `responsive`, or `coach_me`);
- activity type and goal type.

The backend uses the authenticated account ID to compile a bounded context and stores it on `LiveCoachSession`:

- selected workout title, purpose, planned duration, intensity target, and prescription;
- latest readiness choice, energy, and soreness;
- up to three derived guidance priorities;
- up to three cue preferences;
- measurement system and runner-model version;
- a safety-only boolean that forces fixed guidance when illness or pain was reported.

This compiled context stays inside Plainstride in the implemented Google TTS path.

## Device To Plainstride For Each Cue

Each cue request contains:

- opaque cue request ID and semantic moment;
- detection elapsed time and validity window;
- current elapsed time and distance;
- current, rolling, and target pace when available;
- workout segment index and phase when available;
- whether route guidance is active.

Route geometry, GPS coordinates, place names, heart-rate samples, photos, contacts, account name, email, and provider login identifiers are not part of the cue request.

## Plainstride To Google Cloud TTS

Google Cloud TTS receives only:

- the finalized exact sentence;
- Google voice name and language code;
- `LINEAR16`, 24 kHz audio configuration;
- normal Google Cloud authentication/project metadata added by Application Default Credentials.

For periodic progress moments, the sentence can contain the runner's rounded distance, elapsed time, and pace because those values must be spoken. Google receives them only as words in that finalized sentence, not as a structured runner profile or live-state object.

Google Cloud TTS does **not** receive:

- the compiled workout/readiness/profile context;
- semantic-moment metadata or recent cue history;
- user, session, workout, or cue identifiers;
- GPS coordinates or route data;
- the app's Google OAuth client plist.

The Cloud Run runtime service account authenticates the request. Do not ship a Google Cloud API key or service-account credential in the iOS app.

## LLM Data

The implemented live-coach path sends **no data to an LLM**. `APP_AI_KEY`, `APP_AI_BASE_URL`, and `APP_AI_MODEL` continue to support other app AI features, but live coaching does not use them.

If a pre-workout LLM planner is approved later, its allowlisted payload should be limited to:

- locale and measurement system;
- activity type and goal type;
- selected coach persona instructions;
- the bounded workout fields listed above;
- readiness choice, energy, and soreness;
- up to three derived guidance priorities and cue preferences;
- the finite list of semantic coaching events for which exact phrases are requested.

It should never include account or device identifiers, name, email, raw notes, raw activity history, coordinates, route geometry, photos, contacts, or live telemetry. Enabling that planner requires an explicit provider decision, privacy review, retention review, and a separate configuration gate; documenting the payload does not authorize or enable the transfer.

## Storage And Logging

- `LiveCoachSession` stores the bounded compiled context, its SHA-256 hash, route metadata, selected product voice/persona, access reason, and coarse usage counts.
- `LiveCoachCue` stores the semantic moment, source/result category, context hash, coarse latency bucket, optional coarse token bucket, and coarse output-audio byte bucket.
- Dynamic transcript text and audio bytes are returned to the device but are not written to `LiveCoachCue`.
- Provider request bodies, exact progress metrics, transcripts, and audio must not be written to application logs or product analytics.
- Product analytics remains provider-neutral and records only bounded source/result/access/audio-mode values and coarse latency.

## Change Checklist

Before adding a new live-coach field or provider:

1. Decide whether the field is required on device, Plainstride backend, TTS, or a separately approved planner.
2. Keep TTS limited to exact text and synthesis settings.
3. Update this document and the provider allowlist in the same change.
4. Confirm logs and analytics still exclude raw health, profile, location, transcript, and exact metric values.
5. Re-review App Store privacy disclosures and provider retention terms before production rollout.
