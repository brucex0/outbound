# Provider-Agnostic AI Live Coaching Audio Implementation Plan

**Status:** Implemented in code; operational audio-pack review/publication and rollout remain explicit release steps

**Initial provider:** Alibaba Cloud Model Studio / Qwen

**Primary outcome:** Every audible coaching cue is server-generated audio. The iOS app never uses an Apple system voice, chooses a vendor/model, or calls an AI vendor directly.

This document is written for an implementation agent. Complete the tasks in order, keep each commit reviewable, and update this plan when implementation reveals a materially different constraint. Follow `AGENTS.md`: do not run the test suite unless the user explicitly requests it; use build-only checks and the manual acceptance matrix for normal verification.

## Implementation reconciliation — 2026-08-28

Cross-checking the handoff against the repository produced these necessary adjustments:

- Reused `getAuthenticatedAppUser` and the existing first-party access-token boundary rather than adding a parallel live-coach auth system. All live-coach routes resolve the current internal user and accept no client user ID.
- Kept public iOS/backend DTOs in the repository's established camel-case JSON convention. Provider payload shapes remain private to the Alibaba adapter.
- Added the Prisma models to `schema.prisma` and the existing `prisma db push` deployment path; this repo does not maintain a Prisma migrations directory.
- Changed `GuideProfile` to stable `coachPersonaId` and `voiceProfileId` fields and fixed `GET /v1/guide/profile` to return the app-shaped versioned payload instead of a raw Prisma row.
- Preserved `VirtualGuide` moment detection, cooldowns, route arbitration, and outcome evaluation. Its output edge now accepts only validated server WAV bytes or reviewed fixed-pack assets. Arbitrary legacy stat/route strings with no reviewed asset are silent rather than invoking device speech.
- Removed the old `/v1/live-coach/analyze`, debug client model selection, on-device Foundation Model coaching provider, rule-based speech provider, Apple voice picker/help, and `AVSpeechSynthesizer` path in the same cutover.
- Pinned Alibaba's workspace-compatible base URL independently from the deployed model and product-to-provider voice map. The regional workspace ID and API key are deployment inputs, never app/catalog fields.
- Kept the operational mode defaulted to `disabled`. `fixed_only` or `dynamic` fails startup unless an immutable HTTPS pack is marked reviewed/published; `dynamic` additionally requires the Alibaba Secret Manager binding, approved deployed model, and complete voice mapping for all enabled product voices/locales.
- Rechecks both the global dynamic mode and deterministic rollout cohort on every cue, applies authenticated-user plus per-session rate limits, and permits at most one provider generation per session at a time.
- Signs the provider-neutral manifest with ES256, binds it to the expected catalog version, declares compatible product personas, verifies every reviewed WAV again at publication, and makes immutable asset publication safely resumable.
- Implemented generation and publication tooling, but intentionally did not fabricate or commit audio. Human listening approval, immutable upload, CDN URLs, and the bundled minimal pack remain required before enabling server audio.
- `subscription_required` remains fail-closed until a verified StoreKit/server entitlement flow is explicitly marked ready. Open beta is the only enabled V1 access policy.

The Alibaba key shared during implementation was not written to source, documentation, shell commands, logs, or generated artifacts. Rotate it before provisioning Secret Manager because chat is not an approved secret channel.

## 1. Goals

Build one provider-neutral backend boundary that:

- accepts product-level coaching requests rather than provider prompts or model IDs;
- compiles bounded user, plan, readiness, preference, and live-session context on the server;
- chooses an eligible AI service, model, endpoint, and provider voice using server policy;
- uses Alibaba only in the first release while leaving a real routing seam for Gemini or another provider;
- supports multiple product-owned coach personas and multiple acoustic voice profiles without exposing provider voice IDs;
- obtains the dynamic coaching utterance and its audio in one provider request when the selected provider supports that capability;
- serves fixed cues as pre-generated server assets, with no runtime AI call;
- grants dynamic coaching to everyone during an open beta while enforcing a backend entitlement seam that can later require a subscription;
- keeps the new server-audio architecture behind a validated operational mode with a fast dynamic-generation kill switch;
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
- Do not trust a client-side premium boolean, StoreKit state, receipt, persona definition, or voice mapping.

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

### 3.4 Coach personas and acoustic voices

Treat these as two related but independent product concepts:

