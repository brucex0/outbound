# Activity Launch and Live Run UX

Open this when changing the Today launch dock, activity goal selection, countdown, or live-run controls. The clickable reference is `docs/prototypes/activity-start-live-wireframe.html`; the production flow is implemented in `RecordView.swift`, `ActivityGoal.swift`, `LiveMapView.swift`, and `CameraHUDView.swift`.

## Navigation Decision

The launch surface is the Today page itself; there is no separate start-activity setup page. Reuse the center Today position contextually while retaining the production icons, order, labels, and theme tint.

- On Today, the center control becomes an orange play icon with the visible label `Start` and a goal-specific accessibility label.
- On Social or Me, the same position shows the normal Today icon and label; tapping it returns to Today.
- Social and Me hide the launch dock. Returning to Today restores the same retained activity setup without navigating through another screen.
- The primary tab bar remains hidden during countdown, live recording, camera capture, and post-run completion.

## Launch Dock

Use one fixed, flat two-row control area at the bottom of Today. Workout choices occupy a horizontal scrolling row. The second row keeps launch settings in a full-width horizontal scroller with roomy fixed-width controls so compact phones do not compress labels or tap targets. A top-right overflow menu owns the pre-activity Photo and Find Route actions. Before capture its label is the standard ellipsis; after capture the label becomes a circular photo thumbnail with a small ellipsis badge so both photo state and menu behavior remain clear. The Today navigation controls, app shell, and bounded map background remain permanent. The map extends behind the transparent navigation bar to the screen top, then ends at the dock boundary; it never becomes the full-screen app surface.

For discoverability, a compact popover points to the overflow control on at most two Today visits. It names Photo and Routes, disappears when Today or idle setup is left, and is permanently suppressed after `Got it` or either menu action. Modal actions wait for the popover dismissal to complete so the two presentations never overlap. Its exposure uses the existing privacy-safe `feature_exposed` event without route names, photo content, or other private values.

The workout row contains `Planned`, `Run`, `Walk`, `Hike`, and `Bike`. `Planned` represents the recommendation itself rather than one sport, so a recommended walk remains a planned walk. Manual sports come from one extensible supported-sports list so future workout types can join without changing the selector contract. Selecting a manual sport builds the corresponding activity intent and preserves the user's manual goal when switching between sports.
The selected route is an independent setup choice: switching between Planned and manual workout types, or choosing a different planned workout, rebuilds the workout intent while retaining the route and its map preview. Only the explicit Remove Route action clears it.

For a manual sport, a separate horizontal row of compact text-only pills floats immediately above the dock: `Free`, `Distance`, `Time`, and `Calories`. This row is hidden for `Planned`; planned workouts already define their own structure and target. `Free` records without a target, while Distance, Time, and Calories record toward one explicit target. The target modes use their compact information card in the map region, and Free has no information card.

Planned renders the existing Today card and Up Next implementation as a standalone peer-card stack above the dock; it must not use a page-sized scroll container that intercepts touches outside the cards. The Planned card opens the workout picker when tapped. The Distance, Time, or Calories card opens a small anchored chooser with one row of presets and a custom input. Do not use a dimmed full-height sheet for goal values. Settings controls render only their icon and localized title; the floating Photo action is intentionally icon-only and keeps a localized accessibility label and state value. The floating goal controls are text only. Current values remain available through configuration state, the goal card/editor, and accessibility. The dock has no grabber, expansion state, setup heading, or second setup screen. The assistant uses the same shell-owned bottom-leading screen position as on Social and Me, mirrored by Photo at bottom-trailing on Today.

Learn a different manual goal default only after the same mode reaches live recording for three consecutive activities. Exploratory taps and canceled countdowns do not count. Store this preference locally and keep every mode available; selecting a workout or goal never starts the activity.

Configure launch options from the dock:

- Music, Live Track, and Shoes use compact icon-plus-label controls that open focused overlays and return the chosen value to the dock.
- The current `Indoor` or `Outdoor` choice and Voice Guide use the same icon-plus-label treatment and toggle directly. Voice Guide defaults on for a new install and continues to honor an existing saved choice.
- Photo stays outside the settings scroller in the top-right overflow menu. Before capture its menu action opens the camera; afterward the toolbar label becomes the captured thumbnail and the menu action opens the preview with Retake and Remove.
- Find Route uses the same overflow menu. Selecting a route fits its full highlighted polyline on the Today map, shows start/finish markers, and replaces the planned peer card with a compact route name/distance card offering Change and Remove. The menu action changes from Find Route to Change Route while selected.
- Off states must stop using the configured treatment.
- Every independent control keeps a minimum 44-point target and a visible or accessible label.

## Start and Live Recording

The contextual center Start action immediately enters a cancelable countdown, then live recording. The countdown and live status must reflect Indoor/Outdoor and Live Track choices.

