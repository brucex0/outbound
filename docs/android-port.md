# Android Public-Release Port

Open this when planning or implementing the Android app, changing a cross-platform client contract, or deciding how an Apple-specific capability maps to Android.

## Goal

Ship Plainstride on Google Play with the full product surface available on iOS. Android development proceeds in explicit phases and pauses for owner approval after each phase. A phase is complete only when its deliverables pass the stated verification gate and are committed.

This is not a reduced beta port. Camera recording, live coaching, Social, safety, routes, notifications, health integration, music, voice, and wearable support are release scope. Internal and closed testing may be used to validate builds, but public release waits for the complete scope and release gate.

Mainland China remains a separate market and infrastructure project. The first Android release targets Google Play devices with Google Play services.

## Product And Engineering Principles

- Build a native Kotlin and Jetpack Compose client; do not translate SwiftUI line by line.
- Preserve product behavior, data semantics, privacy, and safety rather than platform-specific presentation details.
- Reuse the existing Plainstride backend and first-party access/refresh sessions.
- Keep recording, local save, offline history, active-session recovery, and immediate coaching policy on-device.
- Keep identity, synchronized activities, planning, companion orchestration, Social, safety sessions, recognition, media, and notification routing on the backend.
- Save completed activities locally before attempting remote sync, health export, or media upload.
- Use semantic identifiers in persistence and APIs; localize only at presentation boundaries.
- Add Android analytics for every ported behavior using the existing allowlisted, privacy-preserving event contract.
- Treat Android background execution and device variation as core product constraints, not late QA concerns.
- Prefer clean current contracts over backward compatibility with pre-release local or backend data.

## Release Parity Contract

The following table is the release checklist. A row may use an Android-native replacement, but it may not be omitted without an explicit product decision recorded in this document.

