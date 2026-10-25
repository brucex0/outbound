# Reusable Stretch Routines

Open when adding a stretch entry point, movement, template, or editor behavior. Post-save celebration ownership remains in `activity-post-save-celebration.md`.

## Entry Points And Ownership

- iOS: `StretchSessionView(launch: StretchLaunchContext(entryPoint: .today), voiceProfileID: selectedVoiceID, onExit: dismiss)` launches without a saved activity. Optional `activityType` selects sport defaults; `isIndoor` allows mat preference restoration. Its optional header closure receives the same exit callback used by the flow, preserving dismissal analytics.
- Android: `StretchSessionRoute(launch = StretchLaunchContext(StretchEntryPoint.TODAY), sessionKey = stablePresentationKey, onDone = dismiss, onEvent = analyticsAdapter, fetchAudio = audioAdapter)` launches independently of recording. Keep the presentation key stable across recompositions. A host may supply a composable header.
- `PostWorkoutStretchView` / `PostWorkoutStretchRoute` are post-save adapters that supply the celebration and Share/Done actions. iOS Today exposes a text Stretch action in its leading toolbar while recording is idle. Android has no Today button yet.
- Catalog, customization storage, editor, illustrations, player and audio do not require a saved activity. The Android implementation remains in the recording library module; Today can be wired at the app composition boundary without a dependency from Today to recording.
- Never instantiate guide settings inside the stretch view. Pass the selected voice from the host. Android's existing audio adapter uses its configured guide voice; a new surface must use the same adapter contract.

## iOS Screen Layout

- Today and the finish page use the same `StretchSessionView`; hosts provide context and the selected companion voice. Today does not start or complete a workout when opening stretches.
- The finish page keeps celebration/Share/Done plus a compact recommended routine and fixed Start action. Change routine opens routine details; the header close returns to celebration.
- Routine details show one row per posture, with per-side duration labeled for bilateral movements. Change routine opens a separate chooser. Start remains fixed below scrolling content.
- Playback shows large artwork, side, phase, countdown, one progress bar, essential equipment requirements, gentle-tension guidance, pause and skip/start-now. Full instructions and options use separate sheets; opening either pauses playback and requires explicit resume.
- Voice/tick mute and transition sound/haptics preferences persist across entry points. Setup, transition/audio gating, skipping, background pause and held-time accounting still belong to the existing timer/narrator.
- The editor uses compact rows with duration menus, replacement/removal menus and native reorder mode; accessible move up/down actions remain available. A visual grid serves Add/Replace, with the existing filters and validation. Only the toolbar saves.
- UI copy is in `StretchUI.xcstrings` (EN/ZH/ES), separate from the generated content catalog.

## Content And Generation

- Canonical source: `shared/stretch/catalog.json`. Contains 40 movements, nine templates, EN/ZH/ES copy, equipment/floor flags, illustration geometry, original cue titles and references.
- Regenerate after edits: `python3 scripts/generate-stretch-catalog.py`. Commit manifest plus generated Swift, Kotlin, string catalogs/resources and backend title map. No build-time Python dependency.
- Six additions: standing chest opener, upper-back stretch, overhead triceps, supported lat stretch, wall side stretch and wall chest stretch. References are retained per movement. Instructions and vector drawings are original adaptations; sources do not validate the app's complete routine or drawings.
- Supported lat requires a fixed sturdy surface, despite the reference library's broad “no equipment” label. Wall variants explicitly require a wall. Requirements are computed from entries, never template names.
- Preserve original movement instructions and audio cue transcripts. Schematic geometry remains as a fallback; run movements use orange vector assets with an explicit source-side field for mirroring. Existing cached cues remain valid. New title cues require backend deployment before clients can fetch them; unavailable audio stays silent with diagnostics.
- Templates: standing reset, standing stretch, upper body, mat lower body, mat hips/hamstrings. Swimming initially suggests upper body; other sports suggest standing reset. Valid remembered choices take precedence. Cycling retains access to both body areas rather than implying medical personalization.
- Optional general-wellness movement only. Static routines use gentle holds; Before run uses dynamic movement intervals. No claims of preventing soreness or treating injury. Keep gentle-tension/stop-for-pain guidance visible.

## Editor And Persistence

