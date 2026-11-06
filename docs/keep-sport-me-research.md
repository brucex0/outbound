# Keep Sport And Me Deep Probe — 2026-11-05

Open for the follow-up device probe of the center Sport tab and fifth Me tab. See [the initial research](keep-device-research.md) for the plan investigation and general feature map.

## Evidence and boundaries

- Same logged-in Chinese-language iPhone app, operated through iPhone Mirroring. No alternative connected iPhone-control tool was available in the tool inventory.
- Scrolling **worked in this follow-up**, including the sports picker and Me dashboards. Earlier scroll failures are a limitation of the first probe, not evidence that the app cannot scroll. Some running-settings scroll attempts still produced no movement.
- Observed screens and controls only: no real workout started, no new custom workout saved, no permission granted, and no privacy/recording/audio setting changed.
- One icon thought to be a selector was actually “want to practice”; it briefly added the featured yoga course, then was tapped again. The visible toast confirmed removal. This was the only observed saved-content mutation in this follow-up.
- Personal health values, profile/activity history screenshots, and location maps were inspected but **not saved to the repository**. Retained screenshots focus on controls, catalogs, and workout setup. They still show account-selected preferences and may need review before external sharing.
- “Supported sport” below means an option exists in the picker. Recording quality, sensors, calculations, coaching, and plan support were not validated for each sport.

## Sport tab

### Launch changes with the activity

- Selecting outdoor running changes the hero to a map and exposes goal run, free run, course run, and custom modes. GPS, team, and route shortcuts appear beside it.
- A companion-mode row advertises an easy audio run; music, equipment, and a large GO remain near the bottom.
- Beginner and quick-fat-burn modes in the general exercise launch surface featured member-only yoga courses with title, difficulty, duration and calorie range. These are content-driven launch choices, not simply different running goals.
- The running map and current position were deliberately excluded from retained evidence.

### Goals

- Goal editor has **distance, duration, calorie expenditure, and pace** tabs.
- Distance provides common presets (including 5 km, 10 km, half and full marathon), track-related presets, and a personal historical-best-distance shortcut.
- Pace provides minute/second-per-kilometer entry and preset paces. Cancel and Confirm make the edit boundary explicit.
- Only the distance launch and pace editor were retained as screenshots; the distance editor contained a personal historical record.
- No goal edit was confirmed. Goal-completion behavior, pace alerts and whether goals can combine were not tested.

### Custom running workouts

- Custom mode shows an intensity distribution graphic and a selected workout with duration and distance estimate.
- “Custom workout combination” opens a list of official templates and per-workout Start actions. Visible examples: run/walk adaptation, short easy run, target pace, marathon-pace run, very slow running, and lactate-threshold running.
- List includes Edit and Create new workout combination.
- Create opens a name-entry sheet with a 12-character counter and Confirm. Exited without entering or saving a name; later interval/step editing remains unverified.
- This is evidence of reusable workouts separate from a multi-week plan, an important distinction for Plainstride’s information architecture.

### Sports picker

- “My sports” includes outdoor run, indoor run, outdoor walk, jump rope, indoor cycling and outdoor cycling; Manage is present.
- Running/walking/cycling category additionally shows stair climbing, indoor walking, hiking and trail running.
- Ball sports: badminton, football/soccer, basketball, table tennis, tennis, volleyball, bowling and golf.
- Indoor: yoga, HIIT, gym training, small equipment, mixed cardio, aerobics, dance, Zumba, Pilates, boxing, combat training, barre, elliptical, rowing machine, stepper and stair machine.
- Leisure: frisbee, roller skating, skateboarding and hula hoop.
- Water: pool swimming, open-water/outdoor swimming and surfing.
- Specialist: trampoline, ice skating, skiing, fencing, archery, equestrian and climbing.
- Martial arts: tai chi, wing chun and five-animal exercises. An Other Sports heading was visible, but its final items were not inspected.
- Broad catalog is impressive; do not infer sport-specific coaching or plan generation from a generic recording label.

### Audio and equipment

