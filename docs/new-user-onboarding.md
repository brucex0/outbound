# New User Onboarding

## Fresh-install authentication

Firebase may retain credentials in the iOS Keychain after the app is deleted. Plainstride stores a separate installation marker in `UserDefaults`. If that marker is missing on launch but Firebase restores a user, the app signs out that stale restored session and shows the provider login screen. Normal relaunches and app updates keep the authenticated session because the installation marker remains present.

Onboarding completion is account-scoped and survives sign-out. Preparing a previously completed account must explicitly clear any onboarding presentation left behind while authentication transitioned through a signed-out/local identity.

Plainstride onboarding should create a first win, not teach the whole product.

## Product Goal

New authenticated users should reach a concrete success state in about 90 seconds:

1. Understand that Plainstride combines an adaptive running companion with people and running groups.
2. Authenticate with Apple or Google.
3. Choose a goal, recent baseline, and realistic weekly capacity.
4. Review and correct the companion's understanding.
5. See a credible first week with a concise AI explanation.
6. Understand that the first three normal runs form a low-pressure calibration period.
7. Optionally invite a person or find a club.
8. Land on Today with the first session ready.

The flow should avoid feature tours, early permission prompts, mandatory essays, mandatory body-profile intake, and empty-dashboard handoffs. AI should prove its value through the generated week and explanation rather than through a chatbot-centric setup.

## Target Flow

1. Welcome and authentication
   - Eyebrow: `Your AI running companion`.
   - Promise: `Train with purpose. Run with your people.`
   - Show a labeled orbit with `You` at the AI-assisted center and universal `Family`, `Friends`, and `Groups` nodes. Groups include formal running clubs and casual running groups.
   - Add one small `Better together` cue so the illustration communicates the emotional benefit of connected training rather than a generic social graph.
   - Do not use real names, initials, or club identities in the welcome illustration.
   - Show only Continue with Apple and Continue with Google. Each provider action handles both signup and login; do not add a redundant `Already have an account?` action.
   - Returning users bypass onboarding after provider authentication.

2. Goal
   - Choose run consistently, start running, return after a break, train for a race, or run faster.
   - Offer optional free text for a different goal.
   - Ask race distance and date only when race training is selected.

Before goal intake, show a short identity step only when Apple did not provide a usable display name or verified email. It collects a display name and unique username, plus a contact email only when the provider email is unavailable. Accounts with both a real display name and valid provider email skip this step.

3. Starting point
   - Choose recent running frequency.
   - Choose a comfortable run duration.

4. Realistic week
   - Choose runs per week and typical time available.
   - Ask preferred long-run day only when relevant.
   - Offer one optional context field for injury, illness, travel, or schedule constraints.

5. First week, editable understanding, and calibration
   - Show the three-session week, total time, and one precise AI explanation.
   - Offer easier, different days, or Ask adjustments.
   - Do not add another plan-confirmation screen after the editable understanding and first-week preview.
   - Show a compact summary of goal, realistic schedule, starting baseline, and material constraints.
   - Label runner-provided facts separately from starting estimates and allow section-level edits.
   - Explain that the first 7-10 days use three normal training runs to tune effort, endurance, and recovery.
   - Do not require an all-out fitness test. Offer recent race/imported benchmark input only as an optional experienced-runner path.
   - Keep the explanation on the same final review screen instead of making calibration another read-only step.

6. Optional social connection
   - Ask `Who helps you get out?`
   - Offer invite someone, find a club, or do this later.
   - Explain that health details are not shared.

7. Optional private training details and Apple Health
   - After the goal, baseline, and realistic-week intake, offer one clearly skippable screen before the final review.
   - Let runners add any combination of birthday, height, weight, and sex assigned at birth manually; no field is required.
   - Explain that birthday is stored instead of a static age so it remains accurate.
   - Offer Apple Health on the same screen as a faster alternative to manual entry, not as another onboarding page.
   - Request access only after the user taps Connect Apple Health.
   - Use up to eight weeks of running workouts to refine starting frequency and comfortable duration.
   - Save available birthday, biological sex, height, and weight to the private training profile.
   - Exclude workouts created by Plainstride and let the user continue without connecting.

8. Today
   - Land on the real Today surface with the quote, first workout, and Start action.
   - Keep the onboarding recommendation visually continuous with the product.
   - Show small `Run 1 of 3` calibration progress without making Today feel like an assessment dashboard.

The clickable reference is `docs/prototypes/outbound-onboarding-flow.html`. It remains visual direction; the five-step ordering in this document and `SimplifiedOnboardingFlow.swift` is canonical.

## Permission Timing

- Apple Health: optional on the private training-details screen after core intake, before the combined final review and first-plan creation.
- Location and motion: when the first outdoor run starts.
- Notifications: after the user accepts the plan.
- Camera and photos: on first use.
- Contacts: avoid when link-based invitations are sufficient.
- Live location: when explicitly enabling trusted-person sharing.

Do not request multiple system permissions during initial signup.

## Deferred Profile Inputs

Guide face, guide voice, and detailed preferences belong under Me or should be requested later when a feature has a clear need. Private training details remain editable under Me when the optional onboarding screen is skipped or needs an update. They never block the first useful plan.

## Current Implementation

The simplified shell uses `Features/Onboarding/SimplifiedOnboardingFlow.swift`, a five-step implementation of goal, baseline, realistic week, optional private training details, and one combined understanding/calibration review, preceded by the conditional identity step described above. The optional training-details step supports manual entry, Apple Health, or one-tap skip. Completion persists the local account-scoped onboarding marker, syncs structured runner facts through `PersonalizationStore`, and starts the recommended training plan.

Settings includes a DEBUG-only replay action that restarts the simplified onboarding flow without signing out.

## Implementation

- `App/OnboardingStore.swift`
  - Owns account-scoped completion state in `UserDefaults`.
  - Keeps the in-progress draft local.
  - Stores raw intake text, body basics, extracted intake summary, suggested readiness, and a `SuggestedSession`.
  - Uses a deterministic local intake analyzer for V1 so onboarding remains offline and predictable; a backend or on-device model can replace the analyzer later while preserving the structured summary shape.

- `App/OnboardingFlowView.swift`
  - Renders the full-screen SwiftUI flow.
  - Uses the selected guide face color as the accent.
  - Uses text editors for goal, baseline, and schedule intake.
  - Uses exact fields for age, height, weight, units, and body profile.
  - Shows the extracted guide review before the recommendation.
  - Calls back with whether the user chose to start the first session.

- `App/MainTabView.swift`
  - Presents onboarding after authentication when the current account has not completed it.
  - Applies the profile by setting the daily readiness.
  - Applies the onboarding unit choice to app measurement preferences.
  - Starts `RecordView` with the personalized `SessionIntent` when requested.

- `App/ProfileView.swift`
  - Adds a DEBUG-only Settings button to replay onboarding without signing out.

## Persistence

Completion and profile keys are namespaced by authenticated identity:

- Firebase users: `AuthStore.user.uid`.
- Local sessions: `AuthStore.localSessionLabel`.
- Fallback: `local`.

This keeps a completed flow for one account from hiding onboarding for another account on the same device.

## Debugging

Debug builds show Settings -> Debug -> Run Onboarding Flow.

The debug trigger reopens the flow and resets only the in-progress draft. It does not sign out, clear activity history, clear guide settings, or remove the prior completed profile until the replayed flow is completed.
