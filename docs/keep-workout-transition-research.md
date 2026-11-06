# Keep Planned Workout Transition And Routine Comparison

Device probe: 2026-11-05. Open for the observed warm-up start/player/stop flow and comparison with Plainstride’s current iOS routine implementation. [Earlier plan research](keep-device-research.md) covers calendar structure; [Sport and Me](keep-sport-me-research.md) covers recording controls.

## What was actually exercised

- Returned the full calendar to today, opened the scheduled warm-up row, then tapped GO on its course-detail page.
- GO successfully entered an active full-screen video workout. Inspected movement progression, settings, movement help, pause controls and Stop confirmation.
- **Finish/main-run handoff and stretch playback are not yet verified.** Stop explicitly asks to end training **and save a record**, with Cancel / End Training. No discard option is visible at that boundary. The session was left paused at this confirmation pending Bruce’s answer about saving the research session.
- No permission or setting was changed, no real exercise was performed, and the displayed energy estimate is not a measurement of performed exercise. Playback ran to approximately 4:10 while controls were explored.
- Several pause clicks initially failed to produce a paused state through Mirroring. A slightly lower hit position succeeded, revealing Stop and Resume. Treat failed automation taps as a probe limitation, not a confirmed app defect.
- UI screenshots cannot verify audio quality, coaching wording, ducking, haptics or scientific effectiveness. None of those are claimed here.

## Keep: observed transition and player

1. **Calendar → course detail.** The warm-up opens a generic course detail with hero, membership label, difficulty, five-minute duration, calorie range, movement list, equipment and training-mode actions.
2. **GO → active video player.** Numbered movement/title and a thin overall progress bar sit above the trainer video; the bottom panel shows interval timing, elapsed time, an accumulating numerical metric, previous, pause and next controls. The last metric was not labeled clearly enough to identify conclusively.
3. **Movement progression.** The inspected warm-up contains 11 movements, starting with alternating knee-hug hip circles, hip circles and arm swings. Later visible examples include dynamic hip/leg movements, alternating lunge/side-bend, and high-knee work. Intervals include 20 and 30 seconds.
4. **Movement teaching.** The title’s explanation action opens a separate sheet with a demonstration video plus Steps, Breathing, Movement Feeling, Common Mistakes and Corrections; a Detailed Demonstration heading is further down. These are observed teaching categories, not independently endorsed exercise prescriptions.
5. **Settings.** Separate music and voice-guidance volume sliders, headset control, group exercise, background training and screen-lock controls are present. Existing group/background switches appeared enabled; no switches were changed. Background-training copy promises continued training in background; that behavior was not exercised.
6. **Social overlays.** Floating peer/check-in comments appear across the video, with “How does it feel?” and live-exercise controls. They add activity/social presence but compete visually with movement demonstration.
7. **Pause → Stop / Resume.** Successful pause replaces previous/pause/next with red Stop and green Resume.
8. **Stop → save confirmation.** Dialog explicitly couples ending with saving; no discard was available on that screen. No automatic warm-up → run transition has been observed.

## Plainstride: current source-backed behavior

This comparison uses the checked-in source and focused docs, **not a new device run of Plainstride**. Android layout has documented differences; do not assume iOS runtime parity from shared catalog content.

| Dimension | Keep observed | Plainstride current source/docs | Opportunity |
| --- | --- | --- | --- |
| Entry | Warm-up is a scheduled course, visible beside the main run and stretch | Today’s Stretch action opens generic routine selection; Before run is available there | Add a contextual Warm up action beside the planned run, preselecting a suitable dynamic routine |
| Returning to run | Not yet verified; inspected warm-up is its own course | Today host only dismisses `StretchSessionView`; completion offers Done | Add explicit warm-up-complete outcome and Start planned run action while retaining the selected workout |
| Demonstration | Full-screen moving human trainer | Large original orange vector illustrations, side-aware mirroring | Pilot short looping demonstrations for dynamic movements that are hard to infer from a still image |
| Teaching | Steps, breathing, expected feeling, mistakes/corrections, demo | One concise instruction field plus generic gentle-tension/stop-for-pain guidance | Add optional structured teaching fields and show only the most useful cue during playback |
| Warm-up length | Five-minute course, 11 listed movements | Before run: 16 rows, 19 timed steps, 7:30 movement + setup/transitions = 9:03 baseline | Offer a shorter preparation option; retain the longer routine as a deliberate choice |
| Timing | Interval timer, elapsed counter, total progress | Explicit 3-second preparation, 5-second transitions, per-side timing, final-five ticks, next-movement label | Preserve explicit transition/side clarity; do not shorten the clock by silently omitting setup |
| Editing | Live previous/next controls visible; routine editing not inspected | Add/remove/replace/reorder, per-side duration, reset, account-scoped synced customization | Keep customization; improve default selection before adding editor complexity |
| Post-run entry | Seven-minute stretch is separately scheduled; playback unverified | Successful save leads to optional stretch card with Start / Choose another and persistent Done | Keep durable save first; make stretch continuation feel like the final stage of the same outing |
| Outdoor practicality | The warm-up video includes low positions; support/floor labeling not comprehensively checked | Standing quick/standard options, content-derived support/mat requirements, outdoor remembered standing default | Surface “Standing · No mat” clearly and preserve support/skip instructions |
| Audio | Independent voice/music controls; live audibility unverified | Cached title/side audio, local ticks, optional transition feedback, mute; cache miss keeps visual timer usable | Add a short optional technique cue without overlapping intervals or requiring network playback |
| Interruption | Settings/help opened; exact pause/resume semantics not fully verified | Source explicitly pauses for help/options/background and requires manual resume | Preserve this guarantee when adding video or richer instruction |
| Completion credit | Ending asks to save course record | Routine analytics distinguish held/skipped intervals; standalone routine does not create a recorded activity | Keep warm-up/stretch distinct from primary workout adherence and avoid duplicate load credit |

