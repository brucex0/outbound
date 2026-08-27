# Activity Launch and Live Run UX

Open this when changing the Today launch dock, activity goal selection, countdown, or live-run controls. The clickable reference is `docs/prototypes/activity-start-live-wireframe.html`. Production Swift implementation is still pending.

## Navigation Decision

Keep `Social · Today · Me` as stable navigation with the production icons, order, labels, and theme tint.

- Today remains a destination everywhere; it never becomes Start.
- Start is a separate orange action in the launch dock.
- Social and Me hide the launch dock. Today restores it without changing the selected activity setup.
- Do not ship the contextual Today/Start tab experiment. Repurposing a navigation item as an unlabeled action weakens predictability and conflicts with the app's labeled-tab accessibility contract.

## Launch Dock

Use one fixed, flat control area on Today. It has no grabber, expansion state, setup heading, or second setup screen.

Goal modes are peers:

- `Planned`: the prescribed workout structure; initial default.
- `Freestyle`: record without a target.
- `Distance`, `Time`, and `Calories`: record toward one explicit target.

Selecting Planned opens the workout picker. Selecting Distance, Time, or Calories opens a focused editor with presets and custom input. The detail card then shows only the current value and reopens the same editor when tapped.

Learn a different default only after the same mode reaches live recording for three consecutive activities. Exploratory taps and canceled countdowns do not count. Store this preference locally and keep every mode available; selecting a mode never starts the activity.

Configure launch options from the dock:

- Shoes, Music, and Live Track open focused overlays and return the chosen value to the dock.
- Indoor/Outdoor and Voice Guide toggle directly.
- Off states must stop using the configured treatment.
- Every independent control keeps a minimum 44-point target and a visible or accessible label.

## Start and Live Recording

Start immediately enters a cancelable countdown, then live recording. The countdown and live status must reflect Indoor/Outdoor and Live Track choices.

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

Production analytics should reuse the typed activity funnel in `docs/product-analytics.md`: setup exposure/configuration, `activity_started`, pause/resume/finish, and save/discard. Add `calories` to the bounded `goal_type` contract when implementing this flow. Do not emit an event for every mode tap or include exact targets, contact names, playlist names, or shoe names.

## Acceptance Criteria

- The launch dock fits at 360-point width without hiding Start or the tab bar.
- Tabs retain one meaning on Today, Social, and Me.
- Presets, custom targets, and selected-state labels stay synchronized.
- Setup choices carry into countdown and live status.
- Countdown cancel preserves setup; only entry into live recording advances default learning.
- Goal-specific live metrics, pause/resume, finish confirmation, and expanded-map return all work without console warnings or errors.
