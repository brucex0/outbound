# Simplified Product Refactor Plan

Open this when sequencing implementation of the simplified `Together · Today · Me` product or deciding whether existing client/backend code should be kept, replaced, or deleted.

## Decision

Use **replacement by vertical slice inside the existing iOS target and backend modular monolith**.

Do not:

- incrementally restyle or reshape the current primary screens;
- fully rewrite the iOS app or backend service;
- build compatibility layers for old plans, seeds, onboarding profiles, social fixtures, or local/backend rows.

The current infrastructure contains difficult, valuable behavior. The current product shells and several domain models encode the old product too deeply to refactor economically.

## Why Not a Full Rewrite

Preserve these proven capabilities:

### Client

- Firebase Apple/Google authentication and provider linking;
- GPS/background session state;
- local activity save and sync;
- location, route, and elevation services;
- camera capture mechanics;
- HealthKit integration;
- Live Activities;
- safety/live-share transport;
- progress calculations;
- activity detail, gear, music, and secondary utilities.

Rewriting these would reintroduce background, permission, data-loss, and device-specific risk without improving the new product thesis.

### Backend

- Hono/Cloud Run composition;
- Firebase auth middleware and internal user resolution;
- Prisma/Postgres access;
- canonical idempotent activity ingest and route normalization;
- safety/live-share and live-group primitives;
- AI and transcription provider wrappers;
- deterministic planning seams for athlete state, scoring, generation, adaptation, events, and plan versions.

## Why Not Incremental UI Refactoring

The existing client concentrates unrelated product responsibilities in very large files:

- `App/MainTabView.swift`: navigation, assistant, onboarding, recording portal, motivation, training UI, and launching;
- `App/ProfileView.swift`: Me, settings, assistant, integrations, gear, safety, recognition, and history;
- `App/OutboundApp.swift`: composition plus plan and assistant domains;
- `Activity/RecordView.swift`: start, recording, sharing, camera, and post-run orchestration with many global dependencies.

These are structural mismatches with the new product, not styling issues. Build new feature roots and delete old roots after each complete slice is cut over.

The backend has an equivalent mismatch:

- duplicate static-catalog and generated/runtime plan models;
- old and new planning services bridging each other;
- prototype social endpoints based on caller-supplied actor IDs;
- media placeholders without ownership or private-by-default Moments;
- guide/avatar and generic assistant concepts treated as primary domains.

## Client Keep, Replace, Delete

### Keep behind narrow interfaces

- `App/AuthStore.swift`
- `Core/ActivityRecorder.swift`
- `Activity/ActivityStore.swift`
- `Core/LocalActivityStore.swift`
- `Core/LocationManager.swift`
- route/elevation logic
- `Core/SessionLiveActivityManager.swift`
- `Camera/CameraController.swift`
- `Camera/CameraPreviewLayer.swift`
- HealthKit services
- safety/live-group transports that match new contracts
- `Progress/ProgressStatsEngine.swift`
- API authentication transport

### Replace

- `MainTabView` with a small three-tab shell and root coordinator;
- `MotivationDashboardView` with Today;
- `ProfileView` with Me plus pushed secondary destinations;
- current onboarding store and views;
- `RecordView` and `CameraHUDView` presentation while retaining underlying services;
- seeded Social models/stores/UI with Together contracts;
- generic assistant UI/state with structured contextual guidance actions;
- current client plan models/library with the unified plan/workout contract.

### Delete after cutover

- persistent assistant launcher and generic assistant destination;
- old plan IDs, imported compatibility plans, and old onboarding keys;
- seeded Squad/rival/challenge/relay product surfaces not retained by Together;
- recognition surfaces outside the new scope;
- compile-time Social gating after Together is real;
- backward-decoding paths that exist only for unpublished data.

## Target Client Structure

```text
App/
  OutboundApp
  AppContainer
  RootCoordinator
  AppShell

DesignSystem/
  Tokens
  Components/

Features/
  Authentication/
  Onboarding/
  Today/
  WorkoutDetail/
  LiveWorkout/
  PostRun/
  Together/
  Me/
  CycleAware/
  Settings/

Domains/
  Activities/
  Training/
  Social/
  Health/
  Safety/
  Identity/

Services/
  API/
  Persistence/
  Location/
  Camera/
  HealthKit/
  LiveActivity/
```

Each feature owns one observable screen model or coordinator with explicit dependencies. Do not replace the current environment-object collection with another global service bag exposed to every view.

