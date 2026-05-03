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

- `App/OutboundApp.swift`: app root. Calls `FirebaseBootstrap.configureIfAvailable()`, creates `AuthStore`, `CoachStore`, `CoachCatalogStore`, `ActivityStore`, `GoalStore`, `HealthAuthorizationStore`, `HealthImportStore`, and `DailyCheckInStore`, and shows `MainTabView` after Firebase authentication.
- `App/AppDelegate.swift`: minimal UIKit bridge used by the SwiftUI app to hand Firebase Auth OAuth callback URLs back to `Auth.auth().canHandle(_:)` after Google sign-in.
- `App/AuthStore.swift`: Firebase auth wrapper for hosted Google OAuth plus email/password and phone-number-as-identifier password login. Phone logins are normalized into an internal email alias so the app can support `phone + password` without SMS verification or Apple Sign In.
- `App/AuthView.swift`: login UI for Google sign-in plus email/phone password auth. When `GoogleService-Info.plist` is missing, the screen blocks real auth and explains how to finish Firebase setup.
- `App/MainTabView.swift`: top-level shell with a lightweight floating `Me` / `Social` pill switcher, the floating activity button shown on both sections, the compact assistant bar, and the retained overlay presentation into `RecordView` so live sessions can be hidden and reopened without resetting.
- `OutboundLiveActivityExtension/`: WidgetKit extension that renders the active-session Live Activity for the lock screen and Dynamic Island.

## Recording

- `Activity/RecordView.swift`: owns the shared activity start page and recording flow. When opened from a Me-tab suggestion it shows that confirmation state; when opened from the floating activity button it jumps straight to freestyle confirmation. After Start it opens the live camera/map recorder, activates `VirtualCoach` with `coachCatalog.selectedPersona`, forwards live snapshots to the coach, collects captured photos during the activity, and presents the reflection-first Save/Discard sheet after finish. A top `chevron.down` hides the page without stopping an active session, and the floating activity button reopens it.
- `Core/ActivityRecorder.swift`: main activity state machine. Tracks elapsed time, distance, current pace, heart-rate placeholder, and `liveSnapshot`. Elapsed time is derived from active wall-clock segments rather than only a foreground timer, and location updates also refresh the live snapshot so coaching continues while the app is backgrounded during a run. Supports pause/resume by stopping both the UI timer and GPS updates without discarding the current track. `finish()` returns `ActivitySummary` with track points.
- `Core/SessionLiveActivityManager.swift`: ActivityKit bridge that starts, updates, and ends the active session Live Activity using recorder snapshots.
- `Shared/OutboundLiveActivityAttributes.swift`: shared ActivityKit attributes/content-state model compiled into both the app target and the widget extension.
- `Core/LocationManager.swift`: CoreLocation wrapper. Requests when-in-use permission, tracks locations with best navigation accuracy, computes total distance and recent pace, supports background location updates, and can temporarily stop/resume GPS updates during a paused activity.
- `Core/ActiveSessionSnapshot.swift`: lightweight real-time snapshot passed to the coach.
- `Core/SessionFormatting.swift`: shared formatting helpers for pace and elapsed seconds.

## Camera

- `Camera/CameraController.swift`: AVFoundation capture session, camera authorization, session queue, retained photo-capture delegates, and still-photo capture.
- `Camera/CameraPreviewLayer.swift`: SwiftUI wrapper for `AVCaptureVideoPreviewLayer`.
- `Camera/CameraHUDView.swift`: full-screen camera plus a Strava-style bottom state card and a right-edge control rail during an active session. While recording, the bottom card shows live stats, the latest coach message, music state, and Pause; while paused, it expands into Resume and Finish. Captured photos are returned to `RecordView` with `PhotoMetadata`, including whether the shot was taken while active or paused.

## Local Persistence

- `Core/LocalActivityStore.swift`: saves finished activities under Application Support at `Outbound/Activities`.
- `activities.json`: manifest containing `SavedActivity` entries, compact canonical route data for saved activities, and saved photo metadata. Older manifests with raw `trackPoints` still load through a backward-compatibility path.
- Per-activity photo files are stored as JPEGs under `<activity-id>/photos/photo-XX.jpg`.
- `Core/LocalActivityStore.swift`: also contains the canonical route model plus on-demand route export helpers for `GPX` and `GeoJSON`, so the app stores compact route data and only materializes share files when needed.

## Coach And Session Analysis

