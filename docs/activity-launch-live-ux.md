# Activity Launch and Live Run UX

Open this when changing the Today launch dock, activity goal selection, countdown, or live-run controls. The clickable reference is `docs/prototypes/activity-start-live-wireframe.html`; the production flow is implemented in `RecordView.swift`, `ActivityGoal.swift`, `LiveMapView.swift`, and `CameraHUDView.swift`.

## Default activity titles

- Default freestyle activity titles use the localized sport name without a Freestyle prefix; the goal-mode selector still says Freestyle. Android’s generic recording fallback says Activity.
- Dog-specific, planned, curated, and user-entered titles remain unchanged. This is a display-copy change; activity identifiers and analytics values remain unchanged.

## Ad-hoc race mode

- Run setup exposes Race as a peer of Curated, Freestyle, Distance, Time, and Calories. Selecting it opens the race planner immediately.
- V1 supports 5K, 10K, half marathon, and marathon efforts. The runner may use Plainstride's suggested finish time, edit it, or race by feel.
- The iOS and Android suggestion filters saved runs to at least 2 km and ten minutes, between 50% and 110% of the race distance, then takes the first 30 in recent-history order. It compares runs within 90% of the longest eligible distance and projects with Riegel exponent 1.08, allowing distance ratios from 0.9 through 2. Near-distance efforts (at least 95% of the race) cannot project faster than the recorded duration; shorter efforts receive a five-percent buffer. The fastest candidate is rounded to the nearest minute.
- Without a responsible comparison, the recommendation is an effort-based finish. The current iOS planner seeds a two-hour editable time and Finish by feel strategy in this case; applying retains that time with no pace target and a manual source. Android matches this behavior. Time controls expose 0–23 hours and 0–59 minutes, with Apply disabled below five minutes. Choosing a new distance reseeds time and strategy; opening the planner starts from half marathon rather than the previously applied plan.
- Applying a plan creates typed race context (`RaceExecutionIntent` on iOS, `RecordingRaceIntent` on Android). Distance remains the saved activity goal; race goal mode, time/pace, strategy, and recommendation source remain live-guidance context.
- Training toward a future race date is deferred. This mode plans the race being started now.

## Navigation Decision

The launch surface is the Today page itself; there is no separate start-activity setup page. Reuse the center Today position contextually while retaining the production icons, order, labels, and theme tint.

- On Today, the center control becomes an orange play icon with the visible label `Start` and a goal-specific accessibility label.
- On Social or Me, the same position shows the normal Today icon and label; tapping it returns to Today.
- Social and Me hide the launch dock. Returning to Today restores the same retained activity setup without navigating through another screen.
- The primary tab bar remains hidden during countdown, live recording, camera capture, and post-run completion.

## Launch Dock

Visual contract: option/settings pills are **text only**, including the Watch recorder choice. Sport-type selectors in the Today dock are **icon only**, with localized accessibility labels. Keep this distinction when adding or changing dock controls.

Use one fixed, flat two-row control area at the bottom of Today. Workout choices occupy a horizontal scrolling row. The second row keeps launch settings in a full-width horizontal scroller with roomy fixed-width controls so compact phones do not compress labels or tap targets. A top-right overflow menu owns the pre-activity Photo and Find Route actions. Before capture its label is the standard ellipsis; after capture the label becomes a circular photo thumbnail with a small ellipsis badge so both photo state and menu behavior remain clear. The Today navigation controls, app shell, and bounded map background remain permanent. The map extends behind the transparent navigation bar to the screen top, then ends at the dock boundary; it never becomes the full-screen app surface.

For discoverability, a compact single-line popover points to the overflow control on at most two Today visits and says `Tap for photos and routes`. It has no action button, dismisses when the runner taps outside or leaves Today or idle setup, and is permanently suppressed after either menu action. Modal actions wait for the popover dismissal to complete so the two presentations never overlap. Its exposure uses the existing privacy-safe `feature_exposed` event without route names, photo content, or other private values.

