# Live Coach Audio Operations

Open this when generating or publishing live-coach audio, changing the Google TTS route or voice map, or changing rollout exposure. Open `docs/live-coach-data-boundaries.md` for the exact privacy boundary.

## Current Architecture

Live coaching uses Gemini once at workout start and Google Cloud Text-to-Speech for runtime exact-text cues, planned-audio prewarming, and reviewed fixed-pack generation:

1. At session start, the backend compiles bounded profile, survey, recent training, workout, route-summary, readiness, location, and weather context. Gemini returns a strict-JSON phase-aware phrase plan.
2. iOS keeps semantic detection and cooldowns local, selects a phrase ID from that plan, and sends bounded live state. For `progress`, the backend deterministically formats rounded distance, elapsed time, and pace.
3. Google TTS receives only the finalized sentence, selected voice, language, and 24 kHz PCM settings.
4. Google `streamingSynthesize` chunks are forwarded in a framed HTTP/2 response and played through `AVAudioEngine` as they arrive.
5. Generated plans prewarm up to eight likely WAV phrases in the background. The whole device request, including the wait for response metadata, is raced against a 1.5 second deadline. If cloud audio loses that race, iOS cancels it and immediately uses the planned cache, reviewed local pack, or session-pinned on-device system voice.

iOS keeps the streaming audio engine alive until the final PCM buffer reports `.dataPlayedBack`; buffer-consumption callbacks are not treated as audible completion because doing so can clip the end of stat announcements.

There is no TTS WebSocket and no LLM call in the live cue path. HTTP/2 is device-to-Plainstride and gRPC is Plainstride-to-Google. `live_guidance_audio_first_byte` measures the end-to-end product gate separately from response-metadata latency.

### Current Latency Evidence

On 2026-08-30, the former complete-WAV route measured 790–1,270 ms for direct warm synthesis, with a 1,017 ms median, before iPhone/Cloud Run transport. That evidence rejected the complete-WAV design; it is not evidence for the streaming implementation. Do not claim the new path meets the gate until a real iPhone records device-request-to-first-playable-audio below one second at representative percentiles. During live beta testing, six successful stream requests completed in 637–963 ms, and the owner approved increasing the device fallback threshold from 850 ms to 1.5 seconds so viable cloud streams are not cancelled prematurely.

For a real-device benchmark, install a DEBUG build against the candidate Cloud Run revision, start the run simulator, and trigger at least 30 uncached semantic cues across cold and warm connections. Capture `device_to_first_audio_ms` from the device console. This timer starts before the authenticated HTTP request and stops when the first PCM frame reaches iOS. Report median, p90, p95, cloud-audio success rate, planned-cache rate, and the fraction that crossed into the 1.5 second local fallback. Do not log transcripts, plan/context payloads, exact metrics, or identifiers.

On 2026-08-30 PDT, a synthetic smoke execution using the production container image and `outbound-api-runtime` identity measured 485 ms from the Cloud Run process starting `streamingSynthesize` to its first PCM chunk, with 111,360 audio bytes returned. The same execution received valid strict JSON from `gemini-3.1-pro-preview` in 4,198 ms. This verifies provider availability, runtime IAM, model access, and streaming audio, but it excludes iPhone transport and the live API route and is therefore not the end-to-end device result.

Later that day, a simulated Responsive session showed why request duration must be separated from fallback cause. Earlier streamed responses completed in 0.64–1.64 seconds, while the final two periodic stats calls returned metadata-only responses in 31 ms and 38 ms because the obsolete eight-cue quota rejected them before TTS. This was not a TTS timeout. Per-workout cue quotas have been removed: access is counted in eligible workout sessions, while semantic cooldowns and request-rate controls continue to govern cadence.

## Current Production Deployment

- Revision: `outbound-api-voicepack830`
- Image digest: `sha256:7de1a00889be61699c975215f8db2a05b94629d92088f176e990020701cbe4f1`
- Traffic: 100%
- Scaling: minimum 1 warm instance, maximum 3
- Audio mode/rollout: `dynamic`, 100%, config version `2`
- Access: `founding_trial`, first 1,000 accounts, three later trial runs
- Planner: enabled, `gemini-3.1-pro-preview`, Vertex `global`
- TTS: enabled, Chirp 3 HD through `us-texttospeech.googleapis.com`
- Locales/voices: English and Simplified Chinese; `plainstride_warm_1` and `plainstride_clear_1`
- Fixed pack: signed `2026-08-30.1` manifest; 204 two-voice assets are published, while the enabled EN/ZH subset uses 136
- Alibaba: disabled; its retained secret binding is inactive and remains available only for rollback

The runtime identity has `roles/aiplatform.user` and `roles/serviceusage.serviceUsageConsumer`. Google Cloud Text-to-Speech does not expose a project-level `roles/texttospeech.user` role; the enabled API, attached runtime ADC, and service-usage permission authorize synthesis.

