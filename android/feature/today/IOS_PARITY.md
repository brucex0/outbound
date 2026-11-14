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
- The planned workout card shows weather guidance without provider metadata. The weather pill opens details with the linked MET Norway attribution, matching iOS's placement of Apple Weather credit in its weather details.
- The expanded planned-workout card exposes “Warm-up exercises” only for a running suggestion while recording is idle. The row shows the calculated Today routine duration, including saved customizations, and opens the existing Today stretch destination without starting or completing an activity. It emits `feature_exposed` with only `feature=planned_workout_warmup` and `result=opened`.
- The planned-workout card’s pencil + Change action opens the one-day adjustment sheet and emits `planning_surface_opened` with `source_type = workout_change` and `entry_source = today_planned_card_change`. Overall plan replacement remains in plan details.
- Change matches iOS's three reasons and reason-specific second page: Less time selects 10/15/20 minutes (15 default), Low energy offers 15 minutes easy, and Sore or uncomfortable offers rest. Notes trim to optional content. Apply dismisses immediately and submits readiness; time/energy prepares a separate easy time-targeted run without inherited steps, distance/calorie goals, a planned-workout link, or a selected route. Soreness only submits readiness. Failed check-ins persist in the existing account cache and retry on Today refresh. A pending personalization proposal takes priority over reasons; either decision dismisses immediately, then successful decisions clear it and refetch plan/personalization. Keep original/Close submits nothing.
- Opening the planned-workout card shows a Details sheet with the workout title and duration, compact preview of up to three phases, the workout rationale, and Change workout. Change workout opens the one-day adjustment flow; starting remains on the Today dock. The detail open emits `planning_surface_opened` with the same bounded source and entry-source values as iOS.
- `today_weather_details_opened` and `weather_attribution_opened` record only the control source; they contain no place name, coordinates, or forecast text.
- Outdoor Today shows the same localized “Enable location” chip as iOS when location is unavailable. Tapping it or the weather pill opens the shared location explanation; Enable requests location the first time and opens app settings after a prior denial. Returning from settings refreshes weather when access was granted. Indoor activity hides the location chip.
- Existing workout-start and assistant-launch analytics cover the contextual actions; no coordinates or place names enter analytics.
- Manual calorie goals show estimated distance and duration when the training profile has enough data, using the shared calorie estimator and learned run pace.
- Distance, Time, and Calories goal dialogs replace their title with the localized `Pause at goal` checkmark option. The entire checkmark row owns one accessible touch target at least 48 dp tall. Like iOS, toggling saves the off-by-default preference immediately; Done also closes the editor without requiring a custom target. Reopening restores the checkmark, and the collapsed goal card shows the pause hint. The choice travels with the session and pauses once when the target is reached; Freestyle, Curated, Planned, and Race are ineligible. The runner may resume or finish.
- Embedded Today sport choices are 52-point circular icon-only controls with accessible sport names. Setup options (Voice Guide, With dog, Cheer, Shoes, and Indoor/Outdoor) are text-only pills. The Music pill is temporarily hidden while Android music UX is evaluated; the existing music destination remains available from Settings.
- Selecting Planned with no active plan opens the reusable plan builder with `planned_button` attribution. When a plan exists, Planned keeps the current suggestion selection and start flow.
- A confirmed scheduled rest day reuses the planned-workout card shell, with the planned-workout overline and “No workout scheduled today” title, no workout-details click target or collapse control, and an always-visible compact Plan action inside the card. Expanded planned cards use the same Plan label and calendar icon; minimized planned cards follow iOS by omitting the footer. Pending-workout, loading, and other rest-recommendation states keep Plan access within their existing card in Planned mode while plan details are available or still resolving. Unavailable/no-suggestion states have no Today Plan entry because the offline/retry card was removed. Confirmed no-plan states retain the setup card without a Plan action. Manual modes do not gain a Plan footer. When the group activity card takes priority, it includes a compact Plan action within its surface when a plan or recommendation is available. Tapping planned Start on scheduled rest shows the localized “No workout scheduled today” toast and never starts a workout. Other rest recommendations retain their separate safety card and existing blocked-start behavior. Planned Start is blocked while rest is recommended or its prescription is unavailable for an active plan. Pending planned starts compare the complete suggestion, including same-ID personalization changes, before setup, after permission/GPS preparation, and through countdown to the recording command. Invalidated preparation returns to Today; a recording whose start command was already issued remains open. `workout_started` is emitted only once the recording command is issued, including changed runs.
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