The workout row contains `Planned`, `Run`, `Walk`, `Hike`, and `Bike`. `Planned` represents the recommendation itself rather than one sport, so a recommended walk remains a planned walk. Manual sports come from one extensible supported-sports list so future workout types can join without changing the selector contract. Each manual sport keeps an in-memory setup draft with its selected manual mode plus independent Distance and Time values; Run and Walk also retain Calories. Switching modes, sports, Planned, or Curated and then returning restores that draft instead of replacing it with a preset.
Selecting `Walk` requests Motion & Fitness access when it is still undetermined so live and saved walks can include step count. Declining access does not block the walk; distance, time, and the rest of recording continue without steps.
The selected route is an independent setup choice: switching between Planned and manual workout types, or choosing a different curated workout, rebuilds the workout intent while retaining the route and its map preview. Only the explicit Remove Route action clears it.

For a manual sport, a separate horizontal row of compact text-only pills floats immediately above the dock: `Curated`, `Free`, `Distance`, and `Time`; Run and Walk also expose `Calories`. This row is hidden for `Planned`; planned workouts already define their own structure and target. `Curated` opens the plan-independent workout catalog filtered to the selected sport and keeps that sport selected after a workout is chosen. `Free` records without a target, while Distance, Time, and Calories record toward one explicit target. Curated and target modes use their compact information card in the map region, and Free has no information card.

Distance, Time, and Calories goal editors replace their `Choose …` heading with the `Pause at goal` checkmark option. The collapsed goal card omits the goal-type caption and shows a pause icon with `Pause at goal` in its hint line when enabled; the card remains tappable to edit. The option is off by default and remembers its selection locally. When enabled, recording pauses as soon as the selected distance, elapsed time, or estimated calorie goal is reached. Distance is set to the selected target so users can finish with the intended number; they can also resume and continue recording. The option is unavailable for Freestyle, Curated, and Planned workouts.

Planned is exclusively the active plan source. It renders the prescribed Today or Up Next card as a standalone peer above the dock; it must not use a page-sized scroll container that intercepts touches outside the card. Tapping the card body opens workout details, including the explanation and one-day `Change workout` adaptation. The card footer exposes `Plan` for active-plan details and `Change plan` for the plan picker without an overflow menu. Me's Current Focus card remains a secondary plan-management entry. After an activity is completed, keep the planned card in the `Up next` state without adding a separate completion row. The Distance, Time, or Calories card opens a small anchored chooser with one row of presets and a custom input. Custom uses the same compact pill treatment as every preset rather than a separate full-width action. Selecting it expands one cohesive, compact, leading-aligned numeric field labeled with the runner's distance unit, localized minutes unit, or localized kilocalorie unit; a trailing checkmark applies the value. Let the expansion settle before focusing the field, and keep the Today launch chrome fixed when the keyboard appears so the dock and assistant remain behind the keyboard instead of moving into and obscuring the chooser. Do not use a dimmed full-height sheet for goal values. Settings controls render only their localized title; the floating Photo action is intentionally icon-only and keeps a localized accessibility label and state value. The floating goal controls are text only. Current values remain available through configuration state, the goal card/editor, and accessibility. The dock has no grabber, expansion state, setup heading, or second setup screen. The assistant uses the same shell-owned bottom-leading screen position as on Social and Me, mirrored by Photo at bottom-trailing on Today.

Eligible planned easy and recovery runs expose `Use Calories instead`. A calorie intent has one target and no timed phases; its planner-derived distance and duration remain display-only estimates. The Today calorie card shows that estimate in place of the generic change hint, and calorie editors present it as a prominent callout beneath the target controls. Weight and a reliable pace learned from three valid runs, or completed calibration plus valid run history, are required. Missing body data opens a private body-profile weight prompt and resumes the original choice after save, while insufficient pace evidence leaves the planned time target unchanged. Tempo, interval, long, race-prep, and race workouts never expose this conversion.

