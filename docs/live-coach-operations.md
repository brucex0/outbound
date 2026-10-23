# Live Coach Audio Operations

Open this when generating or publishing live-coach audio, changing the Google TTS route or voice map, or changing rollout exposure. Open `docs/live-coach-data-boundaries.md` for the exact privacy boundary.

## Current Architecture

Ad-hoc Race mode supplies typed race distance, goal mode, optional target time/pace, pacing strategy, and a bounded recommendation source to the start planner. Runtime detection remains on device. Race moments use the same planned-cache and streaming route as other semantic cues. Until a reviewed successor pack adds purpose-built race assets, fixed fallback reuses the closest reviewed early-settle, halfway, rebuild-rhythm, steady, and strong-finish assets; semantics and analytics remain race-specific.

Live coaching uses the configured planner on workout selection or session start and Google Cloud Text-to-Speech for runtime exact-text cues, planned-audio prewarming, and reviewed fixed-pack generation:

1. At session start, the backend compiles bounded profile, survey, recent training, workout, route-summary, readiness, location, and weather context. A standalone selection is sent as a catalog reference; the backend resolves its guide-relevant execution projection before the planner returns a strict-JSON phase-aware and instruction-ID-aware phrase plan.
2. iOS keeps semantic detection, selected-workout distance/time trigger crossings, and cooldowns local, selects a phrase ID from that plan, and sends bounded live state. For `progress`, the backend deterministically formats rounded distance, elapsed time, and pace.
   Final 300-meter/100-meter (or imperial-equivalent) countdowns use the same cloud coach voice with a bounded remaining-distance value. Missing generated or recorded audio remains silent; the app never switches to a system-synthesized voice.
3. Google TTS receives only the finalized sentence, selected voice, language, and 24 kHz PCM settings.
4. Google `streamingSynthesize` chunks are forwarded in a framed HTTP/2 response and played through `AVAudioEngine` as they arrive.
5. Generated plans prewarm up to eight likely WAV phrases in the background, with selected-workout instructions first. The whole device request, including the wait for response metadata, is raced against a 1.5 second deadline. If cloud audio loses that race, iOS cancels it and uses matching reviewed recorded audio when available; otherwise it remains silent.

Selected-workout triggers fire once, with a 20-second elapsed-time or 75-meter distance crossing window. The first zero trigger may fire immediately. Reliable distance is required after the initial cue, stale crossings are skipped, route guidance wins, and elapsed catalog cues replace only the generic timed transition at the same boundary. Each server workout step carries its planned transition instruction, lead time, and countdown policy. Direct transitions speak the coaching-focused instruction slightly before the boundary and do not repeat at the boundary; recovery and walking-break transitions may request the reviewed five-through-one sequence. Those countdowns never request runtime synthesis: iOS preloads and validates the complete fixed-pack sequence before playing its first beat. If the sequence is incomplete or the five-second opening is missed, that countdown remains silent and reports bounded availability telemetry. Pause/resume, route safety, and completion fallback behavior remains deterministic on device.

iOS keeps the streaming audio engine alive until the final PCM buffer reports `.dataPlayedBack`; buffer-consumption callbacks are not treated as audible completion because doing so can clip the end of stat announcements.

At live-session activation, iOS preloads the selected voice's reviewed `workout.pause` and `workout.resume` clips. Auto-pause can begin soon after countdown, so these controls cannot rely on a prior cue having opportunistically populated the fixed-pack cache. If the network and last-known-good cache are both unavailable, the cue remains silent.

There is no TTS WebSocket and no LLM call in the live cue path. HTTP/2 is device-to-Plainstride and gRPC is Plainstride-to-Google. `live_guidance_audio_first_byte` measures the end-to-end product gate separately from response-metadata latency.

### Ordinary-Run Coaching Delivery

- Phrase plans include deterministic, localized execution tips for ordinary runs even while AI planning is pending or unavailable. iOS consumes their explicit `execution_coaching.*` IDs and elapsed triggers; no new cue moment or database shape is introduced. See `docs/live-coaching-moments.md` for scheduling and suppression.
- Prewarming is eligible for any dynamic session, including a fallback phrase plan. Missing audio releases the device queue and emits a diagnostic rather than repeatedly blocking subsequent cues.
- After deploying this change, start a new session with an updated iOS build. Existing sessions do not acquire the new instruction timeline. DEBUG route simulation now supplies synthetic cadence; physical runs continue to require measured cadence.

