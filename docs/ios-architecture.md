# iOS Architecture

Open this when touching app flow, Swift source layout, recording, camera, persistence, or on-device session analysis.

## Project Layout

- `ios/Outbound/Outbound.xcodeproj`: main Xcode project.
- `ios/Outbound/Outbound`: iOS app source. Xcode uses file-system-synchronized groups, so new Swift files under this folder are picked up automatically.
- `ios/Outbound/SupportFiles/Info.plist`: app plist. `GENERATE_INFOPLIST_FILE = NO`, so required bundle keys and usage descriptions must stay here.
- `ios/Outbound/SupportFiles/Outbound.entitlements`: currently an empty entitlement dict for personal-team device installs.
- `ios/Outbound/Outbound/GoogleService-Info.plist`: local Firebase config. This file is gitignored but is copied into the app when present.
- `Tests/OutboundSessionAnalysisTests`: Swift Package tests for the on-device session-analysis module.
- `Package.swift`: exposes only the session-analysis subset as `OutboundSessionAnalysis` for lightweight package testing outside the full iOS app target.

## App Entry

- `App/OutboundApp.swift`: app root. Calls `FirebaseBootstrap.configureIfAvailable()`, creates `AuthStore`, `CoachStore`, `CoachCatalogStore`, `ActivityStore`, and `HealthAuthorizationStore`, and shows `MainTabView` when login is skipped or authenticated.
- `App/AuthStore.swift`: Firebase phone auth wrapper plus login bypass. `AuthStore.isLoginSkipped = true` is the current feature-development switch.
- `App/MainTabView.swift`: three tabs: Today (`TodayView`), Social (`ActivityFeedView`), and Me (`ProfileView`). `MainTabView` now owns modal launch into `RecordView` for both suggested sessions and freestyle starts.

## Recording

- `Activity/RecordView.swift`: owns the shared recording flow presented from Today. It shows the confirmation state for a suggested session or freestyle run, opens the live camera/map recorder after Start, activates `VirtualCoach` with `coachCatalog.selectedPersona`, forwards live snapshots to the coach, collects captured photos during the activity, and presents the reflection-first Save/Discard sheet after finish. Saving an activity also persists the route needed for map display and later export.
- `Core/ActivityRecorder.swift`: main activity state machine. Tracks elapsed time, distance, current pace, heart-rate placeholder, and `liveSnapshot`. Supports pause/resume by stopping both the session timer and GPS updates without discarding the current track. `finish()` returns `ActivitySummary` with track points.
- `Core/LocationManager.swift`: CoreLocation wrapper. Requests when-in-use permission, tracks locations with best navigation accuracy, computes total distance and recent pace, supports background location updates, and can temporarily stop/resume GPS updates during a paused activity.
- `Core/ActiveSessionSnapshot.swift`: lightweight real-time snapshot passed to the coach.
- `Core/SessionFormatting.swift`: shared formatting helpers for pace and elapsed seconds.

## Camera

- `Camera/CameraController.swift`: AVFoundation capture session, camera authorization, session queue, retained photo-capture delegates, and still-photo capture.
- `Camera/CameraPreviewLayer.swift`: SwiftUI wrapper for `AVCaptureVideoPreviewLayer`.
- `Camera/CameraHUDView.swift`: full-screen camera plus a Strava-style bottom state card and a right-edge control rail during an active session. While recording, the bottom card shows live stats and Pause; while paused, it expands into Resume and Finish. Captured photos are returned to `RecordView` with `PhotoMetadata`, including whether the shot was taken while active or paused.

## Local Persistence

- `Core/LocalActivityStore.swift`: saves finished activities under Application Support at `Outbound/Activities`.
- `activities.json`: manifest containing `SavedActivity` entries, compact canonical route data for saved activities, and saved photo metadata. Older manifests with raw `trackPoints` still load through a backward-compatibility path.
- Per-activity photo files are stored as JPEGs under `<activity-id>/photos/photo-XX.jpg`.
- `Core/LocalActivityStore.swift`: also contains the canonical route model plus on-demand route export helpers for `GPX` and `GeoJSON`, so the app stores compact route data and only materializes share files when needed.

## Coach And Session Analysis

- `Coach/CoachTemplate.swift`: predefined coach catalog model. Current fixtures include one female and one male coach for Run and Bike. Each template defines sport, persona traits, sample nudges, voice options, face options, and a prompt seed.
- `Coach/CoachCatalogStore.swift`: local catalog and selected coach customization. Persists selected template, voice, face, coaching intensity, and nudge frequency in `UserDefaults`.
- `Coach/CoachSelectionView.swift`: Me-tab coach picker and customization UI.
- `Coach/VirtualCoach.swift`: consumes `ActiveSessionSnapshot` values while active, keeps a rolling history, requests analysis after 20 seconds and then at the selected persona's nudge frequency, seeds the first message from the selected session intent when present, displays `lastNudge`, and speaks nudges with the selected voice settings.
- `Coach/SessionAnalysisProvider.swift`: provider protocol plus rule-based fallback implementation. `SessionAnalysisRequest` carries both the personalized `CoachProfile` and selected `CoachPersona`.
- `Coach/AppleFoundationModelSessionAnalysisProvider.swift`: preferred provider when FoundationModels is available on iOS 26/macOS 26. Instructions include selected coach persona, style, intensity, and prompt seed.
- `Coach/CoachProfile.swift`: athlete/coach profile model used to contextualize analysis.
- `Coach/CoachStore.swift`: loads/syncs coach profile through `APIClient`; with login skipped it generally has no remote user ID.

## Motivation

- `App/OutboundApp.swift`: now also defines `DailyCheckInStore`, which persists one local readiness selection per day in `UserDefaults`.
- `App/MainTabView.swift`: now also contains the motivation MVP types and `TodayView`, including spark, check-in, suggested actions, momentum strip, recent activity preview, and the local engine that derives motivation state and finish reflections.

## Network And Placeholders

- `Core/APIClient.swift`: placeholder backend client for coach profile and future activity upload.
- `Social/ActivityFeedView.swift`: local-first social hub with Squad, Clubs, and Rivals scopes, seeded feed cards, latest-run sharing from `ActivityStore`, club joins, challenge cards, and rivalry rows. See `docs/social.md` before changing social product loops.
- `App/ProfileView.swift`: selected coach card, Apple Health connection card, profile highlights, `My Activities` section, and sign-out control. Sign-out is a no-op while login is skipped.

## Integrations

- `Integrations/HealthKit/HealthKitService.swift`: lightweight `HealthKit` wrapper that defines the initial workout import/write-back permission set, exposes authorization snapshot state, and safely reports unavailable environments.
- `Integrations/HealthKit/HealthAuthorizationStore.swift`: UI-facing observable store for refreshing HealthKit permission state and requesting Apple Health access from the Me tab.
