# Firebase Configuration

Open this when changing the remaining Firebase Analytics, Messaging, storage, or temporary backend authentication migration support.

## Current Boundary

The iOS app does not use Firebase Authentication. Sign in with Apple is performed by `AuthenticationServices`; the Apple credential is verified by the Plainstride backend, which returns first-party access and refresh tokens. `FirebaseAuth` is not linked into the iOS target.

Firebase remains in the iOS app for Analytics and Messaging. The backend may use Firebase Admin for push delivery, Firebase-backed media storage, and temporary verification of legacy beta Firebase ID tokens.

## Legacy Token Migration

Set `AUTH_ACCEPT_LEGACY_FIREBASE=true` on the backend only while existing beta identities must remain usable. Plainstride access tokens are always attempted first. Legacy tokens resolve through `AuthIdentity(provider: "firebase", providerSubject: uid)` and produce the same provider-neutral request context.

Disable the toggle after beta data is reset or legacy traffic has ended. A later migration can then remove `User.firebaseUid` and Firebase-specific administration code.

## iOS Firebase Plist

`ios/Outbound/Outbound/GoogleService-Info.plist` remains a local, gitignored input for Analytics and Messaging. The app starts without it, but those Firebase services are disabled. The plist is no longer an authentication configuration input.

## Local Debug Personas

`./scripts/build-install-bruce-main.sh --simulator --launch --with-test-personas` starts the local API and launches the Debug app with `-OutboundEnableDebugPersonas`. New Runner, Active Runner, and Social Runner obtain first-party sessions from `POST /v1/auth/debug/persona`; no Firebase Auth Emulator is involved.

The backend enables this route only when `AUTH_ENABLE_DEBUG_PERSONAS=true`, and production startup rejects that setting.
