# Activity Flow Architecture And Refactor Plan

Open when changing activity setup, countdown, live recording, finish/review, or the shared Today/Group recording entry points.

## Scope And Invariants

- Separate SwiftUI presentation, observable screen state, and activity operations without changing launch/navigation behavior.
- Keep `ActivityRecorder`, `ActivitySessionController`, and existing domain stores authoritative. Do not introduce another recording state machine or duplicate their data.
- Preserve retained Today identity, callback/modifier ordering, cancellation, location preflight, indoor/simulation exceptions, Watch ownership/reconciliation, analytics, localization, photo orientation/metadata, and pending-capture finish protection.
- Review retains an immutable finished snapshot; recorder reset must not erase its route/photos. Saving continues to use the latest available elevation correction without waiting for network enrichment.
- Preserve Group event attribution through recording, recovery, save, and discard. Keep exactly the current local-save and HealthKit ownership rules.

## Boundaries

- `RecordView`: dependency-composition adapter retaining the existing initializer for Today and Group callers. Resolve environment dependencies and persisted preferences here.
- `ActivityFlowView`: retained flow presentation and lifecycle subscription host. Keep modifier ordering and subscriptions together; split setup, live, and completion presentation into focused files.
- `ActivityFlowCoordinator`: activity operations and cross-screen transitions through the existing session controller; receives explicit dependency and host-context values. Operations are grouped into launch/recovery, recording, completion/save, setup, lifecycle-event, and analytics files.
- `ActivitySetupViewModel`: launch selection, per-sport drafts, goal editor state, formatting/validation, route-intent construction, recommendations, and provider setup actions.
- `LiveActivityViewModel`: live page/panel and capture state, without copying recorder metrics.
- `ActivityCountdownViewModel`: countdown step/task ownership.
- `ActivityReviewViewModel`: finished snapshot, correction task, and post-save presentation state.
- Pure goal presets/recommendations and countdown presentation live outside the flow host.
- Existing domain services remain direct dependencies. Do not add forwarding service wrappers that merely rename `ActivityRecorder` or `ActivityStore`.

The coordinator owns the screen models for one retained flow. Screen changes and existing observable domain services invalidate the flow through explicit observation; SwiftUI focus and environment values remain in views.

## Maps And Entry Points

- Today keeps its stable `ActivityLaunchMap`, selected route, and camera within the Today shell.
- Live keeps its existing `LiveMapView`/camera and recorder-backed route; paging does not reconstruct the native map.
- Review uses the finished snapshot and existing `PostRunSummaryView` route presentation.
- Share existing map surface/geometry helpers, not mutable camera state between screens. Replacing map renderers is outside this behavior-preserving extraction.
- Today and Group use the same `RecordView` adapter and flow implementation. Preserve embedded Today and immediate standalone Group launch, permission prompts, and return destinations.
- Current Group detail owns a standalone flow presentation; Today retains its own flow. Moving both to one app-owned session and changing conflict/return routing is a separate navigation migration, not claimed as implemented here.

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

- No tests authorized; do not run unit/UI suites.
- Manual device verification must be reported separately: a build does not verify GPS, camera, Watch, audio, map gestures, or visual transitions.
