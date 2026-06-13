# Backend Architecture

Open this when planning backend implementation, changing server boundaries, or deciding whether logic belongs on-device or in Cloud Run.

## Current Server Shape

Today the backend already has the right high-level container shape:

- one Hono service in `backend/src/index.ts`
- route modules for `auth`, `activities`, `assistant`, `coach`, `social`, and `media`
- Prisma + Postgres schema in `backend/prisma/schema.prisma`
- Cloud Run deployment path documented in `docs/backend-deploy.md`

Current strengths:

- assistant chat already works without a database
- database-backed routes are grouped by domain instead of one large file
- iOS already sends a Firebase bearer token to `APIClient`
- coach profile rebuild logic exists and can evolve instead of being rewritten
- authenticated activity ingest now has an initial idempotent path using client-generated activity IDs

Current gaps:

- authenticated identity is not enforced on the server yet
- routes trust client-supplied `userId` and `firebaseUid`
- activity sync retries and media sync are still lightweight, even though base ingest is now idempotent
- media upload flow is placeholder-level
- async work is done with in-request fire-and-forget logic
- readiness history and deeper plan adaptation are still lightweight, although active training plan state and deterministic plan recommendation/today logic now live on the backend
- social routes are still prototype-grade and not aligned with the current iOS local-first Social tab

## Architecture Principles

- Keep recording, local save, and offline UX on-device.
- Keep synced identity, derived coach state, plans, and social state on the backend.
- Treat activities as the canonical workout fact that downstream systems build on.
- Keep the backend as a modular monolith until product and traffic clearly justify splitting services.
- Use deterministic rules for safety-critical progression logic and AI for explanation, summarization, and rewriting.
- Prefer app-shaped API responses over exposing raw database rows.

## Recommended System Shape

Start with one Cloud Run service backed by Postgres and object storage.

Core components:

- `api`: Hono app serving versioned REST endpoints under `/v1`
- `db`: Postgres via Prisma for durable product state
- `media storage`: Google Cloud Storage for activity photos and future derived media
- `jobs`: async workers for coach analysis, plan recompute, feed fanout, and notifications
- `auth`: Firebase Auth token verification on every authenticated route

This is still one product backend, but with explicit module boundaries:

- `identity`
- `activities`
- `coach`
- `assistant`
- `plans`
- `social`
- `safety`
- `gear`
- `media`
- `notifications`

## Source Of Truth Split

Client should own:

- live recording session state
- local activity save and offline history
- cached coach profile and plan snapshots
- offline fallback suggestions and assistant fallback replies
- optimistic UI for syncable actions

Backend should own:

- authenticated user identity mapping
- synced activities and media metadata
- coach profile artifacts and weekly review generation
- active plan state, readiness history, and adaptation logic
- social graph, posts, reactions, comments, clubs, and rival state
- server-side AI orchestration and provider keys

## Domain Boundaries

### Identity

Responsibilities:

- verify Firebase bearer tokens
- map `firebaseUid` to an internal `User`
- provide authenticated `me` endpoints

Rules:

- do not trust `userId` from request bodies when auth is present
- derive current user from verified token
- support local-only app mode by letting the client skip backend sync entirely when not signed in with Firebase

### Activities

Responsibilities:

- ingest completed activities from the phone
- store normalized workout metadata
- store the client-generated finish reflection shown after Save Activity
- attach route summaries and photo metadata
- normalize uploaded route points into an `Activity.route` GeoJSON Feature, using `[longitude, latitude, altitude]` coordinates when altitude is available and preserving per-point timestamps/vertical accuracy in route properties
- trigger downstream coach and plan work

Rules:

- activity ingest must be idempotent
- server should store one canonical activity per logical workout
- route and photo visibility must be policy-controlled, not implied by raw storage

Recommended API shape:

- `POST /v1/activities`
- `GET /v1/activities`
- `GET /v1/activities/:id`

Recommended first response model:

- canonical server `id`
- accepted sync status
- timestamps
- media upload state
- optional lightweight derived summary for the UI

### Coach

Responsibilities:

- persist coach preferences and derived coach profile
- rebuild profile artifacts after activity sync
- generate weekly review and compact coaching context

Rules:

- keep the downloadable coach payload stable and versioned
- do not make the device fetch large raw history for everyday coach use
- move analysis and rebuild work out of request handlers into jobs

Recommended API shape:

- `GET /v1/coach/profile`
- `POST /v1/coach/rebuild`
- `POST /v1/coach/customize`
- `POST /v1/coach/weekly-review`

### Assistant

Responsibilities:

- answer product discovery, navigation, support, brainstorming, and planning prompts
- pull in lightweight structured user context from coach, activity, and plan domains
- return concise app-aware replies

Rules:

- keep provider keys on the server
- derive user identity from auth, not request JSON
- keep the endpoint stateless, but enrich output over time

Recommended evolution:

- V1: `{ message }`
- V2: `{ message, suggestedActions, deepLinks, followUpPrompts }`

### Plans

Responsibilities:

- store one active training plan per authenticated user
- serve the structured plan template catalog and recommendation candidates
- compute current-week progress from synced activities
- compute the `today` recommendation, including readiness-based softening
- explain why a recommendation fits and what tradeoff it carries

Rules:

- backend owns progression and adaptation logic
- AI explains plan logic but does not invent progression from scratch
- plan state must be cacheable on-device for offline rendering

Current API shape:

- `GET /v1/planning/recommendations`
- `GET /v1/coach/plans/state`
- `POST /v1/coach/plans/recommendation`
- `POST /v1/coach/plans`
- `GET /v1/coach/plans/active`
- `GET /v1/coach/plans/active/week`
- `DELETE /v1/coach/plans/active`
- `GET /v1/coach/today`

Next plan work:

- persist readiness check-ins instead of accepting readiness only as request context
- link planned sessions to completed activities for adherence analytics
- add explicit adaptation records when weekly shape changes

### Social

Responsibilities:

- follow graph
- posts from activities
- reactions and comments
- later clubs, rivals, challenges, and live presence

Rules:

- treat feed as a read model, not the source of truth
- start with simple durable objects before fanout complexity
- default privacy should be conservative because activities include route and photo data

Recommended early API shape:

- `GET /v1/social/feed`
- `POST /v1/social/posts`
- `POST /v1/social/follow`
- `DELETE /v1/social/follow/:targetUserId`
- `POST /v1/social/reactions`
- `POST /v1/social/comments`

### Safety

Responsibilities:

- create and end trusted live-share sessions
- receive throttled live location updates during an active workout
- serve time-limited public live-view links
- expire stale shares and avoid long-term high-resolution location retention

Rules:

- live sharing is off by default and explicit per session
- public links use unguessable tokens stored hashed server-side
- recipients can view only the active shared session, not the runner's profile or history
- route privacy zones should be designed before broad route sharing or public live maps

Recommended early API shape:

- `POST /v1/safety/live-shares`
- `PATCH /v1/safety/live-shares/:id/location`
- `POST /v1/safety/live-shares/:id/end`
- `GET /live/:token`

Current V1:

- `backend/src/routes/safety.ts` implements the API above.
- `GET /live/:token` serves the public viewer HTML, and `GET /live/:token?format=json` serves the polling payload.
- `SafetyLiveShare` stores session state, hashed token, expiry, latest location, route preview, elapsed time, and distance.
- `SafetyLiveSharePoint` stores live-share points for the active session history.
- Public tokens are random 32-byte base64url strings and only SHA-256 hashes are stored.
- iOS throttles updates to every 10 seconds or 25 meters and continues recording if sharing fails.

### Gear And Runner Utilities

Responsibilities:

- store shoes and later other gear
- attach gear to activities
- preserve source attribution for local, HealthKit, file, manual, and vendor imports
- support manual activity edits without hiding the original source
- support computed runner stats such as PRs, HR zones, cadence, and race predictions

Rules:

- start local-first on the client, then sync once authenticated activity sync is stable
- distinguish manual edits, imported workouts, and Outbound-recorded workouts in UI and API payloads
- do not fabricate cadence or detailed HR zones when the source data does not provide enough samples

Recommended early API shape after activity sync:

- `GET /v1/gear`
- `POST /v1/gear`
- `PATCH /v1/gear/:id`
- `POST /v1/activities/:id/gear`
- `PATCH /v1/activities/:id`

### Media

Responsibilities:

- create signed upload URLs
- confirm uploads
- bind photos to activities the current user owns
- later generate thumbnails or derivatives

Rules:

- the client should upload directly to storage when possible
- the server should validate ownership on confirm
- storage keys should be opaque and server-issued

## Data Model Direction

Keep the current tables as a starting point:

- `User`
- `CoachProfile`
- `Activity`
- `Photo`
- `Post`
- `Follow`
- `Reaction`
- `Comment`
- `ActiveTrainingPlan`

Add first:

- `clientActivityId` on `Activity` for idempotent sync
- `visibility` on `Activity`
- `syncSource` on `Activity`
- `uploadStatus` on `Photo` or separate media fielding if needed

Add after the first server-owned plan pass:

- `Goal`
- `PlanWeek`
- `PlannedSession`
- `ReadinessCheckIn`
- `PlanAdaptation`
- `SafetyShareSession`
- `TrustedContact`
- `GearItem`
- `ActivityGear`
- optional `ActivityEdit` audit records

Keep `route` as JSON for the first implementation unless query requirements force a separate route table.

## Auth And Request Model

Implementation target:

- add auth middleware that verifies Firebase ID tokens with `firebase-admin`
- attach Firebase identity metadata to request context and resolve it to an internal `User`
- keep `AuthIdentity` rows for each Firebase UID/provider combination, with normalized email and phone indexes for account linking
- introduce authenticated endpoints that no longer take `userId` in the path for self-service routes

Preferred route style:

- `GET /v1/me`
- `GET /v1/coach/profile`
- `POST /v1/activities`
- `GET /v1/social/feed`

Avoid:

- `GET /v1/coach/:userId/profile`
- `GET /v1/social/feed/:userId`
- `POST /v1/activities` with trusted body `userId`

## Async Work Model

Do not keep long-term product logic in request-time fire-and-forget closures.

Move these into explicit jobs:

- coach analysis after activity ingest
- coach profile rebuild after activity ingest
- plan adherence update after activity ingest
- daily recommendation recompute after readiness check-in
- social feed fanout and notifications later

Initial implementation can use a simple database-backed job table or a managed queue, as long as handlers only enqueue work and return quickly.

## Recommended API Cleanup Order

### Milestone 1: Authenticated Foundation

Goal:

- make the current backend safe and consistent enough to build on

Deliver:

- Firebase auth middleware
- authenticated `GET /v1/me`
- authenticated `GET /v1/coach/profile`
- authenticated `POST /v1/coach/rebuild`
- authenticated `POST /v1/activities`
- removal of trusted path/body identity on core routes
- route handlers refactored to call service-layer functions

Notes:

- keep backward compatibility only if the iOS app still needs it during rollout
- prioritize `assistant`, `coach`, and `activities` over `social`

### Milestone 2: Idempotent Activity Sync

Goal:

- support reliable cloud sync from the local-first app

Deliver:

- `clientActivityId` on activity ingest
- duplicate-safe create or upsert behavior
- ownership checks on media confirm
- server-issued upload keys
- normalized activity response payloads

### Milestone 3: Coach Pipeline Hardening

Goal:

- make synced coaching dependable and cheap to evolve

Deliver:

- explicit coach service layer
- background jobs for post-activity analysis and profile rebuild
- stable versioned coach payload contract
- weekly review endpoint retained but moved off fragile inline assumptions

### Milestone 4: Plans Domain

Goal:

- move plan logic from local-first prototype toward server-owned progression

Deliver:

- Prisma models for goals, plans, readiness, and adaptations
- deterministic recommendation engine on the backend
- authenticated plan and readiness endpoints
- on-device caching of last-known plan snapshot

### Milestone 5: Social V1

Goal:

- replace prototype social persistence with authenticated backend objects

Deliver:

- authenticated follow graph
- activity-backed post creation
- reactions and comments
- feed read endpoint shaped for the app

Defer:

- clubs
- rivals
- challenges
- live relay presence

### Milestone 6: Jobs, Notifications, And Read Models

Goal:

- support product loops that depend on asynchronous work

Deliver:

- durable job execution path
- plan refresh jobs
- coach summary jobs
- notification triggers
- feed projection if needed

## Suggested Codebase Refactor

Without splitting services, reorganize the backend into clearer layers:

- `src/index.ts`
- `src/middleware/auth.ts`
- `src/routes/*.ts`
- `src/services/*.ts`
- `src/repositories/*.ts`
- `src/jobs/*.ts`
- `src/types/*.ts`

Use this division:

- routes validate input and map HTTP to domain calls
- services own domain logic
- repositories wrap Prisma queries
- jobs perform async follow-up work

## iOS Rollout Notes

The iOS app already sends Firebase tokens through `APIClient`, so the first rollout can be incremental:

- keep local-only behavior when Firebase is unavailable
- call authenticated server routes only for Firebase-backed sessions
- continue using local cache as the offline fallback
- keep assistant fallback paths intact while backend contracts stabilize

## Decisions To Keep Stable

- modular monolith first
- Postgres behind the API, not direct client DB access
- local-first recording and save flow
- backend-owned plan and coach derivation
- explicit privacy boundary for route and photo sharing

## Open Questions

- whether to use a database-backed job table or a managed queue first
- whether route geometry remains JSON long-term or becomes its own table
- whether social feed should use fanout-on-write early or stay query-built longer
- when to add comments and clubs relative to plan work
