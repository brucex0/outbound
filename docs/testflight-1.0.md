# TestFlight and App Store 1.7.18 Submission Sheet

Open this for the current TestFlight upload and public App Store release. Product behavior and release mechanics remain in `docs/app-store-release.md`.

## Build Identity

- App Store name: `Plainstride: AI Running Coach`.
- Developer: `Plainstride Labs Inc.`
- Bundle ID: `plainstride.outbound`
- Version: `1.7.18`
- Build: `72`
- SKU suggestion: `plainstride-outbound-ios`
- Primary language: English (U.S.)
- Primary category: Health & Fitness
- Secondary category: Sports
- Copyright: `2026 Plainstride Labs Inc.`
- Encryption: no non-exempt encryption; `ITSAppUsesNonExemptEncryption` is `false`.
- Customer-facing and installed app name: `Plainstride`.
- Internal Xcode target, scheme, storage, and backend names may remain `Outbound`.

## Submission Status

- Version 1.7.18 (72), release source `932229b3` (product source `9550610d`), completed unsigned Release compilation, signed archive/export, packaged-bundle preflight, and binary delivery on November 21, 2026 (Pacific). Apple processing completed at 07:29 Pacific; English beta notes and assignment to `Plainstride Team` were confirmed. Submitted through the signed-in App Store Connect UI on November 21, 2026 at 07:31 Pacific. Confirmed **Waiting for Review** with automatic release after approval (`AFTER_APPROVAL`); approval and public availability remain pending.
- Preserved IPA/checkpoint: `~/Library/Application Support/Plainstride/Releases/1.7.18-72/`; the 79,413,156-byte IPA SHA-256 is `11a5a99290875d867499999acd32554c6a537a18f5eb812d783973c2b4a89b0e`; upload ID `8cb42ff8-60a0-4ae6-a42f-be2f26326983`. Binary delivery accepted all 16 chunks at 07:26 Pacific without a reported transfer error.
- Public App Store version ID `5eca3249-3b41-4535-9c5b-76870df5e969`; review submission ID `81128fab-1a90-4c37-bd78-18c8d6b5e4dc`. Independent read-only API verification confirmed `WAITING_FOR_REVIEW`, attached build `72` (`VALID`), and `AFTER_APPROVAL`.
- English (U.S.) Description (2,596 characters) and Promotional Text (157 characters) were preserved exactly from live 1.7.17. UI checks passed before save, after save/reload, immediately before submission, and after submission. API comparisons independently confirmed both fields identical to live before and after submission; approved What's New also matched.
- No tests or physical-device acceptance were run for this release. Compilation and packaged validation do not establish runtime behavior.
- Current live version 1.7.17 (71) was confirmed **Ready for Distribution** by the read-only App Store Connect API on November 21, 2026 (Pacific). Its current English (U.S.) promotional text is preserved exactly in **App Store Promotional Text** below; this supersedes the older sheet copy. No screenshot or listing-copy change is intended.
- Fresh read-only production `/health` probe returned HTTP 200 with `{"status":"ok","version":"0.1.0"}` on November 21, 2026 at 07:28 Pacific. No authenticated scheduling behavior was exercised.
- Historical backend check from November 15, 2026: production routed 100% to `outbound-api-pa-10049c21`, with its additive plan-adjustment schema applied. Health and plan-change authentication-boundary probes returned HTTP 200 and 401 respectively; authenticated scheduling behavior was not exercised. The plan-change authentication-boundary probe and traffic allocation were not rechecked for this release.

### Previous Release: 1.7.17 (71)

- Confirmed **Ready for Distribution** by the read-only API on November 21, 2026. Build 71 is **VALID**, upload `32873ba9-d40d-48ff-a1af-e662f3e67be3` is **COMPLETE**. Preserved artifacts remain in `~/Library/Application Support/Plainstride/Releases/1.7.17-71/`.

### Previous Release: 1.7.16 (70)