| Product area | iOS source of truth | Android implementation | Release requirement |
| --- | --- | --- | --- |
| Identity and sessions | Apple sign-in, `AuthStore`, `SessionCoordinator`, Keychain | Credential Manager Google sign-in, Plainstride Google exchange, encrypted Keystore-backed session store | Sign-in, refresh rotation, logout, reauthentication, deletion, and deliberate Apple/Google account linking |
| App shell | SwiftUI `Social · Today · Me` shell | Compose navigation with equivalent selected-tab and active-session behavior | All entry points and deep links preserve destination and session state |
| Onboarding | Runner intake, understanding, calibration, first plan, optional health and cycle setup | Compose flow backed by the same personalization and planning contracts | Fresh, interrupted, resumed, completed, and debug/review states |
| Today and plans | Cached plan state, readiness, weather, workout customization | Room-backed cache, Android weather provider, shared backend contracts | Useful offline state and exact launch of the displayed workout |
| Recording | `ActivityRecorder`, `SessionCoordinator`, journal, camera/map HUD | Foreground location service, durable session journal, Compose HUD, Maps, CameraX | Run, walk, cycle, hike, and swim/manual behavior supported where applicable; process-death recovery and pause segments preserved |
| Camera and photos | AVFoundation capture, photo metadata and serialized persistence | CameraX capture with serialized local media persistence | Capture cannot interrupt location recording or allow Finish while a required write is pending |
| Local activities | `LocalActivityStore`, `ActivityStore` | Room database plus private app media storage and sync coordinator | Offline create/read/update/delete, pagination, tombstones, routes, photos, and idempotent convergence |
| Activity detail | Maps, elevation, splits, metadata, edit/export/share | Compose detail, Google Maps, Android share and document APIs | Equivalent metrics, segmentation, editing, GPX/GeoJSON, share card, and source attribution |
| Progress and gear | `ProgressStatsEngine`, `ProgressView`, `GearStore` | Pure Kotlin engines and Room repositories | Shared fixtures produce equivalent weekly totals, records, predictions, momentum, and mileage |
| Live coaching | Moment director, session planner, signed audio packs, stream/fixed/system fallback | Pure Kotlin policy, Media3/AudioTrack, Android TTS fallback, encrypted/private cache | Same semantic gates, target logic, priorities, locale/units, 1.5-second fallback, interruptions, and session access |
| Assistant and voice | Companion API, local fallback, speech recognition, App Intents | Companion API, Android speech APIs, App Actions/shortcuts where supported | Text and tap-to-talk assistant, activity preparation, live-session voice commands, and privacy boundaries |
| Social and Circles | Connections, feed, groups, invitations, events, Cheers | Compose surfaces against existing Social and Circle APIs | Cross-platform interaction, privacy visibility, pagination, reporting, blocking, and notification routing |
| Recognition | Local presentation plus server reconciliation | Room cache plus the same recognition APIs | Idempotent awards and identical share-eligibility behavior |
| Routes | Community routes, bookmarks, publication, deterministic route guidance | Google Maps rendering and a fixture-equivalent Kotlin guidance engine | Direction, acquisition, deviation/rejoin, wrong-way, arrival, privacy trimming, offline cache, and export |
| Safety | Trusted contacts, private live links, location updates, group-map sharing | Android contacts/share UI and foreground-safe live updates | Arming, delivery/share fallback, throttling, stale/unavailable states, explicit stop, and cleanup |
| Notifications | APNs/Firebase-backed coordinator and inbox | FCM registration, notification channels, runtime permission, deep links, inbox | Provider-neutral backend registration and equivalent preference/routing semantics |
| Health | HealthKit import/write and normalized sources | Health Connect import/write | Permission education, deduplication, supported workout mapping, route/HR metadata, and local-save-first export |
| Music | Apple Music and Spotify product behavior | Spotify plus Android-supported local/media-session integrations; Apple Music only if its Android SDK/API satisfies the same contract | Durable provider choice, playback state, audio focus, coaching ducking, disconnect and reauthorization behavior |
| Wearables | Apple Watch direction and normalized activity data | Wear OS companion plus Health Services; Health Connect for other-device imports | Start/pause/resume/finish, live metrics/HR, reconnection, and phone/watch session ownership |
| Weather | WeatherKit reduced-accuracy snapshot | Replaceable Android weather adapter with coarse-location input | Same cache lifetime, privacy boundary, attribution, failure handling, and non-blocking guidance |
| Themes | Nine adaptive themes | Compose Material color schemes generated from the same semantic palette | Light/dark, contrast, reactive changes, and persisted account preference |
| Localization | English, Spanish, Simplified Chinese string catalogs | Android resources with locale-aware formatting and speech locale mapping | Complete visible, accessibility, permission education, sharing, notification, and spoken surfaces |
| Analytics and feedback | Typed allowlisted Firebase events and redacted diagnostics | Shared event names/properties with Android platform value and the same sanitizer policy | No coordinates, identifiers, health details, free text, exact timestamps, or credentials |
| Accessibility | SwiftUI accessibility labels/actions and Dynamic Type | TalkBack, font scaling, semantic traversal, switch access, reduced motion, and touch targets | Manual release matrix passes in all supported locales |

## Android Project Shape

Start with one Gradle project under `android/`. Use modules for stable technical boundaries and keep early feature packages inside `app` until build time or ownership justifies extracting them.

```text
android/
  app/
  core/designsystem/
  core/model/
  core/network/
  core/database/
  core/auth/
  core/analytics/
  core/location/
  core/media/
  core/testing/
  feature/auth/
  feature/onboarding/
  feature/today/
  feature/recording/
  feature/activities/
  feature/progress/
  feature/companion/
  feature/social/
  feature/routes/
  feature/settings/
  wear/
```

Baseline technologies:

- Kotlin, Gradle Kotlin DSL, version catalogs, and Jetpack Compose
- Coroutines and `Flow` for asynchronous and observable state
- Room for activities, route points, photos, session journal, caches, and sync work
- DataStore for small device and account preference snapshots
- WorkManager for constrained, retryable sync and media work
- Credential Manager and Google identity for provider authentication
- Android Keystore-backed encrypted storage for refresh-session material
- Hilt for dependency injection
- Retrofit/OkHttp with Kotlin serialization, unless Phase 1 validates a simpler equivalent
- Google Maps and Fused Location Provider for the first Google Play release
- CameraX for camera preview and still capture
- Media3 plus low-level audio playback only where streaming PCM requires it
- Firebase Analytics, Crashlytics, and Messaging behind Plainstride-owned interfaces
- Health Connect on supported Android versions
- Health Services and Compose for Wear OS

