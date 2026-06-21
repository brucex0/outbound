# Live Group Run Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a V1 live group run sharing slice with invite-link create/join, mutual location updates, and friend pins plus runner strip on the in-session map.

**Architecture:** Add a backend `live` route and Prisma models for group-run sessions and participants. Add an iOS `LiveGroupStore` that owns create/join/update/poll/leave and feeds map-ready participant overlays into `RecordView` and `LiveMapView`. Keep `ActivityRecorder` unchanged and continue recording even when group sharing fails.

**Tech Stack:** Hono, Prisma, TypeScript, SwiftUI, MapKit, Combine, Firebase-authenticated API calls.

---

### Task 1: Backend Live Group Domain

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Create: `backend/src/routes/live.ts`
- Modify: `backend/src/index.ts`

- [ ] Add `LiveGroupSession` and `LiveGroupParticipant` models linked to `User`.
- [ ] Add `POST /v1/live/group-runs` to create a group session and creator participant.
- [ ] Add `POST /v1/live/group-runs/join` to join by invite token or invite URL.
- [ ] Add `GET /v1/live/group-runs/:id` to return active participant presence.
- [ ] Add `PATCH /v1/live/group-runs/:id/participants/me/location` to update the caller's latest location.
- [ ] Add leave/end endpoints.
- [ ] Register the route in `backend/src/index.ts`.

### Task 2: iOS Live Group API And Store

**Files:**
- Modify: `ios/Outbound/Outbound/Core/APIClient.swift`
- Create: `ios/Outbound/Outbound/Safety/LiveGroupStore.swift`
- Modify: `ios/Outbound/Outbound/App/OutboundApp.swift`

- [ ] Add request/response DTOs and API methods for group-run create/join/fetch/update/leave/end.
- [ ] Add `LiveGroupStore` with `activeSession`, `participants`, `startPresentation`, invite join text, throttled snapshot updates, polling, stale state, leave/end cleanup, and map overlay models.
- [ ] Inject `LiveGroupStore` as an environment object.

### Task 3: Activity Setup And Lifecycle

**Files:**
- Modify: `ios/Outbound/Outbound/Activity/RecordView.swift`

- [ ] Add create/join controls to the existing session options card.
- [ ] Present invite share sheet when a group is created.
- [ ] Start polling/updating once recording starts.
- [ ] End or leave group sharing on finish, discard, or explicit cleanup.

### Task 4: Map Overlay

**Files:**
- Modify: `ios/Outbound/Outbound/Activity/LiveMapView.swift`
- Modify: `ios/Outbound/Outbound/Camera/CameraHUDView.swift`

- [ ] Draw participant avatar pins.
- [ ] Add runner strip above the status card.
- [ ] Focus map on tapped participant and recenter to the current runner.
- [ ] Show active group sharing indicator and stop control in the camera rail.

### Task 5: Verification

**Files:**
- Review all changed files.

- [ ] Run backend compile check: `cd backend && npm run build`.
- [ ] Run iOS build-only compile check with `scripts/build-install-bruce-main.sh --build-only` if the backend check passes.
- [ ] Do not run the test suite unless explicitly requested.
