# TestFlight 1.0 Submission Sheet

Open this for the first internal or external TestFlight upload. Product behavior and release mechanics remain in `docs/app-store-release.md`.

## Build Identity

- App Store name: `Plainstride` (confirm availability in App Store Connect).
- Developer: `Plainstride Labs Inc.`
- Bundle ID: `plainstride.outbound`
- Version: `1.0`
- Build: `12`
- SKU suggestion: `plainstride-outbound-ios`
- Primary language: English (U.S.)
- Primary category: Health & Fitness
- Secondary category: Sports
- Copyright: `2026 Plainstride Labs Inc.`
- Encryption: no non-exempt encryption; `ITSAppUsesNonExemptEncryption` is `false`.
- Customer-facing and installed app name: `Plainstride`.
- Internal Xcode target, scheme, storage, and backend names may remain `Outbound`.

## TestFlight Requirements

Screenshots are not required for TestFlight. Approved App Store screenshots can optionally appear in later invitations. External TestFlight requires the beta description, feedback email, review contact, and review notes below. Internal testing can start after processing and export-compliance confirmation.

### Beta App Description

Plainstride is a personalized running companion that helps runners decide what to do today, start with less friction, and build sustainable momentum. It combines adaptive training guidance, readiness-aware workout suggestions, GPS activity recording, live guidance, progress insights, Apple Health integration, optional Apple Music playback, local weather context, and private live-run sharing.

This beta focuses on the complete runner journey: signing in, setting a goal and realistic weekly rhythm, reviewing today's workout, recording and saving a run, and seeing progress afterward. Some guidance is generated or adapted automatically and should be treated as fitness guidance, not medical advice.

### What to Test

Please focus on:

- Sign in with Apple or Google, then complete runner onboarding.
- Review Today's suggested workout and readiness adjustment.
- Start, pause, resume, finish, and save an outdoor run.
- Confirm GPS route, elapsed time, distance, pace, photos, and Live Activity behavior.
- Try Apple Health import/write access and optional Apple Music connection.
- Review Progress, recent activity details, goals, and guide guidance in Me.
- Try private live-run sharing only with someone you trust.
- In Settings, confirm sign-out and Delete Account are understandable and functional.

Please report crashes, permission loops, missing activity data, inaccurate state after relaunch, confusing guidance, or any screen that blocks completion.

### How to Report Feedback

From any main Plainstride screen, shake your iPhone to open **Send feedback**. Choose **Bug** or **Suggestion**, describe what happened, and optionally include app/device details. Plainstride automatically captures the screen you were viewing; you can annotate it with the red marker, undo marks, or remove the screenshot before sharing. Tap **Share report**, then choose Mail, Messages, or another sharing app.

If shaking is inconvenient or unavailable, open **Me > Settings > Send feedback** instead.

### Feedback Email

Owner must confirm: `[SUPPORT_EMAIL]`

Suggested temporary value if no support inbox exists: `bruce.xia74@gmail.com`.

### TestFlight Review Contact

- First name: `Jiahe`
- Last name: `Xia`
- Email: `[REVIEW_EMAIL]`
- Phone: `[REVIEW_PHONE_WITH_COUNTRY_CODE]`

### Sign-In Information

- Sign-in is required.
- Sign in with Apple and Google are available.
- Preferred review path: Sign in with Apple; no shared test password is required.
- If Apple requests a dedicated account, create a reviewer-owned account through the normal provider flow. Do not share a personal Apple or Google password.

### Review Notes

Plainstride is an iPhone running and fitness beta. A reviewer can sign in with Apple, complete the short runner intake, and use the Today and Me areas without granting optional permissions.

Location is requested when the reviewer starts an outdoor activity or enables local weather context. Precise/background location records an active route and keeps the session accurate while the screen is locked or the app is backgrounded. Location is not continuously collected when an activity or explicit live share is not active.

Camera access captures optional still photos during an activity. Microphone and speech recognition support optional short voice activity commands. Apple Health read/write access imports workouts and saves completed workouts. Apple Music access provides optional workout playback. WeatherKit uses a one-shot location request for local running conditions. Live Activities show active workout status on the Lock Screen and Dynamic Island.

Private live-run sharing is user-initiated. The runner explicitly arms sharing, receives a private link through the system Share Sheet, and can stop sharing. The default beta build does not enable the broader social feed.