### Countdown Lookup Contract And Regression Checks

- Fixed start and segment countdowns select reviewed clips by cue key, locale, voice, and persona. Do not pass display digits as a transcript constraint: `3` differs from `Three.`, `Tres.`, and `三。`.
- Sentence cues retain transcript matching so a recorded fallback cannot speak a different instruction from the intended message. Do not relax that shared guard to repair countdowns.
- Regression `977d8593` (2026-10-11) added transcript matching to shared cue-key candidates without adapting the countdown consumers. Start aborted on the first miss; segment countdowns also failed despite successful key-only preloading. Compile checks cannot detect this data-contract mismatch.
- Before changing shared audio lookup, inspect all consumers and verify numeric countdowns plus matching/mismatching sentences against actual catalog wording in every locale. Check both locally cached clips and uncached download selection; preloading alone does not verify playback selection.
- Device acceptance: hear the full three-two-one-Go start and five-through-one segment sequence with both voices in EN/ZH; confirm unavailable packs stay silent and emit `live_guidance_fixed_audio_unavailable` with `start_countdown` or `segment_countdown`. Failed lookups also emit a safe `GuideAudio` diagnostic; missed timing windows are normal control flow and are not error-logged.

### Current Latency Evidence

On 2026-08-30, the former complete-WAV route measured 790–1,270 ms for direct warm synthesis, with a 1,017 ms median, before iPhone/Cloud Run transport. That evidence rejected the complete-WAV design; it is not evidence for the streaming implementation. Do not claim the new path meets the gate until a real iPhone records device-request-to-first-playable-audio below one second at representative percentiles. During live beta testing, six successful stream requests completed in 637–963 ms, and the owner approved increasing the device fallback threshold from 850 ms to 1.5 seconds so viable cloud streams are not cancelled prematurely.

For a real-device benchmark, install a DEBUG build against the candidate Cloud Run revision, start the run simulator, and trigger at least 30 uncached semantic cues across cold and warm connections. Capture `device_to_first_audio_ms` from the device console. This timer starts before the authenticated HTTP request and stops when the first PCM frame reaches iOS. Report median, p90, p95, cloud-audio success rate, planned-cache rate, and the fraction that crossed into the 1.5 second local fallback. Do not log transcripts, plan/context payloads, exact metrics, or identifiers.

On 2026-08-30 PDT, a synthetic smoke execution using the production container image and `outbound-api-runtime` identity measured 485 ms from the Cloud Run process starting `streamingSynthesize` to its first PCM chunk, with 111,360 audio bytes returned. The same execution received valid strict JSON from `gemini-3.1-pro-preview` in 4,198 ms. This verifies provider availability, runtime IAM, model access, and streaming audio, but it excludes iPhone transport and the live API route and is therefore not the end-to-end device result.

Later that day, a simulated Responsive session showed why request duration must be separated from fallback cause. Earlier streamed responses completed in 0.64–1.64 seconds, while the final two periodic stats calls returned metadata-only responses in 31 ms and 38 ms because the obsolete eight-cue quota rejected them before TTS. This was not a TTS timeout. Per-workout cue quotas have been removed: access is counted in eligible workout sessions, while semantic cooldowns and request-rate controls continue to govern cadence.

## Current Production Deployment

- Revision and image digest: see the current rollout in `docs/ai-reliability.md`
- Traffic: 100%
- Scaling: minimum 1 warm instance, maximum 3
- Audio mode/rollout: `dynamic`, 100%, config version `2`
- Access: `founding_trial`, first 1,000 accounts, three later trial runs
- Planner: enabled, `gpt-6-luna`, OpenAI Responses with low reasoning
- TTS: enabled, Chirp 3 HD through `us-texttospeech.googleapis.com`
- Locales/voices: English and Simplified Chinese; `plainstride_warm_1` and `plainstride_clear_1`
- Fixed pack: signed `2026-09-08.1` manifest; 216 two-voice assets are published, while the enabled EN/ZH subset uses 144
- Alibaba: disabled; its retained secret binding is inactive and remains available only for rollback

