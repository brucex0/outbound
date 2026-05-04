# Firebase And Google Cloud

Open this when touching Firebase Auth, Google project setup, the Firebase plist, or related REST inspection.

## Project Identity

- Google account: `bruce.xia74@gmail.com`.
- Firebase/GCP display name: `outbound`.
- GCP project ID: `outbound-494602`.
- GCP project number: `186140050970`.
- Firebase iOS app ID: `1:186140050970:ios:e8305464ba7fbb30a033a3`.
- Firebase iOS bundle ID: `xhstudio.Outbound`.
- Firebase Email/Password auth is not part of the user-facing login surface.
- Firebase Phone Auth provider may exist for older experiments, but the app no longer depends on SMS verification or phone/password sign-in.
- Firebase Google auth is enabled through the Identity Platform `google.com` provider with a standard Google web OAuth client.
- Firebase Apple auth must be enabled through the Identity Platform `apple.com` provider, and the iOS target needs the Sign in with Apple entitlement.
- Phone Auth callback URL scheme in `Info.plist`: `app-1-186140050970-ios-e8305464ba7fbb30a033a3`.

## Local Config

- `ios/Outbound/Outbound/GoogleService-Info.plist` is local and gitignored.
- Xcode's file-system-synchronized app target copies the plist into `Outbound.app` when present.
- `firebase` CLI is not installed here. Use `gcloud` and Firebase/Identity Toolkit REST APIs if project setup needs inspection or changes.
- `zxia@snapchat.com` gcloud auth is blocked by Context Aware Access. Use `--account=bruce.xia74@gmail.com`.

## Auth Provider Notes

- App login is provider-backed: Apple and Google are the only user-facing sign-in methods.
- Google sign-in uses Firebase Auth's hosted OAuth flow for `google.com`, so the app can use the existing Firebase callback scheme instead of a separate native Google Sign-In SDK callback.
- Apple sign-in uses native `AuthenticationServices` and sends a nonce-backed Apple ID token to Firebase.
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
- The Firebase app config currently does not expose `CLIENT_ID` or `REVERSED_CLIENT_ID`, so the app uses Firebase Auth's hosted OAuth flow instead of the native Google Sign-In SDK.

## Apple Provider Setup

- Enable the Firebase/Identity Platform `apple.com` provider before shipping provider login.
- Keep `com.apple.developer.applesignin = Default` in `ios/Outbound/SupportFiles/Outbound.entitlements` for Release builds. Debug device builds intentionally use an empty entitlement file so personal-team installs can keep working.
- In the Apple Developer account, ensure bundle ID `xhstudio.Outbound` has Sign in with Apple enabled.
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

Expected values: app ID `1:186140050970:ios:e8305464ba7fbb30a033a3`, project ID `outbound-494602`, bundle ID `xhstudio.Outbound`.