Account deletion is available from Me > Settings > Delete Account. It requires provider reauthentication when needed, deletes server account data, clears local Plainstride data, and signs the user out.

Plainstride provides general fitness guidance and is not a medical service. All permission-dependent features remain optional unless the reviewer actively enters that feature.

## App Store Product Copy (Prepared Early)

These fields are not required to begin TestFlight, but preparing them now avoids a second metadata pass.

- Subtitle: `Your adaptive running guide`
- Promotional text: `A running companion that adapts today's workout to your goals, readiness, recent training, and real life.`
- Keywords: `running,run tracker,training plan,AI guide,GPS,workout,fitness,pace,marathon,5K`

### Description

Plainstride helps you know what to do today—and makes it easier to get out the door.

Build a running rhythm around your goals, current fitness, realistic schedule, and readiness. Plainstride turns that understanding into a clear workout, adapts when your day changes, and keeps the reason behind each adjustment visible.

During a run, track distance, time, pace, and route while receiving optional guidance. Save meaningful moments with photos, keep an eye on the session through Live Activities, and share a private live link with someone you trust when you choose.

Afterward, review recent activities, weekly progress, trends, personal records, race predictions, and shoe mileage. Optional Apple Health, Apple Music, and local weather integrations keep the experience connected without making them prerequisites.

Key features:

- Personalized runner onboarding and adaptive workout guidance
- Readiness-aware Today experience
- Outdoor GPS and indoor activity recording
- Pause, resume, goals, spoken guidance, and Live Activities
- Activity history, weekly trends, records, and progress insights
- Optional Apple Health import and workout saving
- Optional Apple Music playback and local weather context
- User-initiated private live-run sharing
- In-app account deletion and privacy-conscious defaults

Plainstride provides fitness guidance, not medical advice. Availability of Apple services and device features varies by region, subscription, hardware, and operating system.

## URLs and Ownership Blockers

The following must be publicly reachable before App Store submission. They are not needed for the first internal TestFlight build.

- Support URL: `https://run.plainstride.com/support`
- Privacy policy URL: `https://run.plainstride.com/privacy`
- Marketing URL (optional): `[PUBLIC_MARKETING_URL]`
- Privacy choices/account deletion URL (optional): `[PUBLIC_PRIVACY_CHOICES_URL]`

The support and privacy pages are served by the same Cloud Run service as the marketing homepage and live/invitation functionality. Deploy the current backend before entering these URLs in App Store Connect.

## App Privacy Working Draft

Do not publish these answers until production retention and third-party processing are confirmed. Data stored only on the device is not “collected” for Apple's label.

Likely collected and linked to identity:

- Contact Info: email address returned by Apple or Google sign-in.
- Identifiers: Firebase user ID and provider identifiers.
- Fitness: onboarding profile, plan/readiness inputs, workout/activity data, and guidance feedback sent to the backend.
- Precise Location: active live-share coordinates and any uploaded route/activity coordinates.
- User Content: assistant messages, activity reflections, and user-submitted live-share/contact fields; include photos only if the production build uploads them.

Confirm before selecting:

- Diagnostics: select only if production logging/crash tooling receives device diagnostics tied to the app.
- Health: Apple Health values that remain on device are not collected; select Health only if they are sent to the backend.
- Contacts: do not select merely because a user manually enters or shares with a trusted person; review what the backend retains.
- Photos: local activity photos are not collected unless upload is enabled.
- Tracking: current privacy manifest says no tracking; do not declare tracking unless cross-company advertising or tracking is added.

Expected purposes are App Functionality and, where the companion uses runner data to personalize guidance, Product Personalization. Do not select Third-Party Advertising or Developer Advertising unless product behavior changes.

## Final Upload Checklist

- Confirm an Apple Distribution identity with its private key is usable in Keychain.
- Confirm automatic signing for both the app and Live Activity extension under team `WT54K7D7VH`.
- Confirm App Store Connect app record, agreements, and capabilities.
- Fill the support email, reviewer email, and reviewer phone above.
- Run the physical-device acceptance list in `docs/app-store-release.md`.
- Archive `1.0 (12)`, validate, and upload from Xcode Organizer.
- After processing, answer export compliance and add the build to an internal group.
- For external testing, enter the prepared Test Information and submit the first build for TestFlight App Review.
