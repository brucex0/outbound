# First-Party Authentication Sessions Design

## Status

Approved for implementation on 2026-08-20.

## Goal

Remove Firebase Authentication from the iOS client and make Apple authentication usable without a client-to-Google network dependency. Plainstride will verify Apple credentials on its backend and issue its own access and rotating refresh tokens. The identity and session model will remain ready for a future Android-only Google sign-in flow.

This change addresses only authentication. Mainland China distribution, API reachability, media delivery, privacy compliance, and notification delivery remain separate launch requirements.

## Scope

### Included

- Apple-only authentication in the iOS app through `AuthenticationServices`.
- Server-side verification of Apple identity tokens and nonces.
- Plainstride access and refresh sessions.
- Provider-neutral user identity records that can later represent Google identities.
- Keychain-backed iOS session persistence and automatic access-token refresh.
- Temporary backend acceptance of existing Firebase bearer tokens during migration and debugging.
- Debug personas backed by a debug-only first-party session endpoint instead of the Firebase Auth Emulator.
- Account deletion that revokes Plainstride sessions and Apple authorization.
- Removal of the Firebase Auth product from the iOS target.
- Focused documentation updates for authentication, backend configuration, and mainland readiness.

### Excluded

- Google sign-in on iOS.
- Android implementation.
- WeChat, phone, email-code, password, or guest authentication.
- Removal of Firebase Analytics, Firebase-backed media storage, Firebase Admin messaging, or other non-authentication Firebase usage.
- China-specific hosting, ICP work, push routing, or distribution changes.

## Architecture

The iOS app obtains an Apple credential using the existing nonce-protected native authorization flow. It sends the Apple identity token, authorization code, raw nonce, and first-authorization profile metadata to the Plainstride API. The backend verifies Apple, resolves or creates a provider-neutral identity and internal user, persists a refresh session, and returns a short-lived access token and a rotating refresh token.

Authenticated application routes accept the Plainstride access token. During the migration window, the middleware also accepts Firebase ID tokens and maps them through the existing Firebase identity records. Firebase remains available to backend storage and messaging services but is no longer part of a new iOS login, refresh, or API call.

The backend authentication boundary will distinguish token verification from user resolution:

- Token verification proves a caller identity and produces a provider-neutral `AuthContext`.
- Identity resolution maps that context to the stable internal `User`.
- Session issuance and rotation manage application sessions independently from identity providers.

This separation lets a future Android client submit a Google ID token to a Google-specific verifier and receive the same Plainstride session response without changing downstream routes.

## Data Model

### User

`User.id` remains the stable application account identifier. `firebaseUid` becomes nullable during migration and is no longer used as the primary identity key for new accounts.

### AuthIdentity

`AuthIdentity` represents one externally verified identity:

- `id`
- `userId`
- `provider`: initially `apple` or `firebase`; later `google`
- `providerSubject`: the immutable provider-specific subject
- `email`
- `normalizedEmail`
- `emailVerified`
- `displayName`
- `createdAt`
- `updatedAt`

The pair `(provider, providerSubject)` is unique. Provider subjects, rather than email addresses, are authoritative for returning sign-in. A verified email may help an explicit linking flow but must not silently merge two established accounts. Apple private-relay email is treated as an ordinary provider email and is never inferred to match a different visible email.

Legacy Firebase metadata remains only where required for migration, then can be removed in a later cleanup.

### AuthSession

Each signed-in installation has an `AuthSession`:

- `id`
- `userId`
- `familyId`
- `refreshTokenHash`
- `previousRefreshTokenHash`, retained only for bounded reuse detection
- `platform`
- `deviceLabel`
- `createdAt`
- `lastUsedAt`
- `expiresAt`
- `revokedAt`

Refresh token values are generated from at least 32 cryptographically random bytes and are never stored in plaintext. Hash comparison uses SHA-256 over the high-entropy token. Each successful refresh replaces the current token atomically. Presentation of a known previous token revokes the whole session family because it indicates token reuse. Unknown, expired, or revoked tokens return an unauthenticated response without disclosing which condition occurred.

## Tokens and Keys

Plainstride access tokens are asymmetric signed JWTs with:

- issuer `https://api.outbound.run`
- audience `plainstride-api`
- subject equal to the internal `User.id`
- session ID claim
- issued-at and expiration claims
- a 15-minute lifetime
- a key identifier for rotation

The production service receives the active private signing key and key identifier through secrets. Verification uses configured public keys and accepts the current and immediately previous key during rotation. Local development uses an explicit development key and must not silently generate a new production-like key at every process start.

Refresh tokens have a 30-day absolute lifetime for the first implementation. A refresh rotates both the refresh token and access token but does not extend the persisted expiry beyond 30 days from session creation.