Manual walks can use a calorie target as soon as private weight is available. The setup card derives an approximate level-ground duration and distance from a moderate walking speed; live progress switches to the recorded walking speed and includes filtered elevation gain, so uphill work can reach the target sooner than the pre-start estimate.

Learn a different manual mode default per sport only after the same available `Free`, `Distance`, `Time`, or Run/Walk `Calories` mode reaches live recording for three consecutive activities of that sport. When a targeted manual activity reaches live recording, store its canonical target value for that sport and mode immediately; Distance uses meters, Time uses seconds, and Calories uses kilocalories. Curated selection, exploratory taps, and canceled countdowns do not update learned preferences. Store these preferences locally and account-scope them, while keeping every eligible mode available; selecting a workout or goal never starts the activity.

Configure launch options from the dock:

- Music, Live Track, and Shoes use compact text-only pills that open focused overlays and return the chosen value to the dock.
- `Watch app` is a text-only toggle with selected/unselected styling, defaulting on. It controls automatic Plainstride Watch launch; off records on the phone without assuming Apple Workout is running. See `docs/apple-watch-running-parity.md` for Health-save confirmation and import behavior.
- The current `Indoor` or `Outdoor` choice and Voice Guide use the same text-only pill treatment and toggle directly. Voice Guide defaults on for a new install and continues to honor an existing saved choice.
- Photo stays outside the settings scroller in the top-right overflow menu. Before capture its menu action opens the camera; afterward the toolbar label becomes the captured thumbnail and the menu action opens the preview with Retake and Remove.
- Find Route uses the same overflow menu. Selecting a route fits its full highlighted polyline on the Today map, shows start/finish markers, and replaces the planned/event peer slot with a compact route name/distance card offering Change and Remove. An eligible Circle remains visible above the route card, positioned from the route/goal overlay's measured height. The menu action changes from Find Route to Change Route while selected.
- `With dog` is a text-only toggle in the same settings row for Run, Walk, Hike, and Bike only. It stays selected across eligible sport and goal changes and cancels, and it clears automatically with a temporary toast when the chosen sport cannot carry it or a planned workout takes over the slot.
- Off states must stop using the configured treatment.
- Every independent control keeps a minimum 44-point target and a visible or accessible label.

## Start and Live Recording

The contextual center Start action immediately enters a cancelable countdown, then live recording, except Walk and Hike start recording immediately after the normal location preflight. The countdown and live status must reflect Indoor/Outdoor and Live Track choices.

When Voice Guide is enabled, initialize local speech before displaying the countdown so `3`, `2`, `1`, and the localized `Go` cue stay synchronized with the countdown instead of spilling into the live screen. Canceling the countdown stops queued speech and returns to Today. During an active or paused activity, system Back must use the same finish-confirmation flow as the visible Finish control; it must never reveal a retained countdown or setup screen.

Android warms location and local countdown speech while Today is visible and the app is resumed, without requesting permission automatically. Warmup targets a fix within 25 meters using a high-accuracy burst capped at eight seconds, then releases GPS until that fix reaches ten seconds old, or for twenty seconds after poor reception. Passive updates can reuse fixes from other consumers without powering up GPS. Today’s map blue dot uses these supplied fixes instead of running a separate continuous location request. A newer but noisier sample does not replace a more accurate fix during its first ten seconds unless it indicates movement beyond their combined uncertainty. All warmup requests stop when Today is hidden or the app is paused; active recording location behavior is unchanged. A fix must remain at most 15 seconds old with accuracy of 80 meters or better. A ready fix skips the waiting surface: Run/Bike enter countdown directly, and Walk/Hike enter recording directly. Missing location uses the activity map with a compact localized GPS status and Cancel action instead of a full-screen brand-color spinner or blocking GPS dialog. Back cancels GPS and speech preparation before a start command is sent. Walk and Hike skip the countdown after location preflight; other sports retain the voiced countdown. Exposure uses `feature_exposed` with `feature=activity_start_preflight`.

