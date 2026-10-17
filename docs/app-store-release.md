# App Store Release

Open this when preparing a TestFlight or App Store build.

## Repository Readiness

- Customer-facing app name: **Plainstride**. The existing internal target, scheme, bundle IDs, backend identifiers, and migration-safe storage names remain `Outbound` where changing them would break integrations or continuity.
- Prepared version/build are recorded in `docs/testflight-1.0.md`; App Store Connect is the authority for the published version.
- App bundle ID: `plainstride.outbound`.
- Live Activity extension bundle ID: `plainstride.outbound.liveactivity`.
- Version 1 supports iPhone only. `TARGETED_DEVICE_FAMILY` is `1` for every target and the plist has no iPad orientation declaration.
- Version and build number come from `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project. Increment the build number for changed app content; retry an unchanged signed IPA with the same build number.
- Release uses the Plainstride Labs Inc. team (`WT54K7D7VH`) and automatic signing.
- `PrivacyInfo.xcprivacy` declares the app's `UserDefaults` required-reason API use. Keep it current when adding covered APIs.
- `ITSAppUsesNonExemptEncryption` is `false` because the app relies on exempt operating-system and HTTPS encryption and does not implement proprietary cryptography. Reassess this if cryptography is added.
- Production uses `https://outbound-api-186140050970.us-central1.run.app/v1` and the bundled Firebase configuration.
- Public legal pages are `https://plainstride.ai/terms` and `https://plainstride.ai/privacy`. The sign-in disclosure and Settings → Legal link to them.
- Terms acceptance is versioned. New Apple sign-ins presenting the current version accept it through the adjacent disclosure; an authenticated runner whose stored version is older sees a blocking review screen that still permits sign-out and account deletion. Sign-in does not reject a Terms-version mismatch: the session response supplies the server's current version so a terms-aware older client can authenticate and immediately enter that review screen.
- Current Terms version 2 is effective September 1, 2026. Its fitness disclaimer explicitly covers approximate calculated health and fitness data, including calorie estimates, and states that those calculations are not medical information.
- For a material Terms update, change both `CURRENT_TERMS_VERSION` in `backend/src/services/legal.ts` and `PlainstrideLegal.currentTermsVersion` in iOS, update the effective date and public copy, deploy the schema/backend, then release the coordinated client. Before the new client is public, verify the current public build can sign in and is routed to reacceptance by the server-provided version.
- The app icon is a 1024-by-1024 opaque PNG.

## Before Archiving

1. Confirm the Apple Developer identifiers have Sign in with Apple, HealthKit, WeatherKit, and the Live Activity extension configured for distribution.
2. Confirm the distribution profiles cover both bundle IDs and that agreements in App Store Connect are current.
3. Confirm the production backend is deployed, monitored, and compatible with this client build.
4. Exercise authentication, Terms and Privacy links, forced Terms reacceptance, onboarding, activity recording in foreground/background, saving, HealthKit read/write, voice permissions, Apple Music, Live Activities, and account deletion on a physical iPhone.
5. Increment `CURRENT_PROJECT_VERSION` for the app and extension together.
6. Run an unsigned Release compile check:

   ```sh
   xcodebuild -quiet \
     -project ios/Outbound/Outbound.xcodeproj \
     -scheme Outbound \
     -configuration Release \
     -destination 'generic/platform=iOS' \
     CODE_SIGNING_ALLOWED=NO \
     build
   ```

7. In Xcode, select **Any iOS Device (arm64)**, choose **Product > Archive**, then use Organizer to validate and upload the archive.

## Automated TestFlight Upload

Run the repository helper from a clean tracked worktree:

```sh
./scripts/publish-testflight.sh
```

The helper keeps the iPhone app, Live Activity extension, and embedded Watch app on the same version and build number, generates brief release notes from product commits after the last change to the submission sheet’s build identity, saves them in `docs/testflight-1.0.md`, runs the unsigned Release compile check, commits the verified metadata, creates a signed archive in Xcode Organizer's standard archive folder, and uploads it to App Store Connect with external TestFlight eligibility. It then waits for Apple to process the build, copies the generated notes into the English (U.S.) **What to Test** field, and assigns the build to the app's sole internal TestFlight group. It stops before upload if another commit lands during archiving. It does not run tests, and its default mode does not publish the app publicly.

