# Post-Workout Stretch Implementation Prompt

Use this prompt to implement Plainstride's optional post-save stretching experience on iOS and Android.

## Prompt

Implement an optional, local-only guided stretch flow after a successfully saved Plainstride-recorded activity.

Start by reading `AGENTS.md`, `docs/INDEX.md`, `docs/motivation-ux.md`, `docs/ios-architecture.md`, `docs/product-analytics.md`, `docs/localization.md`, `docs/android-port.md`, and `docs/android-build.md`. Inspect the current save, dismissal, navigation, localization, accessibility, and analytics code before editing; do not assume the file list below is exhaustive.

### Non-negotiable product behavior

- Offer the stretch flow only after a Run, Bike, Hike, or Swim has been saved successfully.
- Never offer or show the stretch flow for Walk. Resolve eligibility from the canonical activity type, not a localized title, workout name, pace, distance, or plan label.
- Do not offer it for discarded, too-short, unsaved, manual, imported, or remotely restored activities.
- The activity must be durably saved before any stretch prompt appears. Stretching must never delay, gate, retry, mutate, or roll back activity persistence, photo export, HealthKit handling, plan completion, recognition, Social contribution, or synchronization.
- Keep the existing finish reflection and Save action intact. After Save succeeds, replace the normal dismissal with a lightweight post-save choice for eligible activities: `Start stretching` and `Done`.
- `Done` must immediately complete the recording flow. Stretching is always optional; do not use guilt, streak loss, warnings, or repeated confirmation when the user declines.
- Completing or leaving the stretch flow returns to the same destination that a successful Save uses today.
- If the app is backgrounded during an active stretch, pause the current timer and resume only when the app becomes active. If the process is terminated, do not restore the stretch flow; the activity is already safe.
- V1 is phone-only. Do not add Apple Watch, Wear OS, backend, activity-schema, sync, HealthKit, or Social fields for stretch state.

### Experience and content

- Present one calm, full-screen flow using the existing Plainstride visual language. Lead with `Activity saved`, then offer the stretch without making it feel like another required workout.
- Use deterministic, reviewed local content. Do not generate stretches or health advice with AI.
- Provide one routine per eligible activity type. Each routine should contain four movements, use short localized instructions, and take about four to five minutes including side changes and transitions.
- Each movement must define a stable ID, localized title, localized instruction, optional side (`left`, `right`, or `both`), timer duration, ordering, and a bounded system icon or existing repo-native visual. Do not add downloaded imagery or a new media dependency.
- Show one movement at a time with:
  - movement title and instruction;
  - visible remaining time and overall progress;
  - `Pause` / `Resume`, `Next`, and `End` controls;
  - explicit left/right labeling when relevant;
  - a short persistent safety line such as `Move only into gentle tension. Stop if you feel pain.`
- A bilateral movement should present each side as an explicit timed step so the user never has to infer when to switch.
- Use a subtle haptic at step transitions when haptics are enabled. Do not add spoken coaching or reuse the live-coach audio pipeline in V1.
- Keep the screen awake only while the timed routine is actively running, and restore normal system behavior on pause, completion, backgrounding, or dismissal.
- On the final step, use `Finish` instead of `Next`, show a brief completion state, and then return through the normal saved-activity dismissal path.
- `End` exits immediately after one non-alarming confirmation only if a timer is active. Before the routine starts, `Done` exits without confirmation.

### Routine content boundaries

- Create a small typed local catalog shared by the feature UI rather than embedding arrays directly in view code.
- Keep instructions biomechanically conservative and easy to perform without equipment. Avoid bouncing, forced range of motion, partner assistance, floor positions that are impractical immediately after an outdoor activity, and movements that require balance without offering support guidance.
- Use distinct reviewed routines for Run, Bike, Hike, and Swim. It is acceptable for movements to overlap when appropriate, but routine IDs and activity eligibility must remain explicit.
- Do not claim that stretching prevents injury, eliminates soreness, accelerates recovery, treats pain, or is medically necessary.
- Do not ask about injured or painful body areas in V1. Do not diagnose, personalize around suspected injury, or collect health free text.
- Add a concise localized disclaimer that the routine is general wellness guidance and should be stopped if it causes pain, dizziness, or unusual discomfort. Keep it subordinate to the task rather than presenting a frightening medical modal.

### iOS

- Add the post-save state at the recording-flow owner level so it can outlive `PostRunSummaryView` after persistence succeeds without retaining unsaved activity state.
- Preserve `PostRunSummaryView`'s current save progress and failure behavior. A failed save stays on the review and never opens the stretch prompt.
- Refactor `RecordView.savePendingActivity` only as needed to distinguish:
  - save failure;
  - successful save followed by normal dismissal;
  - successful eligible save followed by the stretch choice.
- Complete all existing successful-save side effects before entering the stretch state. Clear active-session recovery artifacts once persistence is durable so relaunch cannot resurrect a finished workout.
- Capture the canonical saved `ActivityType` in a small post-save context before clearing recording state. The eligibility rule must explicitly exclude `.walking` and include only `.running`, `.cycling`, `.hiking`, and `.swimming`.
- Implement the routine catalog and timer logic as UI-independent Swift types where practical. Use a clock/timer approach that does not drift badly across short suspensions and pauses.
- Build the SwiftUI screen in the activity feature area. Respect Dynamic Type, VoiceOver, Reduce Motion, button target sizes, safe areas, dark mode, and the selected app theme.
- VoiceOver should announce the movement and instruction when a step begins, but must not announce every countdown second.
- Scope `UIApplication.shared.isIdleTimerDisabled` carefully and always restore it when the active routine pauses or leaves the hierarchy.
- Add natural English, Spanish, and Simplified Chinese strings to `Localizable.xcstrings`; do not hard-code display text.

