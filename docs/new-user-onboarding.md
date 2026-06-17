# New User Onboarding

Outbound onboarding should create a first win, not teach the whole product.

## Product Goal

New authenticated users should reach a concrete success state in two to three minutes:

1. Understand that Outbound is for coached endurance sessions.
2. Tell the coach, in their own words, what they want help with.
3. Provide body basics needed for calorie estimates and safer plan sizing.
4. Describe their current baseline and realistic weekly availability.
5. Review the coach's structured read of those answers.
6. See a personalized plan path and first-session setup.
7. Start that session or land on Me with momentum.

The flow should avoid feature tours, early permission prompts, and empty-dashboard handoffs. It should use free-text AI-style intake wherever personal context matters, with preset controls reserved for exact or constrained inputs such as units, body profile, and final plan intensity.

## Flow

1. Welcome
   - Brand signal: Outbound.
   - Promise: tell the coach the real story, then start with a concrete first session.
   - Actions: set up first win or skip.

2. Goal
   - Free-text prompt for what the user wants help with.
   - Example chips fill the text box but do not constrain the answer.
   - The local intake analyzer maps the prose to a plan focus such as first 5K, race preparation, run farther, run faster, fitness and weight support, safe return, or steady fitness.

3. Body basics
   - Unit system.
   - Age.
   - Height.
   - Weight.
   - Optional body profile for calorie estimates.
   - These fields are exact inputs rather than AI intake because calorie estimates and load heuristics need numeric values.

4. Baseline and week
   - Free-text starting-point prompt.
   - Free-text realistic-week prompt.
   - Example chips can seed common answers.
   - The intake analyzer extracts sport, comfortable duration, recent weekly frequency, injury/recovery caution, weekly rhythm, first-session length, and effort preference.

5. Coach review
   - Shows the structured read back to the user.
   - Lets the user choose easier, balanced, or harder before recommendation.
   - Includes an edit path back to the free-text answers.

6. Recommendation
   - Shows the recommended plan path.
   - Shows the first session.
   - Explains why it fits using goal, body basics, baseline, and availability.
   - Offers Start first session as the primary action and Save plan and go to Me as the fast exit.

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
