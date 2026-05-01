# Music Integration Plan

Open this when planning Apple Music or Spotify support, workout playback controls, coach-and-music coexistence, or music-provider account linking.

## Snapshot

Outbound should treat music as a workout companion, not as a media-export feature.

Recommended rollout order:

1. Apple Music playback companion
2. coach and music audio-session polish
3. Spotify playback companion
4. optional smart playlist and recommendation features

Do not plan v1 around soundtrack export, music-attached photo/video output, or deep catalog merchandising.

## Product Goal

Music should make a run easier to start and nicer to stay in without pulling focus away from Outbound's camera-first coach experience.

The right first version is:

- choose a provider
- pick or resume a workout mix quickly
- control playback without leaving the recording flow
- keep coach nudges understandable while music is playing

The wrong first version is:

- large browse surfaces that recreate a music app
- heavy recommendation work before playback is dependable
- features that imply Outbound owns or redistributes music media

## External Constraints

### Apple Music

Best fit for Outbound on iPhone.

Why:

- native iOS framework support through `MusicKit`
- catalog search, user library access, recommendations, and playback
- Apple provides both app-owned playback and system-player control paths
- Apple has sample code specifically framed around outdoor running

Important requirements:

- enable the MusicKit app service for the app's explicit App ID
- add `NSAppleMusicUsageDescription` to `Info.plist`
- request `MusicAuthorization` before accessing music data
- check `MusicSubscription.current` before showing features that require playback or subscription offers

Important playback choice:

- `ApplicationMusicPlayer`: app-owned playback that does not affect the Music app's state
- `SystemMusicPlayer`: controls the Music app's shared playback state

Recommendation:

- prefer `ApplicationMusicPlayer` for Outbound v1 so the run experience feels self-contained
- consider `SystemMusicPlayer` only if users strongly expect continuity with what the Music app is already playing

### Spotify

Possible, but more constrained than Apple Music.

How it works:

- the Spotify iOS SDK primarily controls playback through the Spotify app
- the user authenticates with Spotify
- Outbound connects to the Spotify app and remotely controls playback
- Spotify handles playback, networking, and caching

Important requirements:

- Spotify app installed on the user's device
- Spotify developer app registration and redirect URI setup
- iOS URL-scheme plumbing for auth return
- app-remote connection lifecycle handling when the app becomes active

Important policy constraint:

- Spotify policy forbids synchronizing Spotify audio with visual media

Implication for Outbound:

- Spotify can power in-run playback control
- Spotify should not be used for soundtrack-style photo/video features

## Recommended User Experience

### Primary Entry Points

- `Me` tab: connect provider, disconnect provider, and set a default provider
- `RecordView` pre-start page: choose music source and quick-pick recent playlist or station
- live recorder HUD: compact now-playing row with play/pause and skip
- post-run summary: optionally show what playlist or station was used, but do not make this the focal point

### V1 User Flow

1. User taps `Connect Apple Music` from Me or from the run start page.
2. Outbound explains the benefit: play music during runs and keep coach prompts audible.
3. User grants Apple Music permission.
4. User chooses a quick music source:
   - recent playlist
   - library workout playlist
   - recommended upbeat mix
   - continue current playback
5. During the run, the HUD shows compact playback controls.
6. When the coach speaks, music ducks briefly and returns smoothly.

### V1 UI Rules

- keep music controls secondary to run stats, camera, and pause/finish
- do not add a full-screen music browser inside the recording flow
- favor one-tap quick picks over deep navigation
- treat "continue what I'm already listening to" as a first-class option

## Architecture Recommendation

Add a small provider-agnostic music layer under `Integrations` and keep provider specifics isolated.

Suggested modules:

- `Integrations/Music/MusicProvider.swift`
- `Integrations/Music/MusicAuthorizationStore.swift`
- `Integrations/Music/MusicPlaybackStore.swift`
- `Integrations/Music/MusicQuickPick.swift`
- `Integrations/Music/MusicSessionCoordinator.swift`
- `Integrations/Music/AppleMusic/AppleMusicService.swift`
- `Integrations/Music/AppleMusic/AppleMusicPlaybackController.swift`
- `Integrations/Music/Spotify/SpotifyService.swift`
- `Integrations/Music/Spotify/SpotifyAppRemoteController.swift`

### Responsibilities

`MusicProvider.swift`

- shared enum for `.appleMusic`, `.spotify`, `.none`
- source-of-truth capability flags such as `supportsCatalogSearch` and `requiresCompanionApp`

`MusicAuthorizationStore.swift`

- observable state for connection status, provider availability, and authorization prompts
- user-facing connect/disconnect actions
- default-provider persistence in `UserDefaults`

`MusicPlaybackStore.swift`

- current track metadata for UI
- playback status, elapsed time, and capability flags
- play, pause, resume, skip, seek-if-supported

`MusicQuickPick.swift`

- normalized model for "Run Mix", recent playlist, station, or continue-current item
- provider-agnostic enough for the start screen UI

`MusicSessionCoordinator.swift`

- orchestration layer between recording, coach speech, and provider playback
- reacts to run start, pause, resume, finish
- owns ducking policy during coach voice prompts

`AppleMusicService.swift`

- MusicKit authorization
- subscription and capability checks
- quick-pick loading from library, recent items, and recommendations

`AppleMusicPlaybackController.swift`

- wraps `ApplicationMusicPlayer`
- normalizes player events into Outbound playback state

`SpotifyService.swift`

- auth and provider connection state
- quick-pick retrieval from Spotify APIs where appropriate