Likely iOS areas include:

- `ios/Outbound/Outbound/Activity/RecordView.swift`
- `ios/Outbound/Outbound/Activity/PostRunSummaryView.swift`
- new focused files under `ios/Outbound/Outbound/Activity/` for the catalog, timer/state model, and SwiftUI flow
- `ios/Outbound/Outbound/Core/Analytics/ProductAnalyticsEvent.swift`
- `ios/Outbound/Outbound/Localizable.xcstrings`

### Android

- Add the post-save choice and timed routine to the recording navigation flow only after `RecordingViewModel.saveFinished` returns a successful durable result.
- Preserve the current review state on save failure and never open stretching from a failed or pending save.
- Carry the canonical saved activity kind into a small post-save navigation context. Explicitly exclude walking and include only running, cycling, hiking, and swimming.
- Ensure planned-workout completion and the existing `onSaved` side effects still occur exactly once. Refactor the callback/result shape if necessary so navigation to stretching does not duplicate them.
- Implement the catalog and timer state outside Composable bodies. Use lifecycle-aware state, pause on background, and do not persist or restore the routine after process death.
- Build the Compose screen inside the recording feature with Plainstride theming, 48-dp targets, TalkBack semantics, font scaling, dark mode, and reduced-motion behavior.
- TalkBack should announce each new movement and instruction, not every countdown second.
- Apply the keep-screen-on flag only while the timer is running and remove it reliably on pause, background, completion, and disposal.
- Add natural English, Spanish, and Simplified Chinese resources; do not hard-code display text.

Likely Android areas include:

- `android/feature/recording/src/main/kotlin/com/plainstride/outbound/feature/recording/RecordingScreen.kt`
- `android/feature/recording/src/main/kotlin/com/plainstride/outbound/feature/recording/RecordingViewModel.kt`
- new focused catalog, timer/state, and Compose screen files in `android/feature/recording/`
- app-level recording navigation and `onSaved` handling in `android/app/src/main/kotlin/com/plainstride/outbound/PlainstrideApp.kt`
- `android/core/analytics/`
- recording string resources for English, Spanish, and Simplified Chinese

### Analytics and privacy

- Add the same typed event contract on iOS and Android:
  - `post_workout_stretch_offered` when the post-save choice first appears;
  - `post_workout_stretch_started` when the first timer begins;
  - `post_workout_stretch_completed` after the final movement;
  - `post_workout_stretch_dismissed` when the user chooses `Done` or ends an active routine.
- Allow only bounded properties: `activity_type`, `routine_id`, and `result`. Use `result=not_started` or `result=ended_early` only on the dismissed event.
- Do not emit per-second, per-pause, per-step, or repeated-render events.
- Never send movement instructions, body areas, pain information, activity IDs, exact workout metrics, routes, coordinates, timestamps, or free text.
- Update the event/property allowlists and `docs/product-analytics.md` so both clients enforce the same privacy contract.

### Acceptance criteria

- Saving an eligible Run, Bike, Hike, or Swim shows the optional post-save stretch choice exactly once.
- Saving a Walk follows the existing successful-save path with no stretch UI, no stretch analytics, and no transient glimpse of the feature.
- A save failure remains on the post-activity review and cannot enter the stretch flow.
- Choosing `Done` after Save exits immediately and records one offered event plus one dismissed event with `result=not_started`.
- Starting, pausing, resuming, advancing, ending early, and completing a routine all behave deterministically without re-saving or re-completing the activity.
- Backgrounding pauses timing and screen-awake behavior; foregrounding does not silently consume time.
- Process termination during stretching loses only the optional stretch progress, never the activity.
- Walking titles or planned workouts containing words such as `run` cannot bypass the canonical walking exclusion.
- English, Spanish, and Simplified Chinese layouts remain usable with large text, VoiceOver/TalkBack, dark mode, and Reduce Motion.

### Verification

- Do not run the test suite unless the user explicitly asks. Perform build-only/static verification appropriate to each affected client.
- Build the iOS app with code signing disabled using the documented command.
- Build the affected Android debug variants/modules using `docs/android-build.md`.
- Run `git diff --check`.
- Manually or with existing previews/debug fixtures verify every acceptance criterion, all four eligible activity types, walking exclusion, save failure, repeated taps during save, background/foreground timing, active-timer dismissal, process termination, screen-awake cleanup, localization, accessibility, and analytics cardinality.

### Documentation and commits

- Update `docs/motivation-ux.md`, `docs/ios-architecture.md`, Android parity documentation, and `docs/product-analytics.md` with the delivered behavior and ownership boundaries.
- Follow `AGENTS.md` commit discipline. Commit iOS and Android implementation separately with `[iOS]` and `[Droid]` prefixes; use a separate docs commit if shared documentation would otherwise mix platform changes.
- Keep unrelated working-tree changes and agent metadata out of every commit.

When finished, report the behavior delivered, eligibility handling with explicit proof that Walk is excluded, routine content and localization coverage, analytics changes, verification commands/results, commit hashes by scope, and any genuine remaining blocker. Do not claim completion if the stretch UI can appear before durable save, can re-trigger save side effects, or can appear for walking.
