# Live Coach Audio Operations

Open this when selecting the Alibaba route, generating or publishing fixed audio, rotating the manifest key, or changing live-coach rollout exposure.

## Approved Alibaba Route

Plainstride uses two Alibaba Model Studio APIs in the same Singapore workspace. Dynamic cues retain the dated `qwen3-omni-flash-2025-12-01` conversational snapshot because they require the provider to write and speak a response. Fixed assets use the dedicated non-real-time `qwen3-tts-instruct-flash-2026-01-26` snapshot so the product can supply explicit situation, pacing, emphasis, tone, and voice-style direction while keeping the authored transcript exact. Both are pinned to avoid moving alias behavior.

The configured workspace is `ws-i638drcm5lthrc29` (account `1093525`). Dynamic cues use `https://ws-i638drcm5lthrc29.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1`; fixed TTS uses the same host at `/api/v1`. Both the deploy and local generation scripts use these endpoints by default. Cloud Run and authenticated local generation are configured to share the Secret Manager entry `outbound-alibaba-ai-api-key`; the credential value is not stored in the repository.

The backend owns the following provider map. The iOS app and public APIs see the Plainstride profile ID, stable human product name, style description, and female/male presentation; provider mapping remains backend-owned.

| Product voice | Product style | Alibaba voice | Presentation | `en` | `es` | `zh-Hans` |
| --- | --- | --- | --- | --- | --- | --- |
| `plainstride_warm_1` | Warm | `Cherry` | Female | Yes | Yes | Yes |
| `plainstride_gentle_1` | Gentle | `Serena` | Female | Yes | Yes | Yes |
| `plainstride_composed_1` | Composed | `Maia` | Female | Yes | Yes | Yes |
| `plainstride_clear_1` | Bright | `Ethan` | Male | Yes | Yes | Yes |
| `plainstride_driven_1` | Driven | `Moon` | Male | Yes | Yes | Yes |
| `plainstride_easygoing_1` | Easygoing | `Kai` | Male | Yes | Yes | Yes |

The same provider voice is deliberately used across the three locales so a runner's selected audible identity does not change when the app language changes. Alibaba's instruction-capable non-real-time voice list marks all six voices as supporting Chinese, English, and Spanish. `Ryan` and `Aiden` were replaced because the dedicated Instruct snapshot does not support them.