The runtime identity has `roles/aiplatform.user` and `roles/serviceusage.serviceUsageConsumer`. Google Cloud Text-to-Speech does not expose a project-level `roles/texttospeech.user` role; the enabled API, attached runtime ADC, and service-usage permission authorize synthesis.

There is no per-workout cue allowance. Once a workout has dynamic access, both coaching interventions and periodic distance/time/pace announcements remain eligible for the full session. If cloud or recorded audio is unavailable, iOS remains silent rather than switching to a system voice.

## Approved Google Route And Voices

- API: Google Cloud Text-to-Speech
- Model family: Chirp 3 HD
- Regional endpoint: `us-texttospeech.googleapis.com`
- Authentication: Application Default Credentials from the Cloud Run runtime service account
- Live audio: headerless PCM signed 16-bit little-endian, 24 kHz, mono
- Prewarm/fixed assets: WAV with the same PCM format

The app exposes one provider-neutral female option and one male option. Google identifiers remain backend-only.

| Product voice | Presentation | English | Spanish | Simplified Chinese |
| --- | --- | --- | --- | --- |
| `plainstride_warm_1` | Female | `en-US-Chirp3-HD-Aoede` | `es-US-Chirp3-HD-Aoede` | `cmn-CN-Chirp3-HD-Aoede` |
| `plainstride_clear_1` | Male | `en-US-Chirp3-HD-Charon` | `es-US-Chirp3-HD-Charon` | `cmn-CN-Chirp3-HD-Charon` |

Cloud Run must not use a mobile OAuth client or an API key committed to the app. The supplied `google-tts-client_*.plist` is an iOS OAuth client configuration, not a Google Cloud TTS credential, and is intentionally not copied into the repository.

## Provider Configuration

Production defaults:

```text
GOOGLE_CLOUD_TTS_ENABLED=true
GOOGLE_CLOUD_TTS_API_ENDPOINT=us-texttospeech.googleapis.com
GOOGLE_CLOUD_TTS_ENDPOINT_KEY=google-cloud-tts-us
GOOGLE_CLOUD_TTS_DEPLOYMENT_REGION=us
GOOGLE_CLOUD_TTS_MODEL=chirp3-hd
LIVE_COACH_PLANNER_ENABLED=true
GEMINI_LIVE_COACH_PLANNER_MODEL=gpt-6-luna
GEMINI_VERTEX_PROJECT_ID=outbound-494602
GEMINI_VERTEX_LOCATION=global
GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS=45000
ALIBABA_AI_ENABLED=false
```

Production deployment uses `OPENAI_API_KEY_SECRET=outbound-openai-api-key`; the helper mounts it as `OPENAI_API_KEY`. Do not put the key in ordinary environment values.

`GOOGLE_CLOUD_TTS_VOICE_MAP` is an emergency/experiment JSON override. Normally use the approved map in `backend/src/services/aiProviders/google/approvedLiveCoachConfiguration.ts`.

Enable `texttospeech.googleapis.com` and Vertex AI in project `outbound-494602` before deployment. Cloud Run uses `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com` for Google APIs and mounts the approved OpenAI key from Secret Manager for Luna; no mobile OAuth plist or TTS key is used. Keep `LIVE_COACH_PLANNER_ENABLED=false` until the data-boundary/privacy review and schema deployment are complete.

For local generation, establish ADC outside the repository:

```sh
gcloud auth application-default login
gcloud auth application-default set-quota-project outbound-494602
```

Never copy the generated ADC file, a service-account key, or an OAuth plist into this repository.

## Fixed Pack Inventory

Catalog `2026-09-08.1` adds `countdown.five` and `countdown.four`, bringing the active pack to 36 cues × 3 locales × 2 voices = 216 files.

The source of truth is `backend/resources/liveCoachAudio/catalog.v1.json`. Catalog `2026-09-01.1` contains 34 semantic cues:

| Group | Cue keys |
| --- | --- |
| Countdown | `countdown.three`, `countdown.two`, `countdown.one`, `countdown.go` |
| Workout control | `workout.pause`, `workout.resume`, `workout.segment_start`, `workout.complete` |
| Route and safety | `route.advisory`, `route.caution`, `route.wrong_way`, `route.rejoin`, `route.arrival` |
| Progress | `progress.one_third`, `progress.halfway`, `progress.two_thirds`, `progress.finish_soon`, `progress.steady` |
| Coaching fallback | `coach.early_settle`, `coach.ease_to_target`, `coach.lift_to_target`, `coach.smooth_pace`, `coach.rebuild_rhythm`, `coach.recovery_easy`, `coach.climb_by_effort`, `coach.crest_reset`, `coach.settle`, `coach.restore_rhythm`, `coach.rhythm_recovered`, `coach.strong_finish` |
| Challenges | `challenge.start`, `challenge.complete` |
| Availability and preview | `fallback.unavailable`, `voice.preview` |

Each cue has product-authored English, Spanish, and Simplified Chinese text. The complete pack is:

```text
34 cues × 3 locales × 2 active Google voices = 204 published WAV files
```

Catalog `2026-08-30.1` introduced eight purpose-built cues for early pacing, faster/slower target correction, pace instability, pace drift, recovery effort, climb entry, and crest recovery; `2026-09-01.1` retains them. It does not force these meanings through the older generic settle/restore scripts. Confirmations and workout controls still share an existing cue only where the script expresses the semantic event exactly. The fixed transcript must match the selected catalog entry exactly; see `docs/live-coaching-moments.md` for the semantic-to-audio map.

```text
34 cues × 2 enabled locales × 2 active Google voices = 136 active EN/ZH files
```

Spanish remains gated; its 68 files are published in the same manifest but are not offered by the server.

Print the catalog without an API call:

```sh
./scripts/generate-live-coach-audio.sh --list
```

## Pending Clear-Cue Catalog

Source catalog `2026-10-11.1` replaces vague pace/rhythm/posture scripts with clear actions and specific measured encouragement. The generation wrapper targets this version; production configuration remains on the previously published pack until listening review and signed publication are complete. Changed transcripts cannot reuse old audio solely by cue key: both clients require transcript agreement when playback supplies text. During rollout, changed fixed cues may remain silent until their reviewed recordings are available. Deploy the backend wording/prompt changes and release both clients before considering rollout complete.

## Generate And Review Audio

After ADC is configured:

```sh
./scripts/generate-live-coach-audio.sh --smoke
./scripts/generate-live-coach-audio.sh
```

`--smoke` generates only the English female `voice.preview` file. Full generation writes content-addressed WAV files and `review-manifest.json` under `backend/.local/live-coach-review/2026-10-11.1/`. The directory is gitignored. Reruns validate and reuse completed WAVs.

Fixed generation sends Google the exact transcript and selected voice, then validates the resulting 24 kHz mono PCM WAV before storage. The wrapper generates only `plainstride_warm_1` and `plainstride_clear_1` unless an explicit `--voice-profile` is supplied. It writes content-addressed assets and `review-manifest.json` under the gitignored review directory; reruns validate and reuse completed files, and provider/model/voice identity remains part of the content hash.

Generation does not approve or publish audio. Start the loopback-only review screen from `backend/`, listen to every file, and approve only exact, correctly pronounced, naturally paced output:

```sh
npm run live-coach:review-audio
```

Open `http://127.0.0.1:4173`. Listen to every file and approve only exact, correctly pronounced, naturally paced output. Rejections require a structured reason and can be regenerated selectively:

```sh
./scripts/generate-live-coach-audio.sh \
  --voice-profile plainstride_clear_1 \
  --locale es \
  --cue coach.strong_finish \
  --force

./scripts/generate-live-coach-audio.sh --rejected
```

The provider/model/voice route is part of the content hash, so Google audio cannot silently reuse an Alibaba rendition.

## Manifest Trust And Publication

The active signing key ID is `live-coach-audio-2026-v1`.