## Apple Authentication

### Client request

`POST /v1/auth/apple` accepts:

- Apple identity token
- Apple authorization code
- raw nonce generated before the authorization request
- optional given and family name supplied only by Apple on first authorization
- platform and a bounded device label

### Server verification

The server verifies:

- the JWT signature using Apple's published keys
- issuer `https://appleid.apple.com`
- audience equal to the configured iOS bundle identifier/client identifier
- token expiration
- the token nonce equals the SHA-256 digest of the supplied raw nonce
- a non-empty Apple subject

The authorization code is exchanged with Apple when needed for validation and revocation material. Apple client-secret generation uses a configured Apple team ID, key ID, private key, and client ID. Secrets never enter the client or database logs.

### Identity resolution

If `(apple, sub)` exists, the associated user signs in. Otherwise the backend creates a new `User` and Apple `AuthIdentity` in one transaction. The initial display name uses Apple's one-time name metadata when present and otherwise falls back to a localized-neutral `Runner` profile value. Usernames continue to be generated uniquely by server logic.

New Apple sign-in does not automatically attach to an unrelated legacy user solely because an email matches. Since Plainstride is pre-public-launch, clean account recreation is acceptable. Temporary Firebase acceptance preserves access to existing beta data but does not require a complex automatic cross-provider merge.

## Session API

### `POST /v1/auth/apple`

Verifies Apple and returns:

- `accessToken`
- `accessTokenExpiresAt`
- `refreshToken`
- `refreshTokenExpiresAt`
- a compact authenticated-user summary

Errors use stable machine codes and localizable client presentation:

- invalid or expired Apple credential: `invalid_provider_credential`
- nonce mismatch: `invalid_provider_credential`
- provider temporarily unavailable: `provider_unavailable`
- malformed input: `invalid_request`
- server configuration failure: `authentication_unavailable`

### `POST /v1/auth/refresh`

Accepts the refresh token in the JSON body over TLS, rotates it transactionally, and returns a replacement access/refresh pair. The endpoint is strictly rate-limited by IP and session family.

### `POST /v1/auth/logout`

Requires a valid access token or refresh token and revokes that installation's session. Logout remains idempotent.

### `DELETE /v1/auth/me`

Requires a recent Apple reauthorization payload. It verifies the fresh credential, revokes Apple authorization using the newly obtained revocation material, revokes all application sessions, removes media where currently supported, and deletes the relational user. If Apple revocation fails transiently, account data deletion still proceeds and the response reports that external revocation could not be confirmed without restoring the account.

### Debug persona endpoint

A debug-only endpoint issues sessions for the existing New Runner, Active Runner, and Social Runner identities. It is enabled only when an explicit development environment flag is present and production startup rejects that flag. It is not a general password endpoint. The iOS debug menu continues to seed persona-specific local onboarding state.

## Backend Middleware and Migration

Authentication middleware tries Plainstride access-token verification first. During the migration window it may then try Firebase verification when Firebase is configured. Both paths produce the same provider-neutral `AuthContext`, containing at least:

- internal subject or provider subject
- authentication kind
- provider
- verified email claims
- display-name and picture claims when available
- session ID for Plainstride tokens

Rate limiting keys use the internal user ID or verified provider subject rather than `firebaseUid`.

Existing endpoints stop accepting or trusting request-body Firebase identifiers. Legacy routes whose URL contains `firebaseUid` are removed if no current client requires them. Firebase account deletion occurs only for users reached through the legacy Firebase path during the migration period.

Temporary Firebase acceptance is controlled by configuration and documented with a removal criterion: after existing beta identities are no longer needed or the owner elects to reset beta data, disable legacy verification and delete Firebase-specific identity fields in a follow-up migration.

## iOS Client Design

### Session store

A focused Keychain-backed session repository owns encoded session credentials. It supports load, replace-after-refresh, and delete. Keychain writes use an after-first-unlock, device-only accessibility class suitable for background API refresh without syncing credentials to other devices.

### AuthStore

`AuthStore` owns presentation state and orchestrates native Apple authorization through a separate Apple credential coordinator. It exposes a provider-neutral authenticated user rather than `FirebaseAuth.User`. Provider label and profile bootstrap behavior remain, but Firebase credential linking and the Google button are removed.

On launch, `AuthStore` loads the stored session and considers the user authenticated only when usable session material exists. It does not revive a removed app installation from stale Firebase Keychain state.

### APIClient

`APIClient` obtains bearer tokens from a session coordinator rather than Firebase. For authenticated requests:

1. Use the current access token when it is not near expiry.
2. Coalesce concurrent refresh attempts into one in-flight operation.
3. On an authentication response, refresh once and replay idempotent requests or requests whose body is safely reusable.
4. If refresh fails permanently, clear the session and notify `AuthStore` to present the sign-in screen.

The client must not enter an infinite refresh loop. Provider sign-in and refresh endpoints are explicitly unauthenticated and never trigger refresh behavior.

### User-facing behavior

The sign-in screen offers Apple only. Removed Google controls and connection settings are not shown. All new or changed strings use the existing localization system, including Simplified Chinese and Spanish entries where the project requires explicit catalog values. Authentication results use the project's temporary toast-style feedback convention unless the error prevents continued use and must remain visible on the sign-in screen.

## Android Google Readiness

No Android or Google implementation is included. The following contracts deliberately remain reusable:

- `AuthIdentity.provider` and `providerSubject`
- provider-specific verifier interface
- common session issuer and refresh service
- common session response DTO
- internal-user `AuthContext`
- explicit identity-linking service boundary

A future `POST /v1/auth/google` will verify a Google ID token issued to the Android client ID and then call the same identity resolution and session issuance services. No Apple-specific claim or Firebase UID is allowed in those shared service interfaces.

Existing iOS Firebase Google code is deleted rather than retained as dead code. Git history preserves it, and its reusable product behavior is represented by the provider-neutral boundaries above.

## Error Handling and Observability

- Authentication logs contain request IDs, endpoint outcomes, provider, session ID where safe, and stable error codes.
- Identity tokens, authorization codes, refresh tokens, raw nonces, Apple client secrets, and signing keys are never logged.
- Provider and session errors expose generic client messages but retain structured server diagnostics.
- Refresh reuse, repeated invalid-provider credentials, and debug-endpoint access attempts are security events.
- Apple JWKS retrieval uses bounded caching and fails closed when no valid key can verify a credential.
- Database transactions cover identity creation and session issuance, and separately cover refresh rotation.

## Security Boundaries

- All authentication endpoints require TLS in production.
- CORS is not treated as an authentication control.
- Apple credential verification happens only on the backend.
- Access-token verification checks algorithm, key ID, signature, issuer, audience, expiry, and required claims.
- Refresh tokens are opaque, high entropy, hashed at rest, and scoped to one session family.
- Account and identity linking requires proof of both identities; verified-email equality alone is insufficient.
- Secrets are supplied through deployment configuration and are not committed.
- Production refuses debug-auth configuration.

## Verification Strategy

Repository instructions prohibit running the full test suite unless explicitly requested. Implementation will still follow test-first development with narrowly targeted commands for the affected authentication modules.

Backend focused coverage includes:

- access-token issuance and rejection of altered, expired, wrong-issuer, and wrong-audience tokens
- Apple claim and nonce verification through deterministic verifier boundaries
- identity create and returning-sign-in behavior
- unique provider-subject handling under concurrent requests
- refresh success, atomic rotation, expiration, revocation, and reuse-family revocation
- provider-neutral middleware behavior for Plainstride and temporary Firebase tokens
- logout and account deletion session revocation
- production rejection of debug persona configuration

iOS focused coverage, where the existing package/test boundaries permit it, includes:

- Keychain/session repository behavior through a storage abstraction
- session expiry decisions
- refresh coalescing and one-time request replay
- permanent refresh failure clearing authentication state

Final verification is a backend TypeScript build/check plus the repository's permitted build-only iOS compile command. The full test suite will not run unless the user explicitly requests it.

## Rollout

1. Deploy the schema and backend while continuing to accept Firebase tokens.
2. Verify Apple configuration and first-party session issuance in the development environment.
3. Release the iOS client that uses first-party sessions and contains no Firebase Auth SDK.
4. Observe Apple login, refresh, logout, deletion, and legacy-token traffic.
5. When beta migration is no longer needed, disable Firebase token acceptance.
6. Remove legacy Firebase identity columns and Firebase Auth administration in a separate cleanup.

Rollback keeps the deployed schema additive and retains legacy Firebase verification. If the new iOS release has not reached users, the prior Firebase client can continue using the backend. Once users create only first-party sessions, rollback must preserve the new token verifier or require those users to sign in again.

## Documentation Changes

Implementation updates:

- `docs/firebase.md` to describe Firebase's remaining non-client-auth roles and legacy migration configuration.
- `docs/mainland-china-readiness.md` to record that client authentication no longer contacts Firebase while preserving the broader readiness caveats.
- `docs/backend-architecture.md` to make first-party sessions and provider-neutral identity the target/current auth boundary.
- `docs/build-test-device.md` for debug personas and authentication environment setup.
- deployment documentation for Apple verification, signing keys, and legacy Firebase toggle variables.