- **Coach persona** controls vocabulary, tone, directness, use of metrics, motivation style, and other wording constraints. It is a versioned, product-authored prompt profile such as `plainstride_supportive_v1`, `plainstride_focused_v1`, or `plainstride_calm_v1`.
- **Voice profile** controls the audible identity and acoustic qualities such as warmth, clarity, pace, and energy. It has a stable Plainstride ID such as `plainstride_warm_1`; only the backend maps it to an Alibaba voice for a specific model/locale.

The current `GuideTemplate`/`GuidePersona` combines template, Apple voice, intensity, frequency, and coaching contract. Migrate it so the saved selection contains `coachPersonaId` and `voiceProfileId` separately. Intensity, nudge frequency, and coaching contract remain independent controls.

Each coach persona declares a default voice and an allowlist of compatible voice profiles. The public catalog exposes only combinations that have:

- a supported provider voice mapping for the requested locale;
- a complete and published fixed fallback pack;
- an approved dynamic prompt profile when dynamic coaching is enabled;
- any required product entitlement.

Do not create a provider-specific persona type. A persona is product content; the provider adapter only sees the resolved instructions and voice mapping.

Avoid unnecessary fixed-pack multiplication. Fixed route, safety, countdown, and workout-transition wording should normally be shared across personas and generated once per `(locale, voiceProfileId, cueKey, catalogVersion)`. Add a `scriptStyleId` dimension only when a persona genuinely changes fixed wording. Dynamic cues always include the selected persona's versioned instruction profile.

Pin `coachPersonaId`, persona instruction version, `voiceProfileId`, and resolved provider voice for the entire workout. A catalog/config change applies to the next session, not halfway through a run.

### 3.5 Configuration and kill switches

The backend is the authority for whether the new architecture can run. Start with environment-backed, startup-validated configuration:

```text
LIVE_COACH_SERVER_AUDIO_MODE=disabled|fixed_only|dynamic
LIVE_COACH_ACCESS_MODE=open_beta|subscription_required
LIVE_COACH_CONFIG_VERSION=1
LIVE_COACH_ALLOWED_MARKETS=global
LIVE_COACH_ENABLED_PERSONAS=plainstride_supportive_v1,plainstride_focused_v1
LIVE_COACH_ENABLED_VOICE_PROFILES=plainstride_warm_1,plainstride_clear_1
LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT=0
LIVE_COACH_DYNAMIC_CUE_LIMIT_RESPONSIVE=8
LIVE_COACH_DYNAMIC_CUE_LIMIT_COACH_ME=15
```

Mode semantics:

- `disabled`: do not create server-audio sessions or make AI calls. The app may show non-audio guidance; it must not fall back to Apple speech.
- `fixed_only`: allow published server-generated packs and bundled fallback audio, but make no runtime AI calls.
- `dynamic`: allow dynamic generation after entitlement, quota, route, health, safety, and cost gates; fixed audio remains the fallback.

Default every new deployment and developer environment to `disabled`. Production enablement is an explicit deploy configuration change. Invalid or incomplete configuration fails closed: `dynamic` cannot start without a provider route, voice mappings, published fallback packs, and required secrets.

When mode is `dynamic`, apply `LIVE_COACH_DYNAMIC_ROLLOUT_PERCENT` using a deterministic server-side hash of internal user ID plus config version. Users outside the rollout receive effective `fixed_only` behavior. This supports 0/partial/100-percent rollout without a new app build; it is an availability control, not an entitlement. A future operator override must also be server-owned and audit logged.

Return a provider-neutral snapshot from `GET /v1/live-coach/config` containing the effective mode, config version, catalog version, access presentation state, and supported contract version. Do not expose environment values, provider/model IDs, routing scores, or vendor health. iOS may also have a build-time capability flag while the client implementation is incomplete, but the client flag is never an authorization or cost-control boundary.

Most configuration is pinned when a session starts. The emergency rule is different: every cue request rechecks whether dynamic generation is still globally allowed. Changing `dynamic` to `fixed_only` immediately stops new AI calls for existing sessions and returns a fixed-fallback decision. Never change persona or provider voice mid-session because of a routine config refresh.

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
- Legacy `GuideProfile.personality`/`voiceId` and `backend/src/types/guide.ts`: replace loose personality values and provider-shaped voice IDs with stable `coachPersonaId`/`voiceProfileId`. This project is pre-launch, so use a clean schema migration rather than maintaining both shapes.

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