`SpotifyAppRemoteController.swift`

- app-remote lifecycle
- playback command handling
- player-state subscription

### Boundaries To Keep

- `ActivityRecorder` should not know provider details
- `VirtualCoach` should not issue provider commands directly
- camera and recording UI should consume normalized playback state only
- provider auth callbacks should not leak into unrelated app flows

## App Wiring

Current app entry already creates multiple observable stores in `App/OutboundApp.swift`.

Add:

- `MusicAuthorizationStore`
- `MusicPlaybackStore`

Optional later:

- `MusicSessionCoordinator` as a long-lived object owned by the app root or `RecordView`

Recommended ownership:

- `OutboundApp` creates authorization and playback stores
- `RecordView` asks the coordinator to bind the current activity session
- `VirtualCoach` exposes a narrow callback or notification when speech begins and ends

## Audio Session Strategy

Outbound already declares `audio` in `UIBackgroundModes`, but it does not yet have an explicit music/coaching audio strategy.

V1 behavior should be:

- user music keeps playing while the app records
- coach speech ducks music briefly instead of stopping it
- pausing a run should not automatically stop music
- finishing a run should not force-stop music unless the user started playback from an Outbound-only quick pick and we later decide that behavior is preferable

Implementation guidance:

- centralize `AVAudioSession` policy in one place instead of scattering it across coach and music code
- test for interruptions, headphones disconnecting, and background/foreground transitions
- define whether coach voice uses ducking or spoken-audio interruption before writing provider code

Suggested future file:

- `Core/AudioSessionCoordinator.swift`

Responsibilities:

- configure category and options
- coordinate spoken coach output with background music
- react to interruption and route-change notifications

## Minimum iOS Project Changes

### Required For Apple Music

In `ios/Outbound/SupportFiles/Info.plist` add:

- `NSAppleMusicUsageDescription`

Suggested copy:

- `Outbound uses Apple Music to play music during workouts and keep your coach experience in one place.`

In Apple Developer account:

- edit the app's explicit App ID
- enable the `MusicKit` app service

No new entitlement file entry is expected for the MusicKit app service itself; the service associates to the bundle ID at runtime once enabled in the developer portal.

### Likely Required For Spotify

In `Info.plist`:

- add a Spotify auth callback URL scheme
- add `LSApplicationQueriesSchemes` entries needed to detect or open the Spotify app

In Spotify developer dashboard:

- register the app
- configure redirect URI
- store client identifiers securely in project configuration

## Proposed SwiftUI Surfaces

### Me Tab

Add a `Connected Music` card near the existing Apple Health card.

Contents:

- provider connection state
- connect Apple Music button
- connect Spotify button
- default provider selector
- last used source summary

### Record Start Page

Add a compact `Music` section below session intent and above Start.

Contents:

- provider pill
- quick picks list
- continue-current option
- small "change" action that opens a focused selector sheet

### Live Recorder HUD

Add a compact now-playing strip inside the existing bottom card.

Contents:

- track title
- artist or playlist subtitle
- play/pause
- skip

Rules:

- keep it one row tall by default
- hide artwork in v1 unless it fits cleanly
- collapse gracefully when no provider is connected

## Data Model Guidance

Persist only lightweight, provider-safe metadata.

Suggested model:

- provider kind
- provider item identifier
- display title
- subtitle
- launch context such as `quickPick`, `continueCurrent`, or `recommendation`
- timestamp when playback started

Do not persist:

- raw audio assets
- stream URLs
- anything that implies local media export or redistribution

## Delivery Plan

### Phase 1: Apple Music Foundation

Ship:

- MusicKit app service setup
- `NSAppleMusicUsageDescription`
- authorization flow
- subscription capability checks
- app-owned playback through `ApplicationMusicPlayer`
- Me-tab connection card
- RecordView quick-pick section
- live HUD playback controls

Success bar:

- user can start a run with Apple Music in under three taps from the start page

### Phase 2: Coach And Audio Polish

Ship:

- `AudioSessionCoordinator`
- predictable ducking during coach speech
- interruption handling
- route-change handling for headphones and car audio

Success bar:

- coach voice remains intelligible without making music feel broken

### Phase 3: Spotify Companion

Ship:

- Spotify auth setup
- app-remote connection lifecycle
- quick-pick parity where feasible
- live playback controls

Success bar:

- Spotify users can start and control playback with acceptable parity, while known provider differences remain explicit

### Phase 4: Smarter Music Suggestions

Ship candidates:

- pace-appropriate quick picks
- mood-based suggestions tied to run intent
- recent and favorite workout mixes
- Apple Music recommendations surfaced before the run

Success bar:

- suggestions help users start faster without turning Outbound into a music browser

## Open Questions To Resolve Before Implementation

- Should Apple Music v1 use `ApplicationMusicPlayer` or preserve continuity with current system playback through `SystemMusicPlayer`?
- Should Outbound auto-resume music after coach speech, or only duck audio and let the provider continue naturally?
- Should music controls appear directly in the camera HUD from day one, or only in an expanded bottom card state?
- Do we want provider-specific quick picks, or a single normalized list that hides most differences?
- Is "continue what I'm already listening to" the default, or should Outbound actively suggest a run mix first?

## Recommended Decision Defaults

Use these defaults unless product priorities change:

- ship Apple Music before Spotify
- use `ApplicationMusicPlayer` first
- build one normalized quick-pick UI
- keep controls compact in the recorder HUD
- duck rather than pause during coach speech
- avoid any soundtrack, export, or media-sync claims in product copy