Recheck the [Qwen-Omni model documentation](https://www.alibabacloud.com/help/en/model-studio/qwen-omni), [Qwen TTS API](https://www.alibabacloud.com/help/en/model-studio/qwen-tts-api), and [Qwen TTS voice list](https://www.alibabacloud.com/help/en/model-studio/qwen-tts-voice-list) before changing either pinned snapshot or the map.

## Fixed Pack Inventory

The source of truth is `backend/resources/liveCoachAudio/catalog.v1.json`. Catalog `2026-08-28.1` contains 26 semantic cues:

| Group | Cue keys |
| --- | --- |
| Countdown | `countdown.three`, `countdown.two`, `countdown.one`, `countdown.go` |
| Workout control | `workout.pause`, `workout.resume`, `workout.segment_start`, `workout.complete` |
| Route and safety | `route.advisory`, `route.caution`, `route.wrong_way`, `route.rejoin`, `route.arrival` |
| Progress | `progress.one_third`, `progress.halfway`, `progress.two_thirds`, `progress.finish_soon`, `progress.steady` |
| Coaching fallback | `coach.settle`, `coach.restore_rhythm`, `coach.rhythm_recovered`, `coach.strong_finish` |
| Challenges | `challenge.start`, `challenge.complete` |
| Availability and preview | `fallback.unavailable`, `voice.preview` |

Each cue has product-authored English, Spanish, and Simplified Chinese text. The complete pack is:

```text
26 cues × 3 locales × 6 voices = 468 reviewed WAV files
```

Print every key and all three scripts without making an API call:

```sh
./scripts/generate-live-coach-audio.sh --list
```

## Generate And Download Review Audio

The local script first uses `ALIBABA_AI_API_KEY` or `DASHSCOPE_API_KEY`. If neither is set, it reads `outbound-alibaba-ai-api-key` from project `outbound-494602` using the configured gcloud account. The approved workspace URL is already the default.

```sh
./scripts/generate-live-coach-audio.sh --smoke
./scripts/generate-live-coach-audio.sh
```

`--smoke` generates only the English `voice.preview` cue with `plainstride_warm_1` into `backend/.local/live-coach-smoke/`. Use it after credential or endpoint changes before starting the complete pack.

Fixed generation sends the exact transcript separately from an English delivery instruction. The instruction includes the semantic situation, cue-specific pacing and tone direction, the selected product voice style, outdoor-listening context, and checksum-matched rejection feedback. Alibaba returns a short-lived audio URL; the adapter downloads and validates the resulting 24 kHz mono PCM WAV before storage. Dynamic Omni responses continue to use Base64-encoded audio chunks that the adapter wraps in a standard WAV container.

The script downloads content-addressed WAVs to `backend/.local/live-coach-review/2026-08-28.1/` and writes `review-manifest.json`. The directory is gitignored. Each uncached asset gets up to three attempts when Alibaba times out, is unavailable, or returns invalid output. A rerun validates and reuses existing WAVs, so an interrupted 468-file generation safely resumes without paying for completed assets again. The content hash includes the fixed TTS model, so a model change cannot silently reuse an older model's rendition.

Generation does not approve or publish audio. Listen to every file and set `approved` to `true` only for an exact, correctly pronounced, naturally paced rendition. Regenerate any rejected entry before publication.

Run the loopback-only review screen from `backend/`:

```sh
npm run live-coach:review-audio
```

Open `http://127.0.0.1:4173`. The screen pairs each hashed WAV with its cue, locale, product voice, and exact transcript. Playback must finish before **Approve** or **Reject** is enabled. A rejection also requires a structured reason—such as pronunciation, speed, pacing, tone, emphasis, artifact, or transcript mismatch—and accepts a detailed reviewer note. Use Space to play or pause, A to approve, R to reject, and the arrow keys to navigate. Progress and rejection feedback are written atomically to the gitignored `review-manifest.json` and `review-progress.json`; publication remains blocked while any manifest entry is unapproved.

Regenerate a rejected rendition without replacing the rest of the completed manifest:

```sh
./scripts/generate-live-coach-audio.sh \
  --voice-profile plainstride_clear_1 \
  --locale es \
  --cue coach.strong_finish \
  --force
```

The targeted run safely replaces only that manifest entry. When its current checksum has saved rejection feedback, the generator automatically adds the category-specific correction and reviewer detail to the fixed-text instructions. Its new audio checksum resets approval, so restart the review screen and listen to the replacement before publishing.

Regenerate every currently rejected rendition in one run:

```sh
./scripts/generate-live-coach-audio.sh --rejected
```

`--rejected` implies `--force`, preserves every non-rejected manifest entry, and applies saved checksum-matched rejection feedback. It can be combined with `--voice-profile`, `--locale`, or `--cue` to narrow the rejected set.

## Manifest Trust And Publication

The active key ID is `live-coach-audio-2026-v1`.

- The public P-256 PEM is committed under `LiveCoachAudioManifestPublicKeys` in `ios/Outbound/SupportFiles/Info.plist`.
- The private PEM is stored in Google Secret Manager as `outbound-live-coach-manifest-private-key`; it must never be placed in source, persistent Cloud Run environment values, logs, or chat.
- The publisher signs the provider-neutral manifest with ES256. iOS verifies the signature and each WAV checksum before replacing its last-known-good pack.

The initial fixed-only pilot is deliberately limited to English and Simplified Chinese:

- Pilot catalog: `2026-08-28.1-en-zh`
- Public bucket: `outbound-494602-live-coach-audio`
- Approved matrix: 26 cues × 2 locales × 6 voices = 312 WAV files
- Server locale gate: `LIVE_COACH_ENABLED_LOCALES=en,zh-Hans`

For Spanish, `/v1/live-coach/config` reports `disabled`, the catalog omits the audio pack and voice/persona choices, and session creation is rejected. The existing `audio_mode` and `access_reason` analytics fields therefore record the locale gate without adding a separate event or collecting locale as a new analytics property. Do not add Spanish to the allowlist until all 156 current Spanish assets are reviewed, approved, signed, and published in a complete successor catalog.

Publication still requires an audio storage bucket and public HTTPS base URL. Follow `docs/backend-deploy.md` after human review.

When the approved EN/ZH pack is already published and only the backend voice catalog or display metadata changed, redeploy it with:

```sh
./scripts/redeploy-live-coach-voices.sh
```

The wrapper verifies the published manifest, preserves the `fixed_only` EN/ZH pilot and 0% dynamic rollout, delegates the build and Cloud Run deployment to `deploy-backend-gcloud.sh`, and checks service health. Use the general backend deploy script directly for an intentional rollout-mode, locale, catalog-version, or asset-location change.

## Rollout Meaning

The two rollout controls answer different questions:

| Configuration | What happens |
| --- | --- |
| `mode=fixed_only` | Every eligible runner uses reviewed, pre-generated audio. The backend makes no runtime Alibaba request. Use this to validate download, signature, caching, playback, rollback, and analytics. |
| `mode=dynamic`, `percent=0` | The dynamic provider route, key, model, mappings, and kill switch must all pass startup validation, but no user is assigned dynamic generation. Effective behavior remains `fixed_only`. |
| `mode=dynamic`, `percent=N` | A deterministic `N%` cohort receives dynamic cues; everyone else remains `fixed_only`. Assignment is stable for a config version. |

“Begin dynamic rollout from 0%” therefore means arm and validate the production dynamic path without exposing a runner or incurring runtime generation cost. After health and rollback checks, raise the percentage in small steps such as 1, 5, 25, and 100. Increment `LIVE_COACH_CONFIG_VERSION` only when a fresh cohort assignment is intended.

The iOS progress director sends periodic `progress` moments through the same dynamic route so generated cues can speak the currently available elapsed time, distance, and pace. Alibaba splits one Base64 audio value across SSE events; the backend must concatenate those strings before decoding the complete PCM payload. Decoding each event independently corrupts chunk boundaries and forces every otherwise-valid dynamic cue to the fixed fallback.

Never skip the fixed-only burn-in. If dynamic latency, cost, policy, or provider health degrades, redeploy `fixed_only` to stop new Alibaba calls while keeping reviewed audio available.

## Founding Access And Three-Run Trial

Production uses `LIVE_COACH_ACCESS_MODE=founding_trial` with a founding limit of 1,000 accounts and a three-run trial for later accounts.

| Account | Dynamic access |
| --- | --- |
| One of the oldest 1,000 accounts | A durable `live_coach_dynamic` promotion entitlement with no expiration. |
| Later account with fewer than three consumed trials | Dynamic access for the current guided run; analytics reports the existing bounded `open_beta` reason for compatibility with shipped clients. |
| Later account after three consumed trials | Dynamic generation is unavailable with `entitlement_required`; fixed guidance remains available and no in-run paywall appears. |

A trial reservation is created only for a session that is otherwise eligible for dynamic coaching. It becomes consumed when that session receives its first successful dynamic cue. Canceled starts, Quiet guidance, safety-forced fixed sessions, expired sessions with no dynamic success, and provider failures release the reservation and do not consume a trial. Concurrent sessions cannot reserve past the configured limit. The first-1,000 promotion is persisted in `FeatureEntitlement`; lifetime trial counters use `FeatureUsagePeriod` key `three_run_trial_v1`.

Use unlimited `open_beta` only as a deliberate temporary or development override. Do not switch to `subscription_required` until the verified StoreKit/server entitlement flow and compatible client paywall are ready.

## Current Release Gate

For the EN/ZH pilot, do not enable `fixed_only` until all 312 in-scope assets have been generated, approved, signed, uploaded, exposed through immutable HTTPS URLs, and protected by the server locale gate. A complete three-locale release still requires all 468 assets. Do not set global mode to `dynamic`, even at 0%, until the Alibaba API key is in Secret Manager and startup validation passes with the workspace endpoint, approved model, complete six-voice map, and published pack.
