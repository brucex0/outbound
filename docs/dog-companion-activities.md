# Dog Companion Activities

Open this when designing or implementing the `With dog` activity context across setup, recording, saved activities, progress, coaching, or Social.

Status: implemented across backend, iOS, and Android.

## Implementation Notes

- Contracts represent the context as the optional typed value `companionType: null | "dog"` (Prisma `Activity.companionType` with a nullable-column migration, no backfill; Swift `ActivityCompanionType`; Kotlin `@Serializable ActivityCompanionType`). Missing data decodes as `null` everywhere; unknown read values are dropped safely and never re-sent.
- The activity create/update validator accepts only `"dog"` or `null`. Uploads that omit the field do not erase a stored value during conflict resolution; an explicit `null` clears it.
- iOS threads the value through `RecordView` prepared/active state, `ActiveSessionJournal` recovery, every `SavedActivity` reconstruction path, uploads, sync snapshots, and phone/watch handoff via `PlainstrideWorkoutIdentity`. Android threads it through the Today launch configuration, `RecordingService` intents, `RecordingSnapshot` (serialized into the active-session journal), `SavedActivity`/Room, upload requests, and remote restore.
- Freestyle saves gain localized Dog run/walk/hike/ride titles; planned and curated workout titles are untouched, and the canonical activity type never changes.
- Analytics add the bounded `dog_companion_enabled` boolean to `activity_started` and `activity_saved`, reuse `activity_configuration_changed` with `companion: on/off`, and emit `feature_exposed` with `feature=dog_companion` on first setup use. No pet identity, pet metrics, or free text is ever recorded.
- The Android Room schema bumps to version 4; pre-release destructive migration resets local activity data per the data policy.

## Product Decision

`With dog` is an optional activity context, not a sport or workout mode.

- It is available for Run, Walk, Hike, and Bike, including eligible planned and curated workouts.
- The canonical sport remains running, walking, hiking, or cycling.
- Free, Distance, Time, Calories, structured phases, routes, indoor/outdoor, gear, Live Track, and Voice Guide continue to work normally.
- A dog activity counts toward the same sport totals, goals, plan completion, progress trends, and race models as the workout actually performed.
- The context records that the person brought a dog. It does not measure the dog or assert that the activity was suitable for the dog.

The user-facing label is `With dog`, paired with a paw icon. Internal contracts should use an optional typed companion value such as `dog`, rather than creating `dogWalk`, `dogRun`, or other parallel activity types.

## Why This Shape

- People may walk, run, hike, or bike with a dog.
- A separate Dog Walk sport would fragment history, progress, goals, and planning.
- One independent context keeps the launch flow fast and lets every existing sport retain its correct metrics and behavior.
- The feature supports a frequent non-running habit without shifting Plainstride into pet-health tracking.

## UX Flow

### Setup

- Add one paw-icon `With dog` control to the existing horizontally scrolling settings row beside Music, Live Track, Shoes, Indoor/Outdoor, and Voice Guide.
- Use the same selected and unselected treatment as the other independent settings controls, with a minimum 44-point iOS or 48-dp Android target.
- Do not add a dog sport, a second setup page, a modal, or a required pet profile.
- Preserve the selection when switching among Run, Walk, Hike, Bike, Planned, Curated, and goal modes as long as the resolved sport remains eligible.
- Swimming and future incompatible sports do not expose the control. If an already selected setup resolves to an incompatible sport, clear the context and explain the change with a temporary toast.
- Preserve the selection through countdown cancellation and retained setup restoration. Reset it after Save or Discard so the next activity is not tagged accidentally.
- Planned and curated sessions expose the control only after their resolved sport is known.

### Countdown and live activity

- Reuse the existing countdown, recording state machine, camera/map surfaces, and controls.
- Show a compact paw marker with the activity label where session context is already summarized; do not add a new card or compete with the primary workout metric.
- Keep sport-specific metrics unchanged. All distance, pace, steps, elevation, heart rate, calories, and workout targets describe the person.
- Do not automatically change auto-pause, goals, structured phases, plan completion, target alerts, or Voice Guide cadence.
- Persist the context in interrupted-session recovery and phone/watch handoff so it cannot disappear after relaunch or recording-device changes.
- The app may use warm, non-medical companion language, but must not infer dog distance, pace, exertion, fitness, temperature tolerance, hydration needs, or health.

### Finish, history, and sharing