Android clears the retained recording ViewModel’s start-request flag after saving an activity, so the next Today launch can configure and start normally. The post-save celebration and stretch state remain available until dismissed. Repeated starts continue to emit the existing `activity_started` analytics event.

Android records `activity_countdown_voice_prepared` with only a bounded `success` or `unavailable` result so delayed or missing device TTS initialization can be diagnosed without collecting spoken content.

Android live recording gives map gestures to the map, matching iOS pan, zoom, and rotate behavior. Horizontal map drags never switch to the camera; use the camera/map button to switch from the map. Swiping left on the camera still opens the map. Android surface changes retain the existing `activity_surface_changed` analytics with only the selected surface, without recording map gestures or coordinates.

The live map remains mounted when switching to the camera and back, preserving its camera position, athlete-follow mode, and manually selected participant focus. Switching pages must not trigger an automatic route or world fit. Let the pager move the map offscreen; do not hide its imagery when selection changes, because the outgoing page remains visible during the transition and would flash blank. Existing `live_workout_page_selected` analytics continue to record the selected camera/map surface without camera or location data.

The live map represents the current athlete with a theme-colored, activity-specific companion for running, cycling, hiking, walking, or swimming instead of a generic location dot. Run, walk, and hike companions use an articulated figure whose arms and legs move with activity-specific cadence and stride; other sports retain their activity symbol. The companion follows valid GPS course, moves only while recording, and remains still when paused or Reduce Motion is enabled. Its exposure uses the privacy-safe `feature_exposed` event without location or pace data.

Outdoor GPS acquisition starts with the countdown rather than after it for activities with a countdown; Walk and Hike complete location preflight before starting immediately. The countdown shows a compact localized `GPS ready`, `Improving GPS signal`, `Acquiring GPS`, or `Precise Location is off` status without blocking Start indefinitely. A fresh good-quality countdown fix becomes the recording baseline; canceling the countdown stops the temporary high-accuracy acquisition. If iOS has granted only approximate location, the workout purpose may request temporary precise access using the localized bundle explanation.

Debug builds also expose a manual run simulator under More > Testing. Enabling it preselects the supplied Redmond Harvest route and replaces live Core Location fixes with progressive synthetic locations after the normal countdown. The live overlay can adjust running speed, pause/play simulated time at 1×, 10×, or 60×, and jump forward by one or five minutes. Synthetic fixes continue through `ActivityRecorder`, Route Guidance, `LiveMapView`, and `VirtualGuide`; the simulator does not use the static metric overrides from the seeded 10K UI fixture and does not write an interrupted-session recovery journal. The source GPX return-leg latitude `47.7900` is treated as an obvious discontinuity and corrected to `47.6900`, matching the outbound point.

The top-left cancel action exists only during the countdown. Once recording begins, the live camera/map surface is non-dismissible and remains full-screen until Finish hands off to post-run Save or Discard. The retained recorder renders this surface directly above Today while the shell hides its navigation, tab, and assistant chrome; it does not depend on presenting a child modal from inside the retained tab hierarchy. An interrupted session therefore restores paused into the same live surface rather than behind Today. Relaunch recovery adopts the surviving ActivityKit card for that session and immediately removes duplicate app-owned cards, so repeated force-kill/relaunch cycles still leave exactly one Live Activity.

Primary live metrics follow the selected mode:

| Mode | Primary metric |
| --- | --- |
| Planned or Freestyle | Current distance |
| Distance | Current distance / target |
| Time | Elapsed time / target |
| Calories | Estimated calories / target |

