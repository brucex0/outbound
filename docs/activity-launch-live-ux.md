# Activity Launch and Live Run UX

Open this when changing the Today launch dock, activity goal selection, countdown, or live-run controls. The clickable reference is `docs/prototypes/activity-start-live-wireframe.html`; the production flow is implemented in `RecordView.swift`, `ActivityGoal.swift`, `LiveMapView.swift`, and `CameraHUDView.swift`.

## Navigation Decision

The launch surface is the Today page itself; there is no separate start-activity setup page. Reuse the center Today position contextually while retaining the production icons, order, labels, and theme tint.

- On Today, the center control becomes an orange play icon with the visible label `Start` and a goal-specific accessibility label.
- On Social or Me, the same position shows the normal Today icon and label; tapping it returns to Today.
- Social and Me hide the launch dock. Returning to Today restores the same retained activity setup without navigating through another screen.
- The primary tab bar remains hidden during countdown, live recording, camera capture, and post-run completion.

## Launch Dock

Use one fixed, flat two-row control area at the bottom of Today. The Today navigation title, conditions pill, app shell, and bounded map background remain permanent. Planned, Freestyle, Distance, Time, and Calories are peer modes layered over that same map. Planned renders the existing Today card and Up Next implementation as a standalone peer-card stack above the dock; it must not use a page-sized scroll container that intercepts touches outside the cards. The other modes use their compact goal information card in the same region. The map ends at the dock boundary and never becomes the full-screen app surface. Each dock control renders only its icon and localized title; current values remain available through configuration state, the goal card/editor, and accessibility. The dock has no third row, grabber, expansion state, setup heading, or second setup screen.

Goal modes are peers:

- `Planned`: the prescribed workout structure; initial default.
- `Freestyle`: record without a target.
- `Distance`, `Time`, and `Calories`: record toward one explicit target.

Selecting a mode only updates the information card; it never opens another control. The Planned card opens the workout picker when tapped. The Distance, Time, or Calories card opens a small anchored chooser with one row of presets and a custom input. Do not use a dimmed full-height sheet for goal values. Freestyle has no target editor.

Learn a different default only after the same mode reaches live recording for three consecutive activities. Exploratory taps and canceled countdowns do not count. Store this preference locally and keep every mode available; selecting a mode never starts the activity.

Configure launch options from the dock:

- Music, Live Track, and Shoes use compact icon-plus-label controls that open focused overlays and return the chosen value to the dock.
- Environment and Voice Guide use the same icon-plus-label treatment and toggle directly.
- Off states must stop using the configured treatment.
- Every independent control keeps a minimum 44-point target and a visible or accessible label.

## Start and Live Recording

The contextual center Start action immediately enters a cancelable countdown, then live recording. The countdown and live status must reflect Indoor/Outdoor and Live Track choices.

The top-left cancel action exists only during the countdown. Once recording begins, the live camera/map surface is non-dismissible and remains full-screen until Finish hands off to post-run Save or Discard. An interrupted session restores paused directly into that live surface rather than behind Today.

Primary live metrics follow the selected mode:

| Mode | Primary metric |
| --- | --- |
| Planned or Freestyle | Current distance |
| Distance | Current distance / target |
| Time | Elapsed time / target |
| Calories | Estimated calories / target |

Keep map, current guidance, Pause, and Finish primary. Pause reveals separate Resume and Finish actions. Finish requires confirmation before handing off to post-run review. Expanding the map preserves compact time, pace, and distance plus an obvious return to full metrics.

## Feedback and Measurement

Use temporary toasts for setup changes and learned-default confirmation. Overlays dismiss with their close action, outside tap, or Escape in the web reference. Selection uses text/checkmarks or state labels in addition to color.

Production analytics reuse the typed activity funnel in `docs/product-analytics.md`: setup exposure/configuration, `activity_started`, pause/resume/finish, and save/discard. `calories` is a bounded `goal_type`; calorie targets use coarse target buckets. Do not emit an event for every mode tap or include exact targets, contact names, playlist names, or shoe names.

## Acceptance Criteria

- The two-row launch dock fits at 360-point width without hiding the contextual Start control or tab bar.
- Today opens directly with its existing content plus the retained dock; no Quick Start or Start Activity setup route remains.
- The map remains the background of the bounded content area for every goal mode without covering the Today title, conditions pill, dock, or tab bar.
- Planned retains the existing Today card and Up Next implementation as its peer content layer; other modes show their compact goal information layer.
- The native center tab contains exactly one control: an icon-only Start on idle Today and labeled Today navigation on Social or Me.
- The floating assistant remains available at the top-leading edge of the Today map.
- Choosing Distance, Time, or Calories updates the card without opening the chooser.
- The compact chooser opens only from the value card and supports presets and custom input.
- Presets, custom targets, and selected-state labels stay synchronized.
- Goal and utility dock buttons display no secondary value line.
- Setup choices carry into countdown and live status.
- Countdown cancel preserves setup; only entry into live recording advances default learning.
- Active and paused live recording cannot be minimized by a button, gesture, assistant action, or tab navigation.
- Interrupted-session recovery opens the paused live surface directly.
- Goal-specific live metrics, pause/resume, finish confirmation, and expanded-map return all work without console warnings or errors.
