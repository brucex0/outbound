# Firebase And Google Cloud

Open this when touching Firebase Auth, Google project setup, the Firebase plist, or related REST inspection.

## Project Identity

- Google account: `bruce.xia74@gmail.com`.
- Firebase/GCP display name: `outbound`.
- GCP project ID: `outbound-494602`.
- GCP project number: `186140050970`.
- Firebase iOS app ID: `1:186140050970:ios:e8305464ba7fbb30a033a3`.
- Firebase iOS bundle ID: `xhstudio.Outbound`.
- Firebase Email/Password auth must be enabled for app login.
- Firebase Phone Auth provider is enabled, but the app no longer depends on SMS verification for sign-in.
- Firebase Google auth is enabled through the Identity Platform `google.com` provider with a standard Google web OAuth client.
- Phone Auth callback URL scheme in `Info.plist`: `app-1-186140050970-ios-e8305464ba7fbb30a033a3`.

## Local Config

- `ios/Outbound/Outbound/GoogleService-Info.plist` is local and gitignored.
- Xcode's file-system-synchronized app target copies the plist into `Outbound.app` when present.
- `firebase` CLI is not installed here. Use `gcloud` and Firebase/Identity Toolkit REST APIs if project setup needs inspection or changes.
- `zxia@snapchat.com` gcloud auth is blocked by Context Aware Access. Use `--account=bruce.xia74@gmail.com`.

## Auth Provider Notes

- App login supports two user-facing identifiers: email address and phone number.
- When Firebase is configured, both routes authenticate through Firebase Email/Password.
- Google sign-in uses Firebase Auth's hosted OAuth flow for `google.com`, so the app can use the existing Firebase callback scheme instead of a separate native Google Sign-In SDK callback.
- When a user signs up with a phone number, the app normalizes the digits and stores them as an internal alias email of the form `phone.<digits>@users.outbound.local`.
- When Firebase is not configured, the auth screen now blocks account creation and sign-in instead of silently falling back to local-only accounts.
- This keeps sign-in compatible with Firebase Auth on a personal Apple developer setup, without requiring Apple Sign In or SMS-based phone verification.

## Google Provider Setup

- Firebase Identity Platform provider resource: `projects/186140050970/defaultSupportedIdpConfigs/google.com`.
- Allowed redirect URI: `https://outbound-494602.firebaseapp.com/__/auth/handler`.
- Keep the real Google web OAuth credential in a local-only file such as `config/google-oauth-web-client.local.json`.
- The checked-in example template is `config/google-oauth-web-client.example.json`.
- The Firebase app config currently does not expose `CLIENT_ID` or `REVERSED_CLIENT_ID`, so the app uses Firebase Auth's hosted OAuth flow instead of the native Google Sign-In SDK.

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