- `Coach/CoachTemplate.swift`: predefined coach catalog model. Current fixtures include one female and one male coach for Run and Bike. Each template defines sport, persona traits, sample nudges, voice options, face options, and a prompt seed.
- `Coach/CoachCatalogStore.swift`: local catalog and selected coach customization. Persists selected template, voice, face, coaching intensity, and nudge frequency in `UserDefaults`.
- `Coach/CoachSelectionView.swift`: Me-tab coach picker and customization UI.
- `Coach/VirtualCoach.swift`: consumes `ActiveSessionSnapshot` values while active, keeps a rolling history, requests analysis after 20 seconds and then at the selected persona's nudge frequency, seeds the first message from the selected session intent when present, displays `lastNudge`, suppresses recently repeated spoken lines, and speaks nudges with `AVSpeechSynthesizer` while coordinating the spoken-audio `AVAudioSession` lifecycle.
- `Coach/SessionAnalysisProvider.swift`: provider protocol plus rule-based fallback implementation. `SessionAnalysisRequest` carries both the personalized `CoachProfile` and selected `CoachPersona`.
- `Coach/AppleFoundationModelSessionAnalysisProvider.swift`: preferred provider when FoundationModels is available on iOS 26/macOS 26. Instructions include selected coach persona, style, intensity, and prompt seed.
- `Coach/CoachProfile.swift`: athlete/coach profile model used to contextualize analysis.
- `Coach/CoachStore.swift`: loads/syncs coach profile through `APIClient`; remote sync depends on a Firebase-authenticated user ID, while local-account and local-session auth keep coach data local-only.

## Motivation

- `App/OutboundApp.swift`: now also defines `DailyCheckInStore`, which persists one local readiness selection per day in `UserDefaults`.
- `Goals/GoalModels.swift`, `Goals/GoalProgressEngine.swift`, and `Goals/GoalStore.swift`: local-first weekly focus models, progress computation from saved activities, and persisted coach conversation state.
- `Goals/GoalConversationCard.swift`: motivation-card UI for conversational goal setup, active-focus progress, and lightweight adjustment.
- `App/OutboundApp.swift`: now also defines training plan response models and `TrainingPlanStore`, which fetches server-owned plan state through `APIClient`, caches the last active plan/week/today payload for offline rendering, and falls back to local deterministic rules when the API is unavailable.
- `App/TrainingPlanLibrary.swift`: offline fallback structured plan library. It stores `TrainingPlanTemplate`, `TrainingPlanWeek`, `TrainingPlanWorkout`, and `TrainingPlanWorkoutStep` content, including imported MIT Couch-to-5K data, imported MIT `time-to-run` base and half-marathon plans, and authored 10K, 10 mile, half marathon, consistency, and comeback plans. The backend-exported copy is now the source of truth for authenticated recommendation and Today flows.
- `App/MainTabView.swift`: now also contains the motivation MVP types and `MotivationDashboardView`, which drives the Me-tab spark card, compact `Now` card for either today's plan or coach recommendation, readiness-aware copy, momentum strip, and the local engine that derives motivation state and finish reflections.
- `docs/goals-progress.md`: the product and implementation spec for local-first focus and goal tracking. The V1 implementation now uses `GoalStore`, progress chips in Me's motivation surface, and goal-aware post-run reflection notes.

## Assistant

- `App/OutboundApp.swift`: assistant capabilities, message records, local-first assistant store, `UserDefaults` persistence, and the optional Apple Foundation Models responder.
- `Core/APIClient.swift`: assistant chat transport to the backend, plus existing coach/activity endpoints.
- `App/MainTabView.swift`: persistent bottom assistant shell for the main tabs, collapsed contextual hints, and expanded assistant presentation.
- `Activity/RecordView.swift`: compact live-session assistant entry so the assistant stays reachable without overwhelming the camera/map experience.
- `App/ProfileView.swift`: chat-style assistant UI for discovery, navigation, support, brainstorming, and planning.
- `backend/src/routes/assistant.ts`: backend assistant chat route that currently uses a BoatShare-style DeepSeek integration.
- `docs/assistant.md`: focused product and implementation notes for the assistant surface.

## Network And Placeholders

- `Core/APIClient.swift`: placeholder backend client for coach profile and future activity upload.
- `Social/ActivityFeedView.swift`: local-first social hub with Squad, Clubs, and Rivals scopes, seeded feed cards, latest-run sharing from `ActivityStore`, club joins, challenge cards, and rivalry rows. See `docs/social.md` before changing social product loops.
- `App/ProfileView.swift`: combined Me-tab home surface. It embeds the simplified motivation dashboard above a compact recent-activity card, and adds a top-right Settings entry point that now owns account, coach customization, Apple Health, Apple Music, and sign-out.

## Integrations

- `Integrations/HealthKit/HealthKitService.swift`: lightweight `HealthKit` wrapper that defines the initial workout import/write-back permission set, exposes authorization snapshot state, and safely reports unavailable environments.
- `Integrations/HealthKit/HealthAuthorizationStore.swift`: UI-facing observable stores for refreshing HealthKit permission state, requesting Apple Health access from the Me tab, and previewing recent imported workouts with a normalized `ImportedWorkout` model.
