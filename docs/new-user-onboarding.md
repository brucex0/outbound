# New User Onboarding

Outbound onboarding should create a first win, not teach the whole product.

## Product Goal

New authenticated users should reach a concrete success state in about 90 seconds:

1. Understand that Outbound combines an adaptive running companion with people and clubs.
2. Authenticate with Apple or Google.
3. Choose a goal, recent baseline, and realistic weekly capacity.
4. See a credible first week with a concise AI explanation.
5. Optionally invite a person or find a club.
6. Land on Today with the first session ready.

The flow should avoid feature tours, early permission prompts, mandatory essays, body-profile intake, and empty-dashboard handoffs. AI should prove its value through the generated week and explanation rather than through a chatbot-centric setup.

## Target Flow

1. Welcome and authentication
   - Eyebrow: `Your AI running companion`.
   - Promise: `Train with purpose. Run with your people.`
   - Show a labeled orbit with `You` at the AI-assisted center and universal `Family`, `Friends`, and `Clubs` nodes.
   - Add one small `Better together` cue so the illustration communicates the emotional benefit of connected training rather than a generic social graph.
   - Do not use real names, initials, or club identities in the welcome illustration.
   - Show only Continue with Apple and Continue with Google. Each provider action handles both signup and login; do not add a redundant `Already have an account?` action.
   - Returning users bypass onboarding after provider authentication.

2. Goal
   - Choose run consistently, start running, return after a break, train for a race, or run faster.
   - Offer optional free text for a different goal.
   - Ask race distance and date only when race training is selected.

3. Starting point
   - Choose recent running frequency.
   - Choose a comfortable run duration.
   - Offer an explained, optional Apple Health import.

4. Realistic week
   - Choose runs per week and typical time available.
   - Ask preferred long-run day only when relevant.
   - Offer one optional context field for injury, illness, travel, or schedule constraints.

5. First week
   - Show the three-session week, total time, and one precise AI explanation.
   - Offer easier, different days, or Ask Coach adjustments.
   - Do not add a separate read-back screen.

6. Optional social connection
   - Ask `Who helps you get out?`
   - Offer invite someone, find a club, or do this later.
   - Explain that private training context is not shared.

7. Today
   - Land on the real Today surface with the quote, first workout, and Start action.
   - Keep the onboarding recommendation visually continuous with the product.

The clickable reference is `docs/prototypes/outbound-onboarding-flow.html`.

## Permission Timing

- Apple Health: optional on the Starting point screen.
- Location and motion: when the first outdoor run starts.
- Notifications: after the user accepts the plan.
- Camera and photos: on first use.
- Contacts: avoid when link-based invitations are sufficient.
- Live location: when explicitly enabling trusted-person sharing.

Do not request multiple system permissions during initial signup.

## Deferred Profile Inputs

Age, height, weight, body profile, coach face, coach voice, and detailed preferences belong under Me or should be requested later when a feature has a clear need. They should not block the first useful plan.

## Current Implementation Gap

The current implementation predates this simplified target and still includes longer free-text intake, body basics, a structured coach review, and first-session setup. Preserve the implementation notes below until the SwiftUI flow is replaced; do not treat them as the target product behavior.

## Implementation

- `App/OnboardingStore.swift`
  - Owns account-scoped completion state in `UserDefaults`.
  - Keeps the in-progress draft local.
  - Stores raw intake text, body basics, extracted intake summary, suggested readiness, and a `SuggestedSession`.
  - Uses a deterministic local intake analyzer for V1 so onboarding remains offline and predictable; a backend or on-device model can replace the analyzer later while preserving the structured summary shape.

- `App/OnboardingFlowView.swift`
  - Renders the full-screen SwiftUI flow.
  - Uses the selected coach face color as the accent.
  - Uses text editors for goal, baseline, and schedule intake.
  - Uses exact fields for age, height, weight, units, and body profile.
  - Shows the extracted coach review before the recommendation.
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

The debug trigger reopens the flow and resets only the in-progress draft. It does not sign out, clear activity history, clear coach settings, or remove the prior completed profile until the replayed flow is completed.