The top-left cancel action exists only during the countdown. Once recording begins, the live camera/map surface is non-dismissible and remains full-screen until Finish hands off to post-run Save or Discard. An interrupted session restores paused directly into that live surface rather than behind Today. Cold-launch recovery defers presentation until Today's tab hierarchy is attached, verifies that the full-screen surface appeared, and retries a dropped system presentation request. The embedded setup remains rendered underneath until that handshake succeeds, so a missed presentation cannot leave a blank Today surface. Relaunch recovery adopts the surviving ActivityKit card for that session and immediately removes duplicate app-owned cards, so repeated force-kill/relaunch cycles still leave exactly one Live Activity.

Primary live metrics follow the selected mode:

| Mode | Primary metric |
| --- | --- |
| Planned or Freestyle | Current distance |
| Distance | Current distance / target |
| Time | Elapsed time / target |
| Calories | Estimated calories / target |

Keep map, current guidance, Pause, and Finish primary. Pause reveals separate Resume and Finish actions. Finish requires confirmation before handing off to post-run review. Expanding the map preserves compact time, pace, and distance plus an obvious return to full metrics.

Keep the Apple Maps logo and Legal attribution fully visible on both Today and the live map. Each map uses the measured height of its bottom cards and controls as safe-area padding, so attribution moves above every app-owned overlay while map imagery continues beneath the UI.

The confirmed Finish handoff stays inside the existing full-screen activity surface. Live content fades and scales down slightly while post-run review fades and scales in over a stable background; it must not dismiss the live surface and present a second sliding cover. Reduce Motion uses an opacity-only handoff, and successful completion emits success haptic feedback.

## Feedback and Measurement

Use temporary toasts for setup changes and learned-default confirmation. Overlays dismiss with their close action, outside tap, or Escape in the web reference. Selection uses text/checkmarks or state labels in addition to color.

Production analytics reuse the typed activity funnel in `docs/product-analytics.md`: setup exposure/configuration, `activity_started`, pause/resume/finish, and save/discard. `calories` is a bounded `goal_type`; calorie targets use coarse target buckets. Do not emit an event for every mode tap or include exact targets, contact names, playlist names, or shoe names.

## Acceptance Criteria

- The two-row launch dock fits at 360-point width without compressing controls or hiding the contextual Start control or tab bar; workout choices and launch settings scroll independently while Photo remains floating and visible.
- Today opens directly with its existing content plus the retained dock; no Quick Start or Start Activity setup route remains.
- The map remains the background of the bounded content area for every goal mode, extends behind the navigation controls, and stops before the dock and tab bar.
- The Apple Maps logo and Legal attribution remain unobstructed above Today cards and every live-run bottom overlay, including expanded route-guidance and group-run panels.
- The workout row contains Planned, Run, Walk, Hike, and Bike, with supported manual sports defined in one extensible collection.
- Planned retains the recommendation's assigned sport and the existing Today card and Up Next implementation as its peer content layer.
- The text-only Free, Distance, Time, and Calories pills float above the dock for manual sports and remain hidden for Planned.
- Target-based manual modes show their compact goal information layer, while Free shows no target card.
- The native center tab contains exactly one control: an icon-only Start on idle Today and labeled Today navigation on Social or Me.
- The floating assistant remains available in the same bottom-leading screen position on Today, Social, and Me.
- Idle Today exposes Photo and Find Route through one top-right overflow menu without changing the settings-row width.
- The overflow discovery popover appears no more than twice and stops permanently after acknowledgment or menu use.
- Capturing a pre-activity photo replaces the overflow ellipsis with a circular thumbnail plus an ellipsis badge; removing the photo restores the standard ellipsis.
- Selecting a route fits its highlighted line and endpoint pins in the map and shows a compact route name/distance card with Change and Remove actions.
- Switching workout types or planned workouts retains the selected route; only Remove Route clears it.
- Choosing Run, Walk, Hike, or Bike updates the prepared activity without losing the selected manual goal.
- Choosing Distance, Time, or Calories updates the card without opening the chooser.
- The compact chooser opens only from the value card and supports presets and custom input.
- Presets, custom targets, and selected-state labels stay synchronized.
- Goal and utility dock buttons display no secondary value line.
- Photo is available for Planned and every manual sport, returns to the same retained setup after capture, and exposes preview, Retake, and Remove after a photo is added.
- Setup choices carry into countdown and live status.
- Countdown cancel preserves setup; only entry into live recording advances default learning.
- Active and paused live recording cannot be minimized by a button, gesture, assistant action, or tab navigation.
- Interrupted-session recovery opens the paused live surface directly.
- Cold-launch recovery verifies full-screen presentation and retries a dropped request without exposing a blank launch surface.
- Repeated force-kill/relaunch recovery leaves exactly one app-owned Live Activity card for the recovered session.
- Goal-specific live metrics, pause/resume, finish confirmation, and expanded-map return all work without console warnings or errors.
- A live session with both a target and a route keeps the target as its header and shows the route once in the secondary route row; freestyle route sessions use the route as the header without duplicating it.
