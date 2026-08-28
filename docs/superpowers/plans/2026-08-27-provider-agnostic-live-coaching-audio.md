# Provider-Agnostic AI Live Coaching Audio Implementation Plan

**Status:** Proposed implementation handoff

**Initial provider:** Alibaba Cloud Model Studio / Qwen

**Primary outcome:** Every audible coaching cue is server-generated audio. The iOS app never uses an Apple system voice, chooses a vendor/model, or calls an AI vendor directly.

This document is written for an implementation agent. Complete the tasks in order, keep each commit reviewable, and update this plan when implementation reveals a materially different constraint. Follow `AGENTS.md`: do not run the test suite unless the user explicitly requests it; use build-only checks and the manual acceptance matrix for normal verification.

## 1. Goals

Build one provider-neutral backend boundary that:

- accepts product-level coaching requests rather than provider prompts or model IDs;
- compiles bounded user, plan, readiness, preference, and live-session context on the server;
- chooses an eligible AI service, model, endpoint, and provider voice using server policy;
- uses Alibaba only in the first release while leaving a real routing seam for Gemini or another provider;
- obtains the dynamic coaching utterance and its audio in one provider request when the selected provider supports that capability;
- serves fixed cues as pre-generated server assets, with no runtime AI call;
- pins the selected route for the full workout so the runner does not hear a different voice mid-session;
- bounds cost, latency, privacy exposure, and cue frequency before any provider call;
- falls back to cached, server-generated audio instead of an on-device Apple voice.

This implementation covers the live-coaching path first. The provider registry and text-generation capability should be reusable by assistant and companion features, but migrating every call in `backend/src/services/ai.ts` is a follow-up unless it is needed to remove a conflicting shared configuration. No new feature may add a direct vendor call outside the provider adapter layer.

## 2. Non-goals

- Do not make the client a general prompt or telemetry upload surface.
- Do not allow the client to send a provider name, model ID, endpoint, temperature, or arbitrary packet.
- Do not move moment detection, cooldowns, route-priority arbitration, safety actions, or outcome evaluation into the model.
- Do not stream an open microphone or continuous raw telemetry to the backend.
- Do not add mainland China distribution, hosting, registrations, or data residency in this project. Preserve a routing seam and follow `docs/mainland-china-readiness.md` when that market becomes an explicit launch target.
- Do not keep `AVSpeechSynthesizer` as a hidden fallback. A server-generated cached pack is the offline fallback.
- Do not regenerate fixed assets during every deployment.

## 3. Product and architecture decisions

### 3.1 Audio source

All audible guide content must be one of:

1. **`dynamic_generation`** — a provider-neutral live-coach request produces one short utterance and its audio in one AI-provider request.
2. **`fixed_pack`** — a product-authored semantic cue was generated ahead of time by the configured provider, reviewed, uploaded, and cached.
3. **`cached_fallback`** — the closest safe fixed cue is played when a dynamic result is late, unavailable, invalid, or stale.

There is no `apple_tts`, `device_tts`, or silent conversion of arbitrary generated text to an Apple voice.

### 3.2 Responsibilities

| Concern | Owner |
| --- | --- |
| Detect a meaningful moment | iOS `LiveGuidanceDirector` |
| Enforce coaching contract and local cooldowns | iOS |
| Give route/safety cues priority | iOS |
| Resolve authenticated runner, workout, plan, and preferences | Backend |
| Compile and budget model context | Backend |
| Choose service, region, model, and provider voice | Backend router |
| Generate the utterance and audio | Provider adapter |
| Validate transcript/audio and attach deterministic metadata | Backend orchestrator |
| Decide whether a returned cue is still timely | iOS |
| Play/duck/cancel audio | iOS audio player |
| Evaluate whether coaching helped | Existing iOS outcome evaluator |

The model may choose wording. It must not start, pause, end, reroute, or modify a workout. Urgency, expiration, cue priority, and any product action are derived from the semantic moment and server policy, not trusted model output.

### 3.3 Initial Alibaba strategy

Use Alibaba Cloud Model Studio's non-realtime Qwen Omni text-to-text-and-audio API for dynamic coaching. Pin a dated model snapshot after a small voice/latency evaluation rather than using an unversioned moving alias. Request text and audio modalities, disable thinking when required for audio output, and use one supported WAV format end to end.

The adapter consumes the provider's streaming response internally. The first client contract returns a complete bounded audio payload; provider streaming must not leak into the provider-neutral domain interface. Add client streaming later only if measured latency requires it.

Relevant vendor references, which must be rechecked during implementation because model IDs, voices, regions, and prices change:

