# Firebase And Google Cloud

Open this when touching Firebase Auth, Google project setup, the Firebase plist, or related REST inspection.

## Project Identity

- Google account: `bruce.xia74@gmail.com`.
- Firebase/GCP display name: `outbound`.
- GCP project ID: `outbound-494602`.
- GCP project number: `186140050970`.
- Firebase iOS app ID: `1:186140050970:ios:9dcd3698a906d4cca033a3`.
- Firebase iOS bundle ID: `plainstride.outbound`.
- Firebase Email/Password auth is not part of the user-facing login surface.
- Firebase Phone Auth provider may exist for older experiments, but the app no longer depends on SMS verification or phone/password sign-in.
- Firebase Google auth is enabled through the Identity Platform `google.com` provider with a standard Google web OAuth client.
- Firebase Apple auth is enabled through the Identity Platform `apple.com` provider, and the iOS target includes the Sign in with Apple entitlement.
- Phone Auth callback URL scheme in `Info.plist`: `app-1-186140050970-ios-9dcd3698a906d4cca033a3`.

## Local Config

- `ios/Outbound/Outbound/GoogleService-Info.plist` is local and gitignored.
- Firebase Analytics is linked through Swift Package Manager and accessed only through `Core/Analytics/FirebaseAnalyticsProvider.swift`; features depend on the vendor-neutral `AnalyticsManager`.
- Xcode's file-system-synchronized app target copies the plist into `Outbound.app` when present.
- `firebase` CLI is not installed here. Use `gcloud` and Firebase/Identity Toolkit REST APIs if project setup needs inspection or changes.
- `zxia@snapchat.com` gcloud auth is blocked by Context Aware Access. Use `--account=bruce.xia74@gmail.com`.

## Auth Provider Notes

- App login is provider-backed: Apple and Google are the only user-facing sign-in methods.
- Google sign-in uses Firebase Auth's hosted OAuth flow for `google.com`, so the app can use the existing Firebase callback scheme instead of a separate native Google Sign-In SDK callback.
- Apple sign-in uses native `AuthenticationServices` and sends a nonce-backed Apple ID token plus Apple's first-authorization name metadata to Firebase. Apple supplies name and email only on the first authorization; returning sign-ins normally omit them.
- To repeat a true first-sign-in test, remove Plainstride under Apple ID Settings > Sign-In & Security > Sign in with Apple, then sign in again. Deleting and reinstalling the app alone does not reset Apple's authorization grant.
- The backend stores Firebase identities separately from app users. `AuthIdentity` records the Firebase UID, provider IDs, verified email, and normalized phone values so Apple, Google, and any legacy identities can resolve to the same Outbound user when Firebase reports the same identity.
- Same-email provider linking is not automatic from email match alone. If Apple and Google report the same visible email, Firebase returns a pending credential conflict; the app asks the user to sign in with the already-connected provider once, then links the pending provider to the same Firebase user.
- Keep Firebase Auth in one-account-per-email mode so same-email provider attempts become `account-exists-with-different-credential` conflicts instead of separate Firebase users.
- Apple Hide My Email relay addresses are treated as distinct unless the signed-in user explicitly connects Apple from Settings.
- When Firebase is not configured, the auth screen now blocks account creation and sign-in instead of silently falling back to local-only accounts.
- This keeps sign-in compatible with Firebase Auth while avoiding password storage, password reset, and phone-number privacy burden in the app UX.

## Google Provider Setup

- Firebase Identity Platform provider resource: `projects/186140050970/defaultSupportedIdpConfigs/google.com`.
- Allowed redirect URI: `https://outbound-494602.firebaseapp.com/__/auth/handler`.
- Keep the real Google web OAuth credential in a local-only file such as `config/google-oauth-web-client.local.json`.
- The checked-in example template is `config/google-oauth-web-client.example.json`.
- The app uses Firebase Auth's hosted OAuth flow for Google sign-in; the generated plist also includes `CLIENT_ID` and `REVERSED_CLIENT_ID` for the registered iOS app.

## Apple Provider Setup

- The Firebase/Identity Platform `apple.com` provider is enabled for native iOS sign-in; no Services ID or OAuth code-flow key is configured because the app uses `AuthenticationServices` directly.
- Keep `com.apple.developer.applesignin = Default` in both `ios/Outbound/SupportFiles/OutboundDebug.entitlements` and `ios/Outbound/SupportFiles/Outbound.entitlements` so Apple sign-in is available in Debug and Release builds.
- Keep the `APPLE_SIGN_IN_ENABLED` Swift compilation condition on both the Debug and Release app-target configurations; `AuthStore` uses it to expose Apple sign-in only in builds intended to carry the entitlement.
- In the Apple Developer account, bundle ID `plainstride.outbound` has Sign in with Apple enabled as a primary App ID.
- Apple private relay emails should not be merged with Google-visible emails unless the user links Apple while already signed in.

