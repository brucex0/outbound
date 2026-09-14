# iOS Onboarding Parity

## Adaptive Plan Intake

- Android and iOS consume the same `GET /v1/planning/intake-context` evidence and question contract.
- Both accept a natural-language goal through `POST /v1/planning/intake/interpret` while retaining structured controls as fallback.
- Established runners confirm an editable 28-day baseline; new or insufficient-data runners answer the full baseline questions.
- Event goals collect date, distance, and finish/performance/time intent. Generic goals collect a 4/8/12-week review horizon and optional progress description.
- Birth date, sex assigned at birth, and weight are required for personalized planning. Health Connect and Apple Health are optional autofill paths; height remains optional.
- Analytics contain bounded state and source labels only, never answers, measurements, health facts, or conversational text.

## Authority And Counterparts

- iOS flow: `ios/Outbound/Outbound/Features/Onboarding/SimplifiedOnboardingFlow.swift`
- iOS draft and routing state: `ios/Outbound/Outbound/App/OnboardingStore.swift`
- iOS account status and planning contracts: `ios/Outbound/Outbound/App/AuthStore.swift`, `ios/Outbound/Outbound/Core/AuthSession.swift`, and `ios/Outbound/Outbound/Core/APIClient.swift`
- Android flow: `OnboardingRoute.kt`, `OnboardingViewModel.kt`, and `OnboardingModels.kt`
- Android persistence and network boundary: `OnboardingDraftStore.kt`, `DefaultOnboardingRepository.kt`, `AccountApi.kt`, and `PlanningApi.kt`

## States And Transitions

- Fresh pending accounts complete required identity, then see the welcome promise with `Create my plan` and durable `Explore first` actions.
- Plan setup covers objective, one-or-more activity selection, event details when relevant, starting point, realistic week, optional Health Connect/private details, review, honest indeterminate creation, and the generated starting-week result.
- Builder answers are account-scoped and resume after interruption. `Finish later` resolves first-use onboarding as skipped but keeps the draft; later Today entry points reopen the reusable builder without changing the earlier skip result.
- Resolved accounts bypass first-use onboarding. Debug replay does not clear account identity, activities, or an active plan.
- Creation and skip failures preserve state and surface transient feedback. Startup account-resolution failure remains fail-open.

## Shared Resources

- Copy is generated from `ios/Outbound/Outbound/Localizable.xcstrings` for English, Spanish, and Simplified Chinese.
- Android substitutes Health Connect for Apple Health and Material/Compose controls for SwiftUI controls while preserving the information hierarchy and intent.

## Analytics And Accessibility

- Bounded events cover onboarding resolution, builder entry/exit, step views, health connection, optional private-profile completion, and plan creation result/latency/activity count.
- Free text, measurements, dates, constraints, identity, and workout details are excluded from analytics.
- Headings, progress semantics, selected controls, full-row targets, and localized labels are exposed to TalkBack.

## Reference Scenarios

- Pending account with and without missing identity.
- Explore-first success and retryable failure.
- Interrupted builder resume; event and non-event objectives; one and three activities; one and six weekly sessions.
- Metric and imperial private details; Health Connect unavailable and connected.
- Plan creation success, failure with preserved draft, generated result, and return to Today.
- Completed account startup, Today no-plan entry, and debug replay.

## Status

- Implemented for first-use onboarding, Settings replay, and the Today no-plan entry.
- The `all_plans` source is modeled and instrumented; wiring awaits the Android All Plans screen, which does not yet exist.
- No owner-approved behavioral exceptions.