| Surface | Opened controls | Unverified behavior |
| --- | --- | --- |
| General course sport settings | Voice announcements toggle | Audio playback |
| Running settings | Voice announcements, voice selection, distance announcements, announcement frequency, coaching, coaching density, live activity, live cheering audio, training-stage announcements, route-information announcements | Trigger accuracy, delivery and live audience semantics |
| Coaching density | Detailed: heart-rate/pace alerts + intensity inspection + exercise guidance; concise: alerts + intensity inspection; minimal: alerts | Whether each level exactly follows the description during a run |
| Music source | NetEase Cloud Music, QQ Music, Keep-selected playlists, course default music, no music | Authentication, playback, licensing and mixing |
| Equipment sheet | Equipment / Data Source tabs; wearables list/add; heart-rate-device recommendation | Pairing and vendor coverage |
| Data Source | Heart rate, scan/add heart-rate device | Sensor acquisition and fallback |

## Me tab

### Dashboard architecture

- **Today Overview** combines food, training and sleep gauges with AI insight and deeper analysis.
- **Body Capability** exposes a branded body-age estimate and exercise-state assessment, each with analysis actions. The latter uses a categorical continuum from declining fitness through maintenance/improvement to excessive fatigue.
- Opened exercise-state analysis shows a data-estimation notice, recommends a heart-rate device for greater precision, presents an AI summary, a dated trend chart, More, feedback/useful controls, and deeper analysis.
- The screen makes assertive fitness claims. This probe did not audit its data completeness, model or validity; do not treat the account-specific assessment as a fact about the user’s health.
- **All Data** starts with cumulative exercise time, today’s activity/steps, sport totals, data sync, automatically detected recent records, more records, and Upload Activity Record.
- Four data subcategories: Activity Records, Body Data, Health Data and Performance.

### Data inventory

| Category | Observed modules | Coverage |
| --- | --- | --- |
| Activity Records | Sport icon, distance, duration, pace, date, source attribution, PB markers | List opened; one indoor activity opened |
| Body Data | Weight, BMI, body-fat percentage, height, waist/hip/thigh/calf/chest/arm measurements, body type, body-posture score, posture imaging entry | Catalog visible; no values edited |
| Health Data | Food intake, sleep duration, water, active/resting energy, HRV, sleep HRV, stress, live/resting/average exercise/max heart rate, VO2 max, oxygen saturation | Catalog visible; individual metric details not opened |
| Performance | Running ability, exercise state, muscle ability, weekly calorie deficit, outdoor 5 km PB, prior-week report, exercise trends | Catalog visible; exercise-state analysis opened |

### Activity details

- Indoor run detail leads with activity type and distance, followed by a speed visualization.
- Summary includes training time versus total elapsed time, energy, average speed, average pace, and exercise load.
- Privacy, edit, share and Publish to Community controls are present. None were applied.
- Data Details opens speed, pace, cadence and stride-length charts, with instructions that long-press reveals specific values. Long-press interaction was not exercised.
- Distinguishing moving/training time from elapsed time and preserving source labels are useful patterns to retain in Plainstride.

### Settings and automatic records

- Settings inventory: exercise card, personal information, account/security, minor mode, privacy, shipping address; exercise settings, messages/reminders, general settings, storage, network diagnostics and Keep Lab.
- Exercise settings groups training settings, exercise voice, automatic activity records, exercise shortcuts and casting.
- Automatic-record screen separates Run/Walk from Stair Climbing. Copy describes recognizing continuous walking from phone step-sensor data and automatically generating a record.
- Run/Walk exposes a minimum-distance threshold and a separate route-drawing control. Route copy says Always location permission is needed and privacy processing is applied. These are UI claims; detection and trimming were not tested.
- No location authorization or setting was changed. Do not assume background tracking is enabled simply because automatic step records are enabled.

### Privacy and data controls

- Privacy page exposes messages from non-followed people, personalized content, following/follower visibility, blocklist, device permission management, data management, withdrawal of privacy-policy authorization, and activity-record privacy.
- Data Management includes a data-for-experience-optimization control. Copy explicitly mentions exercise data and AI-interaction content for AI-model training and smart-service optimization; a Tencent/QQ-sharing item is separate. No consent was changed.
- Activity privacy separates route start/end masking distance, map, heart-rate data, equipment, and participation in Keep competition rankings by activity type plus growth ranking.
- Endpoint masking opens a distance ruler. Copy says the default affects future outdoor activity endpoints, hidden distance is excluded from competition statistics, and past records are unaffected. Actual enforcement was not tested.
- Map visibility copy also mentions hiding the matched city from other people. Existing-record privacy can be adjusted per record according to the explanatory text.
- These controls deserve a separate privacy UX comparison before implementing any equivalent; controls alone do not prove the data is protected throughout every share surface.

