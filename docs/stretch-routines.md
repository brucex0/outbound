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

- Canonical source: `shared/stretch/catalog.json`. Contains 15 movements, five templates, EN/ZH/ES copy, equipment/floor flags, illustration geometry, original cue titles and references.
- Regenerate after edits: `python3 scripts/generate-stretch-catalog.py`. Commit manifest plus generated Swift, Kotlin, string catalogs/resources and backend title map. No build-time Python dependency.
- Six additions: standing chest opener, upper-back stretch, overhead triceps, supported lat stretch, wall side stretch and wall chest stretch. References are retained per movement. Instructions and vector drawings are original adaptations; sources do not validate the app's complete routine or drawings.
- Supported lat requires a fixed sturdy surface, despite the reference library's broad “no equipment” label. Wall variants explicitly require a wall. Requirements are computed from entries, never template names.
- Preserve original nine movement geometry, side mirroring, instructions and audio cue transcripts. Existing cached cues remain valid. New title cues require backend deployment before clients can fetch them; unavailable audio stays silent with diagnostics.
- Templates: standing reset, standing stretch, upper body, mat lower body, mat hips/hamstrings. Swimming initially suggests upper body; other sports suggest standing reset. Valid remembered choices take precedence. Cycling retains access to both body areas rather than implying medical personalization.
- Static, optional general-wellness holds only. No claims of preventing soreness or treating injury. Keep gentle-tension/stop-for-pain guidance visible.

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