There is no per-workout cue allowance. Once a workout has dynamic access, both coaching interventions and periodic distance/time/pace announcements remain eligible for the full session. If cloud or recorded audio is unavailable, iOS resolves and pins a same-language system voice matching the selected female/male product presentation at session start; it never substitutes the opposite presentation mid-session.

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
GEMINI_LIVE_COACH_PLANNER_MODEL=gemini-3.1-pro-preview
GEMINI_VERTEX_PROJECT_ID=outbound-494602
GEMINI_VERTEX_LOCATION=global
GEMINI_LIVE_COACH_PLANNER_DEADLINE_MILLISECONDS=20000
ALIBABA_AI_ENABLED=false
```

`GOOGLE_CLOUD_TTS_VOICE_MAP` is an emergency/experiment JSON override. Normally use the approved map in `backend/src/services/aiProviders/google/approvedLiveCoachConfiguration.ts`.

Enable `texttospeech.googleapis.com` and Vertex AI in project `outbound-494602` before deployment. Cloud Run uses `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com` for both; no mobile OAuth plist or TTS key is used. Keep `LIVE_COACH_PLANNER_ENABLED=false` until the data-boundary/privacy review and schema deployment are complete.

For local generation, establish ADC outside the repository:

```sh
gcloud auth application-default login
gcloud auth application-default set-quota-project outbound-494602
```

Never copy the generated ADC file, a service-account key, or an OAuth plist into this repository.

## Fixed Pack Inventory

The source of truth is `backend/resources/liveCoachAudio/catalog.v1.json`. Catalog `2026-08-30.1` contains 34 semantic cues:

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

Catalog `2026-08-30.1` adds eight purpose-built cues for early pacing, faster/slower target correction, pace instability, pace drift, recovery effort, climb entry, and crest recovery. It does not force these meanings through the older generic settle/restore scripts. Confirmations and workout controls still share an existing cue only where the script expresses the semantic event exactly. The fixed transcript must match the selected catalog entry exactly; see `docs/live-coaching-moments.md` for the semantic-to-audio map.

```text
34 cues × 2 enabled locales × 2 active Google voices = 136 active EN/ZH files
```

Spanish remains gated; its 68 files are published in the same manifest but are not offered by the server.

Print the catalog without an API call:

```sh
./scripts/generate-live-coach-audio.sh --list
```

## Generate And Review Audio

After ADC is configured:

```sh
./scripts/generate-live-coach-audio.sh --smoke
./scripts/generate-live-coach-audio.sh
```

`--smoke` generates only the English female `voice.preview` file. Full generation writes content-addressed WAV files and `review-manifest.json` under `backend/.local/live-coach-review/2026-08-30.1/`. The directory is gitignored. Reruns validate and reuse completed WAVs.

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

The pilot remains published as a rollback artifact but is no longer configured. Production uses the signed `2026-08-30.1` manifest: 34 cues × 3 locales × 2 voices = 204 assets, with 136 EN/ZH assets enabled. Existing approved files can be reused only when their cue transcript, locale, voice, provider/model route, and audio checksum still match.

For Spanish, `/v1/live-coach/config` reports `disabled`, the catalog omits the audio pack and voice/persona choices, and session creation is rejected. The 68 Spanish assets are signed and published, but enabling Spanish still requires explicit product approval and listening QA.

On 2026-08-30 the owner explicitly directed publication with bulk approval of all 204 generated entries. The manifest therefore records every entry as approved, but bulk approval is not evidence that every rendition received listening QA; do not treat this release as precedent for skipping the review screen.

Publication still requires an audio storage bucket and public HTTPS base URL. Follow `docs/backend-deploy.md` after approval.

Publish a successor only after every in-scope entry is approved:

```sh
cd backend
npm run live-coach:publish-audio -- \
  --review-manifest .local/live-coach-review/2026-08-30.1/review-manifest.json \
  --approved
```

Configure immutable HTTPS URLs with `LIVE_COACH_AUDIO_MANIFEST_URL` and `LIVE_COACH_AUDIO_ASSET_BASE_URL`, then set `LIVE_COACH_AUDIO_PACK_PUBLISHED=true`. Startup fails closed when the pack, URLs, enabled voices/locales, or provider route is incomplete.

After publication, activate the pack with the guarded wrapper from the repository root:

```sh
./scripts/redeploy-live-coach-voices.sh
```

The wrapper verifies the ES256 signature against the iOS public-key map, then checks the version, approval state, exact catalog transcripts, enabled locale/voice matrix, WAV metadata, and HTTPS asset URLs. It deploys with no traffic, checks the tagged candidate, and only then moves production traffic. Its defaults retain the production dynamic rollout, Gemini planner, founding/trial access, one warm instance, and 1.5-second provider deadline.

## Rollout Meaning

| Configuration | Behavior |
| --- | --- |
| `mode=fixed_only` | Every eligible runner uses reviewed, downloaded audio; no runtime Google TTS request. |
| `mode=dynamic`, `percent=0` | Provider/auth/config validation is armed, but every runner remains fixed-only. |
| `mode=dynamic`, `percent=N` | The deterministic cohort receives one Gemini start plan plus planned-cache/streaming Google TTS cues; everyone else uses the fixed pack. |

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

## Release Gate

Production dynamic coaching is enabled after the Google APIs, runtime IAM, schema, signed fallback pack, Gemini strict-JSON response, and streamed TTS first chunk were verified. The remaining product-quality gate is a representative real-device benchmark with provider-result/fallback telemetry visible; the on-device deadline must continue to speak exact progress instead of `progress.steady` when cloud audio misses 1.5 seconds.

Production now points at `2026-08-30.1`. All 204 two-voice assets are generated through Google, signed, uploaded, and exposed through immutable HTTPS URLs; the locale gate enables the 136 English/Simplified-Chinese assets and keeps the 68 Spanish assets unavailable. The remaining quality work is listening QA for the owner-bulk-approved pack plus the representative real-device latency benchmark above.