## Backend Keep, Replace, Delete

### Keep

- authenticated Hono/Prisma/Cloud Run container;
- identity linking and current-user resolution;
- activity ingest and route normalization;
- safety/live-share and applicable group-run mechanics;
- AI/transcription wrappers;
- deterministic planner algorithms that can target the unified model;
- plan version, planning event, and adjustment-event concepts.

### Replace

- caller-supplied user identity routes with authenticated self-service routes;
- duplicate plan models with one reviewed catalog plus one runtime plan model;
- planning orchestration and DTO assembly;
- prototype Social schema/routes with Together;
- media placeholder with owned, private-by-default Moment upload/share flow;
- GuideProfile as a primary avatar/personality object with compact guidance preferences and derived athlete summary;
- request-time fire-and-forget analysis with durable jobs/events.

### Delete

- `GET /auth/me/:firebaseUid`;
- user-ID-in-path activity, guide, and social self-service routes;
- caller-supplied social actor IDs;
- raw/imported compatibility plan catalog and old plan bridge service;
- fake public media URLs and arbitrary activity attachment;
- generic assistant access to broad user history;
- compatibility migrations for unpublished plan/social rows.

## Unified Backend Domains

### Identity

Authenticated `User` and provider identities. All self-service routes derive the actor from the verified token.

### Activities and Moments

Canonical activities, route data, activity ownership, Moment metadata, private object storage, share approval, and social derivatives.

Moment metadata includes activity ownership, client ID, elapsed seconds, workout phase, private coordinate, share state, and optional alt text.

### Training

- small reviewed plan/archetype catalog;
- `ActivePlan`;
- `PlanVersion`;
- `PlannedWorkout`;
- `WorkoutBlock`;
- `WorkoutStep`;
- `WorkoutCompletion`;
- `ReadinessCheckIn`;
- `PlanAdjustment`.

AI explains deterministic decisions; it does not invent progression.

### Together

- people/connections;
- circles and membership;
- clubs, membership, and roles;
- group runs with distance/pace groups;
- invitations;
- activity shares/posts;
- reactions and comments;
- compatibility results with share-safe explanations only.

### Health Boundary

Raw cycle dates, flow, and symptoms remain on device for V1. Backend planning accepts only a short-lived, idempotent derived signal:

- `no_adjustment`
- `offer_flexible_option`
- `reduce_load`
- `recommend_rest`

Do not put this signal or its private cause in social data, assistant prompts, public adjustment copy, general analytics, logs, notifications, or version-engine-input blobs.

## Target API Shape

```text
GET/PUT  /v1/me
GET/PUT  /v1/onboarding

GET      /v1/today
GET      /v1/plans/active
GET      /v1/plans/active/week
GET      /v1/workouts/:id
POST     /v1/workouts/:id/shorten
POST     /v1/workouts/:id/soften
POST     /v1/workouts/:id/reschedule
POST     /v1/workouts/:id/skip
POST     /v1/workouts/:id/complete

POST     /v1/activities
GET      /v1/activities/:id
POST     /v1/activities/:id/moments
POST     /v1/activity-shares

GET      /v1/together
POST     /v1/connections
GET/POST /v1/circles
GET/POST /v1/clubs
GET/POST /v1/group-runs
GET/POST /v1/invitations
POST     /v1/posts/:id/reactions
POST     /v1/posts/:id/comments

GET      /v1/me/progress
```

`GET /v1/today` is an app-shaped aggregate: quote/context, one typed workout, structured quick actions, at most one share-safe social opportunity, and weekly progress. This prevents the client from coordinating several domains for the first screen.

## Database Reset

No checked-in migrations or public data require preservation. Make one deliberate schema replacement:

1. Optionally snapshot the development database for inspection only.
2. Replace the Prisma schema with retained infrastructure plus unified Training, Together, and Moment models.
3. Reset the development/backend database.
4. Generate the Prisma client.
5. Seed the small reviewed running-plan/archetype catalog.
6. Recreate development users and activity fixtures.
7. Delete compatibility import/translation code.

Document one canonical rebuild command when the schema implementation lands.

## Vertical Migration Sequence

### 0. Freeze contracts

- Finalize DTOs, privacy rules, and shared workout block model.
- Add API contract fixtures consumed by backend and client previews.
- Add a temporary root switch for old/new client shells in development only.

### 1. Onboarding and Today

