# TestFlight and App Store 1.7.10 Submission Sheet

Open this for the current TestFlight upload and public App Store release. Product behavior and release mechanics remain in `docs/app-store-release.md`.

## Build Identity

- App Store name: `Plainstride: AI Running Coach`.
- Developer: `Plainstride Labs Inc.`
- Bundle ID: `plainstride.outbound`
- Version: `1.7.10`
- Build: `62`
- SKU suggestion: `plainstride-outbound-ios`
- Primary language: English (U.S.)
- Primary category: Health & Fitness
- Secondary category: Sports
- Copyright: `2026 Plainstride Labs Inc.`
- Encryption: no non-exempt encryption; `ITSAppUsesNonExemptEncryption` is `false`.
- Customer-facing and installed app name: `Plainstride`.
- Internal Xcode target, scheme, storage, and backend names may remain `Outbound`.

## Submission Status

- Version 1.7.10 (62) passed unsigned Release compilation, signed archive/export, packaged-bundle preflight, upload, and Apple processing. Assigned to internal TestFlight group `Plainstride Team` with English beta release notes.
- Public submission is blocked: `POST /v1/appStoreVersions` returned HTTP 403 because the configured Developer API key cannot manage public versions. Browser sign-in also stalled before authenticated access. This build is **not submitted for public release**.
- Finish in the signed-in App Store Connect UI: create 1.7.10, select build 62, copy **App Store What's New** below, choose automatic release after approval, save, add for review, submit, and verify **Waiting for Review**. Retain existing store metadata and screenshots.
- No tests or physical-device acceptance run were performed for this release.
- Preserved IPA/checkpoint: `~/Library/Application Support/Plainstride/Releases/1.7.10-62/`; upload ID `8ab0e665-fd5b-473b-b066-a5d066d2c2b0`. Do not rebuild or re-upload to finish submission.
- Prior release: 1.7.9 (61) was submitted October 22, 2026, with all eight iPhone and four Watch screenshots reporting `COMPLETE`.

## App Store Positioning Experiment

- Existing App Store localization: English (U.S.) only; in-app Spanish and Simplified Chinese support are unchanged.
- Subtitle: `Daily Plans & Live Guidance`. The requested `Daily Plans & Live Run Guidance` is 31 characters and Apple rejected it.
- Promotional text: `Know what to run today with personalized workouts, live guidance, and flexible race plans. Track your progress and share the journey with friends.`
- Description opens: “Know what to run today. Get a personalized workout, hear guidance during your run, and adjust your training when life changes.” The remaining walking, cycling, and social copy is retained.
- Keywords: `walk,hike,bike,GPS,tracker,race,workout,training,pace,marathon,5K,fitness,health,cadence,10K`. Inspected and replaced the previous field; no keyword-demand claim is implied.
- Eight screenshots lead with “Know What to Run Today,” live workout guidance, and race planning. Live sharing shows fictional Sage Runner with populated stats and voice Cheers.
- Minimum requirements remain iOS 18.0 and watchOS 11.0. Native review prompting is included from merged commit `703f42ba`; no duplicate implementation was added.
- Positioning is an experiment, with no guaranteed download or organic-search outcome.

## TestFlight Requirements

Screenshots are not required for TestFlight. Approved App Store screenshots can optionally appear in later invitations. External TestFlight requires the beta description, feedback email, review contact, and review notes below. Internal testing can start after processing and export-compliance confirmation.

### Beta App Description

Plainstride is a personalized running companion that helps runners decide what to do today, start with less friction, and build sustainable momentum. It combines adaptive training guidance, readiness-aware workout suggestions, GPS activity recording, live guidance, progress insights, Apple Health integration, optional Apple Music playback, local weather context, and private live-run sharing.

This beta focuses on the complete runner journey: signing in, setting a goal and realistic weekly rhythm, reviewing today's workout, recording and saving a run, and seeing progress afterward. Some guidance is generated or adapted automatically and should be treated as fitness guidance, not medical advice.

### What to Test

Please focus on:

- Sign in with Apple or Google, then complete runner onboarding.
- Open Terms and Privacy from sign-in and Settings; if a Terms-version gate is enabled for the build, confirm accept, sign-out, and account-deletion paths.
- Review Today's suggested workout and readiness adjustment.
- Start, pause, resume, finish, and save an outdoor run.
- Confirm GPS route, elapsed time, distance, pace, photos, and Live Activity behavior.
- Try Apple Health import/write access and optional Apple Music connection.
- Review Progress, recent activity details, goals, and guide guidance in Me.
- Try private live-run sharing only with someone you trust.
- In Settings, confirm sign-out and Delete Account are understandable and functional.

Please report crashes, permission loops, missing activity data, inaccurate state after relaunch, confusing guidance, or any screen that blocks completion.

For this build, pay extra attention to the redesigned activity launch flow:

- Confirm the map fills the setup area and the two compact control rows remain readable on a smaller iPhone.
- Switch among Planned, Freestyle, Distance, Time, and Calories; choosing a mode should not open an editor.
- Tap the goal value card to use presets or a custom target, then verify Start immediately enters countdown and live recording.
- Configure Music, Live Track, Shoes, Indoor/Outdoor, and Voice Guide directly from the dock.
- Verify the center Today position becomes Start during setup, and that calorie goals show estimated live progress.

### Beta Release Notes

- [iOS] Clarify saved activity summary and stabilize Share styling
- [iOS] Restore account stretch routines and launch defaults across phones
- [BE] Add revisioned account configuration storage and sync contract
- [iOS] Add run routines and complete orange vector artwork
- [BE] Add finite run warm-up and cooldown audio cues
- Plus 6 more fixes and improvements

### App Store What's New

- Prepare and recover with guided warm-up, cooldown, and stretch routines, with clearer exercise illustrations.
- Keep your saved stretch routines and activity-start preferences in sync across phones.
- Enjoy clearer saved-activity summaries and more consistent sharing screens.
- Includes live coaching and usability improvements.

### How to Report Feedback

When no activity is recording, shake your iPhone twice within three seconds to open **Send feedback**. Choose **Bug** or **Suggestion**, describe what happened, and optionally include app/device details and a privacy-filtered tail of recent Plainstride logs. Plainstride automatically captures the screen you were viewing; you can annotate it with the red marker, undo marks, or remove the screenshot. Tap **Submit report** to send it directly to the Plainstride team.

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

Location is requested when the reviewer starts an outdoor activity, chooses an exact meetup point for a Social activity event, or enables local weather context. Precise/background location records an active route and keeps the session accurate while the screen is locked or the app is backgrounded. Choosing a meetup point stores one exact latitude/longitude pair with that event so participants can find the marker; it is not continuous location collection. Location is not continuously collected when an activity, meetup selection, or explicit live share is not active.

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

- Support URL: `https://plainstride.ai/support`
- Terms of service URL: `https://plainstride.ai/terms`
- Privacy policy URL: `https://plainstride.ai/privacy`
- Marketing URL (optional): `[PUBLIC_MARKETING_URL]`
- Privacy choices/account deletion URL (optional): `[PUBLIC_PRIVACY_CHOICES_URL]`

The support, Terms, and privacy pages are served by the same Cloud Run service as the marketing homepage and live/invitation functionality. Deploy the current backend before entering these URLs in App Store Connect.

## App Privacy Working Draft

Do not publish these answers until production retention and third-party processing are confirmed. Data stored only on the device is not “collected” for Apple's label.

Likely collected and linked to identity:

- Contact Info: email address returned by Apple or Google sign-in.
- Identifiers and account metadata: provider identifiers plus the current accepted Terms version and acceptance time.
- Fitness: onboarding profile, plan/readiness inputs, workout/activity data, and guidance feedback sent to the backend.
- Precise Location: one exact meetup coordinate pair for Social activity events, active live-share coordinates, and any uploaded route/activity coordinates.
- User Content: assistant messages, activity reflections, and user-submitted live-share/contact fields; include photos only if the production build uploads them.

Confirm before selecting:

- Diagnostics: in-app feedback can send optional app/device details and a privacy-filtered recent-log attachment linked to the authenticated account. Confirm the exact App Store Connect diagnostic subtype against the submitted build and final privacy policy.
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
- Archive `1.7.10 (62)`, validate, and upload from Xcode Organizer.
- After processing, confirm the publish script populated **What to Test** and added the build to the selected beta group.
- For external testing, enter the prepared Test Information and submit the first build for TestFlight App Review; group assignment does not bypass that review.
