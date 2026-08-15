# Localization QA

Open this for rendered-app localization findings and release blockers. The supported-language contract lives in `localization.md`.

## 2026-08-13 Simulator Pass

- Localization revision tested: `1a2e329`, immediately before merge to `main` in `b7250b5`.
- Device: iPhone 17 Pro simulator, iOS 26.5.
- Locales: Spanish (`es_ES`) and Simplified Chinese (`zh_CN`).
- Surfaces inspected: authentication, Today, Together empty and populated states, Me with seeded history, Settings, profile editor, activity setup, active and paused activity, post-run summary, and activity detail.
- Data mode: offline UI-test session with one saved activity. Authentication was separately inspected without the test-session bypass.
- Remaining coverage: authenticated onboarding, full activity-history and Progress screens, cycle-aware coaching, gear, safety/live sharing, music, assistant sheets, Dynamic Island, App Intents UI, and on-device speech recognition/synthesis.

## 2026-08-13 Simplified Chinese Rerun

- Revision: `fbc88f0`, including terminology refinement `b955b5f`.
- Build: `OutboundAppTests` compiled successfully with the app and embedded Live Activity extension.
- Rechecked: authentication, Today completed state, populated Together, Me with seeded history, and activity setup.

Confirmed improvements:

- The authentication slogan now reads `在训练中找到自我。和伙伴一起奔跑。` and renders naturally without clipping.
- `Companion insight` now renders as `同伴洞察` instead of `同伴洞察力`.
- Invite actions now use the concise `邀请`.
- The selected Chinese product name `平步青云` renders consistently on the sign-in screen.

Remaining blockers:

- Authentication buttons remain `Continue with Apple` and `Continue with Google`.
- Authentication orbit labels remain `Family`, `Friends`, `You`, and `Groups`.
- Today, Me, Together, and activity setup still contain the English model/helper strings listed under L10N-001.
- Together translates `UP NEXT` as `上一个`, which means “previous” and reverses the schedule meaning. Use a product-reviewed equivalent such as `接下来`.
- Together headings `你的俱乐部` and `最近的` are understandable but read like literal fragments and need native UX review.
- `Quick start` remains `快速启动`, which still reads like starting software or a device.
- The location permission prompt still appears in English when only process launch arguments select Chinese; device/per-app language verification remains required.

## 2026-08-14 Today Runtime-String Fix

- Routed the rotating Today inspiration headline and message through the String Catalog.
- Localized the Today primary `Start run` action and the built-in easy-run title, explanation, and phase labels.
- Added a catalog lookup boundary for app-authored workout titles, explanations, and phase labels arriving through Today models. Unknown server- or user-authored text remains unchanged.
- Changed the completed-activity stat labels to use localized keys instead of display-ready `String` values.
- Added reviewed Simplified Chinese and Spanish translations for every Today phrase activated by this change.
- Build-only simulator compilation passed. Rendered device verification remains required.

## 2026-08-14 Social Localization Pass

- Added context-written Spanish and Simplified Chinese translations for Social navigation, empty states, connections, groups, invitations, notifications, comments, accessibility actions, and activity-feed controls.
- Simplified Chinese uses running-specific terms such as `跑友`, `跑团`, `最新动态`, and the approved phrase `一起跑，更精彩`; Spanish uses natural community and running-event language rather than literal word substitutions.
- Localized runtime counts, conditional actions, group roles, stat labels, and share messages that previously bypassed the catalog.
- User-authored names, group descriptions, captions, and server-authored notification text remain unchanged by design. Server-generated compatibility explanations still require locale-aware backend content.

## Release Blockers

### L10N-001 — Primary journeys contain mixed English

Severity: Blocker

Both translations render English app-authored content inside localized screens.

- Today: the reported rotating inspiration, `Start run`, built-in easy-run card, and fallback workout-step names are fixed in code. Remaining risk is backend-generated workout prose, `Location access is off...`, and uncataloged accessibility content.
- Together: local navigation, roles, counts, metric labels, actions, empty states, and share copy are fixed in code. Remaining risk is offline/server error text and generated compatibility explanations.
- Me: plan title/detail, learned-insight values, `Distance`, `Time`, and the weekly companion sentence.
- Profile editor: `Profile could not be loaded.`
- Activity setup: `Freestyle run`, `Run • no preset target`, coach quote, goal choices, `Start now`, `Music`, and `Run options`.
- Live activity: `No photos captured`, activity title/status, `Pace`, `Avg. pace`, and `HR`.
- Post-run: recognition titles/explanations, `completed`, `Distance`, `Time`, and `Elev Gain`.
- Activity detail: `Distance`, `Avg Pace`, `Moving Time`, `Elev Gain`, `Max Elevation`, `Avg HR`, and `Recorded in Plainstride`.

