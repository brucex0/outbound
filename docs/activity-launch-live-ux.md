# Activity Launch and Live Run UX

Open this when changing the Today launch dock, activity goal selection, countdown, or live-run controls. The clickable reference is `docs/prototypes/activity-start-live-wireframe.html`; the production flow is implemented in `RecordView.swift`, `ActivityGoal.swift`, `LiveMapView.swift`, and `CameraHUDView.swift`.

## Navigation Decision

The launch surface is the Today page itself; there is no separate start-activity setup page. Reuse the center Today position contextually while retaining the production icons, order, labels, and theme tint.

- On Today, the center control becomes an orange play icon with the visible label `Start` and a goal-specific accessibility label.
- On Social or Me, the same position shows the normal Today icon and label; tapping it returns to Today.
- Social and Me hide the launch dock. Returning to Today restores the same retained activity setup without navigating through another screen.
- The primary tab bar remains hidden during countdown, live recording, camera capture, and post-run completion.

## Launch Dock

Use one fixed, flat two-row control area over a full-content map on Today. The map fills every point above the dock and center tab action. The dock has no third row, grabber, expansion state, setup heading, or second setup screen. Keep a small clear gap between the dock content and the raised Start control, and keep compact labels legible at the minimum supported width.

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
- Today opens directly on the retained map and dock; no Quick Start or Start Activity setup route remains.
- The setup map fills the complete content area above the dock without clipping or horizontal overflow.
- The center control clearly reads Start on Today and Today on Social or Me.
- Choosing Distance, Time, or Calories updates the card without opening the chooser.
- The compact chooser opens only from the value card and supports presets and custom input.
- Presets, custom targets, and selected-state labels stay synchronized.
- Setup choices carry into countdown and live status.
- Countdown cancel preserves setup; only entry into live recording advances default learning.
- Goal-specific live metrics, pause/resume, finish confirmation, and expanded-map return all work without console warnings or errors.