## REST Inspection Pattern

```sh
ACCESS_TOKEN=$(gcloud auth print-access-token --account=bruce.xia74@gmail.com)
curl -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "x-goog-user-project: outbound-494602" \
  "https://firebase.googleapis.com/v1beta1/projects/outbound-494602"
```

## Packaged Plist Check

```sh
plutil -extract GOOGLE_APP_ID raw ~/Library/Developer/Xcode/DerivedData/Outbound-gniranfbeecymqczagdjamiipyqq/Build/Products/Debug-iphonesimulator/Outbound.app/GoogleService-Info.plist
plutil -extract PROJECT_ID raw ~/Library/Developer/Xcode/DerivedData/Outbound-gniranfbeecymqczagdjamiipyqq/Build/Products/Debug-iphonesimulator/Outbound.app/GoogleService-Info.plist
plutil -extract BUNDLE_ID raw ~/Library/Developer/Xcode/DerivedData/Outbound-gniranfbeecymqczagdjamiipyqq/Build/Products/Debug-iphonesimulator/Outbound.app/GoogleService-Info.plist
```

Expected values: app ID `1:186140050970:ios:9dcd3698a906d4cca033a3`, project ID `outbound-494602`, bundle ID `plainstride.outbound`.

## Debug Test Personas

Debug builds show a **Sign in with Test User** menu for local, repeatable Firebase Auth Emulator accounts without adding a password login to the release app. The menu offers New Runner, Active Runner, and Social Runner. Selecting a persona without the emulator launch argument shows a setup error; with the argument present, it creates the emulator account on first use and signs into it afterward.

Start the Auth Emulator from the repository root:

```sh
npx --yes firebase-tools emulators:start --only auth --project outbound-494602
```

The checked-in emulator configuration binds Auth to `0.0.0.0` so a physical
device on the same trusted local network can reach it. The Emulator UI remains
bound to localhost.

Start the local backend in a second terminal. Firebase Admin accepts emulator tokens only when `FIREBASE_AUTH_EMULATOR_HOST` is set:

```sh
cd backend
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
FIREBASE_PROJECT_ID=outbound-494602 \
npm run start:local
```

Seed or reset the four reserved personas from a third terminal after the local backend has initialized its database:

```sh
cd backend
FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
FIREBASE_PROJECT_ID=outbound-494602 \
DATABASE_URL=postgresql://outbound:outbound@127.0.0.1:54329/outbound?schema=public \
npm run seed:e2e
```

The command refuses non-local Auth Emulator and database hosts. It deletes and recreates only the reserved test identities before inserting deterministic data:

- New Runner: authenticated account with no onboarding or activity history.
- Active Runner: completed runner profile, calibration, three activities with screenshot-ready running photos, and learned insights.
- Social Runner: completed runner profile, accepted and pending connections, joined and discoverable groups, an upcoming group run with RSVP, feed interaction, notifications, an invitation, and a blocked runner.
- Blocked Runner: completed runner profile reserved as the deterministic block-list target for Social Runner.

The Debug persona picker also resets the account-scoped onboarding marker: New Runner always enters onboarding, while Active Runner and Social Runner skip it. Server-backed activity and social data still come from the local API.

Run `seed:e2e` before a local E2E session whenever a clean baseline is needed. Do not use Delete Account inside a test that expects a later test to reuse that persona; reseed afterward if account deletion is the behavior under test.

In the Debug scheme's Run arguments, add:

```text
-OutboundUseFirebaseAuthEmulator
-OutboundAPIBaseURL
http://127.0.0.1:3000/v1
```

The defaults target an iOS Simulator on the same Mac. For a physical iPhone, also pass `-OutboundFirebaseAuthEmulatorHost` followed by the Mac's LAN address and use that address in `-OutboundAPIBaseURL`.

In Debug builds, enabling `-OutboundUseFirebaseAuthEmulator` also defaults the API base URL to `http://<emulator-host>:3000/v1` when `-OutboundAPIBaseURL` is omitted. This keeps unsigned emulator ID tokens away from the production API. An explicit API base URL still takes precedence.

The device build helper supplies those launch arguments and auto-detects the
Mac's LAN address:

```sh
./scripts/build-install-bruce-main.sh --launch --with-test-personas
```

Override detection with `OUTBOUND_LOCAL_HOST=<mac-lan-address>` when needed.
The helper also starts the Firebase Auth Emulator when port `9099` is not
already serving it, followed by embedded PostgreSQL and the local API when they
are not already healthy. Add `--simulator` to build, install, and launch on the
first available iPhone simulator using localhost instead. Run `npm run seed:e2e`
separately after the stack is ready whenever deterministic persona data should
be reset.

Stopping the emulator clears its accounts unless import/export persistence is added. Production and Release builds never expose persona login or honor these Debug-only routing arguments.