- Backend: `/v1/me`, onboarding draft/complete, runner facts, calibration status, `/v1/today`, reviewed plan seed.
- Client: new shell, shared design system, onboarding, editable understanding, calibration overview, Today, workout preview/detail.
- Reset old onboarding and plan state.

### 1A. First personalization loop

- Freeze shared readiness, feedback, runner-insight, confidence, and adjustment DTOs with JSON fixtures.
- Backend: versioned runner-model projection, readiness and workout-feedback writes, reviewed calibration evidence, and one bounded immediate adjustment policy.
- Client: conditional pre-run check-in, post-run effort feedback, `What I learned`, and before/after adjustment explanation with undo.
- Complete this slice before expanding generic AI conversation. The acceptance path is one observed run producing one evidence-backed, safe, explained adjustment.

### 2. Guided workout

- Backend: typed workout detail and structured adjustment actions.
- Client: new live-workout presentation over retained recorder/location/Live Activity services.
- Validate background/pause/resume/finish behavior before deleting the old presentation.

### 3. Post-run and Moments

- Backend: owned signed upload/confirm, private Moment metadata, share draft/publish.
- Client: capture, private preview, post-run reflection, AI caption draft.

### 4. Me

- Backend: progress aggregate.
- Client: new progress hierarchy over retained stats, history, gear, and settings capabilities.

### 5. Together

- Backend: connections, clubs, group runs, invitations, posts, reactions, comments, and compatibility.
- Client: Together actionable sections and rich social activity cards.
- Remove seeded Social and compile-time gating.

### 6. Cycle-aware guidance

- Client: isolated local health store and derived signal generation.
- Backend: short-lived private adjustment input only.
- Verify no raw health data reaches social, analytics, logs, notifications, or general AI.

### 7. Delete the old product

- Remove old screens, assistant domain, plan library/bridges, social seeds, legacy routes, and compatibility decoding.
- Remove the temporary shell switch.

## Effort and Risk

Indicative single-engineer effort:

- Client: roughly 10-15 engineering weeks.
- Backend: roughly 7-10 engineering weeks.
- Parallel client/backend delivery: approximately 10-14 elapsed weeks with stable contracts and focused scope.

Primary risks:

- active-session/background regressions;
- contract churn between Today/Training/Together;
- planner correctness after schema unification;
- Moment ownership and visibility;
- private health reasons leaking into social or AI contexts;
- recreating global state coupling in the new client.

Mitigate by shipping and validating complete vertical slices, using contract fixtures, retaining old service implementations behind adapters until each slice passes device checks, and deleting old product code promptly after cutover.

## Acceptance Criteria for the Refactor

- Primary app is `Together · Today · Me` with no generic assistant destination.
- Today comes from one typed aggregate and always has a safe fallback.
- Training uses one shared workout block model across preview, detail, live, and post-run.
- Recorder, background, local save, and safety behavior remain reliable.
- Moments are private until approved.
- Together cannot access private plan or health causes.
- One runtime plan model exists on both client and backend.
- Old plan/social/onboarding data and compatibility code are removed.
- New feature roots have explicit dependencies and reusable UI components.
- Old primary screens and legacy routes are deleted rather than indefinitely retained.

## Implemented Product Cutover

The production root now uses `Together · Today · Me`; the prior shell is not a release path. The current implementation includes:

- editable runner intake, calibration sessions, readiness, workout feedback, learned insights, and explained adjustment decisions;
- Today with plan-backed interval summaries, a direct path into run setup, quick Open/Distance/Time runs, optional readiness actions, and safe fallbacks;
- the retained recorder, camera Moment capture, pause/resume/finish, local activity save, and post-run reflection/feedback;
- Me with live plan/week progress, saved weekly totals, recent activity history, learned insights, settings, and cycle-aware guidance;
- Together backed by authenticated connections, clubs, group runs, invitations, posts, reactions, comments, compatibility, and cached client state;
- private-by-default Moment records with ownership checks and an explicit share transition;
- raw cycle/wellbeing data stored on-device, with only `noAdjustment`, `offerFlexibleOption`, `reduceLoad`, or `recommendRest` sent to planning.

The older SwiftUI feature files remain only as reusable secondary destinations or dormant code while production navigation no longer exposes the old primary shell. Remove them incrementally after retained utilities (history, detail, recorder, gear, and safety) are split into dedicated feature modules.

Because the Prisma model changed before public launch, rebuild the development database rather than preserving old rows:

```sh
cd backend
npx prisma db push --force-reset
```
