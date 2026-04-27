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

- `App/OutboundApp.swift`: app root. Calls `FirebaseBootstrap.configureIfAvailable()`, creates `AuthStore` and `CoachStore`, and shows `MainTabView` when login is skipped or authenticated.
- `App/AuthStore.swift`: Firebase phone auth wrapper plus login bypass. `AuthStore.isLoginSkipped = true` is the current feature-development switch.
- `App/MainTabView.swift`: three tabs: Home (`ActivityFeedView`), Record (`RecordView`), and Me (`ProfileView`).

## Recording

- `Activity/RecordView.swift`: owns recording screen state. Creates `LocationManager` and `ActivityRecorder`, starts/stops recording, forwards live snapshots to `VirtualCoach`, collects captured photos, and presents the Save/Discard sheet.
- `Core/ActivityRecorder.swift`: main activity state machine. Tracks elapsed time, distance, current pace, heart-rate placeholder, and `liveSnapshot`. `finish()` returns `ActivitySummary` with track points.
- `Core/LocationManager.swift`: CoreLocation wrapper. Requests when-in-use permission, tracks locations with best navigation accuracy, computes total distance and recent pace, and supports background location updates.
- `Core/ActiveSessionSnapshot.swift`: lightweight real-time snapshot passed to the coach.
- `Core/SessionFormatting.swift`: shared formatting helpers for pace and elapsed seconds.

## Camera

- `Camera/CameraController.swift`: AVFoundation capture session, camera authorization, session queue, retained photo-capture delegates, and still-photo capture.
- `Camera/CameraPreviewLayer.swift`: SwiftUI wrapper for `AVCaptureVideoPreviewLayer`.
- `Camera/CameraHUDView.swift`: full-screen camera plus bottom data overlay. The activity overlay pins a persistent round photo thumbnail slot to its right edge without shrinking the stats grid, shows a stacked last-photo thumbnail/count after capture, and animates the captured image from the shutter area into the stack after a valid capture. Captured photos are returned to `RecordView` with `PhotoMetadata`.

## Local Persistence

- `Core/LocalActivityStore.swift`: saves finished activities under Application Support at `Outbound/Activities`.
- `activities.json`: manifest containing `SavedActivity` entries, track points, and saved photo metadata.
- Per-activity photo files are stored as JPEGs under `<activity-id>/photos/photo-XX.jpg`.

## Coach And Session Analysis

- `Coach/VirtualCoach.swift`: consumes `ActiveSessionSnapshot` values while active, keeps a rolling history, requests analysis after 20 seconds and then every 75 seconds, displays `lastNudge`, and speaks nudges with `AVSpeechSynthesizer`.
- `Coach/SessionAnalysisProvider.swift`: provider protocol plus rule-based fallback implementation.
- `Coach/AppleFoundationModelSessionAnalysisProvider.swift`: preferred provider when FoundationModels is available on iOS 26/macOS 26.
- `Coach/CoachProfile.swift`: athlete/coach profile model used to contextualize analysis.
- `Coach/CoachStore.swift`: loads/syncs coach profile through `APIClient`; with login skipped it generally has no remote user ID.

## Network And Placeholders

- `Core/APIClient.swift`: placeholder backend client for coach profile and future activity upload.
- `Social/ActivityFeedView.swift`: placeholder feed UI.
- `App/ProfileView.swift`: profile/coach card and sign-out control. Sign-out is a no-op while login is skipped.