Release notes use the newest five commit subjects that touch `ios/Outbound`,
`backend`, or `Package.swift`. When more changes exist, the final bullet reports
the remaining count. Documentation and release-tooling-only commits are omitted,
and publishing stops when no product commits exist since the last release. Use
`--dry-run` to preview the exact generated notes. Upload retries that specify the
current prepared build number, and `--beta-setup-only` retries, reuse the notes
already saved for that build.

For reliable command-line authentication, create an App Store Connect API key with the access needed to upload builds, keep its `.p8` file outside the repository, and provide all three values:

```sh
ASC_KEY_PATH=/secure/path/AuthKey_KEYID.p8 \
ASC_KEY_ID=KEYID \
ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000 \
./scripts/publish-testflight.sh
```

When these values are omitted, the helper falls back to the Apple Account saved in Xcode. API-key values are passed directly to `xcodebuild`; they are not copied into the repository or archive.

Bruce's development Mac has a least-privilege `Developer` key at
`~/Library/Application Support/Plainstride/AppStoreConnect/AuthKey_8F64X54A9C.p8`.
The helper detects it automatically, so normal unattended uploads require no
environment variables. The private key stays outside the repository with
owner-only permissions. Explicit `ASC_KEY_PATH`, `ASC_KEY_ID`, and
`ASC_ISSUER_ID` values override this local default. The API key is required for
automatic release-note and beta-group setup; pass `--skip-beta-setup` only when
an upload intentionally needs to stop before those steps.

To send a build to a specific group, including an external beta group, use its
exact App Store Connect name:

```sh
./scripts/publish-testflight.sh --beta-group "External Beta"
```

The same value can be supplied as `BETA_GROUP`. `BETA_LOCALE` overrides the
release-note locale, and `ASC_PROCESSING_TIMEOUT` / `ASC_POLL_INTERVAL` tune the
default one-hour processing wait and 30-second polling interval. Assigning an
external group does not bypass Apple's Beta App Review. The API-key workflow exports the signed IPA, runs packaged-bundle preflight,
and uses Apple's supported **Build Upload API** to upload the IPA directly.
The native local analysis-description/SPI transfer is not part of this path.
`ASC_UPLOAD_METHOD=altool` selects the older uploader explicitly; its attempts
and IPA export use `ASC_UPLOAD_TIMEOUT` (900 seconds by default).

### Reliable delivery and recovery

With an App Manager/Admin key authorized to manage App Store versions, the public-release command remains:

```sh
./scripts/publish-testflight.sh --public-release
```

A fresh build checks Xcode first-launch/license readiness before changing local
version metadata. The workflow never accepts legal agreements automatically.
Prepared-IPA and setup-only retries skip build-only prerequisites.

The public command creates or reconciles the App Store draft before compiling or
uploading, so a missing create-version permission fails early. Bruce’s default
Developer key supports binary upload and TestFlight setup, but **not public
version management**. With that key, prepare/upload the intended marketing version
without `--public-release`, then finish in the signed-in App Store Connect UI:

```sh
./scripts/publish-testflight.sh --version "$VERSION"
```

In Distribution, create that version, attach the processed build, copy the saved
**App Store What’s New**, choose automatic release after approval, save, add for
review, and submit the draft. Verify **Waiting for Review**. Do not claim a
TestFlight upload is a public submission. For unattended public submission, the
owner must provide a suitable App Manager/Admin API key through the existing
`ASC_KEY_*` variables; the workflow never broadens key permissions itself.

