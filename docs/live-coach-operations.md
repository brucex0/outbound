# Live Coach Audio Operations

Open this when selecting the Alibaba route, generating or publishing fixed audio, rotating the manifest key, or changing live-coach rollout exposure.

## Approved Alibaba Route

Plainstride uses Alibaba Model Studio's workspace-specific Singapore OpenAI-compatible endpoint. The approved model is the dated `qwen3-omni-flash-2025-12-01` snapshot. It fits short, cost-sensitive coaching output, supports `en`, `es`, and Mandarin audio, and avoids the moving behavior of an unversioned model alias.

The backend owns the following provider map. The iOS app and public APIs see only the Plainstride profile ID and localized product name.

| Product voice | Product style | Alibaba voice | Presentation | `en` | `es` | `zh-Hans` |
| --- | --- | --- | --- | --- | --- | --- |
| `plainstride_warm_1` | Warm | `Cherry` | Female | Yes | Yes | Yes |
| `plainstride_gentle_1` | Gentle | `Serena` | Female | Yes | Yes | Yes |
| `plainstride_composed_1` | Composed | `Maia` | Female | Yes | Yes | Yes |
| `plainstride_clear_1` | Bright | `Ethan` | Male | Yes | Yes | Yes |
| `plainstride_driven_1` | Driven | `Ryan` | Male | Yes | Yes | Yes |
| `plainstride_easygoing_1` | Easygoing | `Aiden` | Male | Yes | Yes | Yes |

The same provider voice is deliberately used across the three locales so a runner's selected audible identity does not change when the app language changes. Alibaba's official snapshot-specific list marks all six voices as supporting Chinese, English, and Spanish.

Recheck the [Qwen-Omni model documentation](https://www.alibabacloud.com/help/en/model-studio/qwen-omni) and [official Omni voice list](https://www.alibabacloud.com/help/en/model-studio/omni-voice-list) before changing the pinned snapshot or map.

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

Use a Singapore API key and the workspace-specific compatible endpoint. Do not pass the key as a command argument or commit it to dotenv files.

```sh
export DASHSCOPE_API_KEY='REDACTED'
export ALIBABA_AI_BASE_URL='https://WORKSPACE_ID.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1'
./scripts/generate-live-coach-audio.sh
```

The script downloads content-addressed WAVs to `backend/.local/live-coach-review/2026-08-28.1/` and writes `review-manifest.json`. The directory is gitignored. A rerun validates and reuses existing WAVs, so an interrupted 468-file generation safely resumes without paying for completed assets again.

Generation does not approve or publish audio. Listen to every file and set `approved` to `true` only for an exact, correctly pronounced, naturally paced rendition. Regenerate any rejected entry before publication.

## Manifest Trust And Publication

The active key ID is `live-coach-audio-2026-v1`.

- The public P-256 PEM is committed under `LiveCoachAudioManifestPublicKeys` in `ios/Outbound/SupportFiles/Info.plist`.
- The private PEM is stored in Google Secret Manager as `outbound-live-coach-manifest-private-key`; it must never be placed in source, persistent Cloud Run environment values, logs, or chat.
- The publisher signs the provider-neutral manifest with ES256. iOS verifies the signature and each WAV checksum before replacing its last-known-good pack.

Publication still requires an audio storage bucket and public HTTPS base URL. Follow `docs/backend-deploy.md` after human review.

## Rollout Meaning

The two rollout controls answer different questions:

| Configuration | What happens |
| --- | --- |
| `mode=fixed_only` | Every eligible runner uses reviewed, pre-generated audio. The backend makes no runtime Alibaba request. Use this to validate download, signature, caching, playback, rollback, and analytics. |
| `mode=dynamic`, `percent=0` | The dynamic provider route, key, model, mappings, and kill switch must all pass startup validation, but no user is assigned dynamic generation. Effective behavior remains `fixed_only`. |
| `mode=dynamic`, `percent=N` | A deterministic `N%` cohort receives dynamic cues; everyone else remains `fixed_only`. Assignment is stable for a config version. |

“Begin dynamic rollout from 0%” therefore means arm and validate the production dynamic path without exposing a runner or incurring runtime generation cost. After health and rollback checks, raise the percentage in small steps such as 1, 5, 25, and 100. Increment `LIVE_COACH_CONFIG_VERSION` only when a fresh cohort assignment is intended.

Never skip the fixed-only burn-in. If dynamic latency, cost, policy, or provider health degrades, redeploy `fixed_only` to stop new Alibaba calls while keeping reviewed audio available.

## Current Release Gate

Do not enable `fixed_only` until all 468 assets have been generated, listened to, approved, signed, uploaded, and exposed through immutable HTTPS URLs. Do not set global mode to `dynamic`, even at 0%, until the Alibaba API key is in Secret Manager and startup validation passes with the workspace endpoint, approved model, complete six-voice map, and published pack.
