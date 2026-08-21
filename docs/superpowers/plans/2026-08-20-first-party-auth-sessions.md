# First-Party Authentication Sessions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace iOS Firebase Authentication with backend-verified Apple authentication and Plainstride access/refresh sessions while retaining temporary backend Firebase-token compatibility.

**Architecture:** The backend verifies provider credentials into a provider-neutral auth context, resolves an external identity to an internal user, and independently issues asymmetric JWT access tokens plus opaque rotating refresh tokens. The iOS client stores session material in device-only Keychain storage and obtains tokens through a refresh-coalescing coordinator used by `APIClient`.

**Tech Stack:** Hono, TypeScript, Node crypto, Prisma/Postgres, SwiftUI, AuthenticationServices, CryptoKit, Security/Keychain.

---

### Task 1: Provider-neutral schema and identity boundary

**Files:**
- Modify: `backend/prisma/schema.prisma`
- Modify: `backend/src/types/hono.ts`
- Modify: `backend/src/services/currentUser.ts`
- Modify: `backend/src/middleware/rateLimit.ts`

- [ ] Make `User.firebaseUid` nullable, replace Firebase-specific identity fields with provider/subject fields, and add `AuthSession`.
- [ ] Change `AuthContext` to expose internal/provider subjects, provider, authentication kind, and optional session ID.
- [ ] Resolve users by `(provider, providerSubject)` without email-based merging for new Apple identities.
- [ ] Key rate limits by internal user or verified provider subject.

### Task 2: Token, Apple, and session services

**Files:**
- Create: `backend/src/services/accessTokens.ts`
- Create: `backend/src/services/appleAuth.ts`
- Create: `backend/src/services/authSessions.ts`

- [ ] Verify access-token algorithm, key ID, signature, issuer, audience, expiry, subject, and session claims.
- [ ] Verify Apple signature, issuer, audience, expiry, nonce digest, and subject using cached Apple JWKS.
- [ ] Issue 15-minute access tokens and 30-day opaque refresh tokens hashed with SHA-256.
- [ ] Rotate refresh tokens transactionally and revoke the family when the immediately previous token is reused.

### Task 3: Auth middleware and routes

**Files:**
- Modify: `backend/src/middleware/auth.ts`
- Modify: `backend/src/routes/auth.ts`
- Modify: `backend/src/index.ts`
- Modify: `backend/src/scripts/seedTestPersonas.ts`

- [ ] Prefer Plainstride access-token verification, then optionally accept Firebase tokens behind configuration.
- [ ] Add Apple sign-in, refresh, logout, recent-Apple account deletion, and debug-persona session endpoints.
- [ ] Remove the unauthenticated Firebase-UID lookup route and body-identifier trust.
- [ ] Reject debug authentication in production and apply strict refresh rate limiting.

### Task 4: iOS session persistence and API authorization

**Files:**
- Create: `ios/Outbound/Outbound/Core/AuthSession.swift`
- Create: `ios/Outbound/Outbound/Core/SessionRepository.swift`
- Create: `ios/Outbound/Outbound/Core/SessionCoordinator.swift`
- Modify: `ios/Outbound/Outbound/Core/APIClient.swift`

- [ ] Store the encoded session with after-first-unlock, device-only Keychain accessibility.
- [ ] Return unexpired access tokens and coalesce refreshes into one in-flight task.
- [ ] Clear the session after permanent refresh failure and publish an authentication-expired notification.
- [ ] Replay a request at most once after a 401 and never refresh auth endpoints.

### Task 5: Apple-only iOS authentication

**Files:**
- Rewrite: `ios/Outbound/Outbound/App/AuthStore.swift`
- Modify: `ios/Outbound/Outbound/App/AuthView.swift`
- Modify: `ios/Outbound/Outbound/App/MainTabView.swift`
- Modify: `ios/Outbound/Outbound/App/AppDelegate.swift`
- Modify: `ios/Outbound/Outbound.xcodeproj/project.pbxproj`

- [ ] Exchange nonce-protected native Apple credentials with the backend and persist the returned session.
- [ ] Restore authentication only from usable first-party Keychain material.
- [ ] Replace emulator personas with the debug-only backend endpoint.
- [ ] Reauthorize with Apple for deletion and remove Google/linking UI and Firebase Auth imports/product dependency.
- [ ] Localize every changed user-facing string.

### Task 6: Configuration and documentation

**Files:**
- Modify: `scripts/build-install-bruce-main.sh`
- Modify: `scripts/run-local-e2e.sh`
- Modify: `scripts/deploy-backend-gcloud.sh`
- Modify: `docs/INDEX.md`
- Modify: `docs/firebase.md`
- Modify: `docs/mainland-china-readiness.md`
- Modify: `docs/backend-architecture.md`
- Modify: `docs/build-test-device.md`
- Modify: `docs/backend-deploy.md`

- [ ] Document Apple IDs/keys, access signing keys, legacy Firebase toggle, and debug-auth guard.
- [ ] Update local persona tooling to use first-party debug sessions.
- [ ] Record that iOS no longer contacts Firebase Auth while broader China readiness remains unchanged.

### Task 7: Verification and commit

- [ ] Generate Prisma Client and run the backend TypeScript build.
- [ ] Run the permitted iOS build-only command.
- [ ] Review the diff for secrets, Firebase Auth references, and unrelated files.
- [ ] Commit only the scoped implementation and documentation.