Keep map, current guidance, Pause, and Finish primary. The camera and map share one compact bottom workout panel by default. Its grabber and chevron support both an upward drag and a tap to open a full-screen workout dashboard with a large goal-aware primary metric, progress, supporting metrics, structured-workout and route context, the latest live-coach message, and persistent session controls. The expanded dashboard uses only compact and full-screen states, remains synchronized while switching between camera and map, and can drag or tap down only to collapse; it cannot dismiss or minimize the active workout. Pause reveals separate Resume and Finish actions. Finish requires confirmation before handing off to post-run review.

Keep the Apple Maps logo and Legal attribution fully visible on both Today and the live map. Each map uses the measured height of its bottom cards and controls as safe-area padding, so attribution moves above every app-owned overlay while map imagery continues beneath the UI. Today bounds the map to its available region above the fixed dock; its attribution inset also includes the measured goal-mode pills and location-permission chip, plus any route/goal cards. Peer cards use that same measured control height so their placement stays aligned when controls appear or disappear.

The confirmed Finish handoff stays inside the existing full-screen activity surface. Live content fades and scales down slightly while post-run review fades and scales in over a stable background; it must not dismiss the live surface and present a second sliding cover. Reduce Motion uses an opacity-only handoff, and successful completion emits success haptic feedback.

## Feedback and Measurement

Use temporary toasts for setup changes and learned-default confirmation. Overlays dismiss with their close action, outside tap, or Escape in the web reference. Selection uses text/checkmarks or state labels in addition to color.

Production analytics reuse the typed activity funnel in `docs/product-analytics.md`: setup exposure/configuration, `activity_started`, pause/resume/finish, and save/discard. `calories` is a bounded `goal_type`, `activity_type` distinguishes walking from running without exposing workout facts, and calorie targets use coarse target buckets. Do not emit an event for every mode tap or include exact targets, contact names, playlist names, or shoe names.

## Acceptance Criteria