export type CoachPersona = {
  id: "plainstride_supportive_v1" | "plainstride_focused_v1" | "plainstride_calm_v1";
  instructionVersion: number;
  defaultVoiceProfileId: VoiceProfile["id"];
  allowedVoiceProfileIds: Array<VoiceProfile["id"]>;
  fixedScriptStyleId: "standard" | "calm";
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
  coachPersonaId: CoachPersona["id"];
  coachPersonaInstructions: string;
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

### 9.1 Effective configuration

`GET /v1/live-coach/config`

This authenticated endpoint lets iOS decide which setup UI to expose without making the client authoritative:

```json
{
  "contractVersion": 1,
  "configVersion": "1",
  "mode": "dynamic",
  "catalogVersion": "2026-08-28.1",
  "access": {
    "dynamicCoaching": "allowed",
    "reason": "open_beta",
    "paywallAvailable": false
  }
}
```

Cache briefly and refresh before starting a workout. The create-session response is authoritative if this snapshot is stale. When the endpoint is unavailable, iOS uses its bundled fixed pack only.

### 9.2 Coach and voice catalog

`GET /v1/live-coach/catalog?locale=en`

Response:

```json
{
  "contractVersion": 1,
  "catalogVersion": "2026-08-28.1",
  "audioPack": {
    "manifestVersion": "2026-08-28.1",
    "manifestUrl": "https://cdn.example/live-coach/2026-08-28.1/manifest.json"
  },
  "coachPersonas": [
    {
      "id": "plainstride_supportive_v1",
      "displayName": "Supportive",
      "description": "Encouraging, practical coaching that keeps effort sustainable.",
      "defaultVoiceProfileId": "plainstride_warm_1",
      "allowedVoiceProfileIds": ["plainstride_warm_1", "plainstride_clear_1"],
      "fixedScriptStyleId": "standard",
      "access": "included"
    }
  ],
  "voices": [
    {
      "id": "plainstride_warm_1",
      "displayName": "Warm",
      "description": "Relaxed, natural, and reassuring.",
      "style": "warm",
      "previewAssetId": "voice.preview"
    }
  ]
}
```

Display names and descriptions are localized product strings. `access` is a bounded presentation hint such as `included` or `upgrade_required`; session creation rechecks it. Do not return prompt instructions, provider, model, endpoint, or vendor voice IDs.

### 9.3 Create a live-coach session

`POST /v1/live-coach/sessions`

Request:

```json
{
  "contractVersion": 1,
  "clientSessionId": "uuid",
  "workoutId": "optional-authoritative-workout-id",
  "locale": "en",
  "coachPersonaId": "plainstride_supportive_v1",
  "voiceProfileId": "plainstride_warm_1",
  "coachingContract": "responsive",
  "sessionIntent": {
    "activityType": "running",
    "goalType": "workout"
  },
  "appDistributionHint": "global"
}
```

The backend authenticates the user, validates workout ownership, resolves the authoritative market, compiles session context once, selects and pins a route, and returns:

```json
{
  "contractVersion": 1,
  "sessionId": "opaque-id",
  "contextVersion": 1,
  "expiresAt": "ISO-8601",
  "effectiveMode": "dynamic",
  "dynamicCoachingAvailable": true,
  "access": {
    "dynamicCoaching": "allowed",
    "reason": "open_beta",
    "paywallAvailable": false
  },
  "audioPack": {
    "manifestVersion": "2026-08-28.1",
    "manifestUrl": "short-lived-or-public-content-url"
  },
  "limits": {
    "cueValidityMilliseconds": 5000,
    "maximumDynamicCues": 8
  }
}
```

Session creation must be idempotent for `(user, clientSessionId)`. The backend validates persona/voice compatibility, access, fixed-pack readiness, and operational mode. If dynamic access is unavailable, still create a `fixed_only` session instead of breaking workout guidance. The app may offer an upgrade before the workout when `paywallAvailable` is true, but never interrupt an active run with a paywall.

### 9.4 Request a cue

`POST /v1/live-coach/sessions/:sessionId/cues`

Request:

```json
{
  "contractVersion": 1,
  "cueRequestId": "uuid",
  "moment": "pace_drift",
  "detectedAtElapsedSeconds": 842,
  "validForMilliseconds": 5000,
  "liveState": {
    "elapsedSeconds": 842,
    "distanceMeters": 2740,
    "currentPaceSecondsPerKilometer": 331,
    "rollingPaceSecondsPerKilometer": 324,
    "targetPaceSecondsPerKilometer": 315,
    "workoutSegmentIndex": 2,
    "workoutSegmentPhase": "work",
    "routeGuidanceActive": false
  }
}
```

Only allow named bounded fields. Do not accept coordinates, route geometry, raw sample arrays, arbitrary history, user prose, or a client-supplied system prompt. Exact telemetry exists in this transactional request but must not enter general product analytics or application logs.

Response:

```json
{
  "contractVersion": 1,
  "cueRequestId": "uuid",
  "source": "dynamic_generation",
  "result": "success",
  "moment": "pace_drift",
  "urgency": "opportunity",
  "transcript": "Ease it back a touch and settle into your target rhythm.",
  "audio": {
    "contentType": "audio/wav",
    "base64": "...",
    "durationMilliseconds": 3100
  },
  "generatedAt": "ISO-8601",
  "expiresAt": "ISO-8601"
}
```

V1 uses base64 because cues are tiny and this keeps one authenticated request. If measurement shows response overhead or time-to-first-audio is unacceptable, add a provider-neutral binary/streaming endpoint without changing the domain provider interface.

The cue route is idempotent for `(session, cueRequestId)`. Concurrent duplicates share one in-flight generation. The server may retain the completed bounded result only until its short expiration; do not permanently store audio or transcript.

If configuration, entitlement, or quota no longer permits a dynamic call, return an appropriate `fixed_pack`/`cached_fallback` cue envelope and make no provider request. A modified client cannot bypass this behavior.

### 9.5 End a session

`POST /v1/live-coach/sessions/:sessionId/end`

Accept final coarse counts and outcome buckets needed for cost/reliability reconciliation. Mark the session ended, discard any transient cue payload cache, and abort in-flight generation. Do not upload the full local cue record unless a separate privacy-reviewed learning design requires it.

### 9.6 Fixed assets

Expose an immutable manifest and asset endpoint/CDN path. The manifest maps semantic keys, locale, voice-profile ID, optional fixed-script style, and version to a checksum, duration, content type, and URL. It declares compatible coach personas but never includes prompt instructions or provider/model metadata.

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

Create a semantic catalog in `backend/resources/liveCoachAudio/` for `en`, `es`, and `zh-Hans`. Product strings must be natural translations, not concatenated word fragments. Keep universal/safety scripts separate from the smaller set of persona-specific script styles so adding a persona does not automatically duplicate the whole catalog.

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
npm run live-coach:generate-audio -- --catalog-version 2026-08-28.1 --provider alibaba
```

The command must:

1. load secrets only from environment/Secret Manager integration;
2. hash normalized text + locale + voice profile + script style + audio spec + provider route version;
3. skip already generated matching hashes;
4. call the provider through the same registry with request kind `live_coach_fixed_asset`;
5. validate WAV format, maximum duration, transcript agreement, and non-silence;
6. write a review manifest outside committed source artifacts;
7. require an explicit publish step after human listening review;
8. upload immutable content-addressed objects;
9. publish a provider-neutral signed manifest atomically.

Bundle a small default pack with the app for countdown, workout transitions, route safety, and generic fallback. Download the selected persona-compatible voice pack after selection/session setup and cache by checksum. Retain the last known-good pack until the replacement is fully verified.

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
  coachPersonaId        String
  personaVersion        Int
  voiceProfileId        String
  coachingContract      String
  effectiveAudioMode    String
  configVersion         String
  accessReason          String
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

model FeatureEntitlement {
  id                    String   @id @default(cuid())
  userId                String
  capability            String
  source                String
  status                String
  sourceReferenceHash   String?  @unique
  startsAt              DateTime
  expiresAt             DateTime?
  createdAt             DateTime @default(now())
  updatedAt             DateTime @updatedAt

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, capability, source])
  @@index([userId, capability, status, expiresAt])
}

model FeatureUsagePeriod {
  id                    String   @id @default(cuid())
  userId                String
  capability            String
  periodKey             String
  reservedCount         Int      @default(0)
  successfulCount       Int      @default(0)
  limitSnapshot         Int?
  createdAt             DateTime @default(now())
  updatedAt             DateTime @updatedAt

  user User @relation(fields: [userId], references: [id], onDelete: Cascade)

  @@unique([userId, capability, periodKey])
}
```

Adjust relations to the actual Prisma `User` model. `FeatureEntitlement` stores only durable, backend-verified grants; the `open_beta` policy is computed and does not create a fake grant for every user. Store only a hash or opaque reference for an external transaction, never raw receipts or signed payloads. `FeatureUsagePeriod` is optional until a cross-session/monthly quota is enabled, but the access interface must support it from the start.

Treat provider/model/voice as internal operational data. Do not persist transcript, audio, prompt, exact telemetry, or provider response body in `LiveCoachCue`. Use an in-process short TTL cache for V1 idempotent response replay; if Cloud Run concurrency or multiple instances make duplicate cost measurable, move only the short-lived encrypted result and in-flight lock to an appropriate shared cache.

Because this product is pre-public launch, use the cleanest schema and document the required migration/reset command; do not build compatibility layers for old debug live-coach rows.

## 13. Entitlements, future paywall, cost, and latency

### 13.1 Access policy

Gate the backend capability `live_coach_dynamic`, not a provider/model and not the entire workout recorder. Fixed countdown, workout-transition, route, safety, and generic fallback audio remains available without a paid entitlement. This preserves a useful free product and guarantees that losing access never removes safety-critical guidance.

Create a provider-neutral resolver:

```ts
type LiveCoachAccessDecision = {
  capability: "live_coach_dynamic";
  allowed: boolean;
  reason:
    | "open_beta"
    | "verified_subscription"
    | "promotion"
    | "entitlement_required"
    | "quota_exhausted"
    | "feature_disabled";
  quota?: { limit: number; remaining: number; resetsAt?: Date };
  paywallAvailable: boolean;
};

interface LiveCoachEntitlementResolver {
  resolve(userId: string, now: Date): Promise<LiveCoachAccessDecision>;
}
```

V1 uses `LIVE_COACH_ACCESS_MODE=open_beta`; every authenticated user receives an ephemeral `allowed: true, reason: open_beta` decision, subject to operational mode and abuse/cost limits. There is no paywall UI and no database entitlement row for this automatic grant.

Future monetization changes the backend mode to `subscription_required` only after the purchase flow and server verifier are deployed. iOS uses StoreKit 2 for localized product display, purchase, restore, and immediate UI state, then sends the App Store-signed transaction representation to a dedicated backend sync endpoint. The backend verifies the signed transaction and current subscription state, binds it to the authenticated Plainstride account, and writes/revokes a durable capability grant. Apple documents that StoreKit transactions and App Store Server API transaction/subscription results are App Store-signed JWS data; use the current official [StoreKit Transaction](https://developer.apple.com/documentation/storekit/transaction), [App Store Server API](https://developer.apple.com/documentation/appstoreserverapi), and [App Store Server Notifications](https://developer.apple.com/documentation/AppStoreServerNotifications/receiving-app-store-server-notifications) guidance when implementing this later phase.

Rules for the future paid mode:

- the backend is authoritative; a client `isPremium` boolean or local StoreKit cache never authorizes an AI call;
- use an app-account token or equivalent verified binding so a transaction cannot be claimed by another Plainstride account;
- process renewal, expiration, billing-retry/grace state, refund, and revocation updates idempotently;
- provide `POST /v1/entitlements/app-store/sync` for purchase/restore reconciliation and a signed server-notification endpoint;
- never store raw receipt/JWS payloads longer than operationally required; retain normalized grant state and opaque/hash references;
- require the correct bundle, environment, product allowlist, subscription group, signature, and validity window;
- prevent `subscription_required` configuration from activating until the minimum supported iOS build has a working localized paywall and restore path;
- show upgrade UI in setup/settings, not during an active run;
- entitlement service failure fails closed for new dynamic calls but fixed audio continues;
- promotions, trials, staff access, or future web billing issue the same `live_coach_dynamic` capability through different verified grant sources.

Persona and voice monetization may later use additional stable capabilities such as `live_coach_persona:plainstride_focused_v1` or `live_coach_voice:plainstride_warm_1`. Do not encode `isPremium` into persona IDs, voice IDs, provider mappings, or fixed manifests. V1 includes all enabled personas/voices for open-beta users unless product configuration explicitly says otherwise.

Quota enforcement occurs after entitlement resolution and before provider selection. Reserve usage atomically before calling the provider, finalize on a valid successful result, and release the reservation for provider failure, timeout, cancellation, or stale output. Idempotent duplicate cue requests reuse the original reservation/result and never double count.

### 13.2 Runtime cost and latency policy

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
- `result`: `success`, `offline`, `timeout`, `stale`, `invalid`, `unavailable`, `feature_disabled`, `entitlement_required`, `quota_exhausted`, `budget_exhausted`;
- effective audio mode and bounded access reason (`open_beta`, `verified_subscription`, `promotion`, or `entitlement_required`);
- coarse latency bucket;
- semantic moment, coaching contract, outcome, and coarse cue-count bucket already allowed by the product analytics spec.

Never send provider/model/voice vendor ID, transcript, audio, prompt, exact pace/distance/time, session ID, request ID, user ID, transaction ID, receipt/JWS, or subscription expiration timestamp as Firebase event properties.

When the paid phase is implemented, add typed events for paywall exposure, purchase/restore attempted, and bounded result. Those events answer funnel/reliability questions; they do not authorize access. Do not emit a paywall exposure during a workout.

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
- `backend/src/services/liveCoach/liveCoachFeatureConfig.ts`
- `backend/src/services/liveCoach/liveCoachCatalog.ts`

**Modify**

- `backend/package.json` only if an official SDK or audio validation dependency is justified; prefer the existing `fetch` runtime for a small adapter.

**Acceptance**

- Product code can express required capability without naming a vendor/model.
- Configuration defaults to `disabled` and rejects enabled routes with missing secrets, model, endpoint, persona profiles, voice mappings, or published fixed packs.
- The catalog keeps product coach-persona instructions separate from provider voice mappings and exposes only compatible combinations.
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

### Task 4: Add live-coach persistence, access policy, and context compilation

**Create**

- Prisma migration for `LiveCoachSession`, `LiveCoachCue`, `FeatureEntitlement`, and optional `FeatureUsagePeriod`
- `backend/src/services/liveCoach/liveCoachTypes.ts`
- `backend/src/services/liveCoach/liveCoachContextCompiler.ts`
- `backend/src/services/liveCoach/liveCoachSessionService.ts`
- `backend/src/services/liveCoach/liveCoachCueRepository.ts`
- `backend/src/services/liveCoach/liveCoachAccessPolicy.ts`

**Modify**

- `backend/prisma/schema.prisma`
- `backend/src/types/guide.ts`
- `backend/src/routes/guide.ts` where guide settings/profile DTOs expose the legacy fields
- `backend/src/services/companion/sessionBrief.ts` only if a provider-neutral projection is needed; preserve existing consumers.

**Acceptance**

- Context is compiled once with stable ordering, a hash, and an enforced budget.
- Guide profile/settings persistence uses stable coach-persona and voice-profile IDs; provider voice IDs never enter the user profile.
- `open_beta` grants every authenticated user dynamic access without fake persisted grants.
- Session ownership, config mode, entitlement, idempotent creation, expiration, usage reservations, and cue quotas are enforced transactionally.
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
- Configuration, persona/voice compatibility, entitlement, quota, and fixed-pack readiness are checked before provider routing.
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
- Implement effective-config, coach/voice catalog, create-session, cue, and end-session endpoints.
- Use strict schemas, request-size bounds, ownership checks, and user/session rate limits.
- Public DTOs contain no provider implementation details.
- A denied dynamic entitlement or `fixed_only` mode creates a usable fixed-audio session and cannot be bypassed by the client.

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
- Every exposed persona/voice/locale combination has a complete fixed fallback pack; shared scripts are not duplicated across personas unnecessarily.
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
- `ios/Outbound/Outbound/Guide/LiveCoachFeatureState.swift`

**Remove after call sites migrate**

- `ios/Outbound/Outbound/Guide/RemoteSessionAnalysisProvider.swift`
- `ios/Outbound/Outbound/Guide/AppleFoundationModelSessionAnalysisProvider.swift`

**Acceptance**

- iOS sends semantic moment plus bounded state, never a provider/model/prompt.
- iOS consumes effective mode/access/catalog state but never authorizes itself.
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

### Task 10: Replace Apple voice selection with Plainstride coach personas and voice profiles

**Modify**

- `ios/Outbound/Outbound/Guide/GuideTemplate.swift`
- `ios/Outbound/Outbound/Guide/GuideCatalogStore.swift`
- `ios/Outbound/Outbound/Guide/GuideSelectionView.swift`
- `ios/Outbound/Outbound/Localizable.xcstrings`

**Acceptance**

- Settings store a stable Plainstride voice-profile ID.
- Settings store the stable coach-persona ID separately from voice profile, intensity, frequency, and coaching contract.
- The picker shows only server-approved compatible persona/voice combinations and falls back to each persona's default voice when a saved option disappears.
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
- Effective mode, bounded access reason, paywall exposure, and future purchase/restore result use typed privacy-reviewed values.
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
- `LIVE_COACH_SERVER_AUDIO_MODE` and `LIVE_COACH_ACCESS_MODE` default to safe values, are validated at startup, and have documented rollout/rollback commands.
- Audio bucket access, cache headers, lifecycle, and publish command are documented.
- Rollback uses `fixed_only` to stop AI cost immediately while preserving fixed packs; `disabled` never re-enables Apple speech.

### Deferred paid phase: implement verified App Store entitlements

Do not implement or expose the paywall during the free launch. Complete this phase before changing `LIVE_COACH_ACCESS_MODE` to `subscription_required`.

**Create**

- `backend/src/routes/entitlements.ts`
- `backend/src/services/entitlements/appStoreEntitlementService.ts`
- `backend/src/services/entitlements/appStoreNotificationService.ts`
- `ios/Outbound/Outbound/Core/Entitlements/StoreKitEntitlementStore.swift`
- `ios/Outbound/Outbound/Guide/LiveCoachPaywallView.swift`

**Modify**

- `backend/src/index.ts`
- `backend/prisma/schema.prisma` if the entitlement schema was deferred in the free phase
- `ios/Outbound/Outbound/Core/APIClient.swift`
- `ios/Outbound/Outbound/Localizable.xcstrings`
- `docs/app-store-release.md`
- product analytics contract and App Store privacy/subscription disclosures.

**Acceptance**

- StoreKit product display, purchase, restore, and subscription management UI is localized and accessible.
- The backend verifies App Store-signed data and current status before issuing `live_coach_dynamic`.
- Server notifications idempotently update renewals, expiration, refunds, and revocations.
- Account binding prevents one purchase from being claimed by unrelated Plainstride accounts.
- The app handles offline/unknown entitlement state without granting a new dynamic call; fixed audio continues.
- Paywall and restore flows are reachable before a run and never interrupt an active workout.
- Switching to `subscription_required` is blocked until the minimum supported client version includes this flow.

### Task 13: Add focused tests, but do not run them without user authorization

**Backend test coverage to add**

- route hard eligibility and deterministic scoring;
- market/locale separation;
- config mode fail-closed behavior and per-cue dynamic kill-switch recheck;
- deterministic 0/partial/100-percent rollout with fixed-only behavior outside the cohort;
- coach-persona/voice compatibility and catalog filtering;
- `open_beta`, entitlement-required, promotion, subscription, and quota decisions;
- idempotent quota reservation/finalization/release;
- Alibaba stream parsing and sanitized errors;
- audio format/size/duration validation;
- context ordering, truncation, exclusion, and hashing;
- idempotent session/cue behavior and ownership;
- quota/deadline/stale gates;
- no provider details in public DTOs;
- fixed catalog/manifest completeness for every exposed persona/voice/locale combination.

**iOS test coverage to add**

- stale cue rejection;
- cancellation and single in-flight request;
- disabled/fixed-only/dynamic UI and session behavior;
- separate persona/voice selection and missing-selection fallback;
- access-denied fixed-audio behavior with no in-run paywall;
- fixed fallback selection;
- audio queue priority and interruption state;
- pack checksum/last-known-good behavior;
- analytics privacy allowlist.

Do not execute these tests unless the user explicitly asks. A later authorized verification run should use the narrowest relevant commands before broader suites.

### Task 14: Build-only and manual verification

Run the backend TypeScript build and an iOS build-only compile check. Then verify on a real device/network profile:

1. select each Plainstride voice profile and hear its generated preview;
2. select each enabled coach persona with at least its default compatible voice and confirm the wording style changes without exposing a provider voice;
3. start a workout and hear server-generated countdown audio;
4. trigger a dynamic semantic moment and confirm one Alibaba call returns matching text/audio;
5. set `LIVE_COACH_SERVER_AUDIO_MODE=fixed_only` and confirm no new Alibaba calls occur while fixed cues continue;
6. set the mode to `disabled` and confirm neither server AI nor Apple speech runs;
7. use `LIVE_COACH_ACCESS_MODE=open_beta` and confirm every authenticated user is allowed subject to quotas;
8. simulate an entitlement-required decision and confirm fixed guidance continues and no paywall appears mid-run;
9. confirm music ducks and resumes;
10. trigger route caution during coaching and confirm priority/cancellation;
11. introduce slow/offline networking and confirm stale audio never plays and cached fallback is used;
12. finish the session and confirm in-flight work stops;
13. run in `en`, `es`, and `zh-Hans`;
14. inspect logs/analytics to confirm no prompt, transcript, audio, exact telemetry, transaction data, provider response, or credentials were emitted;
15. confirm the app contains no active Apple speech path.

## 17. Rollout sequence

1. Land contracts, catalog, access resolver, router, Alibaba adapter, validation, and operational metrics with `LIVE_COACH_SERVER_AUDIO_MODE=disabled` and `LIVE_COACH_ACCESS_MODE=open_beta`.
2. Generate, review, publish, and bundle fixed packs before enabling any dynamic path.
3. Publish the first server catalog with at least one coach persona and one compatible voice per supported locale; add more combinations only after their fixed packs pass review.
4. Land new backend routes while the old debug `/analyze` path remains disabled outside local development.
5. Land iOS provider-neutral session/cue client and audio player behind its build capability flag.
6. Remove Apple/Foundation/debug provider paths and the old `/analyze` route in the same release boundary; do not ship a mixed voice fallback.
7. Enable `fixed_only` for device testing and validate config rollback before allowing AI traffic.
8. Enable `dynamic` for an internal cohort with Alibaba pinned to one dated model and voice mapping. Keep access mode `open_beta`.
9. Measure p50/p95 latency, invalid/stale/fallback rate, cue frequency, and estimated cost by locale, persona, and voice profile.
10. Tune request deadlines and cue limits through server policy, then gradually expand the dynamic cohort. The emergency dynamic kill switch remains effective for existing sessions.
11. Before charging, complete the deferred StoreKit/server-verification phase, ship a localized paywall/restore path, enforce a minimum client version, and validate subscription lifecycle events. Only then switch access mode to `subscription_required`.
12. Add a second provider only after defining its adapter, capability/market facts, voice-quality evaluation, and explicit route policy. Do not add provider conditionals to routes or iOS.

## 18. Completion criteria

The implementation is complete only when:

- the iOS app has no live-coaching dependency on Apple system speech or an on-device model;
- all fixed and dynamic audible cues are server-generated audio;
- fixed cues require no runtime AI call;
- dynamic wording and audio use one Alibaba request where supported;
- the client cannot choose or observe service/model/endpoint/vendor voice;
- Alibaba is the only registered V1 provider, selected through the generic router;
- coach persona and acoustic voice are separate stable product selections, with every exposed combination supported by dynamic routing and a reviewed fixed fallback pack;
- the selected route is pinned for the workout and failure uses a cached generated pack;
- the backend architecture defaults to `disabled`, supports `fixed_only`/`dynamic`, fails closed on invalid configuration, and rechecks the emergency dynamic kill switch for every cue;
- free launch uses the backend `open_beta` access policy for all authenticated users, and no client flag can bypass entitlement/quota decisions;
- future paid mode has a documented server-verified capability-grant path and cannot remove fixed safety/workout audio;
- live-coach routes require auth, ownership, bounded schemas, idempotency, quotas, and deadlines;
- server context is authoritative, compact, deterministic, privacy-filtered, and compiled once per session;
- provider prompts/results/audio and exact live telemetry do not enter logs or product analytics;
- cost, latency, health, and categorized fallback metrics are available for future routing decisions;
- `en`, `es`, and `zh-Hans` voice packs and settings are complete;
- backend and iOS build-only verification succeeds;
- focused docs are updated and the final implementation commit excludes unrelated workspace files.
