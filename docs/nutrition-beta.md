# iPhone Nutrition beta

Open when changing workout food guidance, local food logs, or their privacy boundary.

## Scope

- iPhone first: Me exposes a normal Nutrition library row after My Routes, keeping the profile first. It opens the date-first food diary for any signed-in account, with no plan or workout requirement. Today has no standalone Nutrition map card in any launch mode. Its expanded planned-workout footer offers a compact Nutrition action beside Plan and Change. Compact Food & fueling actions remain in planned/scheduled workout details, the saved-activity celebration (including its post-save stretch variant), and private saved-activity details. No forced prompt interrupts saving an activity.
- Before/During/After cards use readable advice text with an optional natural-color, 52-point cutout photo trailing it. No tile or image column is reserved for short During or general Before/After. The unchanged duration selection pairs each existing action key with its photo: toast/banana before, yogurt/fruit after, drink for medium/general During, portable food/drink for long During. Accessibility text sizes reflow the tiny photo below the advice. Photos preserve aspect/alpha and are decorative; localized text conveys the meaning. Stage actions open blank editable food drafts with exact workout/phase preselected. Suggestions never become intake without Save; diary entries do not influence guidance yet. During advice remains qualitative within the AIS endurance framework.
- Before-workout guidance uses the displayed intent or effective scheduled workout. After-workout guidance uses the saved activity. Running, cycling and swimming are supported endurance contexts; absent/unsupported sport or nonpositive/missing duration uses general advice. Scheduled workouts require explicit supported modality.
- `NutritionAdvice.ruleVersion = qualitative-v1` selects qualitative editorial advice. Before: under 45 minutes, 45–89 minutes, or at least 90 minutes. After: recovery food examples plus timing context. The thresholds organize advice, not clinical eligibility or precision.
- No individual dietary assessment, calculated nutrients, calorie replacement, weight-loss targets, hydration/sodium doses, or athlete carbohydrate/protein doses. Adult eligibility is not established, so guidance stays qualitative. No accuracy percentage or dietitian validation is claimed.
- Android, cloud sync, food database lookup, live fueling reminders and full diet planning are deferred.

## Finding Nutrition

- Only the diary destination header carries the localized amber/dark Beta corner ribbon. Entry controls have no ribbon or reserved ribbon footprint: workout entries are content-sized secondary Food & fueling actions; Me uses a whole-row library entry with a fork icon, title, subtitle and chevron. The entire library row is tappable.
- The journal has one main Add action, meal sections, compact actual-food records and an explicit date/history/workout scope. Meal choice remains in the editor. A separate workout-context row opens guidance; an associated record's compact workout link opens its precise stored guidance snapshot. Empty and plan-free diaries are normal.

- Before a workout: on Today, use Nutrition in the expanded planned-workout footer to open guidance directly for the displayed intent (including custom or calibration context). Food diary opens its exact linked-record scope. The title still opens Details with Food & fueling; scheduled workout details retain the same action. The account/calendar/workout snapshot is captured on tap, with no same-day matching or inferred future date from the Up next label.
- After saving: use Food & fueling beneath the saved activity's sport/time/distance summary, above the celebration card. The same optional entry appears when the saved screen offers stretching; saving does not automatically open Nutrition.
- Later: open your saved activity from your activity history. Food & fueling appears below its title, above photos and statistics, rather than below elevation and splits. Social activity details do not expose it.
- An account-backed sign-in is required. Debug launch flags that bypass authentication without creating a user do not expose Nutrition or enable guest food logging; real debug-persona sessions have an account ID.
- The save flow presents a celebration or stretch screen, then Done closes the flow. It does not open `ActivityDetailView`; placing Nutrition only in saved-activity detail did not make it discoverable immediately after save.

## Provenance and applicability

These foundational references inform editorial rules; they are not independent validation of this feature or new clinical guidelines:

- [Get Active Victoria](https://www.getactive.vic.gov.au/resources/what-to-eat-before-and-after-exercise/): practical pre-exercise carbohydrate and post-exercise carbohydrate/protein food examples. Foods are examples and require individual dietary suitability.
- [Australian Institute of Sport](https://www.ausport.gov.au/ais/nutrition/supplements/group_a/sports-foods2/sports-drink/how-and-when-do-i-use-it): endurance-duration carbohydrate framework. Under 45 minutes generally needs no intra-session carbohydrate; longer endurance sessions warrant preparation. The beta intentionally does not prescribe numeric athlete targets.
- [ACSM / AND / DC, 2016](https://www.dietitians.ca/DietitiansOfCanada/media/Documents/Resources/noap-position-paper.pdf): rapid carbohydrate recovery depends on closely spaced demanding sessions (less than 8 hours). The beta does not infer this condition.
- [ISSN nutrient timing, 2017](https://doi.org/10.1186/s12970-017-0189-4): healthy exercising adults, adequate daily intake and contextual timing. No universal immediate post-workout deadline.

The sheet exposes these sources, assumptions and the rule version under Why this / Sources. Age, pregnancy, illness, allergies, eating concerns and individual dietary needs are not assessed. A concise healthy-adult/general-guidance limitation directs those situations toward individual professional advice.

## Logs and privacy

- Users explicitly record actual food/drink, optional portion and note, consumption time, and breakfast/lunch/dinner/snack. Workout association is optional; workout-origin drafts preselect the exact context and allow unlinking. Before/during/after records timing only, never an inferred performance benefit. Suggestions are never automatically logged. Missing records mean unknown intake, not zero.
- Workout contexts resolve scheduled date labels and planned fallback date keys in the captured account calendar; existing stored snapshots are not remapped.
- Account-calendar date browsing, edit/delete, recent-food editable drafts and all-account-history browsing are available. Repeat never copies the original workout association/date or automatically saves consumption. Entries retain workout title/date plus available sport/duration as a guidance snapshot; “Workout guidance” opens that snapshot, not full workout details. A log retains its original workout title/date and stable linkage. Issued planned and completed workouts share plan-version/slot identity where the performed-workout reference exists; otherwise each source uses its own identity. No same-day fuzzy association is made. All logs remain accessible after plan/day changes through Browse all dates.
- `NutritionLogStore` stores version-1 JSON under Application Support/NutritionLogs-v1, with a SHA-256 filename derived from the account owner. Writes are atomic and use complete file protection. The directory is excluded from device backup. Logs do not synchronize to the backend or appear in social activity detail, sharing or exports.
- A scene-owned stable hosting root captures account/calendar/workout/mode once per opening; entry-button refreshes or responsive-layout candidate changes never replace that root. Store instances capture and validate the account boundary before each operation; an account subscription retained for the complete opening dismisses the root and all nested sheets when identity changes. Sign-out retains each account's separate local history; delete-account explicitly removes that owner's file. Uninstalling also removes local logs. The diary adds optional fields to the same version-1 JSON; existing actual food records remain readable without a reset. Old meal sections use consumption time as a presentation fallback. A future incompatible schema should use a new versioned store and document a reset.
- Decode/load failure preserves the file and disables add/edit/delete controls until a successful reload. Save/delete failure preserves the last successful published state; editor save failure retains the draft. Diagnostics contain only operation and numeric error code.
- Analytics events (`nutrition_beta_exposed`, `nutrition_advice_viewed`, `nutrition_advice_explained`, `nutrition_log_saved`, `nutrition_log_deleted`, `nutrition_journal_viewed`, `nutrition_journal_date_changed`, `nutrition_history_viewed`, `nutrition_food_repeated`, `nutrition_association_changed`) have no feature properties. Food content, portions, consumption timing, health details and workout/account identifiers are excluded.

## Verification

- Build-only compilation and the added-line design-system checker are permitted; no test suite or simulator/emulator checks were requested.
- Source review covers duration boundaries, missing/unsupported context, account isolation, failed reads/writes, explicit actual-consumption save/edit/delete, persisted linkage/history, private/social guards and localized resources.
- Runtime layout, keyboard, Dynamic Type, themes, VoiceOver, device persistence/account switching and real nutrition suitability remain unverified until specifically checked. A successful build is not evidence of runtime or clinical correctness.

### Initial beta verification — 2026-11-16

- Signed iPhone build passed and installed on Bruce main. Launch was blocked by the locked phone; iPhone Mirroring required Mac authentication, so no runtime UX evidence was obtained.
- Independent UX source review found two issues, both corrected: logging controls now wait for a successful storage load, and the main logging action uses the shared primary button. No unresolved source findings remain. The design-system checker and diff check passed; English, Spanish and Simplified Chinese Nutrition resources are present in the signed app.
- UX QA remains **Incomplete** for the runtime checks listed above. Bruce explicitly accepted this documented runtime UX waiver and authorized merge on 2026-11-16. The waiver does not establish runtime correctness or clinical validation. No test suite or simulator/emulator checks ran.

### Saved-workout discoverability — 2026-11-16

- The post-save celebration and stretch offer now expose Nutrition beneath the activity summary. Private saved-activity details place the same entry beneath the title. Account guards, social exclusion, localized labels and property-free analytics remain unchanged.
- Build-only compilation, design-system checks and diff checks passed. Independent UX review found no source issues and returned **Incomplete** because runtime layout, presentation and interaction checks were not performed. No test suite or simulator checks ran.
- Bruce explicitly authorized merge and phone installation with runtime UX QA waived for this revision on 2026-11-16. The waiver does not establish runtime correctness; phone installation is recorded separately from verification.

### Beta corner ribbon — 2026-11-16

- Nutrition entries and the sheet header use a localized diagonal corner ribbon instead of inline Beta text. Existing guidance, logging, privacy, and analytics behavior is unchanged.
- Signed build, design-system checker, and diff checks passed. Installed and launched on Bruce main; no test suite or simulator checks ran.
- Independent UX review found no unresolved source findings after correcting small-text contrast. QA remains **Incomplete** for runtime layout, themes, text scaling, and accessibility checks.
- Bruce explicitly accepted the documented runtime UX QA waiver and authorized merge for this revision. Installation and launch do not establish visual or runtime correctness.

### Date-first journal — 2026-11-16

- Today and Me now expose the diary permanently; workout routes retain exact context. Day, all-date history and exact-workout scopes are explicit. Meal sections, optional portions, repeat drafts and visual stage guidance remain local-only. The shared Beta ribbon uses warm amber with dark ink.
- Bruce explicitly requested installation on Bruce main and **skipped UX verification** for this revision. No independent UX review or runtime UX checks were performed; no QA Pass is claimed. Build/install outcomes are recorded separately. No tests or simulator/emulator checks run.
- Final signed incremental build passed, then installed and launched on Bruce main (2026-11-16, 23:12 Pacific). Added-line design-system checker, diff whitespace check and source localization/privacy checks passed. These results do not establish runtime UX or nutrition suitability. Existing unrelated compiler warnings remain.

### Entry placement and journal density — 2026-11-17

- Removed the standalone Today Nutrition card and its attribution measurement without changing existing planned/manual/live peer layout. Moved Me's entry below My Routes, after the profile and existing plan content. Removed entry ribbon spacers; the amber Beta accent remains on the journal header only.
- Consolidated meal add controls into one main Add action; record actions use a compact menu, and workout links retain title/date/phase and exact stored guidance. Storage, scopes, draft reuse, sources, account/calendar protections and property-free analytics are unchanged. No reset or schema change.
- Bruce authorized the change and phone installation while continuing to **skip UX verification**. No independent/runtime UX review, tests or simulator/emulator checks were performed; no QA Pass is claimed.
- Signed build passed, then the final revision installed and launched on Bruce main on 2026-11-17 at 06:51 Pacific. Added-line design-system and diff checks passed; source checks confirmed complete EN/ES/zh-Hans strings, unchanged model/storage and guidance/editor logic, one destination ribbon, and no standalone Today card. This does not establish runtime layout or accessibility correctness.

### Planned-card Nutrition action — 2026-11-17

- Expanded planned-workout footers contain content-sized Plan, Change and Nutrition actions, reflowing vertically when their natural widths do not fit. They are separate from title/collapse controls; rest-day, minimized, manual and live layouts retain their existing behavior.
- Nutrition opens guidance as the initial content of the existing protected presentation, without an automatic second sheet. Food diary opens exact linked records; phase log actions keep the same account-owned editor and explicit Save. Existing Me/Details routes, qualitative rules, local schema and property-free analytics remain unchanged. Guidance logging waits for successful local load.
- Bruce continued to skip UX verification and authorized phone installation. No tests, simulator/emulator or independent/runtime UX checks were performed; no QA Pass is claimed.
- Signed build passed and the final source installed and launched on Bruce main on 2026-11-17 at 07:01 Pacific. Added-line design-system, diff and source preservation/localization checks passed. Installation and launch do not establish runtime UX correctness.

### Stable presentation ownership — 2026-11-17

- Bruce reported that Nutrition guidance jumped and reset while scrolling. Source audit found per-entry SwiftUI sheet state duplicated inside the planned footer's `ViewThatFits` candidates, rather than a durable presentation owner. This is the same ownership risk addressed earlier by Curated Workouts; source evidence does not prove the exact runtime trigger.
- Entries now request one scene-owned hosting lifetime, using the shared stable-sheet primitive also used by the existing curated presenter. Context, calendar, protected store, scroll/disclosure state and editor drafts remain in that opening; explicit guidance-to-diary switching remains intentional. Appearance changes still propagate. Account invalidation closes the entire private modal tree, including an editor, even if the source entry disappears.
- The general ownership/extension contract and bounded audit are in `docs/ios-architecture.md`. No schema, nutrition rules, new strings or analytics payloads change. Bruce continued to skip independent/runtime UX verification; no tests or simulator/emulator checks were run, and no QA Pass or runtime regression fix is claimed. Phone installation enables Bruce's own confirmation.
- Final signed incremental build passed and installed/launched on Bruce main on 2026-11-17 at 07:13 Pacific. Design-system, diff and source preservation/lifecycle checks passed. The installed source includes opening-scoped account invalidation and late-callback guards. Scrolling, interactive cancellation, themes and account-switching runtime behavior were not independently verified under the requested UX skip.

- Completing a planned workout retains Nutrition in the Today card footer and scheduled workout details. Completed Today guidance captures the retained scheduled prescription, date label and slot identity instead of the inactive recording setup intent. Plan and completed-activity navigation remain available; completion only hides Change.

### Food illustration matching — 2026-11-19

- Replaced the carrot, bottle-only and takeaway glyphs with small native vector scenes that match the selected advice. Text keys and scenes share one selection so the unchanged 45/90-minute bands cannot choose mismatched visuals. No advice wording, qualitative rules, portion prescription, logging, privacy, navigation or stable-sheet ownership changed. Property-free analytics remain unchanged because this is decorative presentation only; no new strings.
- Source mapping checks cover missing/nonpositive duration, unsupported sport and both duration boundaries. Independent UX review is dispatched in parallel under the current nonblocking policy; its status and any unchecked visual/runtime behavior are reported separately. No tests or simulator/emulator checks were requested.
- Final signed build passed and installed on Bruce main on 2026-11-19 at 20:05 Pacific. Automatic launch was denied because the phone was locked (`FBSOpenApplicationErrorDomain` code 7); installation is complete, but launch is not confirmed. Design-system, diff and source-preservation checks passed.
- Parallel independent UX review of the frozen source and static shape contact sheet returned **Incomplete**, with no actionable findings. The contact sheet uses stub theme values for illustration recognizability, not the app environment. Full-app layout, actual themes, Dynamic Type, VoiceOver and interaction/runtime behavior were not checked; no QA Pass is claimed.

### Compact photo guidance — 2026-11-20

- Replaced the vector tiles with four original-color photo cutouts. Short sessions and unsupported general meal contexts have no image and use the full text width. Advice wording/thresholds, local records, protected account/calendar snapshots, stable sheet ownership and navigation are unchanged. Photos are food examples, not serving-size prescriptions or logged intake.
- Each stage has a compact Why this / Sources and Log footer that reflows vertically when needed. Expansion state is keyed by phase, preserving source/rationale content; phase expansion now emits the existing property-free `nutrition_advice_explained` event. Log retains the full accessible action name, opens the exact-context/phase draft and remains disabled before local load. Log and expansion states are localized in English, Spanish and Simplified Chinese.
- Shared `OutboundPrimaryButton.compact` provides a small content-sized visual with a label-internal 44-point hit target. Default button styling is unchanged. Compact text uses the theme’s action-fill contrast foreground; source calculations cover all eight themes in light/dark, with a minimum selected contrast of 4.93:1.
- Independent UX review runs in parallel against the frozen revision. No tests, simulator/emulator or runtime app checks were requested; build/install/review outcomes are recorded separately.

#### Photo asset provenance

- Generated with the built-in `image_gen` tool using `transparent_background=true`; originals were copied byte-for-byte, without image edits. Asset catalog paths are under `ios/Outbound/Outbound/Assets.xcassets/` with original-color rendering. The approved screen preview and generation metadata are not bundled.
- Common exact generation prompt:

> Use case: product-mockup. Asset type: a genuine transparent-background photo cutout for a tiny 52-point iPhone nutrition thumbnail. Square composition. High-quality realistic editorial food photography, natural colors and fine real texture, softly lit from upper left, slightly elevated three-quarter camera. Subjects large and tightly composed within frame with small safe margin, entirely visible and no cropping. Transparent alpha everywhere outside the subject, NO background, no fake transparency checkerboard, no backdrop tile, no ground plane or big shadow. Clean premium food photo, not illustration, not 3D render, not icon, not emoji. No text, no logos, no packaging branding, no decoration, no gold tint.

Each request appended `Subject: ` plus its subject below:

| Asset path | Subject |
| --- | --- |
| `nutrition_toast_banana.imageset/nutrition_toast_banana.png` | One small slice of golden-brown toasted bread on the left and one small ripe yellow banana on the right, close together as one compact balanced composition. No butter, jam, toppings, plate or cutlery. |
| `nutrition_yogurt_fruit.imageset/nutrition_yogurt_fruit.png` | One small off-white ceramic bowl containing plain white yogurt with a few blueberries and two strawberry slices on top. Bowl seen slightly from above so yogurt and fruit are visible. No spoon, placemat, extra fruit outside bowl or other props. |
| `nutrition_drink.imageset/nutrition_drink.png` | One simple clear drinking glass half filled with clear water. Crisp subtle glass contours, rim, realistic highlights and refraction remain legible on light or dark app backgrounds. No ice, straw, lemon, condensation clutter or other objects. |
| `nutrition_portable_food_drink.imageset/nutrition_portable_food_drink.png` | One small unbranded oat-and-fruit snack bar, partly wrapped in minimal plain neutral paper, next to one simple clear drinking glass half filled with clear water. Compact close grouping, bar on left and glass right, both entirely visible. No readable labels, brand marks, plate, fruit garnish or other props. |

- Final signed build passed and installed on Bruce main on 2026-11-20 at 18:20 Pacific. Automatic launch was denied because the phone was locked (`FBSOpenApplicationErrorDomain` code 7); installation is complete, launch is not confirmed. Design-system/diff/source checks passed; all four PNG copies match the generated originals byte-for-byte and contain genuine 0–255 alpha. Isolated 52-point thumbnail rendering on light/dark backgrounds confirmed recognizable clean cutouts; this is asset evidence, not an app screenshot.
- Parallel independent UX review of the exact frozen source/assets returned **Incomplete**, with no actionable findings. It independently confirmed the 4.93:1 minimum compact-label contrast across sixteen theme/appearance pairs. Full-app layout, themes, Dynamic Type, VoiceOver and interaction/runtime behavior were not checked; no QA Pass is claimed.