Exact versions are selected and locked in Phase 1 after checking current stable Android and Play requirements.

## Shared Contract Strategy

The backend remains the contract authority. Avoid maintaining independent Swift and Kotlin interpretations of undocumented payloads.

1. Add a versioned OpenAPI artifact derived from route validators or maintained beside them.
2. Keep canonical request/response examples under `contracts/<domain>/<version>/`.
3. Cover identity, preferences, activities, media, planning, personalization, companion, coaching, recognition, Social, Circles, routes, safety, notifications, feedback, and health-source metadata.
4. Store semantic values, meters, seconds, UTC instants, and explicit nullable fields in contracts.
5. Return stable machine error codes; clients own localized error presentation.
6. Add fixture suites for deterministic algorithms that must agree across Swift and Kotlin:
   - activity save eligibility;
   - route segmentation and simplification;
   - elevation gain;
   - goals and progress;
   - pace and unit formatting inputs;
   - training-plan fallback selection;
   - coaching moment detection and cooldowns;
   - route guidance states;
   - recognition claims.
7. Contract changes are complete only when the backend, iOS decoder, Android decoder, examples, and relevant documentation agree.

## Phase Plan

### Phase 0 — Scope And Contracts

Deliverables:

- This public-release parity contract and platform mapping.
- Android project boundaries and ownership rules.
- Shared-contract and deterministic-fixture strategy.
- Phase gates and release definition of done.
- Explicit record that no current feature is silently deferred beyond public release.

Verification:

- Every current top-level iOS product area is represented in the parity table.
- Every Apple-only dependency has an Android replacement or an explicit product decision point.
- Documentation index routes Android work here.

### Phase 1 — Project Foundation

Deliverables:

- Gradle project, application and Wear OS placeholders, build variants, dependency injection, navigation, design system, localization foundation, logging, analytics sanitizer, and CI build commands.
- Core model, network, database, secure-session, clock, locale, and feature-flag interfaces.
- English, Spanish, and Simplified Chinese resource structure from the first user-facing string.
- Debug environment configuration that cannot be enabled in release builds.

Gate:

- Debug and release variants compile.
- Lint and static checks pass.
- A process-recreated sample state survives without credential or private-data logging.

### Phase 2 — Backend Contracts And Identity

Deliverables:

- OpenAPI and canonical fixtures for the initial vertical slice.
- Backend Google credential verification and Plainstride session issuance.
- Android Credential Manager sign-in, secure refresh rotation, logout, reauthentication, deletion, and account-linking UX.
- Auth analytics and localized errors.

Gate:

- A new Google user and an explicitly linked existing Apple user both reach the same stable internal account on Android and iOS.
- Rotation races, stale access tokens, offline launch, revoked sessions, and deletion behave safely.

### Phase 3 — Shell, Onboarding, Today, And Planning

Deliverables:

- Production navigation shell, onboarding, personalization, calibration, plan creation, Today, readiness, weather, workout detail/customization, Me foundation, and settings/preferences sync.
- Offline caches tagged by locale and account.
- Themes, accessibility, analytics, and all supported translations for these surfaces.

Gate:

- A new user can complete onboarding and launch the exact displayed workout online or from a valid offline cache.

### Phase 4 — Recording, Camera, And Recovery

Deliverables:

- Foreground recording service, map/camera modes, countdown, goals, structured workouts, GPS filtering, elevation, pause segments, live metrics, photo capture, active-session journal, finish reflection, discard confirmation, and local save.
- Notification-channel and permission flows needed for recording.
- Battery, thermal, storage, lifecycle, and process-death handling.

Gate:

- Real-device long sessions survive screen lock, background restrictions, camera use, Bluetooth changes, and process recreation without lost distance, teleport lines, duplicate saves, or corrupt media.

### Phase 5 — Activity Sync, Detail, Progress, And Health

Deliverables:

- Full local activity database, media files, pagination, two-way synchronization, tombstones, photo transfer, edit/delete, manual sessions, share cards, GPX/GeoJSON, activity detail, splits, elevation, progress, gear, PRs, predictions, and Health Connect import/export.
- Cross-platform deterministic fixtures for core calculations.