- The public P-256 PEM is committed in `ios/Outbound/SupportFiles/Info.plist` under `LiveCoachAudioManifestPublicKeys`.
- The private PEM is in Secret Manager as `outbound-live-coach-manifest-private-key` and must never enter source, logs, chat, or persistent Cloud Run environment values.
- iOS verifies the ES256 manifest signature and each WAV SHA-256 before replacing its last-known-good pack.

The prior fixed-only pilot was deliberately limited to English and Simplified Chinese:

- Pilot catalog: `2026-08-28.1-en-zh`
- Public bucket: `outbound-494602-live-coach-audio`
- Approved matrix: 26 cues × 2 locales × 6 voices = 312 WAV files
- Former active runtime subset: 26 cues × 2 locales × 2 enabled voices = 104 WAV files
- Server locale gate: `LIVE_COACH_ENABLED_LOCALES=en,zh-Hans`

The pilot and `2026-09-01.1` packs remain published as rollback artifacts but are no longer configured. Production uses the signed `2026-09-08.1` manifest: 36 cues × 3 locales × 2 voices = 216 assets, with 144 EN/ZH assets enabled. It carries forward the approved `2026-09-01.1` recordings and adds the twelve reviewed `countdown.five` and `countdown.four` variants. Existing approved files can be reused only when their cue transcript, locale, voice, provider/model route, and audio checksum still match.

For Spanish, `/v1/live-coach/config` reports `disabled`, the catalog omits the audio pack and voice/persona choices, and session creation is rejected. The 68 Spanish assets are signed and published, but enabling Spanish still requires explicit product approval and listening QA.

On 2026-08-30 the owner explicitly directed publication with bulk approval of all 204 generated entries. The manifest therefore records every entry as approved, but bulk approval is not evidence that every rendition received listening QA; do not treat this release as precedent for skipping the review screen.

Publication still requires an audio storage bucket and public HTTPS base URL. Follow `docs/backend-deploy.md` after approval.

Publish a successor only after every in-scope entry is approved:

```sh
cd backend
npm run live-coach:publish-audio -- \
  --review-manifest .local/live-coach-review/2026-09-08.1/review-manifest.json \
  --approved
```

Configure immutable HTTPS URLs with `LIVE_COACH_AUDIO_MANIFEST_URL` and `LIVE_COACH_AUDIO_ASSET_BASE_URL`, then set `LIVE_COACH_AUDIO_PACK_PUBLISHED=true`. Startup fails closed when the pack, URLs, enabled voices/locales, or provider route is incomplete.

After publication, activate the pack with the guarded wrapper from the repository root:

```sh
./scripts/redeploy-live-coach-voices.sh
```

The wrapper verifies the ES256 signature against the iOS public-key map, then checks the version, approval state, exact catalog transcripts, enabled locale/voice matrix, WAV metadata, and HTTPS asset URLs. It deploys with no traffic, checks the tagged candidate, and only then moves production traffic. Its defaults retain the production dynamic rollout, configured planner, founding/trial access, one warm instance, and 1.5-second provider deadline.

## Rollout Meaning

| Configuration | Behavior |
| --- | --- |
| `mode=fixed_only` | Every eligible runner uses reviewed, downloaded audio; no runtime Google TTS request. |
| `mode=dynamic`, `percent=0` | Provider/auth/config validation is armed, but every runner remains fixed-only. |
| `mode=dynamic`, `percent=N` | The deterministic cohort receives one configured start plan plus planned-cache/streaming Google TTS cues; everyone else uses the fixed pack. |

Use `fixed_only` for pack/cache/playback burn-in. Then arm the planner and `dynamic` at 0%, run a real Cloud Run/device first-audio benchmark, and explicitly set 100% only when the owner accepts the measured results. `founding_trial` grants the oldest 1,000 accounts permanently and gives later accounts three runs. Increment `LIVE_COACH_CONFIG_VERSION` only when a fresh cohort assignment is intended.

To stop runtime TTS cost immediately while keeping spoken guidance available, redeploy `fixed_only`. Use `disabled` only when server audio itself must be unavailable.

## Founding Access And Three-Run Trial

Production uses `LIVE_COACH_ACCESS_MODE=founding_trial`, a founding limit of 1,000 accounts, and a three-run trial for later accounts.

