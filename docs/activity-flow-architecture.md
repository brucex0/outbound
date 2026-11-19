# Activity Flow Architecture And Refactor Plan

Open when changing activity setup, countdown, live recording, finish/review, or the shared Today/Group recording entry points.

## Scope And Invariants

- Separate SwiftUI presentation, observable screen state, and activity operations without changing launch/navigation behavior.
- Keep `ActivityRecorder`, `ActivitySessionController`, and existing domain stores authoritative. Do not introduce another recording state machine or duplicate their data.
- Preserve retained Today identity, callback/modifier ordering, cancellation, location preflight, indoor/simulation exceptions, Watch ownership/reconciliation, analytics, localization, photo orientation/metadata, and pending-capture finish protection.
- Review retains an immutable finished snapshot; recorder reset must not erase its route/photos. Saving continues to use the latest available elevation correction without waiting for network enrichment.
- Preserve Group event attribution through recording, recovery, save, and discard. Keep exactly the current local-save and HealthKit ownership rules.

## Boundaries

- `ActivityFlowStore.shared`: app-owned lifetime for the sole `ActivityFlowCoordinator`; only this store can construct the coordinator. `ActivityRecorder.shared` owns the sole production recorder and restores its recovery journal once.
- `RecordView`: the single recording host in `MainTabView`; resolves environment dependencies and persisted preferences. Group, Today, reminders, and Watch entry points route to this host instead of presenting another recorder.
- `ActivityFlowView`: retained flow presentation and lifecycle subscription host. Keep modifier ordering and subscriptions together; split setup, live, and completion presentation into focused files.
- `ActivityFlowCoordinator`: activity operations and cross-screen transitions through the existing session controller; receives explicit dependency and host-context values. Operations are grouped into launch/recovery, recording, completion/save, setup, lifecycle-event, and analytics files.
- `ActivitySetupViewModel`: launch selection, per-sport drafts, goal editor state, formatting/validation, route-intent construction, recommendations, and provider setup actions.
- `CommunityRouteSelectionDraft`: one route-picker presentation's pending choice and preparation task. Activity setup retains its instance outside the native sheet content; the route store continues to own only route data and caches.
- `LiveActivityViewModel`: live page/panel and capture state, without copying recorder metrics.
- `ActivityCountdownViewModel`: countdown step/task ownership.
- `ActivityReviewViewModel`: finished snapshot, correction task, and post-save presentation state.
- Pure goal presets/recommendations and countdown presentation live outside the flow host.
- Existing domain services remain direct dependencies. Do not add forwarding service wrappers that merely rename `ActivityRecorder` or `ActivityStore`.

The singleton coordinator owns the screen models for the app’s retained flow. Screen changes and existing observable domain services invalidate the flow through explicit observation; SwiftUI focus and environment values remain in views.

## Preference Tap Pipeline

- Launch and goal options use native SwiftUI `Button` actions, then coordinator setters, then persisted preferences. Setters notify `objectWillChange` before writing, so selected styling and open goal editors update through the retained coordinator.
- `ActivityFlowPreferences.persisted` provides a plain storage accessor that reads UserDefaults live, without SwiftUI Binding value caching. Do not retain projected `@AppStorage` bindings in the coordinator: their cached reads can outlive the view update that created them, making taps appear ineffective and returning stale values to guide setup or analytics.
- `RecordView` retains AppStorage subscriptions for external settings/account-sync edits; the flow's preference snapshot propagates those changes without replacing session identity.
- Auto Pause computes its next value at action time. Configuration analytics retain their existing event/property names and report the value just written. Pause at goal exposes a full-width, minimum 44-point row.
- Verification for this repair: build-only compilation, source tracing, and a standalone storage probe covering defaults, repeated toggles, external edits, reopening, reset, and string values; repeated physical-device taps, external sync while the editor is open, and relaunch persistence still require manual verification.

## Maps And Entry Points

