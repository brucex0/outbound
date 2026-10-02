# Progress iOS Parity

Open this when changing Android Progress calculations, evidence, surfaces, or analytics.

## Authority And Counterparts

- iOS calculation authority: `ios/Outbound/Outbound/Progress/ProgressStatsEngine.swift`.
- iOS screen and saved-activity normalization: `ios/Outbound/Outbound/Progress/ProgressView.swift`.
- Android calculations: `ProgressStatsEngine.kt`; presentation: `ProgressScreen.kt` and `ProgressRoute.kt`.
- Android activity facts come from the complete local Room activity history through `ActivityRepository.observeAll`; route distance, measurable goal completion, and HR-zone seconds are normalized in `P0IntegrationViewModel`.
- Localized copy is owned by `Localizable.xcstrings` entries marked `[android:progress]` and generated into this feature's English, Spanish, and Simplified Chinese resources.

## Journeys And States

- Empty history: first-activity explanation; no tabs or fabricated values.
- Saved history: `Now`, `Trends`, `Insights`, and `Records` tabs.
- The four tab labels stay on one line in a horizontally scrollable row on narrow screens.
- Gear management is outside Progress and lives in Me → Settings → Gear, matching the iOS product boundary.
- `Now`: current week, matched week delta, top supported insight, recent activity stats.
- Me entry point: the `This week` header's localized `View insights` action opens Progress and records the existing `progress_surface_opened` event with `entry_source=me`.
- `Trends`: matched current/prior week and month, rolling 28-day comparison, sport selector, 4W/3M/6M/1Y selector, and distance/time/count/elevation/pace selector.
- `Insights`: deterministically ranked evidence cards, confidence, supporting figures, bounded next step, and evidence-based empty state.
- `Records`: running-only best efforts, PR history, and race predictions.
- Activity feed is local-first and includes all locally saved rows, including offline rows; stale/removed rows follow Room tombstones.

## Contract Coverage

- Shared rules: ignore sessions of 60 seconds or less; matched elapsed calendar periods; 28-day and trend windows; running-only best efforts, PRs, and predictions; HR efficiency, load ramp, and zone-balance gates; measurable-goal tolerance; preferred-time sample thresholds; confidence and ranking.
- Insights remain deterministic and on device. Analytics emits only `progress_surface_opened`, `progress_control_changed`, and `progress_insights_exposed` with bounded values and count buckets.
- TalkBack labels are provided for controls, charts, and accessible cards; controls use Compose semantics and system font scaling.

## Reference Scenarios

- Empty account; one activity; mixed-sport history; no route; route-based efforts; missing HR; complete HR zones; measurable and freestyle goals; offline-only local activity; week/month boundary; all trend ranges and metrics; all eight insight categories; metric and imperial display.
- Compare iOS and Android with the same saved-activity fixture in English, Spanish, and Simplified Chinese, light/dark themes, and enlarged text.

## Status

- Implementation: complete for the documented Progress journey and calculations.
- Verification: build-only compile required; visual/device reference comparison remains a release acceptance step.
- Approved exceptions: none.