Delivery preserves `Outbound.ipa`, `upload.json`, and sanitized `events.jsonl`
under `~/Library/Application Support/Plainstride/Releases/VERSION-BUILD/`.
`ASC_RELEASE_ROOT` overrides that directory. The checkpoint records the IPA's
SHA-256, identity, size, Apple upload/file IDs, and completed chunks. New archives
also record the source commit and archive path. Never edit the checkpoint or
replace an IPA under an existing build identity.

The shell workflow runs from an immutable temporary snapshot, so editing or
merging the script cannot corrupt commands read after a long network wait.

The uploader checks ZIP integrity, matching app/Watch/extension versions, and
known Watch background-mode values before network delivery. It uploads Apple's
specified byte ranges sequentially, checkpoints each successful chunk, and
retries only transient chunk failures (up to three retries, with backoff).
Requests have connection/read/write timeouts. It verifies the full IPA checksum
again before finalizing. Credentials and signed upload URLs are never written
to the checkpoint or event log.

**Do not rebuild after a delivery failure.** Rerun the preserved IPA:

```sh
./scripts/publish-testflight.sh --public-release \
  --upload-only "$HOME/Library/Application Support/Plainstride/Releases/VERSION-BUILD/Outbound.ipa"
```

The API uploader locks repository-managed delivery, reconciles uncertain API
responses, resumes its own existing reservation, and skips completed chunks.
It refuses a changed IPA or an upload owned by another client. Once Apple has
received the binary, reruns do not upload it again. POST requests are not blindly
retried after unknown responses; rerunning reconciles server state first.

When upload has succeeded and only processing, beta setup, or public submission
remains, use the prepared identity without any compile or upload:

```sh
./scripts/publish-testflight.sh --public-release --setup-only \
  --version "$VERSION" --build-number "$BUILD"
```

Uploading, Apple processing, and App Review are separate stages. A delivered
binary is not a public release. The workflow reports each stage and submits
for automatic release after approval only after processing succeeds.

### Recover an older Transporter/altool reservation

First stop the delivery and close Transporter, Xcode, and any `altool` or
Transporter CLI process. Never reset a record while another client is using it.
Read the exact identity and file states:

```sh
ruby scripts/testflight-upload-status.rb --version "$VERSION" --build-number "$BUILD"
```

If there is no build record and the matching upload is `AWAITING_UPLOAD` with
no app binary attached, clear only the exact abandoned ID printed above:

```sh
ruby scripts/testflight-upload-status.rb \
  --version "$VERSION" --build-number "$BUILD" --delete-awaiting "$UPLOAD_ID"
```

The helper refuses mismatched IDs, accepted builds, attached app binaries, or
open upload clients (including GUI clients, treated conservatively as active).
The new API uploader does **not** automatically delete another client's upload.
After clearing the legacy reservation, deliver the preserved IPA with
`--upload-only`. Use `--latest` on the status helper for a read-only overview.

### Incident lessons retained

- **September 29, 2026 — 1.7.4 (48):** multiple clients remained stuck on an
  old reservation. Clearing it and resending the same IPA on the same network
  succeeded. `NSURLErrorDomain -1005` and checksum retry messages did not prove
  that the local network was the root cause.
- **October 16, 2026 — 1.7.8 (60):** altool and Transporter repeatedly stalled
  on local analysis-description/SPI uploads despite fresh reservations. The
  supported binary-upload API delivered the same 31,107,303-byte IPA in six
  chunks in about 20 seconds. Broken-pipe errors on chunks 4 and 6 recovered
  through bounded per-chunk retries. A second delivery run recognized Apple's
  `PROCESSING` record and sent no chunks. This validates the new path for this
  incident; it does not establish that Apple or the network can never fail.
  Build 60 processed successfully, was assigned to the internal TestFlight team,
  and was submitted through the signed-in App Store Connect UI with automatic
  release after approval. Confirmed state: **Waiting for Review**. The Developer
  API key returned 403 when creating the public version; this is a permissions
  issue, not a reason to rebuild or re-upload. A complete `--public-release
  --upload-only` rerun then recognized the accepted build and existing
  `WAITING_FOR_REVIEW` submission without another binary upload or submission.