- Version 1.7.16 (70) completed unsigned Release compilation, signed archive/export, packaged-bundle preflight, and binary delivery on November 13, 2026 (Pacific), from source `04755cff`. Apple processing completed at 22:31 Pacific; English beta notes and assignment to `Plainstride Team` were confirmed.
- Preserved IPA/checkpoint: `~/Library/Application Support/Plainstride/Releases/1.7.16-70/`; the 73,197,471-byte IPA SHA-256 is `1ffda84a5ad42aee935ce93591147b7fe73b85a12fb5f6621238a36ee0230f82`; upload ID `5c9def8c-97d6-4d4b-9223-a13b1fb75b32`. All 14 chunks were accepted after resuming the same IPA. See the runbook incident for recovered SSL/broken-pipe failures.
- Submitted 1.7.16 (70) through App Store Connect on November 13, 2026 at 22:32 Pacific. Confirmed **Waiting for Review**, submission `dd1f5155-c36a-455a-bbc6-5e94e7470929`, with automatic release after approval and immediate availability to all users configured. This is a public App Review submission; approval and public availability remain pending.
- English (U.S.) Promotional Text was initially blank, restored exactly from the live listing, and verified before saving, after saving/reload, immediately before submission, and after submission/reload. The read-only API also confirmed the exact promotional text, approved What's New, attached build, `AFTER_APPROVAL`, and `WAITING_FOR_REVIEW`.
- Version 1.7.15 (69) is confirmed **Ready for Distribution** in App Store Connect on November 13, 2026. Its live promotional text was preserved.
- No tests or physical-device acceptance were run for this release. Release compilation succeeded with existing compiler warnings; it does not confirm device behavior.

### Previous Release: 1.7.15 (69)

- Completed unsigned Release compilation, signed archive/export, packaged-bundle preflight, upload, and Apple processing on November 11, 2026 (Pacific), from source `c09174f241d1ed8cda17432f676cfb325e7b0a2b`. English beta notes were published and assignment to internal TestFlight group `Plainstride Team` was confirmed.
- Submitted November 11, 2026 at 2:34 PM Pacific, submission `bba96776-83c5-433b-ade3-f20c1d0733f3`, with automatic release after approval. Now **Ready for Distribution**.
- Preserved IPA/checkpoint: `~/Library/Application Support/Plainstride/Releases/1.7.15-69/`; the 72,804,550-byte IPA SHA-256 is `cea03b52ea341c4f409be05d237468743be5ae7d72a86290714635f6fb779f62`; upload ID `1364ffe8-bf1b-4749-aabd-5267ef5b1f86`.

### Previous Release: 1.7.14 (68)

- Version 1.7.14 (68) completed unsigned Release compilation, signed archive/export, packaged-bundle preflight, upload, and Apple processing on November 8, 2026 (Pacific), from source `5b837f2f82d91fa9be9769bda76bf8f1a765a233`. English beta notes were published and assignment to internal TestFlight group `Plainstride Team` was confirmed.
- Submitted through App Store Connect on November 8, 2026 at 11:20 PM Pacific. It was approved and is now **Ready for Distribution**.
- Preserved IPA/checkpoint: `~/Library/Application Support/Plainstride/Releases/1.7.14-68/`; the 71,746,744-byte IPA SHA-256 is `164870945774542dbb03ece6e0d742144498234c6399c308a66f0bbb24187aa4`; upload ID `fef02fad-345b-48c1-80fb-bf8a7230d389`.

### Previous Release: 1.7.13 (67)

- Version 1.7.13 (67) completed unsigned Release compilation, signed archive/export, packaged-bundle preflight, upload, and Apple processing on November 8, 2026, from source `bc44c81e` (product source `6e48ecb1`). English beta notes were published and assignment to internal TestFlight group `Plainstride Team` was confirmed.
- Submitted 1.7.13 (67) through App Store Connect at 9:08 AM Pacific on November 8. It was later approved and is now Ready for Distribution.
- Preserved IPA/checkpoint: `~/Library/Application Support/Plainstride/Releases/1.7.13-67/`; upload ID `7553ea8b-8d77-4671-a67c-22d66fc61e49`; IPA SHA-256 `5dde7f1f98a3b0d17edad990aaa245b2c3928a03d6f1e0982794a9c771a1b86c`.
- Production backend health returned HTTP 200. Public privacy, support, and Terms pages opened successfully in the browser from the configured `.ai` URLs; command-line requests returned HTTP 403, so association endpoints remain unverified.

## App Store Positioning Experiment