| Account | Dynamic access |
| --- | --- |
| Oldest 1,000 accounts | Durable `live_coach_dynamic` promotion entitlement with no expiration. |
| Later account with fewer than three consumed trials | Dynamic access for the current guided run. |
| Later account after three consumed trials | `entitlement_required`; reviewed fixed guidance remains available. |

A trial is consumed only after the first successful dynamic cue in that workout, then the rest of that workout remains uncapped. Canceled starts, Quiet guidance, safety-forced fixed sessions, expired sessions without a dynamic success, and provider failures do not consume a run.

The database-backed `paywall_enabled` control overrides trial enforcement. While the paywall is disabled, non-entitled accounts receive unlimited open-beta access without reserving or consuming trial runs, and existing founding or subscription entitlements retain their more specific access reason for diagnostics.

## Release Gate

Production dynamic coaching is enabled after the Google APIs, runtime IAM, schema, signed fallback pack, Gemini strict-JSON response, and streamed TTS first chunk were verified. The remaining product-quality gate is a representative real-device benchmark with provider-result/fallback telemetry visible; the on-device deadline must continue to speak exact progress instead of `progress.steady` when cloud audio misses 1.5 seconds.

Production retains pack `2026-09-08.1`; current service revision is recorded in `docs/ai-reliability.md`. All 216 two-voice assets are generated through Google, signed, uploaded, and exposed through immutable HTTPS URLs; the locale gate enables the 144 English/Simplified-Chinese assets and keeps the 72 Spanish assets unavailable. The remaining quality work is listening QA for the owner-bulk-approved base pack plus the representative real-device latency benchmark above.

## Planner Failure Diagnostics

- `live_coach_planning_fallback` records the operation, numeric HTTP status when available, and a bounded timeout/provider/validation category. It excludes provider bodies, runner context, and generated phrases. A successful audio stream does not prove planning succeeded; inspect `plannerStatus` too.
- The live planner uses low reasoning (GPT) or low thinking (Gemini) within its 45-second planning deadline. Array bounds stay in runtime validation because nested bounded arrays caused Gemini 3.8 Flash to reject the schema with HTTP 400.
- Verify the actual coaching planner with a synthetic selected workout before a model rollout; assistant-only JSON smoke checks do not exercise the coaching schema.

## Preplanning Before Start

- iOS starts preparation from the visible idle launch screen when a Run is selected. Selection, language, coach/voice, units, environment, and runner-model changes invalidate its request fingerprint; obsolete responses cannot replace the current selection.
- `POST /v1/live-coach/preparations` compiles current bounded context and immediately returns an account-owned preparation ID/status. `POST /preparations/:id/generate` holds an authenticated HTTP request open until generation completes. No detached Cloud Run task or process-local cache is required.
- Preparations are keyed by account, compiled context hash, coach/voice/contract, config, model, and prompt versions. They expire after 15 minutes; provider fallback entries expire after 30 seconds. Expired rows are removed on the next preparation for that account and during daily planning maintenance. Generation uses an atomic claim with a 90-second recovery lease.
- iOS sends `deferPlanning=true` at Start. The server recompiles context and reevaluates eligibility/safety, attaches a matching ready preparation, or immediately creates a deterministic fallback session. Preparation never reserves a trial run; session creation remains the reservation boundary.
- If generation is pending, iOS keeps the generation request open and fetches `GET /sessions/:sessionId` to adopt the ready plan. Attachment requires the same account and frozen session context hash; session-generation checks prevent results from attaching after another run starts. Audio caches remain keyed by the new plan hash.
- Existing clients that omit `deferPlanning` retain synchronous session planning. No Android compatibility layer or data migration is added.
- The configured planner generates applicable reactive moments plus every selected-workout instruction in the app language only. Progress, pause/resume, unselected challenges, and race-only moments outside a typed race retain deterministic fallback coverage. Existing trigger timing, pace thresholds, safety gates, and cadence bounds are preserved.
- Deploy backend/schema before distributing the matching iOS build: `./scripts/deploy-backend-gcloud.sh` pins and executes the schema job. This adds `LiveCoachPreparation` and an optional session reference; existing session rows require no reset.