- Reuse the existing reflection, photo, Save Activity, and discard flows.
- Default titles for freestyle activities may use localized sport-specific forms such as `Dog walk`, `Dog run`, `Dog hike`, or `Dog ride`; planned and curated activities retain their workout title. The underlying sport remains unchanged and the title remains editable where currently supported.
- Show a small paw marker in recent activity cards, history, activity detail, and share-safe Social activity surfaces.
- Include the context in activity sync and cross-device restoration.
- Treat `dog` as share-safe metadata. Never include a dog name, photo identity, health data, or free text in the V1 contract.
- Imported and manually entered activities are not tagged in V1 unless a later activity editor explicitly adds support.

## Training, Progress, and Coaching Rules

- A dog run is still a run, a dog walk is still a walk, and so on.
- Apply existing plan-completion rules using the recorded sport, goal, duration, distance, and workout structure. The dog context neither guarantees nor prevents completion.
- Include the activity in the normal sport totals and progress trends. Do not create separate dog mileage, streaks, leaderboards, or recognition in V1.
- Running pace history, race predictions, calorie estimates, and readiness inputs continue to use the athlete's recorded data under existing eligibility and quality rules.
- Do not send pet identity or pet-health facts to the live coach. If the `dog` context is provided to coaching, constrain it to tone only and prohibit veterinary, safety, or performance claims about the dog.
- A future `Relaxed outing` choice may deliberately change coaching and pause behavior, but `With dog` alone must not do so.

## Data Contract

Use one optional typed value through every layer:

```text
companionType: null | "dog"
```

- `null` means no companion context.
- Do not encode the feature into `ActivityType`, a title, or an unstructured notes field.
- Persist the value in the prepared session, active-session journal, saved local activity, sync snapshot, canonical backend activity, Android database/model, and share-safe activity DTOs.
- Older records decode a missing value as `null`. No historical backfill is needed.
- Reject unknown write values at API boundaries while allowing additive read handling appropriate to each client.

## Analytics and Privacy

- Reuse the typed activity funnel instead of creating a parallel dog-activity funnel.
- Add the bounded boolean property `dog_companion_enabled` to `activity_started` and `activity_saved`.
- Record configuration changes through `activity_configuration_changed` using bounded values for the companion control.
- Record the first eligible display through `feature_exposed` with `feature=dog_companion`.
- Never send dog names, photos, free text, routes, coordinates, exact targets, or other pet-identifying details to analytics.
- The context must not alter location-sharing or Social visibility. Existing user-controlled privacy rules remain authoritative.

## Localization and Accessibility

- Localize every visible string in English, Spanish, and Simplified Chinese using the existing platform localization systems.
- Recommended labels are `With dog`, `Con perro`, and `带狗狗`; translators should preserve the friendly activity context rather than use clinical pet terminology.
- The control exposes a localized label, paw meaning, and selected state to VoiceOver and TalkBack without relying on color.
- Announce automatic clearing when the user moves to an incompatible sport.
- Paw markers are decorative when the adjacent text already communicates the context; otherwise they need an accessible label.

## Deferred Scope

- Dog profiles, names, breeds, ages, photos, and multiple-dog selection.
- Pet-health, veterinary, nutrition, hydration, heat, or safe-pace guidance.
- Dog-specific GPS, sensors, wearables, distance, calories, fitness scores, or training plans.
- Potty, medication, feeding, or care logs.
- Dog-friendly route claims, businesses, parks, or local-rule databases.
- Dog-only goals, progress dashboards, recognition, Social groups, or leaderboards.
- Automatic relaxed-outing, coaching, or auto-pause behavior.

## Acceptance Criteria

- Run, Walk, Hike, and Bike can independently enable `With dog` without changing sport or goal selection.
- Planned and curated workouts support the context when their resolved sport is eligible.
- Switching among eligible sports and goals retains the context; an incompatible sport clears it with temporary feedback.
- Countdown cancellation and interrupted-session recovery preserve the context, while Save and Discard reset the next setup to off.
- Live metrics, auto-pause, structured workout behavior, and plan completion remain driven by the original sport and workout.
- Saved local, synced backend, restored cross-device, and Android/iOS representations agree on `null | dog`.
- History, detail, and permitted Social surfaces show a localized, accessible paw treatment without creating a new activity category.
- Progress, goals, race predictions, and calorie calculations continue to classify the activity by its canonical sport.
- Analytics use only the allowlisted boolean/bounded values and contain no pet identity or location data.
- English, Spanish, and Simplified Chinese UI, large text, VoiceOver/TalkBack, dark mode, and supported themes remain usable.