Most failures are display-ready strings produced by models, fixtures, API/offline state, or helper properties rather than absent catalog values.

### L10N-002 — Brand and provider marks are translated

Severity: Blocker

- Spanish renders `PLAINSTRIDE` as `PASO LLANO`.
- Simplified Chinese renders it as `Plainstride青云`.
- Spanish renders the Google `G` mark as `GRAMO`.

Mark these entries non-translatable and preserve the marks verbatim.

### L10N-003 — Authentication actions remain English

Severity: Blocker

`Continue with Apple` and `Continue with Google` remain English in both supported translations.

### L10N-004 — Permission prompt did not follow process locale

Severity: High; confirmation required

The Spanish launch-argument run displayed the location permission explanation and system buttons in English while app content rendered in Spanish. Repeat with the Simulator device language or iOS per-app language changed through Settings; process arguments may not control SpringBoard-owned permission UI.

## Translation Quality

### L10N-005 — Spanish terminology needs native review

Severity: High

- Running-equipment `Gear` becomes `Engranaje`, a mechanical gear. Prefer product-reviewed running terminology such as `Equipo`.
- Profile tab `Me` becomes `A mí`, which is unnatural as a tab label.
- Together section `UP NEXT` becomes the literal `ARRIBA SIGUIENTE`; use natural schedule language such as `A continuación`.
- Protected brand/provider terms were translated.

### L10N-006 — Simplified Chinese terminology needs native review

Severity: High

- `Quick start` becomes `快速启动`, a software/device-start phrase.
- `Companion insight` was improved from `同伴洞察力` to `同伴洞察` in `b955b5f`.
- Confirm whether profile-tab `我` should use a profile-specific label.
- Chinese accessibility sentences contain English workout fragments.

## Formatting And Accessibility

### L10N-007 — Accessibility output repeats mixed-language defects

Severity: High

Complete labels and hints expose untranslated workout summaries, companion hints, activity setup copy, live metrics, and recognition text. Localize complete accessibility sentences instead of concatenating visible fragments.

### L10N-008 — Sampled locale formatting passes

Severity: Pass in sampled scope

- Spanish showed decimal commas and `28 abr 2024`.
- Simplified Chinese showed decimal points and `2024年4月28日`.
- User-authored seeded title `UI Test Route Activity` remained unchanged.
- Seeded club, person, run, activity, and caption names remained unchanged; this is correct for server/user-authored content. Server-generated compatibility prose and semantic club roles still need locale-aware contracts.

## Catalog Audit

- Main app catalog has localized Spanish and Simplified Chinese values for every non-empty key.
- InfoPlist catalog has values for all 12 entries in all supported locales.
- App Shortcuts catalog has six localized phrase sets per supported locale.
- Catalog completeness does not prevent model- or server-originated English from reaching localized screens.

## Automated Verification

- `OutboundAppTests` scheme compiled successfully after localization merged into `main`; this builds the app and embedded Live Activity extension resources.
- The four-scenario English app regression runner passed after the merge in 67.25 seconds: launch/auth bypass, seeded primary navigation, recording/post-run lifecycle, and launch performance.
- All checked string catalogs parse as JSON. The catalog audit and rendered passes found translation defects, not resource-loading or compilation failures.

## Next Pass

1. Protect brand/provider strings and localize authentication actions.
2. Convert listed model, offline, error, recognition, and metric strings to semantic localized resources.
3. Add locale-aware UI tests with stable accessibility identifiers for every primary state.
4. Re-run Spanish and Simplified Chinese with metric and imperial units and zero/one/two/large counts.
5. Retest permission prompts using device/per-app language settings.
6. Complete the remaining screen, Dynamic Island, App Intent, and physical-device speech matrix.
7. Obtain native-speaker review before release.
