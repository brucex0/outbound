# Live Cue Usefulness Review

Open this when editing spoken scripts, fixed fallback mappings, or recorded packs. Canonical scripts are in `backend/resources/liveCoachAudio/catalog.v1.json`; this document records the semantic review, not a second transcript catalog.

## Acceptance Rules

- A correction states the measured event and one concrete next action.
- A confirmation names the measured behavior to preserve. A progress update may simply report a useful fact.
- Instructions follow the actual workout phase and supplied target. Missing targets do not become invented prescriptions.
- Do not infer posture, breathing, fatigue, or intent from speed. Optional self-check instructions must sound like suggestions, not detected faults.
- No unexplained rhythm, composure, posture, or motivational filler. Correct audio must match the displayed sentence, selected voice, and language.
- Editing source prose is insufficient: regenerate changed recordings, review them, and verify actual asset lookup and playback. Older downloaded packs must not mask current app-bundled recordings.

## Fixed Cue Review — 2026-10-22

| Cue | Required evidence/purpose | Decision |
| --- | --- | --- |
| `countdown.five` | Five-second boundary countdown | Keep exact beat |
| `countdown.four` | Four-second boundary countdown | Keep exact beat |
| `countdown.three` | Three seconds to start/boundary | Keep exact beat |
| `countdown.two` | Two seconds to start/boundary | Keep exact beat |
| `countdown.one` | One second to start/boundary | Keep exact beat |
| `countdown.go` | Activity start | Keep exact command |
| `workout.pause` | Recorder actually paused | Keep state confirmation |
| `workout.resume` | Recorder actually resumed | Keep state confirmation |
| `workout.segment_start` | Actual workout boundary | Replace vague settling/pressing with prescribed-effort adjustment |
| `workout.complete` | Workout completion | Keep completion and gradual easing |
| `route.advisory` | Route update | Keep safe map-check action |
| `route.off_route` | Measured deviation from selected route | State deviation and safe return to highlighted line |
| `route.caution` | Route caution | Keep slowing/map-check action |
| `route.wrong_way` | Wrong-way evidence | Keep uncertainty and map-check action |
| `route.rejoin` | Rejoined selected route | Keep measured confirmation |
| `route.arrival` | End of selected route | Keep arrival fact |
| `progress.one_third` | One third of goal reached | Remove filler; report fraction |
| `progress.halfway` | Half of goal reached | Remove filler; report fraction |
| `progress.two_thirds` | Two thirds of goal reached | Remove filler; report fraction |
| `progress.finish_soon` | Near-goal milestone | Replace composure filler with controlled finish |
| `progress.steady` | Validated target lock | Name target lock; do not use for generic progress |
| `coach.early_settle` | Opening pace exceeds supplied target | Name deviation and gradual correction |
| `coach.ease_to_target` | Faster than supplied target | Name deviation and gradual return |
| `coach.lift_to_target` | Slower than supplied target | Name deviation and gradual increase |
| `coach.smooth_pace` | Reliable shift outside supplied target | Name shift and target-directed adjustment |
| `coach.rebuild_rhythm` | Sustained slowing below target | Name deviation; conditional gradual return |
| `coach.recovery_easy` | Warmup/recovery/cooldown faster than prescribed | Name easy-segment deviation and conversational-effort action |
| `coach.climb_by_effort` | Sustained climb | Name climb and shorter-step/pace action |
| `coach.crest_reset` | Climb easing | Name terrain change and gradual rebuild |
| `coach.settle` | Current Android independent acceleration key | Replace generic effort sentence with explicit acceleration cue |
| `coach.restore_rhythm` | Current Android independent slowdown key | Replace shoulder/rhythm advice with conditional return after slowing |
| `coach.rhythm_recovered` | Measured target correction | Name correction and hold before readjusting |
| `coach.strong_finish` | Finish opportunity | Name finish; conditional gradual build, no sprint command |
| `challenge.start` | User-selected challenge begins | Name challenge and controlled gradual increase |
| `challenge.complete` | Selected challenge ends | Name completion and return to preceding pace |
| `fallback.unavailable` | Coaching unavailable | Report availability; no invented effort advice |
| `voice.preview` | User previews a voice | Explain voice purpose; remove unearned praise |
| `race.start_restraint` | Race opening, without assumed overspeed | Separate controlled-start instruction from target deviation |
| `coach.speed_increase` | Stable trusted speed increased sharply | Explicit acceleration plus steady/gradual action |
| `coach.speed_decrease` | Stable running speed dropped sharply | Explicit slowdown; return conditional on continuing |