- Today keeps its stable `ActivityLaunchMap`, selected route, and camera within the Today shell.
- Live keeps its existing `LiveMapView`/camera and recorder-backed route; paging does not reconstruct the native map.
- Review uses the finished snapshot and existing `PostRunSummaryView` route presentation.
- Share existing map surface/geometry helpers, not mutable camera state between screens. Replacing map renderers is outside this behavior-preserving extraction.
- Reusable plan setup presents as a full-screen cover above the retained main shell when `OnboardingStore.isPresented` changes after startup. First-use onboarding retains its startup destination; finishing the reusable builder returns to the same Today draft. The existing builder analytics retain their presentation source.
- Today retains the only `RecordView`/`ActivityFlowView`; its identity is stable across launch requests. Group Start closes its detail presentation and sends a request to that host, preserving its event/attendance context and immediate permission/GPS/countdown path.
- Passive Today prescription refreshes retain the launch UUID and existing setup model. `ActivityFlowView` reconciles changed prescription data through `refreshPrescribedIntent`, rather than treating server/cache updates as a new recording entry. An open sheet, route-library draft, photo, and selected route survive. Planned selection adopts the updated workout underneath its route; an explicitly edited manual selection retains its sport/goal draft while the stored Planned choice updates. Removing a route restores that latest underlying workout. Explicit entry requests still get a new UUID and retain their existing setup-reset behavior; unfinished-session and recovery guards remain authoritative.
- Re-entry during preflight, countdown, active/paused recording, review, save, or celebration reveals the existing session. It preserves that session’s intent, photos, sharing, and review. Explicit Group Start may attach its event context to an active/paused unlinked recorder without replacing its route, goals, metrics, or identity; an already-linked recording and review/save cannot be reassigned. Only setup can accept a replacement launch; setup drafts are refreshed without reconstructing the coordinator, recorder, or live screen.
- Finish requires an active/paused recorder and no existing review; save accepts only the current pending review ID. These guards prevent stale finish/save callbacks from writing another activity or recovery checkpoint.
- Today’s **Join this run** selection adds only event attribution at start, validated against eligible cached Social events; location consent remains a separate **Share live location** switch. Account-scoped completion markers remove finished-event Today controls through review, discard, save, and relaunch.
- `activity_recording_entry` records `entry_source=app|group_activity` and `result=prepared|reused_existing`; it contains no activity/event/session IDs or personal data.

### Manual startup-refresh probe

For an isolated Debug Simulator, launch with `-OutboundUITestTodayPrescriptionRefresh`. Send the signal once to establish a local prescribed-workout fixture, then open Today overflow or the route picker and send it again:

```sh
xcrun simctl spawn <simulator-udid> notifyutil -p com.plainstride.outbound.debug.today-prescription-refresh
```

Each signal toggles the local Today customization between 20 and 30 minutes through the normal `defaultTodayIntent` observer. Only with the explicit probe flag, that local customization supplies the default intent independently of account/plan availability; no real plan is required. Verify the menu stays open, picker selection survives, Done retains the route, and Remove restores the updated workout. The probe has no observer without the opt-in argument, is compiled out of device/release builds, and never changes account/server data. This exercises refresh reconciliation; it does not reproduce real network startup timing or verify physical-device behavior.

### Startup refresh verification — 2026-11-16

- Simulator build, design-system guardrail and diff checks passed. Independent UX review passed the focused change at code revision `c162c9b2` after inspecting source and manual Simulator captures.
- On an isolated iPhone 17 Pro / iOS 27.0 Simulator, explicit refreshes retained an open overflow menu, pending route selection, applied route, and a typed 47-minute goal with the keyboard open. Apply, Change/reopen/Close, and Remove remained usable; Remove kept the latest 20-minute prescription, and returning to manual Run restored its 47-minute draft.
- Verification used synthetic guest data and a local imported route with the opt-in probe. No test suite ran. Original network-startup timing, physical-phone behavior, photo capture, nil-prescription runtime transitions, VoiceOver and the broader layout/theme matrix remain unverified.
- Bruce's subsequent physical-phone retest of `b68cacb9` reported the same overflow flashing and route-picker reset. The focused probe verified only prescription reconciliation; it did not resolve or reproduce the original startup problem.

