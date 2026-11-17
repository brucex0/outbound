# iPhone Nutrition beta

Open when changing workout food guidance, local food logs, or their privacy boundary.

## Scope

- iPhone first: Nutrition · Beta appears in Today planned-workout details, scheduled-workout details, the saved-activity celebration (including its post-save stretch variant), and private saved-activity details. No forced prompt interrupts saving an activity.
- Before-workout guidance uses the displayed intent or effective scheduled workout. After-workout guidance uses the saved activity. Running, cycling and swimming are supported endurance contexts; absent/unsupported sport or nonpositive/missing duration uses general advice. Scheduled workouts require explicit supported modality.
- `NutritionAdvice.ruleVersion = qualitative-v1` selects qualitative editorial advice. Before: under 45 minutes, 45–89 minutes, or at least 90 minutes. After: recovery food examples plus timing context. The thresholds organize advice, not clinical eligibility or precision.
- No individual dietary assessment, calculated nutrients, calorie replacement, weight-loss targets, hydration/sodium doses, or athlete carbohydrate/protein doses. Adult eligibility is not established, so guidance stays qualitative. No accuracy percentage or dietitian validation is claimed.
- Android, cloud sync, food database lookup, live fueling reminders and full diet planning are deferred.

## Finding Nutrition

- Before a workout: on Today, tap the planned workout title to open Details, or open a scheduled workout from the plan details page.
- After saving: use Nutrition · Beta beneath the saved activity's sport/time/distance summary, above the celebration card. The same optional entry appears when the saved screen offers stretching; saving does not automatically open Nutrition.
- Later: open your saved activity from your activity history. Nutrition · Beta appears below its title, above photos and statistics, rather than below elevation and splits. Social activity details do not expose it.
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

- Users explicitly record actual food/drink, optional portion/note, consumption time, and before/after relation. Suggestions are never automatically logged. Missing records mean unknown intake, not zero.
- Entries support edit/delete and all-account-history browsing. A log retains its original workout title/date and stable linkage. Issued planned and completed workouts share plan-version/slot identity where the performed-workout reference exists; otherwise each source uses its own identity. No same-day fuzzy association is made. All logs remain accessible after plan/day changes through Show all my food logs.
- `NutritionLogStore` stores version-1 JSON under Application Support/NutritionLogs-v1, with a SHA-256 filename derived from the account owner. Writes are atomic and use complete file protection. The directory is excluded from device backup. Logs do not synchronize to the backend or appear in social activity detail, sharing or exports.
- Store instances capture and validate the account boundary before each operation; account changes dismiss the presentation. Sign-out retains each account's separate local history; delete-account explicitly removes that owner's file. Uninstalling also removes local logs. There is no migration: a future incompatible schema should use a new versioned store and document a reset.
- Decode/load failure preserves the file and disables add/edit/delete controls until a successful reload. Save/delete failure preserves the last successful published state; editor save failure retains the draft. Diagnostics contain only operation and numeric error code.
- Analytics events (`nutrition_beta_exposed`, `nutrition_advice_viewed`, `nutrition_advice_explained`, `nutrition_log_saved`, `nutrition_log_deleted`) have no feature properties. Food content, portions, consumption timing, health details and workout/account identifiers are excluded.

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