- Customize before Start; Add, Remove, Replace, Move up/down, duration selection, Undo removal and Reset to original. Catalog filters body area and requirements. Replace initially filters the current body area.
- One row is one posture. Bilateral rows expand into consecutive left/right steps; duration applies to each side. No duplicate movement IDs; 1–20 entries; durations 15/20/25/30 seconds. Empty drafts cannot save.
- Cancel/swipe dismissal discards the draft. Save persists one local customization per template across sports and entry points. Reset immediately removes that customization. No named copies, user-authored postures or cloud sync.
- iOS keys: `stretch_customization_v1_<template>` in UserDefaults. Android: `stretch_customizations_v1` preferences. Payload is ordered movement IDs and seconds only. Validate decoded entries; corrupt/invalid payloads log safe diagnostics and use the built-in template. Reset via the editor; no database rebuild or migration needed.
- Last selected routine/standing preference still changes only on Start. Mat-containing edits are categorized under More routines and excluded from automatic outdoor restoration where a standing choice exists. If every customized template requires a mat, show an original standing reset as an explicit fallback without deleting saved edits.
- Player takes an immutable selected routine at Start; editing cannot occur during playback. Audio preload keys include actual cue lists, so replacing content under the same template reloads cues.
- Existing setup/transition timing, cache-only audio, five final ticks, mute, pause/background, skip and completion semantics remain in place.

## Verification

- Build only: iOS Simulator `xcodebuild … build`; Android `:app:assembleDebug`; backend `npm run build`. No test suite without explicit request.
- Manual iOS standalone route: launch a Debug build with `-OutboundDebugStretch`. This uses normal local stretch preferences; use a dedicated QA simulator. Release builds omit the route.
- Manual acceptance: add/remove/undo/replace/reorder/duration, empty draft, cancel/save/reset, relaunch persistence, paired sides, mixed mat/support requirements, swimming and remembered defaults, sharing dismissal, and offline audio after editing.
- Check illustrations at 56/72 pt previews and adaptive large playback artwork, EN/ZH/ES layouts and accessibility, cache misses/hits, mute during titles/ticks/completion, background/manual resume, last-step skip and fully held completion.

### Verification Record (2026-10-24)

- Backend TypeScript build, Android `:app:assembleDebug`, iOS Simulator build and `git diff --check` passed. No test suite run.
- Dedicated iOS simulator: standalone screen without an activity; EN/ZH setup/editor copy; remove/Undo; replacement body-area filter and triceps pair; duration change; Save/Your version; changed total time; persistence after relaunch; customized player start with voice muted; manual pause. The original unsaved draft was discarded on relaunch, while the explicitly saved upper-body edit remained. Number choices were corrected to show seconds rather than the app's duration formatter.
- Not manually verified: Android UI, Spanish layout, actual title/tick audibility and haptics, cached/uncached/offline audio, post-save sharing dismissal, background/resume, all drawings/sides, complete/last-step skip, all-mat outdoor fallback and corrupt-storage recovery. Source review preserved existing player timing/mute/skip/lifecycle paths and checked paired expansion plus content-derived requirements; build success is not runtime proof of these cases.

### iOS Layout Verification (2026-10-24)

- iOS Simulator build and `git diff --check` passed; no test suite run.
- Isolated iPhone 17 Pro simulator: routine details/sticky Start, compact editor, Add grid, adding supported quad stretch, Save toast, updated duration/requirements, player preparation/hold layout, instruction sheet and explicit paused Resume state. Existing illustrations are retained.
- Source diff preserves timer/narrator code, bilateral expansion, customization storage/validation and existing analytics accounting. New UI interactions use bounded analytics values.
- Not manually verified in this pass: Today authenticated entry, post-save celebration/Share/Done handoff, all editor actions, Dynamic Type, Spanish/Chinese layout, real audio/haptics/cache/offline behavior, full completion and background/resume. Android UI is unchanged.

## Run Routines

- Add only the movement union of the four supplied run routines to the app, retaining the five existing templates. The expanded offline illustration pack has 78 entries (original 50 plus 28 additions); it is not the app catalog. Standing reset remains useful for a short outdoor break; Upper body remains useful for swimming/cycling. Existing lower-body templates and saved customizations remain available.
- Before run is available from Today/standalone stretch entry points, never from post-save. Its 16 visible source movements are used without inventing a hidden row. Screenshot duration headings do not override the calculated clock.
- Original concise instructions and EN/ZH/ES translations are in the catalog. No injury-prevention, soreness-reduction or treatment claims are imported from the screenshots.

| Template | Movement time | Contents |
| --- | --- | --- |
| `pre_run` | 7:30 | Leg swings, lateral leg swings, gate opener, heel-to-toe rocks, lateral foot rocks, knee circles, dynamic side bends, split squats, lateral lunge, runner’s lunge twist, toe touch twist, high knee twists, dynamic quad, hamstring scoops, high knees, butt kicks |
| `post_run_1` | 5:00 | Standing quad, cross-leg fold, kneeling lunge, lying figure four, seated hamstring |
| `post_run_2` | 6:30 | Standing quad, seated wide-leg fold, leaning calf, side lunge, kneeling lunge, lying hamstring, lying figure four |
| `post_run_3` | 10:00 | Bent-over calf, standing quad, leaning calf, wide-leg side bend, cross-leg fold, kneeling lunge, downward dog, supported pigeon, seated hamstring, butterfly, modified seated twist |

