# Firebase And Google Cloud

Open this when touching Firebase Auth, Google project setup, the Firebase plist, or related REST inspection.

## Project Identity

- Google account: `bruce.xia74@gmail.com`.
- Firebase/GCP display name: `outbound`.
- GCP project ID: `outbound-494602`.
- GCP project number: `186140050970`.
- Firebase iOS app ID: `1:186140050970:ios:e8305464ba7fbb30a033a3`.
- Firebase iOS bundle ID: `xhstudio.Outbound`.
- Firebase Phone Auth provider is enabled.
- Phone Auth callback URL scheme in `Info.plist`: `app-1-186140050970-ios-e8305464ba7fbb30a033a3`.

## Local Config

- `ios/Outbound/Outbound/GoogleService-Info.plist` is local and gitignored.
- Xcode's file-system-synchronized app target copies the plist into `Outbound.app` when present.
- `firebase` CLI is not installed here. Use `gcloud` and Firebase/Identity Toolkit REST APIs if project setup needs inspection or changes.
- `zxia@snapchat.com` gcloud auth is blocked by Context Aware Access. Use `--account=bruce.xia74@gmail.com`.

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
