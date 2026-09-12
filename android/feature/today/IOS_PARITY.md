# Today iOS Parity

## Authority And Counterparts

- iOS shell and contextual center action: `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift`
- Android shell: `android/app/src/main/kotlin/com/plainstride/outbound/PlainstrideApp.kt`
- Android Today surface: `TodayScreen.kt`
- iOS weather store: `ios/Outbound/Outbound/Integrations/Weather/SituationalWeatherStore.swift`
- Android weather adapter: `android/core/weather`

## Current Contract

- The bottom navigation is a compact floating capsule with a separate, identically surfaced assistant action.
- On Today, the center item becomes the icon-only Start action and launches the activity currently prepared in the Today dock; the dock renders neither a second start button nor a full-width Return to Run button. During an active session it remains Today.
- Weather, inbox, overflow, and assistant controls use opaque elevated surfaces so the map cannot reduce icon contrast.
- The weather pill shows a localized on-device city or region when Android geocoding can resolve one, followed by temperature. Weather remains usable when naming is unavailable.
- Existing workout-start and assistant-launch analytics cover the contextual actions; no coordinates or place names enter analytics.
- Manual calorie goals show estimated distance and duration when the training profile has enough data, using the shared calorie estimator and learned run pace.

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