## Other Spoken Paths

- Authored reactive variants use the same specific scripts; vague transition and challenge alternatives were removed.
- Planner prompt `2026-10-22.4` requires an observed deviation plus action for corrections, and an identified measured behavior for confirmations. Phase, target, safety, and private-data constraints remain.
- Spanish/Chinese selected-workout fallback instructions now state the supplied RPE range instead of a generic segment instruction. Existing purpose-built half-marathon instructions remain.
- Phase-based execution instructions and cadence introduction were reviewed: they explain intended effort, recovery, or how to follow beats. Optional breathing/tension checks remain suggestions; no unmeasured fault is claimed.
- Route-event display/speech strings and workout-completion text now match their exact fixed recordings; the off-route event has its own cue instead of borrowing a generic caution.
- iOS goal announcements remove filler such as “stay tall,” “keep stacking it,” and “stay composed.” Distance/time facts and numerical summaries remain; changed strings are localized in EN/ES/ZH.
- Generic progress without measured content remains silent instead of borrowing a target-lock recording. Measured progress still uses the existing exact-text cloud route and preferred local text.

## Recording And Verification Status

- Catalog `2026-10-22.1` contains 40 cues in three locales and two product voices (240 entries). Unchanged published assets may retain approval only when script, voice, language, route, and checksum agree.
- Verification: backend build and 297 focused contract checks passed; 65 focused iOS cases passed against the approved app bundle, including actual WAV selection, all locale/voice fallback mappings, recorder ramps, and unreviewed-pack rejection. All 240 entries also passed native AVAudioPlayer preparation; the six locale/voice cases passed again after moving decoder preparation off the main actor, with no runtime warnings. Android live-coach Kotlin compilation passed.
- The signed pack is published at its immutable `live-coach/2026-10-22.1/manifest.json` URL. All 228 unique public WAVs passed download, SHA-256, 24 kHz mono PCM, and duration checks. The iPhone build passed, all 240 packaged entries matched their checksums, and installation on Bruce main succeeded. After unlocking and normal launch, the device logged `Speed warning audio prepared ready=2 expected=2`. New-cue physical audibility remains unverified.
- The owner-approved production rollout passed candidate and production health checks; revision and immutable image are recorded in `docs/backend-deploy.md`.
- On 2026-10-22, the owner explicitly approved all 240 entries without checking them. Bulk approval is recorded; it does not establish per-recording listening QA. WAV format/checksum checks and code-level text review do not establish pronunciation or natural delivery.
- Use the focused commands in `docs/build-test-device.md`. Sensor replays and playback spies verify selection and bytes; physical-device listening verifies audibility and usefulness.

## Review And Export

The approved pack is bundled under `ios/Outbound/Outbound/LiveCoachAudio/` and published at the immutable URL above. During generation, the gitignored review manifest and assets are retained under `backend/.local/live-coach-cue-review/complete/` in the working checkout. Review changed recordings before publication:

```sh
cd backend
npm run live-coach:review-audio -- --review-manifest .local/live-coach-cue-review/complete/review-manifest.json --port 4176
```

After approval, export the exact approved bytes into the app:

```sh
node scripts/export-bundled-live-coach-audio.mjs --review-manifest .local/live-coach-cue-review/complete/review-manifest.json
```

The exporter refuses unapproved entries, verifies each WAV/checksum/duration, and writes a selected-voice/locale bundle. `--unreviewed-test-fixture` stages assets for regression tests while preserving false approval flags; production playback rejects that manifest. Do not release that fixture. New recordings still need listening approval; unchanged signed recordings retain their existing approval.

- Android current fallback resources and race-start/halfway mappings are aligned with this shared catalog. Its detector and playback policy are unchanged.