- [Qwen Omni API](https://www.alibabacloud.com/help/en/model-studio/qwen-omni)
- [Alibaba Model Studio pricing](https://www.alibabacloud.com/help/en/model-studio/model-pricing)
- [Alibaba context cache](https://www.alibabacloud.com/help/en/model-studio/context-cache)
- Future adapter reference: [Gemini text-to-speech](https://ai.google.dev/gemini-api/docs/speech-generation)
- Future low-latency reference: [Gemini Live API capabilities](https://ai.google.dev/gemini-api/docs/live-api/capabilities)

Do not make correctness depend on a vendor prompt cache. Cache hits are an optional cost optimization; the complete request must remain valid on a cache miss.

## 4. Current code: preserve and replace

### Preserve

- `ios/Outbound/Outbound/Guide/LiveGuidanceModels.swift`: semantic moments, contracts, cooldown behavior, and cue outcome evaluation.
- `ios/Outbound/Outbound/Guide/VirtualGuide.swift`: session lifecycle, pending-moment queue, route quiet window, repetition checks, and event callbacks. Refactor its provider and playback edges rather than replacing the director.
- `backend/src/services/companion/sessionBrief.ts`: authoritative, compact workout/readiness/preference inputs.
- `backend/src/services/companion/contextCompiler.ts`: provenance, stable hashing, and context-budget concepts. Reuse its data gateway and patterns; do not send its full general-purpose context to live coaching.
- `backend/src/services/avatarStorage.ts` and `backend/src/services/activityPhotoStorage.ts`: storage/signing conventions.
- Existing typed analytics and privacy allowlist in `ios/Outbound/Outbound/Core/Analytics`.

### Replace

- `backend/src/routes/liveCoach.ts`: it currently accepts a client-selected model and arbitrary packet, calls an OpenAI-compatible endpoint directly, and returns the model name. Replace it with authenticated, schema-bounded session and cue routes.
- `ios/Outbound/Outbound/Guide/RemoteSessionAnalysisProvider.swift`: remove client model selection and the debug-only `/analyze` contract.
- `ios/Outbound/Outbound/Guide/AppleFoundationModelSessionAnalysisProvider.swift`: remove it from live cue generation.
- `ios/Outbound/Outbound/Guide/GuideSpeechSynthesizer.swift`: replace `AVSpeechSynthesizer` with playback of server-generated audio data/assets.
- Apple installed-voice discovery in `GuideTemplate.swift`, `GuideCatalogStore.swift`, and `GuideSelectionView.swift`: replace provider voice identifiers with stable Plainstride voice-profile IDs returned by the backend.

### Existing auth gap

`backend/src/middleware/auth.ts` intentionally allows unauthenticated requests through with `auth = null`. Every new live-coach route that reads user context or incurs AI cost must explicitly require an authenticated internal user. Add or reuse a `requireAuth` route guard and never trust a user ID from the request body.

## 5. Target request flow

```text
iOS moment detector
  -> local contract/cooldown/priority gate
  -> POST /v1/live-coach/sessions/:sessionId/cues
       -> require authenticated user and session ownership
       -> validate semantic request and idempotency key
       -> reject stale/ineligible/over-budget request
       -> merge stored session context with bounded telemetry delta
       -> resolve the route pinned at session creation
       -> provider-neutral generation request
            -> Alibaba Qwen Omni adapter (V1)
       -> validate text/audio, duration, size, and policy
       -> provider-neutral cue envelope
  -> iOS rejects stale result if the moment is no longer valid
  -> audio queue ducks music and plays WAV
  -> existing local outcome evaluator records aggregate usefulness
```

Fixed cues follow a different path:

```text
versioned semantic cue catalog
  -> offline generator command
  -> Alibaba voice-only/text+audio generation
  -> validation and human review manifest
  -> object storage + immutable provider-neutral manifest
  -> iOS download/cache
  -> playback with no runtime AI request
```

## 6. Provider-neutral domain model

Create a shared AI platform under `backend/src/services/aiProviders/`. Live-coaching code may depend on these interfaces; routes and product services must not import Alibaba SDK types.

Use this conceptual shape, adjusted to project TypeScript conventions:

```ts
export type AIProviderKey = "alibaba" | "gemini";
export type AIMarket = "global" | "mainland_china";
export type AIRequestKind =
  | "live_coach_dynamic"
  | "live_coach_fixed_asset"
  | "assistant_text"
  | "companion_text";

export type AudioEncoding = {
  container: "wav";
  codec: "pcm_s16le";
  sampleRateHz: 24_000;
  channels: 1;
};

export type VoiceProfile = {
  id: "plainstride_warm_1" | "plainstride_clear_1";
  supportedLocales: Array<"en" | "es" | "zh-Hans">;
  style: "warm" | "clear";
};

export type ProviderCapabilities = {
  text: boolean;
  audioOutput: boolean;
  combinedTextAndAudio: boolean;
  supportedLocales: string[];
  supportedMarkets: AIMarket[];
  supportedAudio: AudioEncoding[];
  maximumOutputSeconds: number;
};

export type LiveCoachGenerationInput = {
  requestId: string;
  locale: "en" | "es" | "zh-Hans";
  voiceProfileId: VoiceProfile["id"];
  semanticMoment: string;
  stableInstructions: string;
  compiledContext: LiveCoachCompiledContext;
  liveState: LiveCoachLiveState;
  recentCueSummaries: string[];
  maximumSpokenWordsEquivalent: number;
  deadline: Date;
};

export type LiveCoachProviderResult = {
  transcript: string;
  audio: Uint8Array;
  audioEncoding: AudioEncoding;
  durationMilliseconds: number;
  usage: {
    inputTokens?: number;
    outputTextTokens?: number;
    outputAudioTokens?: number;
  };
  providerRequestId?: string;
};

export interface LiveCoachAIProvider {
  readonly key: AIProviderKey;
  capabilities(): ProviderCapabilities;
  generateCue(
    input: LiveCoachGenerationInput,
    signal: AbortSignal
  ): Promise<LiveCoachProviderResult>;
}
```

Keep provider/model identity out of public API responses and mobile persistence. Internally record it for cost, reliability, and audit metrics.

Define provider-independent errors such as `not_configured`, `not_eligible`, `rate_limited`, `deadline_exceeded`, `provider_unavailable`, `invalid_provider_output`, and `budget_exhausted`. Adapters translate vendor status codes and payload failures into these categories without logging vendor bodies that may contain prompt data.

## 7. Provider registry, selection, and session pinning

### 7.1 Route facts

The router takes a server-owned facts object:

```ts
type AIRouteFacts = {
  requestKind: AIRequestKind;
  market: AIMarket;
  locale: SupportedLocale;
  voiceProfileId: VoiceProfileId;
  requiredCapabilities: Array<"audio_output" | "combined_text_audio">;
  deploymentRegion: string;
  latencyClass: "interactive" | "offline";
  experimentKey?: string;
};
```

The request may carry an informational app-distribution hint, but the backend resolves the authoritative market from deployment/release configuration or a future verified account market. Do not infer mainland status from UI language, GPS, or a single IP lookup. Locale is not market.

The mainland example is a policy constraint, not a claim that the iPhone must reach Gemini directly: the iPhone reaches Plainstride. A future mainland route must validate the entire Plainstride deployment-to-provider path, provider terms/region availability, latency, data handling, storage, and applicable distribution/compliance requirements.

### 7.2 Eligibility first, scoring second

Filter routes using hard constraints:

- provider and endpoint enabled for the deployment;
- secret present;
- request capability supported;
- locale and Plainstride voice mapping supported;
- provider/endpoint permitted for the resolved market and data policy;
- recent circuit-breaker state allows traffic;
- request fits provider duration and payload limits;
- fixed pack version exists when selecting a cached route.

Then score eligible routes using configuration, not product code:

- explicit market preference;
- voice quality evaluation for the locale;
- current availability/circuit health;
- rolling p95 latency;
- estimated request cost;
- experiment assignment;
- cache readiness;
- stable default order as final tie-breaker.

V1 registers only Alibaba, so the scoring outcome is deliberately simple. Do not add fake fallback branches that can never work. The interface and policy table are the future seam.

### 7.3 Pinning and failover

Resolve the provider, endpoint region, dated model ID, and provider voice at session creation. Store the route on `LiveCoachSession` and use it for every dynamic cue in that workout.

Do not fail over to another provider mid-session: voice and prosody changes are a poor runner experience, and a second request can arrive too late. On a pinned-route failure, return a categorized failure and let iOS use the cached fallback pack. A future session may select a different healthy route.

## 8. Alibaba adapter

Create `backend/src/services/aiProviders/alibaba/` with no imports from routes or iOS-shaped DTOs.

### Configuration

Use server configuration similar to:

```text
AI_ROUTE_POLICY_VERSION=1
ALIBABA_AI_ENABLED=true
ALIBABA_AI_API_KEY=<Secret Manager binding>
ALIBABA_AI_BASE_URL=<approved regional Model Studio endpoint>
ALIBABA_LIVE_COACH_MODEL=<dated Qwen Omni model ID>
ALIBABA_LIVE_COACH_VOICE_MAP=<server config or validated JSON>
```

Do not reuse the ambiguous `APP_AI_*` names for live coaching. Do not expose these values to the app. Keep base URL and model selection server-controlled and validate configuration on boot when the feature is enabled.

### Adapter behavior

For each dynamic request:

1. Map the Plainstride voice profile to a supported Alibaba voice for the chosen locale/model.
2. Build a stable system prefix and a compact, deterministic JSON user payload.
3. Ask for one short spoken coaching utterance in the requested locale.
4. Request text and audio modalities in one call; disable thinking if the chosen model requires that for audio.
5. Parse the provider's streaming text/audio deltas without forwarding vendor event types.
6. Accumulate into the bounded provider-neutral result.
7. Capture usage and provider request ID for server operations only.
8. Abort at the request deadline and stop consuming the stream.
9. Validate that the bytes are a mono WAV of the configured sample format, within size/duration limits, and nonempty.
10. Normalize the returned text and verify length, language plausibility, prohibited content, and correspondence with the audio metadata available from the provider.

For fixed assets, pass the exact product-authored transcript and require the returned text, when present, to normalize to the same transcript. A mismatch blocks publication.

Never place full prompts, provider response bodies, transcripts, audio bytes, auth headers, or exact live telemetry in logs or thrown error messages.

## 9. Public API contracts

Use provider-neutral DTOs with strict Zod schemas, size limits, enumerations, and unknown-key rejection. Include a contract version in every response.

### 9.1 Voice profiles

`GET /v1/live-coach/voices?locale=en`

Response:

```json
{
  "contract_version": 1,
  "voices": [
    {
      "id": "plainstride_warm_1",
      "display_name": "Warm",
      "style": "warm",
      "preview_asset_id": "voice-preview/en/plainstride_warm_1/v3"
    }
  ]
}
```

Display names are localized product strings. Do not return provider, model, endpoint, or vendor voice IDs.

### 9.2 Create a live-coach session

`POST /v1/live-coach/sessions`

Request:

```json
{
  "contract_version": 1,
  "client_session_id": "uuid",
  "workout_id": "optional-authoritative-workout-id",
  "locale": "en",
  "voice_profile_id": "plainstride_warm_1",
  "coaching_contract": "responsive",
  "tone": "encouraging",
  "session_intent": {
    "activity_type": "running",
    "goal_type": "workout"
  },
  "app_distribution_hint": "global"
}
```

The backend authenticates the user, validates workout ownership, resolves the authoritative market, compiles session context once, selects and pins a route, and returns:

```json
{
  "contract_version": 1,
  "session_id": "opaque-id",
  "context_version": 1,
  "expires_at": "ISO-8601",
  "dynamic_coaching_available": true,
  "audio_pack": {
    "manifest_version": "2026-08-27.1",
    "manifest_url": "short-lived-or-public-content-url"
  },
  "limits": {
    "cue_validity_milliseconds": 5000,
    "maximum_dynamic_cues": 8
  }
}
```

Session creation must be idempotent for `(user, client_session_id)`.

### 9.3 Request a cue

`POST /v1/live-coach/sessions/:sessionId/cues`

Request:

```json
{
  "contract_version": 1,
  "cue_request_id": "uuid",
  "moment": "pace_drift",
  "detected_at_elapsed_seconds": 842,
  "valid_for_milliseconds": 5000,
  "live_state": {
    "elapsed_seconds": 842,
    "distance_meters": 2740,
    "current_pace_seconds_per_kilometer": 331,
    "rolling_pace_seconds_per_kilometer": 324,
    "target_pace_seconds_per_kilometer": 315,
    "workout_segment_index": 2,
    "workout_segment_phase": "work",
    "route_guidance_active": false
  }
}
```

Only allow named bounded fields. Do not accept coordinates, route geometry, raw sample arrays, arbitrary history, user prose, or a client-supplied system prompt. Exact telemetry exists in this transactional request but must not enter general product analytics or application logs.

Response:

```json
{
  "contract_version": 1,
  "cue_request_id": "uuid",
  "source": "dynamic_generation",
  "moment": "pace_drift",
  "urgency": "opportunity",
  "transcript": "Ease it back a touch and settle into your target rhythm.",
  "audio": {
    "content_type": "audio/wav",
    "base64": "...",
    "duration_milliseconds": 3100
  },
  "generated_at": "ISO-8601",
  "expires_at": "ISO-8601"
}
```

V1 uses base64 because cues are tiny and this keeps one authenticated request. If measurement shows response overhead or time-to-first-audio is unacceptable, add a provider-neutral binary/streaming endpoint without changing the domain provider interface.

The cue route is idempotent for `(session, cue_request_id)`. Concurrent duplicates share one in-flight generation. The server may retain the completed bounded result only until its short expiration; do not permanently store audio or transcript.

### 9.4 End a session

`POST /v1/live-coach/sessions/:sessionId/end`

Accept final coarse counts and outcome buckets needed for cost/reliability reconciliation. Mark the session ended, discard any transient cue payload cache, and abort in-flight generation. Do not upload the full local cue record unless a separate privacy-reviewed learning design requires it.

### 9.5 Fixed assets

Expose an immutable manifest and asset endpoint/CDN path. The manifest maps semantic keys, locale, voice-profile ID, and version to a checksum, duration, content type, and URL. It never includes provider/model metadata.

## 10. Live-coach context compilation

Create a dedicated compiler rather than serializing client structs or sending all companion context.

### Authoritative sources

- authenticated internal user ID;
- selected workout and current plan from `domainToolGateway`/the same authoritative plan queries;
- compact session brief from `sessionBrief.ts`;
- current readiness when fresh enough for the product policy;
- confirmed or bounded preference/recovery beliefs;
- guide persona settings and stable voice-profile ID;
- server-maintained recent cue summaries for this live-coach session;
- bounded live-state delta supplied by the active client.

### Exclusions

- name, email, phone, Firebase UID, or social graph;
- coordinates, route geometry, place names, photos, and media;
- raw activity history and raw sensor arrays;
- menstrual-cycle details or other highly sensitive health details;
- unrestricted companion conversation or user free text;
- expired beliefs or stale readiness;
- database IDs not required for model reasoning.

### Budget and determinism

Target at most 1,250 estimated input tokens for a dynamic cue:

| Section | Budget |
| --- | ---: |
| Stable product/safety/locale instructions | 300 |
| Workout and session purpose | 250 |
| Runner preferences/readiness | 200 |
| Current semantic moment and live state | 300 |
| Last three cue summaries/repetition guard | 150 |
| Output instruction | 50 |

Use stable key ordering and deterministic truncation. Store the compiled session context or its encrypted/approved representation plus a SHA-256 hash on session creation; store the hash and budget metrics for each request. Do not rebuild the full user/plan context on every cue. Merge only the live delta and small recent-cue window.

The stable prefix should be identical across sessions for a given policy/locale when possible, followed by session-stable context, then the changing cue data. This ordering improves provider cache opportunity without relying on it.

## 11. Fixed audio pack pipeline

Create a semantic catalog in `backend/resources/liveCoachAudio/` for `en`, `es`, and `zh-Hans`. Product strings must be natural translations, not concatenated word fragments.

Initial asset families:

- start countdown and start confirmation;
- pause/resume/end confirmations;
- interval start, recovery start, next segment, halfway, and workout complete;
- distance/time milestones already emitted by `VirtualGuide`;
- route advisory, caution, wrong-way, rejoin, and arrival patterns that do not require arbitrary street names;
- challenge start/complete;
- generic safe cues for settle, hold steady, ease back, strong finish, and stop/check-in;
- one preview per voice profile and locale;
- a neutral unavailable/offline fallback when no more specific cue applies.

Do not synthesize messages by joining independently recorded fragments unless listening tests prove transitions are natural. Prefer complete sentences with a bounded set of parameterized variants. If a cue requires arbitrary values, either cover useful buckets (for example whole kilometers/minutes) or use dynamic generation when online.

Add an explicit generator command such as:

```bash
npm run live-coach:generate-audio -- --catalog-version 2026-08-27.1 --provider alibaba
```

The command must:

1. load secrets only from environment/Secret Manager integration;
2. hash normalized text + locale + voice profile + audio spec + provider route version;
3. skip already generated matching hashes;
4. call the provider through the same registry with request kind `live_coach_fixed_asset`;
5. validate WAV format, maximum duration, transcript agreement, and non-silence;
6. write a review manifest outside committed source artifacts;
7. require an explicit publish step after human listening review;
8. upload immutable content-addressed objects;
9. publish a provider-neutral signed manifest atomically.

Bundle a small default pack with the app for countdown, workout transitions, route safety, and generic fallback. Download the selected full pack after voice selection/session setup and cache by checksum. Retain the last known-good pack until the replacement is fully verified.

## 12. Persistence and transient caching

Add Prisma models conceptually equivalent to:

```prisma
model LiveCoachSession {
  id                    String   @id @default(cuid())
  userId                String
  clientSessionId       String
  workoutId             String?
  status                String
  locale                String
  market                String
  voiceProfileId        String
  coachingContract      String
  providerKey           String
  providerEndpointKey   String
  providerModel         String
  providerVoice         String
  routePolicyVersion    String
  compiledContext       Json
  contextHash           String
  contextVersion        Int
  dynamicCueLimit       Int
  dynamicCueCount       Int      @default(0)
  expiresAt             DateTime
  endedAt               DateTime?
  createdAt             DateTime @default(now())
  updatedAt             DateTime @updatedAt

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, clientSessionId])
  @@index([userId, status, createdAt])
  @@index([expiresAt])
}

model LiveCoachCue {
  id                  String   @id @default(cuid())
  sessionId           String
  cueRequestId        String
  moment              String
  source              String
  resultCategory      String
  contextHash         String
  latencyBucket       String?
  inputTokenBucket    String?
  outputAudioBucket   String?
  createdAt           DateTime @default(now())
  expiresAt           DateTime

  session LiveCoachSession @relation(fields: [sessionId], references: [id], onDelete: Cascade)

  @@unique([sessionId, cueRequestId])
  @@index([expiresAt])
}
```

Adjust relations to the actual Prisma `User` model. Treat provider/model/voice as internal operational data. Do not persist transcript, audio, prompt, exact telemetry, or provider response body in `LiveCoachCue`. Use an in-process short TTL cache for V1 idempotent response replay; if Cloud Run concurrency or multiple instances make duplicate cost measurable, move only the short-lived encrypted result and in-flight lock to an appropriate shared cache.

Because this product is pre-public launch, use the cleanest schema and document the required migration/reset command; do not build compatibility layers for old debug live-coach rows.

## 13. Cost and latency policy

Enforce policy before calling Alibaba:

- only `responsive` and `coach_me` moments request dynamic generation;
- fixed progress, countdown, transition, route, safety, and completion cues use the pack;
- reject duplicate, stale, suppressed, route-conflicting, and cooldown-ineligible moments;
- compile context once per session;
- send only current live delta and last three cue summaries per request;
- cap output to roughly 18 English spoken words or a locale-adjusted equivalent;
- cap generated audio at 4.5 seconds and 512 KiB;
- set a provider deadline of 4 seconds and a cue validity window of 5 seconds initially;
- maximum 8 dynamic cues for `responsive` and 15 for `coach_me`, configurable by policy;
- never retry a live dynamic generation after the deadline; use cached fallback;
- do not send parallel generations for the same session unless the prior request has been canceled or resolved;
- abort server/provider work when the client disconnects or the session ends.

Measure actual time to usable audio, provider p50/p95, fallback rate, audio bytes, and token usage before changing the limits. The cost estimator belongs in provider configuration because vendors meter text/audio differently.

## 14. Security, privacy, and safety

- Require authentication and verify session ownership on every session/cue/end request.
- Validate selected workout ownership server-side.
- Rate-limit by authenticated user and session in addition to the existing IP limiter.
- Reject unknown JSON keys and cap request bodies before parsing.
- Keep Alibaba keys only in Google Secret Manager/Cloud Run secret bindings.
- Never return internal provider/model/endpoint IDs.
- Never log prompts, transcripts, audio, exact telemetry, coordinates, auth headers, or vendor response bodies.
- Add request IDs, categorized outcomes, coarse usage, and coarse latency to structured logs.
- Validate WAV headers, declared/actual size, sample rate, channels, duration, and nonempty payload before returning audio.
- Keep medical/safety wording deterministic where possible. A concerning symptom or route/safety condition must select an approved fixed cue and product behavior, not ask the model to improvise.
- Keep model output non-actionable: no tool execution and no mutation instructions in the provider result.
- Cancel or discard generated cues that expire before playback.
- Add localized cloud-processing disclosure/consent if required by product/privacy review, and update App Store privacy disclosures before release.

## 15. Analytics and operations

Preserve existing semantic Live Guidance events. Update the typed analytics contract so provider results use only bounded product values:

- `source`: `dynamic_generation`, `fixed_pack`, `cached_fallback`;
- `result`: `success`, `offline`, `timeout`, `stale`, `invalid`, `unavailable`, `budget_exhausted`;
- coarse latency bucket;
- semantic moment, coaching contract, outcome, and coarse cue-count bucket already allowed by the product analytics spec.

Never send provider/model/voice vendor ID, transcript, audio, prompt, exact pace/distance/time, session ID, request ID, or user ID as Firebase event properties.

Server operational metrics may include provider, dated model, endpoint key/region, route-policy version, resolved market, locale, Plainstride voice profile, categorized result, latency, usage buckets, audio-size bucket, context-token bucket, and circuit state. Keep user identity and sensitive content out. Use these metrics to support future provider selection and cost decisions.

Add health state per provider route:

- rolling success/error counts;
- latency histogram;
- rate-limit and deadline categories;
- circuit closed/open/half-open state;
- last successful synthetic health probe, where vendor terms allow it.

Health checks must not call the model on every application `/health` request.

## 16. File-level implementation tasks

### Task 1: Add shared AI provider contracts and configuration

**Create**

- `backend/src/services/aiProviders/types.ts`
- `backend/src/services/aiProviders/errors.ts`
- `backend/src/services/aiProviders/config.ts`
- `backend/src/services/aiProviders/registry.ts`

**Modify**

- `backend/package.json` only if an official SDK or audio validation dependency is justified; prefer the existing `fetch` runtime for a small adapter.

**Acceptance**

- Product code can express required capability without naming a vendor/model.
- Configuration rejects enabled routes with missing secrets, model, endpoint, or voice mappings.
- Provider errors are sanitized and categorized.

### Task 2: Implement routing, scoring, health, and route pinning types

**Create**

- `backend/src/services/aiProviders/router.ts`
- `backend/src/services/aiProviders/routePolicy.ts`
- `backend/src/services/aiProviders/health.ts`

**Acceptance**

- V1 returns Alibaba only when every hard constraint passes.
- No eligible route produces `not_eligible`, never a silent default.
- A resolved route is serializable into internal session persistence.
- Market comes from trusted backend policy, not locale/GPS/IP.

### Task 3: Implement the Alibaba Qwen Omni adapter

**Create**

- `backend/src/services/aiProviders/alibaba/alibabaLiveCoachProvider.ts`
- `backend/src/services/aiProviders/alibaba/alibabaSchemas.ts`
- `backend/src/services/aiProviders/alibaba/alibabaStreamParser.ts`
- `backend/src/services/aiProviders/alibaba/alibabaVoiceMap.ts`
- `backend/src/services/aiProviders/audioValidation.ts`

**Acceptance**

- One dynamic provider request returns transcript and audio.
- Streaming chunks, abort, non-2xx errors, missing modalities, malformed audio, size limits, and usage parsing are handled.
- No Alibaba type escapes the adapter directory.
- Error paths do not log response bodies.

### Task 4: Add live-coach persistence and context compilation

**Create**

- Prisma migration for `LiveCoachSession` and `LiveCoachCue`
- `backend/src/services/liveCoach/liveCoachTypes.ts`
- `backend/src/services/liveCoach/liveCoachContextCompiler.ts`
- `backend/src/services/liveCoach/liveCoachSessionService.ts`
- `backend/src/services/liveCoach/liveCoachCueRepository.ts`

**Modify**

- `backend/prisma/schema.prisma`
- `backend/src/services/companion/sessionBrief.ts` only if a provider-neutral projection is needed; preserve existing consumers.

**Acceptance**

- Context is compiled once with stable ordering, a hash, and an enforced budget.
- Session ownership, idempotent creation, expiration, and cue quotas are enforced transactionally.
- Cue rows contain only operational metadata, never content or exact telemetry.

### Task 5: Add cue policy, prompt construction, and orchestration

**Create**

- `backend/src/services/liveCoach/liveCoachCuePolicy.ts`
- `backend/src/services/liveCoach/liveCoachPrompt.ts`
- `backend/src/services/liveCoach/liveCoachOrchestrator.ts`
- `backend/src/services/liveCoach/liveCoachOutputValidation.ts`
- `backend/src/services/liveCoach/liveCoachFallback.ts`

**Acceptance**

- Fixed vs dynamic selection is deterministic.
- Urgency, expiry, and fallback selection do not trust model output.
- Only one generation is in flight for a session.
- Disconnect, session end, and deadline abort provider work.

### Task 6: Replace the public live-coach API

**Modify**

- `backend/src/routes/liveCoach.ts`
- `backend/src/index.ts`
- add/reuse an authenticated-route guard under `backend/src/middleware/`.

**Acceptance**

- Remove `/analyze` and all client-selected `model`/arbitrary `packet` handling.
- Implement voices, create-session, cue, and end-session endpoints.
- Use strict schemas, request-size bounds, ownership checks, and user/session rate limits.
- Public DTOs contain no provider implementation details.

### Task 7: Build and publish fixed server-generated voice packs

**Create**

- `backend/resources/liveCoachAudio/catalog.v1.json`
- localized catalog files if separation improves reviewability
- `backend/src/services/liveCoach/audioPackManifest.ts`
- `backend/src/services/liveCoach/audioPackStorage.ts`
- `backend/scripts/generate-live-coach-audio.ts`
- `backend/scripts/publish-live-coach-audio.ts`

**Modify**

- `backend/package.json`
- `scripts/deploy-backend-gcloud.sh` for the approved bucket/config only; generation remains explicit.

**Acceptance**

- Generation is content-addressed, resumable, validated, and separate from publication.
- Publication requires a reviewed manifest and is atomic.
- Manifest/asset contracts are provider-neutral and immutable.
- Minimal fallback packs for all supported locales are ready to bundle with iOS.

### Task 8: Add provider-neutral iOS API and session lifecycle

**Modify**

- `ios/Outbound/Outbound/Core/APIClient.swift`
- `ios/Outbound/Outbound/Guide/SessionAnalysisProvider.swift`
- `ios/Outbound/Outbound/Guide/VirtualGuide.swift`

**Create**

- `ios/Outbound/Outbound/Guide/LiveCoachAPIModels.swift`
- `ios/Outbound/Outbound/Guide/ServerLiveCoachProvider.swift`
- `ios/Outbound/Outbound/Guide/LiveCoachSessionController.swift`

**Remove after call sites migrate**

- `ios/Outbound/Outbound/Guide/RemoteSessionAnalysisProvider.swift`
- `ios/Outbound/Outbound/Guide/AppleFoundationModelSessionAnalysisProvider.swift`

**Acceptance**

- iOS sends semantic moment plus bounded state, never a provider/model/prompt.
- A server session is created once and ended best-effort.
- Cue tasks are cancelable and stale responses never play.
- Server unavailability selects fixed cached audio without invoking device TTS.

### Task 9: Replace Apple speech with generated-audio playback

**Create**

- `ios/Outbound/Outbound/Guide/GuideAudioPlayer.swift`
- `ios/Outbound/Outbound/Guide/GuideAudioPackStore.swift`
- bundled `LiveCoachAudio` resources and manifest.

**Modify**

- `ios/Outbound/Outbound/Guide/VirtualGuide.swift`
- audio-session/music-ducking integration currently used by `GuideSpeechSynthesizer.swift`.

**Remove**

- `ios/Outbound/Outbound/Guide/GuideSpeechSynthesizer.swift` after playback parity is complete.

**Acceptance**

- No `AVSpeechSynthesizer`, `AVSpeechUtterance`, or installed Apple voice remains in active coaching.
- Dynamic bytes and fixed assets share one playback queue.
- Advisory/caution/arrival priority, music ducking, cancellation, interruption recovery, and speech start/finish callbacks still work.
- Audio validation failure is silent or fixed fallback according to cue policy; it never reaches Apple TTS.

### Task 10: Replace Apple voice selection with Plainstride profiles

**Modify**

- `ios/Outbound/Outbound/Guide/GuideTemplate.swift`
- `ios/Outbound/Outbound/Guide/GuideCatalogStore.swift`
- `ios/Outbound/Outbound/Guide/GuideSelectionView.swift`
- `ios/Outbound/Outbound/Localizable.xcstrings`

**Acceptance**

- Settings store a stable Plainstride voice-profile ID.
- Voice previews play server-generated preview assets.
- All new/changed user-facing strings are localized naturally in `en`, `es`, and `zh-Hans`.
- Save/load/API failures use temporary toast-style feedback unless user action is required.

### Task 11: Update analytics without leaking provider details

**Modify**

- `ios/Outbound/Outbound/Core/Analytics/ProductAnalyticsEvent.swift`
- relevant event mapping in `VirtualGuide.swift`/session controller
- `docs/product-analytics.md`

**Acceptance**

- New source/result/latency values pass the typed allowlist.
- No generated content, exact telemetry, vendor/model ID, or request/session identifier reaches Firebase.
- Fixed, dynamic, fallback, stale, and unavailable outcomes are distinguishable.

### Task 12: Deployment, secrets, storage, and focused docs

**Modify**

- `scripts/deploy-backend-gcloud.sh`
- `docs/backend-deploy.md`
- `docs/ios-architecture.md`
- `docs/localization.md` if generated-audio locale behavior needs clarification
- `docs/mainland-china-readiness.md` to reference provider-route validation when mainland becomes a target
- `docs/INDEX.md`

**Acceptance**

- Alibaba secret is a Secret Manager binding, not an ordinary environment variable.
- Deployment configuration selects one approved endpoint/model/route policy.
- Audio bucket access, cache headers, lifecycle, and publish command are documented.
- Rollback includes disabling dynamic generation while preserving fixed packs.

### Task 13: Add focused tests, but do not run them without user authorization

**Backend test coverage to add**

- route hard eligibility and deterministic scoring;
- market/locale separation;
- Alibaba stream parsing and sanitized errors;
- audio format/size/duration validation;
- context ordering, truncation, exclusion, and hashing;
- idempotent session/cue behavior and ownership;
- quota/deadline/stale gates;
- no provider details in public DTOs;
- fixed catalog/manifest completeness for all locales.

**iOS test coverage to add**

- stale cue rejection;
- cancellation and single in-flight request;
- fixed fallback selection;
- audio queue priority and interruption state;
- pack checksum/last-known-good behavior;
- analytics privacy allowlist.

Do not execute these tests unless the user explicitly asks. A later authorized verification run should use the narrowest relevant commands before broader suites.

### Task 14: Build-only and manual verification

Run the backend TypeScript build and an iOS build-only compile check. Then verify on a real device/network profile:

1. select each Plainstride voice profile and hear its generated preview;
2. start a workout and hear server-generated countdown audio;
3. trigger a dynamic semantic moment and confirm one Alibaba call returns matching text/audio;
4. confirm music ducks and resumes;
5. trigger route caution during coaching and confirm priority/cancellation;
6. introduce slow/offline networking and confirm stale audio never plays and cached fallback is used;
7. finish the session and confirm in-flight work stops;
8. run in `en`, `es`, and `zh-Hans`;
9. inspect logs/analytics to confirm no prompt, transcript, audio, exact telemetry, provider response, or credentials were emitted;
10. confirm the app contains no active Apple speech path.

## 17. Rollout sequence

1. Land contracts, router, Alibaba adapter, validation, and operational metrics behind `LIVE_COACH_SERVER_AUDIO_ENABLED=false`.
2. Generate, review, publish, and bundle fixed packs before enabling any dynamic path.
3. Land new backend routes while the old debug `/analyze` path remains disabled outside local development.
4. Land iOS provider-neutral session/cue client and audio player behind a feature flag.
5. Remove Apple/Foundation/debug provider paths and the old `/analyze` route in the same release boundary; do not ship a mixed voice fallback.
6. Enable employee/device testing with Alibaba pinned to one dated model and voice mapping.
7. Measure p50/p95 latency, invalid/stale/fallback rate, cue frequency, and estimated cost by locale/voice profile.
8. Tune request deadlines and cue limits through server policy.
9. Gradually enable dynamic coaching; fixed server-generated cues remain available even when the feature flag is off.
10. Add a second provider only after defining its adapter, capability/market facts, voice-quality evaluation, and explicit route policy. Do not add provider conditionals to routes or iOS.

## 18. Completion criteria

The implementation is complete only when:

- the iOS app has no live-coaching dependency on Apple system speech or an on-device model;
- all fixed and dynamic audible cues are server-generated audio;
- fixed cues require no runtime AI call;
- dynamic wording and audio use one Alibaba request where supported;
- the client cannot choose or observe service/model/endpoint/vendor voice;
- Alibaba is the only registered V1 provider, selected through the generic router;
- the selected route is pinned for the workout and failure uses a cached generated pack;
- live-coach routes require auth, ownership, bounded schemas, idempotency, quotas, and deadlines;
- server context is authoritative, compact, deterministic, privacy-filtered, and compiled once per session;
- provider prompts/results/audio and exact live telemetry do not enter logs or product analytics;
- cost, latency, health, and categorized fallback metrics are available for future routing decisions;
- `en`, `es`, and `zh-Hans` voice packs and settings are complete;
- backend and iOS build-only verification succeeds;
- focused docs are updated and the final implementation commit excludes unrelated workspace files.