- The two-row launch dock fits at 360-point width without compressing controls or hiding the contextual Start control or tab bar; workout choices and launch settings scroll independently while Photo remains floating and visible.
- Today opens directly with its existing content plus the retained dock; no Quick Start or Start Activity setup route remains.
- The map remains the background of the bounded content area for every goal mode, extends behind the navigation controls, and stops before the dock and tab bar.
- The Apple Maps logo and Legal attribution remain unobstructed above Today cards and every live-run bottom overlay, including expanded route-guidance and group-run panels.
- The workout row contains Planned, Run, Walk, Hike, and Bike, with supported manual sports defined in one extensible collection.
- Planned retains the recommendation's assigned sport and the existing Today card and Up Next implementation as its peer content layer.
- Planned easy and recovery runs may be replaced by one continuous calorie target only when private weight and reliable learned pace are available; quality, long, and race workouts retain their phases.
- Tapping Planned only restores the prescribed workout; tapping its card body opens workout details rather than the standalone catalog.
- The planned card exposes visible Plan and Change plan footer actions; Current Focus in Me remains a secondary plan-details entry, and More plans remains available in recommendations.
- Tapping Calories without a saved weight prompts for a private weight value, saves it to the training profile, and resumes the calorie-goal choice; canceling leaves the current goal unchanged.
- Completing an activity removes its Today completion summary while keeping the planned card available as `Up next`.
- The text-only Curated, Free, Distance, and Time pills float above the dock for manual sports; Calories is additionally available for Run and Walk, and all manual-goal pills remain hidden for Planned.
- Curated opens a catalog filtered to the selected Run, Walk, Hike, or Bike type and returns the chosen structured workout to that manual sport.
- Target-based manual modes show their compact goal information layer, while Free shows no target card.
- The native center tab contains exactly one control: an icon-only Start on idle Today and labeled Today navigation on Social or Me.
- The floating assistant remains available in the same bottom-leading screen position on Today, Social, and Me.
- Idle Today exposes Photo and Find Route through one top-right overflow menu without changing the settings-row width.
- The overflow discovery popover appears no more than twice, has no action button, dismisses on an outside tap, and stops permanently after menu use.
- Capturing a pre-activity photo replaces the overflow ellipsis with a circular thumbnail plus an ellipsis badge; removing the photo restores the standard ellipsis.
- Selecting a route fits its highlighted line and endpoint pins in the map and shows a compact route name/distance card with Change and Remove actions.
- Switching workout types or planned workouts retains the selected route; only Remove Route clears it.
- Choosing Run, Walk, Hike, or Bike updates the prepared activity and restores that sport's draft mode and target values.
- Choosing Walk requests Motion & Fitness access only when authorization is undetermined; the walk remains usable if access is unavailable or declined.
- Choosing Distance or Time, plus Calories for Run or Walk, updates the card without opening the chooser.
- The compact chooser opens only from the value card and supports presets plus an embedded, unit-labeled custom field for Distance, Time, and Calories; Custom is a peer pill and the field owns a compact trailing commit control.
- Opening the custom keyboard keeps the compact field visible without translating the Today dock, assistant, or launch controls over it; the numeric entry is leading-aligned and sized for a short target rather than the chooser width.
- The Calories card subtitle shows its approximate distance and duration, and the Calories chooser repeats that estimate in a visually prominent callout.
- Presets, custom targets, and selected-state labels stay synchronized.
- Distance, Time, and Calories goal editors show the `Pause at goal` checkmark in place of the picker heading; it is off by default and its selection is visible and accessible.
- With `Pause at goal` enabled, reaching the active target pauses recording once. A distance target displays the exact selected distance; the runner can resume or finish. Freestyle, Curated, and Planned sessions do not auto-pause.
- Goal and utility dock buttons display no secondary value line.
- Photo is available for Planned and every manual sport, returns to the same retained setup after capture, and exposes preview, Retake, and Remove after a photo is added.
- Setup choices carry into countdown and live status.
- Walk and Hike start recording without a countdown after the normal outdoor location preflight; other activities retain the existing cancelable countdown.
- Countdown starts high-accuracy acquisition, communicates GPS quality without delaying `Go`, and reuses a fresh suitable fix as the zero-distance baseline.
- Switching among Distance, Time, and Calories restores each mode's current draft value, including values edited before any activity starts.
- Countdown cancel preserves setup; only entry into live recording persists targets and advances default learning.
- Edge-to-edge countdown and live backgrounds keep their top controls below the device status area.
- Active and paused live recording cannot be minimized by a button, gesture, assistant action, or tab navigation.
- Camera and map use the same compact-by-default, two-detent workout bottom sheet. Dragging its grabber interactively follows the finger and snaps between compact and full-screen states; tapping the compact card surface expands it, while tapping the expanded header or grabber collapses it without ending the activity.
- The full-screen dashboard keeps the goal-aware primary metric, supporting metrics, workout step or route context, coaching message, Pause/Resume, and paused-only Finish usable at compact phone heights and with larger accessibility text.
- Interrupted-session recovery opens the paused live surface directly.
- Setup and live photos survive interrupted-session recovery and remain available on the finish page.
- Cold-launch recovery renders the retained live surface directly, without a child modal or disabled fallback layer.
- Repeated force-kill/relaunch recovery leaves exactly one app-owned Live Activity card for the recovered session.
- Goal-specific live metrics, pause/resume, finish confirmation, and expanded-map return all work without console warnings or errors.
- A live session with both a target and a route keeps the target as its header and shows the route once in the secondary route row; freestyle route sessions use the route as the header without duplicating it.

The live recording assistant reuses `DesignSystem/AssistantLauncherButton.swift`, including the fox mark, theme color, animation, and accessibility. Its top-trailing placement is specific to recording; its appearance is shared with the main navigation dock.

The fullscreen recording surface owns the live assistant launcher. The outer RecordView launcher is limited to standalone setup, preventing overlapping setup and live launchers.
