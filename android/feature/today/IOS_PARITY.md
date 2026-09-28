# Today iOS Parity

## Authority And Counterparts

- iOS shell and contextual center action: `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift`
- Android shell: `android/app/src/main/kotlin/com/plainstride/outbound/PlainstrideApp.kt`
- Android Today surface: `TodayScreen.kt`
- iOS weather store: `ios/Outbound/Outbound/Integrations/Weather/SituationalWeatherStore.swift`
- Android weather adapter: `android/core/weather`
- iOS embedded activity controls: `ios/Outbound/Outbound/Activity/RecordView.swift` (`launchDock`, `launchWorkoutButton`, `launchGoalPill`)
- Android activity controls: `TodayScreen.kt` (`ActivityLaunchDock`, `ChoiceButton`, `GoalPill`)

## Current Contract

- The bottom navigation is a compact floating capsule with a separate, identically surfaced assistant action.
- On Today, the center item becomes the icon-only Start action and launches the activity currently prepared in the Today dock; the dock renders neither a second start button nor a full-width Return to Run button. During an active session it remains Today.
- Weather, inbox, overflow, and assistant controls use opaque elevated surfaces so the map cannot reduce icon contrast.
- The weather pill shows a localized on-device city or region when Android geocoding can resolve one, followed by temperature. Weather remains usable when naming is unavailable.
- Outdoor Today shows the same localized “Enable location” chip as iOS when location is unavailable. Tapping it or the weather pill opens the shared location explanation; Enable requests location the first time and opens app settings after a prior denial. Returning from settings refreshes weather when access was granted. Indoor activity hides the location chip.
- Existing workout-start and assistant-launch analytics cover the contextual actions; no coordinates or place names enter analytics.
- Manual calorie goals show estimated distance and duration when the training profile has enough data, using the shared calorie estimator and learned run pace.
- Embedded Today sport choices are 52-point circular icon-only controls with accessible sport names. Setup options (Voice Guide, With dog, Cheer, Shoes, and Indoor/Outdoor) are text-only pills. The Music pill is temporarily hidden while Android music UX is evaluated; the existing music destination remains available from Settings.
- With dog is available for eligible manual sports and eligible planned run, walk, or bike workouts; its context is passed into recording for both launch paths.

## States Covered

- Planned and manual activity configurations
- Active session and idle session
- Weather loading, available with or without place name, cached, permission-required, and unavailable
- High-contrast numeric Notification Center badge, locally cleared when the center opens, and overflow photo preview

## Verification

- Build-only gate: `./gradlew :app:assembleDebug`
- Manual visual comparison remains required across supported themes, locales, font scales, and phone sizes.

## Approved Exceptions

- None.
