# New User Onboarding

Outbound onboarding should create a first win, not teach the whole product.

## Product Goal

New authenticated users should reach a concrete success state in two to three minutes:

1. Understand that Outbound is for coached endurance sessions.
2. Tell the app why they are here.
3. Give only the context needed to shape the first session.
4. See a personalized first-session setup.
5. Start that session or land on Me with momentum.

The flow should avoid feature tours, early permission prompts, and empty-dashboard handoffs.

## Flow

1. Welcome
   - Brand signal: Outbound.
   - Promise: one small win first, coach-guided next steps after.
   - Actions: set up first win or skip.

2. Intent
   - Options: move today, build rhythm, restart gently, train for a goal.
   - This determines the tone and suggested first session.

3. Context
   - First sport: run or bike.
   - Starting point: new, returning, or steady.
   - Today: 10, 20, or 35 minutes.
   - Weekly rhythm: 2x, 3x, or 4x.

4. Setup
   - Shows the personalized first session.
   - Shows the lightweight weekly setup.
   - Offers Start first session as the primary action and Go to Me as the fast exit.

## Implementation

- `App/OnboardingStore.swift`
  - Owns account-scoped completion state in `UserDefaults`.
  - Keeps the in-progress draft local.
  - Produces an `OnboardingProfile`, suggested readiness, and a `SuggestedSession`.

- `App/OnboardingFlowView.swift`
  - Renders the full-screen SwiftUI flow.
  - Uses the selected coach face color as the accent.
  - Calls back with whether the user chose to start the first session.

- `App/MainTabView.swift`
  - Presents onboarding after authentication when the current account has not completed it.
  - Applies the profile by setting the daily readiness.
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