- Existing App Store localization: English (U.S.) only; in-app Spanish and Simplified Chinese support are unchanged.
- Subtitle: `Daily Plans & Live Guidance`. The requested `Daily Plans & Live Run Guidance` is 31 characters and Apple rejected it.
- Promotional text: use the approved **App Store Promotional Text** below.
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

- [iOS] Compact nutrition cards with natural food photos
- [iOS] Match nutrition illustrations to food guidance
- [iOS] Keep finish encouragement out of cooldown phases
- [iOS] Restore completed Planned access and unmerged interaction fixes
- [iOS] Open workout changes only on user request
- Plus 10 more fixes and improvements

### App Store What's New

Explore Nutrition beta with workout guidance and a private food diary. Review completed workouts and plan history more easily. This update also improves workout adjustments, cooldown voice guidance, and startup stability.

### App Store Promotional Text

Personalized training and race plans, live guidance, warm up and stretch routines, deep insights, run with with friends, share live location with loved ones.

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

## App Store Product Copy

The current live description below is the source for preserving listing copy. The early subtitle and keyword drafts are historical, not instructions to overwrite live fields.

- Subtitle: `Your adaptive running guide`
- Promotional text: preserve the exact approved **App Store Promotional Text** above; this early draft is not a source for overwriting current listing copy.
- Keywords: `running,run tracker,training plan,AI guide,GPS,workout,fitness,pace,marathon,5K`

### Description

Current live English (U.S.) copy, preserved exactly from App Store Connect on November 21, 2026:

Tired of juggling between multiple apps for tracking, training, stretching, and countless paywalls?
Plainstride bring it all, completely free!

Get a personalized workout, hear guidance during your run,  adjust your training when life changes.
Run with your group, share live location with your loved ones!

MEET YOUR AI ACTIVITY BUDDY
Your AI buddy helps you decide what to do today based on your goals, fitness, schedule, readiness, and recent training. Set smart, flexible goals based on distance, time, or calories, and explore a robust library of prebuilt plans and curated workouts. When life changes the plan, Plainstride adapts your workout and explains why, so you can spend less time guessing and more time moving.
GO SOLO OR BRING THE CREW
During a group run, walk, or ride, track your distance, time, pace, and route, capture shared moments with photos, and enjoy optional spoken guidance and Apple Music playback. When someone can’t join, share a private live link so they can follow along and cheer you on from wherever they are.
CELEBRATE & TRACK PROGRESS
Afterward, celebrate the miles together and see how far you’ve come. Review recent activities, weekly progress, trends, personal records, race predictions, and shoe mileage. Optional Apple Health and local weather integrations keep the experience connected while leaving you in control.
KEY FEATURES:
• Multi-Sport Tracking: Full support for running, walking, and biking
• AI Activity Buddy: Personalized, adaptive guidance for your workouts
• Smart Goal Setting: Flexible targets based on distance, time, or calories
• Curated Workouts: A wide variety of prebuilt training plans and guided sessions
• Group Sessions: Fun, social tracking for group runs, walks, or rides
• Smart Adjustments: Readiness-aware daily plans that fit real life
• Live Tracking: Private live-activity sharing with friends and family
• Memories: Capture photos of memorable miles together
• Audio Integration: Optional Apple Music playback and spoken guidance
• Versatile Tracking: Outdoor GPS and indoor activity recording
• In-Motion Controls: Pause, resume, goal-tracking, and Live Activities support
• Deep Analytics: Activity history, weekly trends, records, and progress insights
• Apple Health: Optional Health import and manual workout logging
• Smart Context: Local weather insights for planning your route
Move for the goal. Stay for the good company.
—
Disclaimer: Plainstride provides fitness guidance, not medical advice. Availability of Apple services and device features varies by region, subscription, hardware, and operating system.

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
- Build `1.7.18 (72)` was archived, validated, and uploaded with the repository helper. Apple processing completed; the helper populated **What to Test** and confirmed the build in the `Plainstride Team` internal group.
- Version `1.7.18 (72)` is **Waiting for Review**, submitted with automatic release after approval; approval and public availability remain pending.
- For external testing, enter the prepared Test Information and submit the first build for TestFlight App Review; group assignment does not bypass that review.
