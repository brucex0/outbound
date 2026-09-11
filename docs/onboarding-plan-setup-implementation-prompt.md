# Onboarding And Plan Setup Implementation Prompt

Use this prompt to implement the product contract in `docs/new-user-onboarding.md`.

## Prompt

Implement the production onboarding and reusable plan-setup redesign for Plainstride across the backend and iOS app.

Before editing, read:

- `AGENTS.md`
- `docs/INDEX.md`
- `docs/new-user-onboarding.md`
- `docs/guidance-plans.md`
- `docs/adaptive-planning-engine.md`
- `docs/product-analytics.md`
- `docs/ios-architecture.md`
- `docs/localization.md`

Treat `docs/new-user-onboarding.md` as the canonical product contract. Preserve unrelated working-tree changes. Do not run the test suite unless explicitly asked; use build-only and backend compile checks for verification. Because this work crosses backend and iOS, create separate focused commits titled with `[BE]` and `[iOS]` prefixes.

### Required behavior

1. Separate onboarding resolution from active-plan state.
   - Add a server-backed account status with `pending`, `skipped`, and `completed` semantics.
   - A skipped account must never be routed into onboarding automatically on a later launch, reinstall, or second device.
   - Replace the current inference from `RunnerProfile.completedAt`; profile completeness and plan existence are separate concerns.
   - Expose the new status through login, refresh, and `/auth/me` responses and persist it in the iOS Keychain session.
   - Add an authenticated mutation for resolving onboarding as skipped. Successful plan creation from the pending first-use route marks it completed.
   - Once resolved, preserve the original first-use outcome: later plan creation must not rewrite an earlier `skipped` status.
   - Give existing accounts a deterministic migration/backfill so active users are not unexpectedly returned to onboarding.

2. Make the current onboarding questionnaire a reusable plan builder.
   - It must launch from first use, the Today `Planned` control, and the All Plans page.
   - First use offers `Create my plan` and `Explore first` after required authentication, terms, and identity work.
   - `Explore first` persists `skipped` before entering the app.
   - Closing a later step preserves a local account-scoped draft and creates no partial plan.
   - Required identity fields are not part of the skippable plan builder.

3. Replace habit-oriented goals with outcome-oriented objectives.
   - Remove `Build consistency` and `Get active regularly` from user-facing objective choices.
   - Support one objective from: event preparation, endurance, speed, weight loss, fitness maintenance, health/energy, and optional other.
   - Treat starting out and returning after a break as baseline context.
   - Ask event distance/date only for event preparation.
   - Update the clean backend goal contract and persistence model so the selected objective is not ranked against secondary goals.
   - Remove or rename user-facing `Consistency` plan/focus copy; an internal base or adherence strategy may still implement consistent training.

4. Make setup and planning genuinely multi-activity.
   - Capture one or more unranked activities.
   - Offer only modalities that have an end-to-end credible adapter and client launch path.
   - For now, offer Run, Walk/Hike, and Bike. Keep Strength and Mobility hidden until their end-to-end planning and launch paths are credible.
   - Never fall through from Bike, Mixed, or another unsupported modality to Run.
   - Let the shared planner select stimuli and let modality adapters translate them into concrete sessions.

5. Accept realistic weekly capacity.
   - Change the range to 1–6 sessions per week.
   - Replace run-specific labels with activity-neutral localized copy.
   - Make preferred days optional and ask for a long-session day only when relevant; remove the hard-coded Saturday assumption.
   - For a one-session week, create one meaningful anchor session. Any recovery or mobility addition must be optional and must not inflate the stated commitment.
   - Calibration tracks the first three relevant completed sessions regardless of how many calendar weeks they span.

6. Create and present a real plan.
   - Use `Create my plan`, not `Build my first week`.
   - Submit the captured objective, modalities, baseline, availability, and constraints to the backend planning service; do not accept the first recommendation merely because it is first in an array.
   - Creation defines the overall plan and persists an active plan while concretely scheduling the adaptive starting 7–14 day window.
   - While waiting, show an honest indeterminate state without fake progress or artificial delay.
   - On failure, keep the draft and show a temporary toast with Retry.
   - On success, show `Your plan` and `Your starting week`, with the plan direction, activity mix, scheduled sessions, total time, explanation, adjustment actions, and `Go to Today`.

7. Implement the no-plan experience.
   - When `activePlan == nil`, Today defaults to the manual Run mode and must not surface a generated or fallback planned workout as if it were a plan.
   - Keep the `Planned` control visible. Tapping it opens the reusable plan builder.
   - If a plan is ended or deleted, return to this same behavior without changing onboarding status.
   - In `TrainingPlanPickerView`, lead with a prominent `Build my plan` entry, followed by recommended authored plans and the full catalog.

8. Add analytics and localization in the same change.
   - Add typed events and allowlisted properties for onboarding resolution, builder opening source, bounded exit step, and coarse plan-creation result/latency.
   - Do not send free-form objective text, profile/body data, dates, constraints, workout details, or identifiers.
   - Localize every new or changed iOS display string in English, Simplified Chinese, and Spanish with natural product-context translations.
   - Present transient API failures as toast-style feedback.

### Likely implementation areas

Backend:

- `backend/prisma/schema.prisma` and a focused migration
- `backend/src/services/authSessions.ts`
- `backend/src/routes/auth.ts`
- onboarding-resolution route/service
- `backend/src/routes/planning.ts`
- `backend/src/services/planning/types.ts`
- `backend/src/services/planning/planningService.ts`
- `backend/src/services/planning/generator.ts`
- `backend/src/services/planning/adapters/`

iOS:

- `ios/Outbound/Outbound/Core/AuthSession.swift`
- `ios/Outbound/Outbound/App/AuthStore.swift`
- `ios/Outbound/Outbound/App/OutboundApp.swift`
- `ios/Outbound/Outbound/App/OnboardingStore.swift`
- `ios/Outbound/Outbound/Features/Onboarding/SimplifiedOnboardingFlow.swift`
- `ios/Outbound/Outbound/Features/Simplified/SimplifiedAppShell.swift`
- `ios/Outbound/Outbound/Features/Planning/TrainingPlanViews.swift`
- `ios/Outbound/Outbound/Core/APIClient.swift`
- `ios/Outbound/Outbound/Core/Analytics/ProductAnalyticsEvent.swift`
- `ios/Outbound/Outbound/Localizable.xcstrings`

Update focused documentation when exact contracts or file ownership change.

### Acceptance criteria

- A new user can choose `Explore first`, reach Today, relaunch, reinstall/sign in again, and never receive automatic onboarding.
- A user without an active plan lands in Run mode; `Planned` opens plan setup.
- All Plans displays `Build my plan` before catalog plans.
- The builder has no consistency/get-active objective, supports one unranked objective and one or more unranked activities, and supports 1–6 weekly sessions.
- The builder uses activity-neutral language and produces sport-correct sessions without silently converting modalities to Run.
- `Create my plan` creates the plan that reflects the submitted inputs and shows its starting week.
- Exiting midway preserves a draft but creates no plan.
- Ending a plan restores no-plan behavior without restarting onboarding.
- New analytics pass the typed privacy allowlist and new strings are localized.
- Backend type/build verification and an iOS build-only compile check succeed.
