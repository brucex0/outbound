# Device And App Integration Plan

Open this when deciding how Outbound should ingest health, wearable, or third-party fitness-app data.

## Snapshot

Outbound can support external fitness data through three integration paths:

- Apple `HealthKit` on iPhone
- direct watch or sensor integration
- vendor or app cloud APIs with account linking

For the current product, the best path is `HealthKit` first, Apple Watch second, and selected third-party OAuth imports after that.

## What "Direct" Usually Means

There are several different levels of integration:

- device writes into Apple Health, and Outbound reads via `HealthKit`
- Outbound talks to a watch app running on Apple Watch during a live workout
- Outbound talks to a sensor or wearable SDK directly on the phone
- Outbound imports from a vendor or fitness app backend after the user signs in

These are not equally available. On iPhone, `HealthKit` is the broadest and most reliable integration surface.

## Recommended Default Strategy

Use this priority order unless a specific partner opportunity changes it:

1. read from Apple Health
2. write Outbound workouts back to Apple Health
3. add a dedicated Apple Watch companion for live sessions
4. add OAuth-based imports for a few high-value services
5. consider direct BLE or vendor-SDK work only for a clear product need

Why this order:

- lowest user friction
- strongest iOS fit
- broadest ecosystem coverage through one integration
- avoids building separate importer logic for every watch or app too early

## Source Categories

### Apple Health on iPhone

Status:
- strong yes

Best use cases:
- historical workout import
- route, distance, duration, calories
- heart rate and resting heart rate
- VO2 max and cardio-fitness context when available
- sleep or recovery inputs if Outbound later wants readiness signals

Notes:
- data access is permission-based
- not every metric is available for every user
- some samples arrive after a delay depending on source-device sync behavior

Recommended v1 data types:

- workouts
- workout routes
- heart rate
- active energy burned
- distance walking/running
- resting heart rate

Recommended v2 data types:

- heart-rate variability
- respiratory rate
- sleep analysis
- VO2 max
- step count

### Apple Watch

Status:
- yes, but split into two product modes

Mode 1: HealthKit-backed watch sync
- Apple Watch records through the system or another app
- data lands in Apple Health
- Outbound reads it on iPhone

Mode 2: dedicated Outbound watch experience
- build a watchOS companion
- start and monitor live workouts on watch
- pass state to the phone app when needed
- support live heart rate and watch-native workout capture

Recommendation:
- do Mode 1 first for breadth
- do Mode 2 when live watch-led workouts become important to retention

### Popular Fitness Apps

There are two common cases.

Case 1: app syncs to Apple Health
- Outbound can often read the resulting workout or metric through `HealthKit`

Case 2: app has its own API
- Outbound can import with OAuth and vendor-specific mapping

Examples worth evaluating after HealthKit:

- Strava
- Oura
- TrainingPeaks

These are good candidates because they cover social fitness, recovery, and coaching/training use cases.

### Popular Watches And Wearables

General rule:
- many wearables are not practical as true local-direct integrations on iPhone
- the realistic options are Apple Health sync or vendor cloud APIs

Vendor notes:

- Garmin: likely via Garmin Connect APIs or Apple Health sync, not local-direct watch integration
- Fitbit: usually via Fitbit account APIs or Apple Health sync where available
- Oura: best treated as an OAuth/cloud integration
- WHOOP: best treated as an OAuth/cloud integration
- Polar, COROS, Suunto: usually cloud/API or Apple Health sync, not direct local watch access

## Recommended Product Scope

### Phase 1: Health Foundation

Goal:
- make Outbound compatible with the data users already have

Ship:
- Apple Health permission flow
- import of recent workouts and routes
- read heart rate for activity detail and coach context
- write Outbound-recorded workouts back to Apple Health

User value:
- Outbound stops feeling like an isolated tracker
- coach features can use real fitness context

### Phase 2: Better Coaching Inputs

Goal:
- improve readiness and in-run coaching quality

Ship:
- read resting HR, HRV, sleep, and recent training load proxies
- use imported history for suggested actions and comeback logic
- show source attribution on imported activities

User value:
- suggestions feel more personalized and credible

### Phase 3: Apple Watch Depth

Goal:
- support users who want live wearable-driven sessions

Ship:
- watchOS app for start/pause/finish
- live heart-rate awareness during recording
- route and workout continuity between phone and watch

User value:
- Outbound can support serious runners without giving up its camera-first phone experience

### Phase 4: Targeted OAuth Integrations

Goal:
- cover the external ecosystems users most care about

Ship candidates:
- Strava import/export
- Oura recovery import
- TrainingPeaks workout-plan import

Selection rule:
- only add an integration when it unlocks a distinct product benefit, not just parity

## Architecture Recommendation

Add a small integration layer rather than mixing vendor logic into recording or coach code.

Suggested modules:

- `Integrations/HealthKit/HealthKitService.swift`
- `Integrations/HealthKit/HealthAuthorizationStore.swift`
- `Integrations/Imports/ImportedWorkout.swift`
- `Integrations/Imports/WorkoutImportCoordinator.swift`
- `Integrations/Vendors/<VendorName>/...` only when needed later

Responsibilities:

- authorization and permission state
- sample queries and writes
- normalization into one Outbound activity model
- deduplication between local and imported workouts
- source attribution for UI and analytics

Keep these boundaries:

- `ActivityRecorder` remains focused on live recording
- coach logic consumes normalized session or history inputs, not raw `HealthKit` samples
- vendor-specific mapping stays isolated from core app flows

## Data Model Guidance

Normalize imported data into a source-aware model.

Important fields:

- source kind: `local`, `healthKit`, `strava`, `oura`, `trainingPeaks`, other vendor
- external source identifier
- workout type
- start and end date
- distance
- duration
- calories
- average and max heart rate
- route availability
- import timestamp
- write-back status

Avoid assuming all sources can provide:

- route geometry
- cadence
- elevation
- splits
- live heart rate

## UX Guidance

Keep the first version simple.

Recommended entry points:

- onboarding card: connect Apple Health
- Me tab: manage connected sources
- Today tab: optional "imported yesterday" or readiness context
- activity detail: show source badge such as `Apple Health` or `Garmin via Health`

Permission copy should explain the user benefit clearly:

- read workouts and heart rate to personalize coaching
- save Outbound workouts back to Apple Health

Do not ask for every health permission at once unless the product needs it immediately.

## Current Repo Constraints

Current repo state:

- `Info.plist` already includes `NSHealthShareUsageDescription` and `NSHealthUpdateUsageDescription`
- no `HealthKit` integration code is present yet
- `ios/Outbound/SupportFiles/Outbound.entitlements` is empty
- `docs/build-test-device.md` says the current personal-team setup must keep entitlements empty

Implication:

- HealthKit implementation should wait until the project is on a paid Apple Developer team that can support `com.apple.developer.healthkit`
- architecture and UI planning can happen now without enabling the entitlement yet

## Decision Summary

If choosing only one path now, choose Apple Health.

Why:

- covers Apple Watch indirectly
- can absorb data from many apps that sync into Health
- keeps the integration surface native and smaller
- creates a stable base for later watch and OAuth work

If choosing the first three concrete deliverables, choose:

1. Apple Health read permissions plus workout import
2. Apple Health write-back for Outbound-recorded workouts
3. normalized integration layer that can later accept Strava or Oura imports
