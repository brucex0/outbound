# Live Coach Audio Operations

Open this when generating or publishing live-coach audio, changing the Google TTS route or voice map, or changing rollout exposure. Open `docs/live-coach-data-boundaries.md` for the exact privacy boundary.

## Current Architecture

Live coaching uses Google Cloud Text-to-Speech for both runtime exact-text cues and reviewed fixed-pack generation. The live path is:

1. iOS detects a semantic moment and sends bounded live state to Plainstride.
2. The backend selects a product-authored exact sentence. For `progress`, it deterministically formats rounded distance, elapsed time, and pace.
3. Google TTS receives only the exact sentence, selected voice, language, and 24 kHz `LINEAR16` settings.
4. The backend validates the complete mono PCM WAV and returns it as Base64 JSON.
5. iOS plays it if it is still timely; otherwise it uses the reviewed fixed pack.

There is no live-coach LLM call and no end-to-end audio stream or TTS WebSocket in this version. A cue response contains a complete WAV. The existing coarse `live_guidance_provider_result` latency buckets measure whether this is usable; do not assume the route is under one second until a deployed device-to-server-to-device benchmark proves it.

### Current Latency Evidence

On 2026-08-30, five direct warm-client requests from the development Mac to the regional Google endpoint for the same eight-word preview sentence completed in 790–1,270 ms, with a 1,017 ms median. A separate request through the implemented adapter returned the exact sentence, a 3,480 ms WAV, and 167,084 audio bytes in 1,031 ms. These figures exclude iPhone-to-Cloud-Run and Cloud-Run-to-iPhone time, so this full-WAV route does **not** currently satisfy the sub-second end-to-end product gate. Keep dynamic rollout at zero until a faster delivery design or provider proves the actual device round trip.

## Approved Google Route And Voices

- API: Google Cloud Text-to-Speech
- Model family: Chirp 3 HD
- Regional endpoint: `us-texttospeech.googleapis.com`
- Authentication: Application Default Credentials from the Cloud Run runtime service account
- Audio: WAV, PCM signed 16-bit little-endian, 24 kHz, mono

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
ALIBABA_AI_ENABLED=false
```

`GOOGLE_CLOUD_TTS_VOICE_MAP` is an emergency/experiment JSON override. Normally use the approved map in `backend/src/services/aiProviders/google/approvedLiveCoachConfiguration.ts`.

Enable `texttospeech.googleapis.com` in project `outbound-494602` before deployment. Cloud Run uses `outbound-api-runtime@outbound-494602.iam.gserviceaccount.com`; no TTS secret binding is required.

For local generation, establish ADC outside the repository:

```sh
gcloud auth application-default login
gcloud auth application-default set-quota-project outbound-494602
```

Never copy the generated ADC file, a service-account key, or an OAuth plist into this repository.

## Fixed Pack Inventory

The source is `backend/resources/liveCoachAudio/catalog.v1.json`. Catalog `2026-08-30.1` contains 26 semantic cues in English, Spanish, and Simplified Chinese.

```text
26 cues × 3 locales × 2 voices = 156 reviewed WAV files
```

The initial English/Simplified-Chinese release requires:

```text
26 cues × 2 locales × 2 voices = 104 reviewed WAV files
```

The English/Chinese published manifest version is `2026-08-30.1-en-zh`. Spanish remains gated until its 52 files are reviewed and published in a complete successor manifest.

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

Generation does not approve or publish audio. Start the loopback-only review screen from `backend/`:

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

Publish only after every in-scope entry is approved:

```sh
cd backend
npm run live-coach:publish-audio -- \
  --review-manifest .local/live-coach-review/2026-08-30.1/review-manifest.json \
  --approved
```

Configure immutable HTTPS URLs with `LIVE_COACH_AUDIO_MANIFEST_URL` and `LIVE_COACH_AUDIO_ASSET_BASE_URL`, then set `LIVE_COACH_AUDIO_PACK_PUBLISHED=true`. Startup fails closed when the pack, URLs, enabled voices/locales, or provider route is incomplete.

## Rollout Meaning

| Configuration | Behavior |
| --- | --- |
| `mode=fixed_only` | Every eligible runner uses reviewed, downloaded audio; no runtime Google TTS request. |
| `mode=dynamic`, `percent=0` | Provider/auth/config validation is armed, but every runner remains fixed-only. |
| `mode=dynamic`, `percent=N` | The deterministic cohort receives exact-text Google TTS cues; everyone else uses the fixed pack. |

Use `fixed_only` for the first pack/cache/playback burn-in. Then arm `dynamic` at 0%, run a real Cloud Run/device latency benchmark, and increase 1, 5, 25, then 100 only if success/fallback and latency buckets meet the product gate. Increment `LIVE_COACH_CONFIG_VERSION` only when a fresh cohort assignment is intended.

To stop runtime TTS cost immediately while keeping spoken guidance available, redeploy `fixed_only`. Use `disabled` only when server audio itself must be unavailable.

## Founding Access And Three-Run Trial

Production uses `LIVE_COACH_ACCESS_MODE=founding_trial`, a founding limit of 1,000 accounts, and a three-run trial for later accounts.

| Account | Dynamic access |
| --- | --- |
| Oldest 1,000 accounts | Durable `live_coach_dynamic` promotion entitlement with no expiration. |
| Later account with fewer than three consumed trials | Dynamic access for the current guided run. |
| Later account after three consumed trials | `entitlement_required`; reviewed fixed guidance remains available. |

A trial is consumed only after the first successful dynamic cue. Canceled starts, Quiet guidance, safety-forced fixed sessions, expired sessions without a dynamic success, and provider failures do not consume a run.

## Release Gate

Do not enable the English/Chinese fixed pack until all 104 files are generated, reviewed, signed, uploaded, and exposed through immutable HTTPS URLs. Do not enable a dynamic cohort until:

- `texttospeech.googleapis.com` is enabled;
- the runtime service account can synthesize speech through the regional endpoint;
- the published two-voice fixed pack passes on-device fallback checks;
- a real device-to-Cloud-Run-to-device benchmark shows acceptable end-to-end latency;
- provider-result success, fallback, and latency buckets are visible.