- Packaged validation is separate from compilation. Build 59 compiled but Apple
  rejected `location` in Watch `WKBackgroundModes`; build 60 uses the correct
  `UIBackgroundModes` declaration. The uploader now catches that known failure
  locally, and validation errors are not treated as transient transfer errors.
- A basic Transporter diagnostic can pass TCP checks, report an empty web-service
  response, and still exit zero. Read its results; do not treat exit zero as
  proof that delivery is healthy. Do not share raw ContentDelivery logs publicly:
  they can contain signed URLs. Use the sanitized release events for triage.

Apple references: [Build Upload API walkthrough](https://developer.apple.com/videos/play/wwdc2025/324/)
and [upload/build statuses](https://developer.apple.com/help/app-store-connect/reference/app-uploads/build-upload-statuses/).

Preview the next build number without changing files:

```sh
./scripts/publish-testflight.sh --dry-run
```

To upload an already-prepared build without incrementing it again, pass its
current number explicitly:

```sh
./scripts/publish-testflight.sh --build-number 10
```

If command-line upload cannot authenticate, the script preserves the verified archive and prints the exact Organizer fallback. A `Failed to Use Accounts` error means the saved-account fallback could not find App Store Connect access for the configured team; use the API-key environment variables above for future unattended uploads. When beta setup is enabled, a processing timeout or metadata error leaves the successfully uploaded build in App Store Connect and returns a nonzero exit so the remaining step can be completed manually or retried with `--beta-setup-only`.

Retry only the App Store Connect setup for an uploaded build without compiling,
archiving, or uploading it again:

```sh
./scripts/publish-testflight.sh --beta-setup-only --build-number 29
```

## Automated Public Release

Use the explicit public-release mode only after the product page, screenshots,
privacy answers, agreements, review contact, and release notes in
`docs/testflight-1.0.md` are ready:

```sh
./scripts/publish-testflight.sh --public-release
```

For a public release, the helper increments the last component of the marketing
version and the build number by default (`1.1 (35)` becomes `1.2 (36)`). It
updates both app targets and both Live Activity extension configurations, builds
and uploads the new archive, creates the matching iOS App Store version when it
does not exist, copies **App Store What's New** into the configured localization,
attaches the processed build, and submits the version through App Review. The
default release type is **After approval**, so Apple makes the version public
when review succeeds.

Override either generated number independently:

```sh
./scripts/publish-testflight.sh \
  --public-release \
  --version 1.2.1 \
  --build-number 40
```

Use `--manual-release` to hold an approved version in **Pending Developer
Release** instead. Use `--skip-beta-setup` when the public build should not also
be assigned to the TestFlight group.

If the build is already uploaded, retry only the App Store Connect work with
the exact prepared identity:

```sh
./scripts/publish-testflight.sh \
  --public-release \
  --setup-only \
  --skip-beta-setup \
  --version 1.2 \
  --build-number 36
```

Creating an App Store version through the API does not fill missing product
metadata, screenshots, review details, privacy answers, agreements, or
localizations. The helper returns a nonzero error when those prerequisites are
missing; complete them in App Store Connect and rerun the setup-only command.
The API key must have permission to manage and submit the app version. A public
submission is idempotent when the requested build is already attached or the
version is already waiting for review.

## App Store Connect Checklist

- Create App Store version `1.1` on the existing **Plainstride** record with bundle ID `plainstride.outbound`, primary category **Health & Fitness**, and the existing availability/price.
- Supply the name, subtitle, description, keywords, support URL, marketing URL if available, copyright, privacy policy URL, and any owner-approved custom EULA. Apple’s standard EULA remains in effect when no custom EULA is supplied; Plainstride’s service Terms remain separately available in the app and on the web.
- Upload truthful iPhone screenshots captured from the release build.
- Complete age rating, content-rights, advertising-identifier, accessibility, and export-compliance questions.
- Complete App Privacy from actual production behavior, including Firebase and backend handling. Audit at least: account identifiers and contact information, user content, health/fitness data, precise location, diagnostics, and any photos uploaded off device. Local-only data is not “collected” for the label merely because it is stored on device.
- Provide App Review contact details and concise review notes explaining why background location, HealthKit, microphone/speech, camera, Apple Music, WeatherKit, and Live Activities are used. Include a working review account only if Apple/Google sign-in cannot give review access.
- Select the processed build and submit it for review manually, or use `./scripts/publish-testflight.sh --public-release` after all required metadata and review answers are complete.

## Owner Decisions Still Required

- Final product-page copy, URLs, screenshots, territories, price, age rating, and release method.
- Final legal review of the public Terms and privacy policy. These must match production retention, deletion, diagnostics, third-party processing, social behavior, and fitness-safety boundaries—not only the iOS source.
- Final hands-on device acceptance and permission-path review before upload.

## Account Deletion

- Settings exposes **Delete Account** with a destructive confirmation.
- The forced Terms-review screen also exposes account deletion, so a runner can delete their account without accepting updated Terms.
- Apple-linked users reauthorize and the app revokes the Apple authorization token before deletion. Google-only users reauthenticate with Google.
- `DELETE /v1/auth/me` deletes the user's relational data through database cascades and then deletes the Firebase Auth identity.
- After the server confirms deletion, the app removes local activities and all Outbound `UserDefaults`, signs out, and returns to authentication.
- Deploy the backend schema change before reviewing this flow. Because the project is pre-publication and has no migration history, use the documented database rebuild command when resetting the current environment:

  ```sh
  cd backend
  npm run db:rebuild
  ```

## Header, Search Creative, And First Three Screenshots

Generate the coordinated static asset set from existing local captures and the
repository's coastal-trail photo (no app build or test run required):

```sh
swift -module-cache-path /tmp/plainstride-creative-module-cache \
  scripts/generate-app-store-creative.swift "$PWD" \
  "$PWD/artifacts/app-store-creative"
```

The first argument is the checkout containing `artifacts/app-store-screenshots`.
When working in an isolated worktree, supply the main checkout's absolute path.
The generator stops if a required source cannot be read or text exceeds its box.
It preserves screenshot contents and aspect ratios, and exports opaque sRGB PNGs:

- `header.png`: 3840 × 1646; one brand promise over green and coastal photography.
- `search.png`: 1920 × 1280; next-run promise beside the actual Today capture.
- `01-screenshot.png` through `03-screenshot.png`: 1284 × 2778; Today,
  workout explanation/adjustment entry, and Progress Records.
- `en-US`, `es`, and `zh-Hans` directories contain independently composed captions.
  Spanish and Chinese exports currently retain English app UI and are review
  drafts until matching localized captures replace the three inputs.

These are review assets, not proof of release readiness. The existing capture
README identifies Debug demo data. Before uploading, recapture the corresponding
release-equivalent screens with synthetic data and consistent status bars.
The current Today image has an overly broad map and workout interval labels
that do not match its descriptions; the assistant image shows an explanation,
not a completed plan adjustment. Replace those captures before submission.
Do not fabricate or edit app UI to hide these problems. Progress copy deliberately
promises best efforts and records rather than an unshown trend or AI insight.
Confirm the coastal photo's marketing usage rights before publishing.

Validate pixel dimensions, opacity, legibility, and crops locally, then check
Apple's device previews and template safe areas in App Store Connect. Upload
creative assets through Asset Library and submit for approval; applying them to
the live page remains a separate publishing action. These files do not include
Duo captures or establish Duo layout support.

Apple references (checked October 16, 2026):

- [Creative asset specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/creative-assets-specifications)
- [Asset best practices and safe-area templates](https://developer.apple.com/app-store/asset-best-practices/)
- [Manage assets and preview placements](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-your-app-store-assets)

After enough traffic accumulates, compare a second headline using product page
optimization. Review App Store conversion alongside onboarding, first activity,
and second activity within seven days. Avoid declaring a winner from a small
sample; the existing launch scorecard remains the measurement authority.