Gate:

- Offline changes converge idempotently across Android, backend, and iOS.
- Swift and Kotlin engines produce equivalent semantic results for canonical fixtures.

### Phase 6 — Live Coaching, Assistant, Voice, And Music

Deliverables:

- Catalog and preference selection, coaching session planning, signed fixed packs, planned-audio cache, streaming/fixed/TTS playback, moment policy, audio focus, ducking, interruptions, Bluetooth routing, companion chat, local fallbacks, speech recognition, live voice commands, app shortcuts, Spotify, and supported Android music integration.

Gate:

- Coaching and commands work during locked-screen recording with intermittent networking, music playback, wired/Bluetooth output, calls, and audio-focus changes in every supported language.

### Phase 7 — Social, Recognition, Routes, Safety, And Notifications

Deliverables:

- Feed, profiles, connections, groups, Circles, events, invitations, Cheers, recognition, community routes, bookmarks, publishing, route guidance, trusted contacts, private live sharing, group live maps, inbox, FCM, deep links, reporting, and blocking.
- Equivalent visibility, route privacy, health/plan exclusion, and analytics safeguards.

Gate:

- Android and iOS accounts can complete every cross-platform interaction and receive correctly routed notifications without exposing private training or health causes.

### Phase 8 — Wear OS And Platform Integration

Deliverables:

- Wear OS start/pause/resume/finish, live metrics and heart rate, workout ownership, disconnection recovery, Health Services recording, phone synchronization, complications/tiles where product-approved, and activity-source deduplication.
- Final Android shortcuts, widgets, share targets, and platform polish.

Gate:

- Phone-only, watch-only, and phone-plus-watch sessions have one canonical owner and cannot create duplicate activities.

### Phase 9 — Public Release

Deliverables:

- Supported-device/OS matrix, performance and battery budgets, Play policy audit, Data safety form inputs, privacy disclosures, content rating, store assets, native-speaker review, accessibility audit, security review, staged rollout controls, operational dashboards, and rollback/kill-switch runbook.
- Closed-track evidence is used for release validation, not as a reduced product destination.

Gate:

- All parity rows are complete or explicitly removed from both platforms by an owner decision.
- Release build passes compilation, lint, contract, integration, migration, device, localization, accessibility, privacy, security, battery, and recovery checks.
- Backend capacity, alerting, provider configuration, notification delivery, media storage, and account deletion are production-ready.

## Cross-Cutting Acceptance Matrix

Every feature phase must cover:

- signed-in, signed-out, expired-session, and account-switch states;
- first use, denied permission, permanently denied permission, revoked permission, and unavailable hardware/service;
- online, offline, slow, interrupted, retry, duplicate request, and stale-cache states;
- foreground, background, locked screen, process recreation, low memory, and low storage where relevant;
- light/dark and all Plainstride themes;
- English, Spanish, and Simplified Chinese, including TalkBack and spoken output;
- metric/imperial distance and Celsius/Fahrenheit combinations;
- analytics success/failure coverage without sensitive properties;
- account deletion and local/private-data cleanup;
- iOS/Android interoperability for shared backend state.

## Release Definition Of Done

Android is ready for public release only when:

- every parity row is implemented and verified or an explicit owner decision changes the product contract;
- local recording and save do not depend on backend availability;
- active sessions recover safely from normal Android lifecycle and process-loss scenarios;
- synchronized writes are idempotent and cross-device state converges;
- permissions are requested in context with useful denied-state behavior;
- all user-facing and accessibility text is localized in the three supported languages;
- analytics and diagnostics pass the existing privacy allowlist;
- account export/deletion, notification controls, and health permissions meet platform and product requirements;
- release builds contain no debug identities, development endpoints, verbose private logs, or test credentials;
- Play production rollout has monitoring, feature kill switches, and a documented rollback path.

## Phase Change Discipline

- Work on one approved phase at a time.
- At the end of each phase, run its documented checks without running unrelated test suites unless explicitly requested.
- Update this document when implementation reveals a changed boundary or release requirement.
- Commit only phase-owned files and leave unrelated worktree changes untouched.
- Report completed deliverables, verification evidence, known risks, and the next phase scope, then wait for owner confirmation.