### Debug startup lifecycle diagnostics

- Debug builds emit `ui_stability` lines to the `ActivityLifecycle` log and stdout for filtered `devicectl --console` capture. Release builds omit them.
- Process-local presentation counters distinguish Today, overflow, activity-flow, and route-picker lifetimes. Picker events distinguish row actions, pending preparation, successful selection, store publication, and new-launch setup replacement; preparation outcomes use only safe error categories and source labels.
- A one-time theme check compares two freshly requested accent colors, their bridged UIColors, and resolved light/dark colors. This diagnoses value identity without printing color values.
- These diagnostics contain fixed labels, process-local counters, and booleans, never account/activity/route identifiers, route geometry, names, or user-entered content. They are local diagnostics, not product analytics.

### Native picker retention follow-up — 2026-11-16

- Authenticated iOS 26.6.2 phone diagnostics observed the first route-picker subtree disappear and receive a new presentation counter after discovery-store publications, while Today and activity-flow counters stayed unchanged and no new launch/setup replacement occurred. The recording also showed a selected checkmark and enabled confirmation become an empty, disabled selection. The old picker-local state did not survive native subtree replacement.
- Phone and iOS 26.5 Simulator diagnostics found two reads of the same theme produced unequal `Color`/`UIColor` values with identical resolved light/dark colors. The theme now retains its accent provider per case to avoid those unnecessary native tint updates. This establishes a source of tint churn, not that every native subtree replacement has only that cause.
- Setup owns an optional route draft and presents it by stable item identity. Recreated sheet content observes the same draft. Genuine open creates a fresh draft; Close, Apply, interactive dismissal, and a new activity launch invalidate its pending request. Child `onDisappear` does not clear it. Dismissal callbacks check the expected draft so an old sheet cannot clear a newer presentation.
- Draft-owned tasks use request, active-presentation, and account-epoch guards. A later choice, canceled request, closed sheet, or different account cannot accept an old completion. A failed preparation retains the previous choice. Close does not apply pending changes; applying and explicit row-toggle removal keep their existing semantics. Query/filter/search focus remain local UI state.
- Embedded or cached geometry uses the same synchronous validation, persistence, and LRU path as async preparation, without publishing a fake Preparing/disabled-confirmation frame. Network preparation retains its actual busy state and disables confirmation until completion. The async detail-view consumer keeps the same API.
- Final application revision `572ad4b1` passed arm64 Simulator compilation, a signed phone build, the design-system guardrail, and diff checks. It was installed and launched on Bruce main; Bruce's subsequent response was “I think it's fixed.” This is tentative physical-device acceptance of the reported problem, not exhaustive regression coverage.
- Manual iOS 26.5 checks used synthetic guest routes served by a local HTTP fixture. One picker presentation retained selection through store publications, repeated cached choices, a real delayed network response, and Dark → Light appearance switching. Apply produced the expected route card and map. Repeated accent reads compared equal for both `Color` and `UIColor`, with unchanged resolved light/dark values.
- An intentional HTTP 503 retained the previous selection and showed temporary error feedback. Selecting a cached route superseded a delayed request; closing during preparation canceled acceptance, left the applied route unchanged, and reopening started from that applied route. These checks used UI actions and local logs, not the test suite.
- Independent Sol/Medium review found no actionable source defects. Its QA status remains `Incomplete`: interactive swipe dismissal and switching distinct theme cases lack final runtime evidence; the broader accessibility/layout/input matrix was not rerun. Bruce requested merge on 2026-11-18 under the immediate-merge exception. An integration audit confirmed every task addition was already present in main at `9c04ef3c`; the stale task worktree and branch can be removed. No test suite was authorized or run.

## Implementation Sequence