### Verified catalog timing

Calculated directly from `shared/stretch/catalog.json` using the current bilateral expansion and `movement seconds + 3 + 5 × (expanded steps − 1)` rule. Baseline excludes pauses or narration overruns.

| Routine | Visible rows / timed steps | Movement time | Baseline total |
| --- | --- | --- | --- |
| Before run | 16 / 19 | 7:30 | 9:03 |
| Standing reset | 3 / 6 | 1:30 | 1:58 |
| Standing stretch | 5 / 10 | 4:10 | 4:58 |
| After run 1 | 5 / 10 | 5:00 | 5:48 |
| After run 2 | 7 / 13 | 6:30 | 7:33 |
| After run 3 | 11 / 20 | 10:00 | 11:38 |

Keep’s five/seven-minute labels are displayed course durations. Their exact timing basis was not validated; do not present these as precisely equivalent measurement methods.

## Recommended product changes — proposals only

### P0: make preparation part of starting the planned run

- Present one outing: **Warm up (optional) → Run → Stretch (optional)**, with the main run clearly primary.
- Put Warm up beside Start run, rather than requiring discovery through a generic Stretch toolbar action. Preserve an immediate Start run path.
- On warm-up completion, offer **Start planned run** prominently, with a secondary Done / Not now. Ending early should offer Continue to run without claiming warm-up completion.
- Carry immutable planned-workout identity, sport, route, goals and launch configuration through the warm-up. Revalidate stale/day-changed plan data when returning; never silently start a newly substituted workout.
- Start the main activity recorder and GPS workout clock only through the normal Start transition, not at warm-up entry. Keep preparation timing separate.
- After durable save, use the existing celebration/stretch integration; optional stretching must not block save or require a second activity record.
- Expose overall commitment honestly: main run time plus optional routine totals. Do not imply everyone must perform every add-on.

### P1: teach the movements better

- Begin with dynamic warm-up movements where a still image is least clear: swings, hip circles, alternating lunges and high knees.
- Keep existing vector artwork as a fast offline fallback. Any new loop must show full movement range, direction, side and a stable camera; retain mirrored-side correctness and Reduce Motion behavior.
- Structure original localized content into **How to move**, **What to notice**, **Common mistake**, and **Easier option/support**. Keep detailed content behind the instruction sheet; show one short action cue in the player.
- Pause the interval during detailed instruction/demo viewing and require explicit Resume. Narration must not consume movement time; preserve current cache-only playback and transition gates.
- Do not import Keep’s injury/soreness promises or trainer footage. Original instruction and licensed/original demonstration assets require their own content review.

### P1: reduce default warm-up friction

- Offer a compact Before run option as the initial UX candidate, with the current 9:03 sequence under a longer option. Exact movements/durations need focused content review; five minutes is a competitor benchmark, not proof of an optimal prescription.
- Name entry points **Warm up** before running and **Stretch** after running, while retaining the reusable catalog and dynamic/static validation internally.
- Keep standing/no-mat and support requirements visible. Preserve editable duration, replacements, skip and stop-for-discomfort guidance.
- Avoid social ticker overlays in the default movement-teaching view; optional social presence should not cover the demonstration.

### Measure and verify before implementation is called complete

- Funnel: planned-run exposure → warm-up offered/start → fully timed / skipped / ended early → return-to-run → activity started. Do not infer actual exercise from a running timer.
- Use stable routine IDs and bounded outcomes; no health conditions, exact targets, plan IDs, free text or route data in analytics.
- Verify direct Start without warm-up; completion/early exit; canceled countdown; changed plan/date; background and recovery; offline demonstration/audio fallback; side correctness; help/options pause; user-selected voice; no duplicate activity/load credit.
- Compare preparation uptake and subsequent main-run starts, plus abandonment and time-to-start. A higher warm-up completion count alone is not success.
- No product code changed and no test suite was run for this research.

## Source references

- [Reusable routines](stretch-routines.md) and [post-save contract](activity-post-save-celebration.md).
- `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift`: Today opens the reusable view with a dismissal-only callback.
- `ios/Outbound/Outbound/Activity/PostWorkoutStretch.swift`: setup/player, instruction/options sheets, pause/background, completion and analytics.
- `ios/Outbound/Outbound/Activity/StretchCatalog.swift` and `shared/stretch/catalog.json`: selection, bilateral expansion, timing and content.

## Screenshots

- [55-planned-warmup-launch](../artifacts/keep-research-2026-11-05/55-planned-warmup-launch.jpg)
- [56-warmup-player](../artifacts/keep-research-2026-11-05/56-warmup-player.jpg)
- [57-warmup-live-settings](../artifacts/keep-research-2026-11-05/57-warmup-live-settings.jpg)
- [58-movement-instructions](../artifacts/keep-research-2026-11-05/58-movement-instructions.jpg)
- [59-warmup-paused](../artifacts/keep-research-2026-11-05/59-warmup-paused.jpg)
- [60-stop-saves-record](../artifacts/keep-research-2026-11-05/60-stop-saves-record.jpg)