- The app adds three seconds of preparation and five seconds between expanded steps. Static bilateral rows are 30 seconds **per side**, matching 1:00 row totals; symmetric rows are 30 seconds total. Pre-run leg swings, lateral leg swings and split squats are 15 seconds per side; the other dynamic drills alternate over 30 seconds total, except high knees/butt kicks at 15 seconds total.
- Dynamic and static entries cannot be mixed in an editor draft. The picker filters to the routine’s mode. The same timer, pause/background handling, audio gates, ticks, skip behavior and elapsed-time accounting remain in use. Dynamic intervals say “Move gently” and alternating movements say “Alternate sides”; preparation/transitions remain explicit. Existing analytics `held` / `fully_held` results mean timed interval participation, including moving intervals, not proof of performed exercise.
- Screenshot names/thumbnails are reference material, not detailed pose instructions. `Hurdler` is deliberately represented by a modified seated hamstring stretch with the bent foot in front of the pelvis. Wide-leg fold uses a seated version; wide-leg side bend is standing. Exact equivalence to Bend’s private instructional content is not established.
- Movement references: [Johns Hopkins dynamic drills](https://www.hopkinsmedicine.org/health/expert-qa/soccer-warmups-to-prepare-for-your-game), [Hartford dynamic warm-up](https://rehab.hartfordhospital.org/services/sports-medicine/conditions-treatments/dynamic-stretch-warmup). These do not validate the complete app sequence or generated illustrations.

### Vector Artwork

- Editable canonical files: `shared/stretch/illustrations/<movement>.svg`, only for the 40 app movements. All contain real vector paths, not embedded bitmaps. Generated originals are traced approximations with a reduced palette. Keep aspect ratio and full-body framing; no stretch-to-fill.
- Run `python3 scripts/generate-stretch-catalog.py` after content changes. For art changes, install authoring-only `svglib` and `reportlab` in an isolated environment, then run `python3 scripts/generate-stretch-artwork.py`. Commit the SVG, iOS PDF imageset and Android VectorDrawable together within their component commits. Runtime/builds do not require Python or these packages.
- iOS PDFs preserve vector representation; Android uses path-based drawables. Renderers mirror only unilateral cues according to `artworkSide`; alternating multi-position images are not mirrored. All current movements have orange vector artwork; the schematic renderer remains a fallback.
- Backend allowlisting derives sides and alternating announcements from generated `stretchCatalogModes.ts`. Old cue transcripts are unchanged. Deploy backend before relying on new titles; cache misses/unavailable audio retain the existing diagnostic and visual-timer behavior.
- No database reset or migration is required. Existing customization and selection keys remain valid. Post-save filters out the warm-up before restoring a selection.

### Run-Routine Verification (2026-10-24)

- Backend TypeScript, Android `:app:assembleDebug`, and iOS Simulator builds passed; no test suite run. Catalog generation validates translation coverage, unique IDs, modes and artwork sources. Content comparison confirmed all original movement fields and five original templates are preserved, and new app movements are limited to the four run routines.
- Verified 78 SVG/PNG pairs in `artifacts/stretch-illustrations`, no embedded bitmap SVGs, and 40 native PDF/VectorDrawable pairs without raster PDF images. All new SVGs are below 100,000 bytes. The complete pack, original 50-image Word guide, prompts, mapping and run sequences are also packaged in `artifacts/orange_stretch_illustrations_78.zip`.
- Dedicated iOS QA simulator: existing saved Standing reset customization restored; all nine routines visible; Before run shows all 16 source rows and calculated 9:03 runtime; new artwork renders in list and player; left-side 15-second dynamic interval, pause and right-side transition work with the Move gently label. Native vector export was also rendered for visual inspection.
- Not fully manually verified: Android UI, every pose/side and accessibility size, Chinese/Spanish layouts, new voice title playback on deployed backend, cached/uncached audio, end-to-end full completion, post-save filtering at runtime and background/resume. Static content and post-save filtering were source-reviewed; builds alone do not establish those behaviors.

- Remaining-artwork audit: reused pack IDs 2, 5, 11–15 for bent-knee calves, standing hamstrings, supported lat, upper back, cross-body shoulder, triceps and wall chest. Generated exact-instruction chest opener (77) and wall side stretch (78). All 40 app movements now have vector assets; movement instructions and timed sequences are unchanged.

- Final artwork follow-up (2026-10-25): iOS Simulator/device builds and Android Debug build passed. Upper-body routine was visually checked in the simulator with all four orange illustrations. Final signed app installed successfully on both available physical iPhones (Bruce main and Rina’s iPhone). No tests run; full on-device playback and audio remain unverified.