## Product ideas for Plainstride

- **Explain audio levels.** Use plain descriptions of which cues remain, with a preview; keep safety/goal alerts distinct from optional motivational speech. Keep’s density selector is a useful concrete benchmark.
- **Unify workout reuse and planning.** Let a runner save a favorite custom session, preview its steps/time, and ask to fit it into the week with an explicit adjustment preview. Keep’s separate combinations list shows the value of reusable workouts.
- **Prefer a focused sport set with real depth.** Keep’s catalog gives breadth; Plainstride should expose a modality only when recording, workout generation, coaching and progress are credible. Do not add dozens of labels solely to match the picker.
- **Make insights evidence-aware.** Show data coverage, source and uncertainty alongside fitness status; provide a useful next action. Missing wearable data or incomplete imported history should not become an overconfident decline claim.
- **Give Me a clear hierarchy.** Lead with progress toward the person’s goal and recent sessions; make detailed health metrics discoverable. Avoid making the default experience a wall of empty measurements.
- **Label automatic records.** If added, distinguish detected movement from deliberately recorded or planned workouts, expose inclusion rules, and prevent duplicate adherence/load credit.
- **Preview sharing privacy.** Show exactly what another person will see, including endpoint trimming and heart-rate visibility, before sharing. Reconcile historical versus future settings clearly.
- **Separate personalization from model-training consent.** Explain each purpose independently instead of hiding it under an ambiguous optimization label. This is a proposed design principle, not a claim about existing Plainstride consent implementation.

## Remaining checks

- Real recording, goal completion, audio cadence/ducking, live cheers and notification delivery.
- Custom interval-step editor beyond name creation, template editing, course-run selection, route and team flows.
- Wearable pairing, auto-detection, import/upload, duplicate reconciliation, privacy enforcement and background behavior.
- Individual health metric details, body-age calculation/explanation, weekly reports, all account-menu destinations and full lower settings.
- Sport picker Other entries and any unobserved modes. No claim of exhaustive feature coverage.

## Retained screenshots

- [22-sport-beginner](../artifacts/keep-research-2026-11-05/22-sport-beginner.jpg)
- [23-sport-fat-burn](../artifacts/keep-research-2026-11-05/23-sport-fat-burn.jpg)
- [24-sports-picker](../artifacts/keep-research-2026-11-05/24-sports-picker.jpg)
- [25-sports-indoor](../artifacts/keep-research-2026-11-05/25-sports-indoor.jpg)
- [26-sports-leisure-water](../artifacts/keep-research-2026-11-05/26-sports-leisure-water.jpg)
- [27-sports-specialist](../artifacts/keep-research-2026-11-05/27-sports-specialist.jpg)
- [28-sport-course-settings](../artifacts/keep-research-2026-11-05/28-sport-course-settings.jpg)
- [29-sport-equipment](../artifacts/keep-research-2026-11-05/29-sport-equipment.jpg)
- [30-heart-rate-source](../artifacts/keep-research-2026-11-05/30-heart-rate-source.jpg)
- [31-music-sources](../artifacts/keep-research-2026-11-05/31-music-sources.jpg)
- [32-running-settings](../artifacts/keep-research-2026-11-05/32-running-settings.jpg)
- [33-coaching-density](../artifacts/keep-research-2026-11-05/33-coaching-density.jpg)
- [34-me-settings](../artifacts/keep-research-2026-11-05/34-me-settings.jpg)
- [35-exercise-settings](../artifacts/keep-research-2026-11-05/35-exercise-settings.jpg)
- [36-auto-activity-records](../artifacts/keep-research-2026-11-05/36-auto-activity-records.jpg)
- [37-run-goal-distance](../artifacts/keep-research-2026-11-05/37-run-goal-distance.jpg)
- [38-pace-goal-editor](../artifacts/keep-research-2026-11-05/38-pace-goal-editor.jpg)
- [39-custom-run](../artifacts/keep-research-2026-11-05/39-custom-run.jpg)
- [40-workout-combinations](../artifacts/keep-research-2026-11-05/40-workout-combinations.jpg)
- [41-create-combination](../artifacts/keep-research-2026-11-05/41-create-combination.jpg)