1. Extract pure types, goal recommendations, countdown presentation, and layout helpers unchanged.
2. Introduce observable setup/live/countdown/review state with exactly the existing initial values.
3. Move non-view activity operations into the dependency-injected coordinator; split by responsibility.
4. Move presentation into setup/live/completion files while retaining existing view identity and lifecycle modifier order.
5. Keep caller APIs stable, review normalized extraction diffs, and build for iOS Simulator without running tests.
6. Record verification limits, squash-merge the focused iOS commit into main, then remove the worktree/branch.

## Acceptance Matrix

| Area | Scenarios |
| --- | --- |
| Setup | Planned/manual/curated/race goals, sport drafts, metric/imperial units, routes, indoor, companion, gear/music/voice |
| Start | Missing permission, GPS wait, foreground retry, countdown cancellation, walk/hike skip, rapid taps |
| Live | Pause/resume/auto-pause, photo capture and pending finish guard, page switching, map camera, guidance/sharing |
| Navigation | Today hide/reopen, Group immediate launch and return, recommendation refresh during review/post-save |
| Finish/save | Immutable summary, Watch final metrics, correction result, too-short eligibility, save failure/retry, discard, event linkage |
| Recovery | Active/paused/finished journal, restored photos, Group restoration, Watch-owned session |
| Post-save | Celebration exposure once, stretch exit, app-review callback |

## Verification Record

- Implemented the extraction sequence above; `RecordView` is a composition adapter, not the screen-state owner.
- Debug iOS Simulator build passed with `CODE_SIGNING_ALLOWED=NO`; unrelated existing project warnings remain.
- Compared all 240 original view/operation members after normalizing ownership and bindings: 238 retain identical statement structure, including extracted lifecycle-handler bodies. Reviewed the two deliberate differences: countdown progression delegated to its model, and guide/preparation callbacks capture the flow weakly to avoid retaining completed flows.
- Reviewed unchanged pure helpers and initial state/defaults, location/countdown guards, capture-finish protection, review correction/Watch reconciliation, save guards, Group-event attribution, and analytics/localization references.
- Build command (reuse an available package cache if needed):

  ```sh
  xcodebuild -quiet -jobs 2 -project ios/Outbound/Outbound.xcodeproj \
    -scheme Outbound -destination 'generic/platform=iOS Simulator' \
    -derivedDataPath /tmp/outbound-record-refactor-derived \
    CODE_SIGNING_ALLOWED=NO build
  ```

- Follow-up tests were explicitly authorized. Portable metrics tests and the complete iOS unit target pass after repairing stale package dependencies, service mocks, persistence APIs, and onboarding replay expectations. Live guide tests run in the iOS target against the current moment-driven contract.
- UI regressions use the custom dock and current Social/photo flows. Seeded scenarios explicitly clear synthetic recording journals; group recovery retains its journal across two relaunches and owns its loopback API fixture.
- Requested verification passed: 15 Swift Package tests and all 91 unique iOS tests (69 unit, 22 UI) on a fresh iPhone 17 / iOS 26.5 simulator. The full scheme includes all six Watch scenarios and six launch configurations. Photo coverage checks preview, long-press selection, drag reordering, deletion, and the saved photo count.
- Manual device verification must be reported separately: a build does not verify GPS, camera, Watch, audio, map gestures, or visual transitions.

### Single app-owned recording repair (2026-11-01)

- Connected-device logs confirmed a second in-process journal recovery while the original Group recording remained alive, followed by separate normal and recovered saves. Group no longer constructs its own flow.
- Verification: Debug arm64 iOS Simulator build and clean incremental build passed. A standalone Swift probe using the production owner, launch/ownership guards, cancellation methods, and session controller with stub domain services confirmed one coordinator/recorder identity, preserved intent/photos across all seven in-flight phases, next-session reuse, idempotent launch requests, and release after countdown/GPS cancellation. Source audit confirms one production recording host and one private production recorder constructor.
- No test suite ran. Visual navigation, real-device GPS/camera/audio, and paired Watch behavior were not manually reverified. The new build was not installed on a phone.
