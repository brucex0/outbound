# Product Analytics

Open this when defining product events, measuring feature adoption, changing analytics providers, or reviewing analytics privacy.

## Goal

Use analytics to answer a small set of product questions:

- Do runners discover a feature?
- Do they configure it and start an activity with it?
- Does it work through activity save?
- Do they use it again?
- Which combinations make activity starts, saves, and retention more likely?

Measure decisions and outcomes, not every tap. An event must support a product decision, funnel, reliability check, or privacy obligation.

## Current State

The app already has a provider-neutral foundation in `Core/Analytics`:

- `AnalyticsService` defines initialization, event, identity, property, and screen operations.
- `AnalyticsManager` fans operations out to one or more providers.
- `FirebaseAnalyticsProvider` and `NoOpAnalyticsProvider` are the only adapters.
- Firebase Analytics is linked through Swift Package Manager and is selected when Firebase configuration is available.
- `ProductAnalyticsEvent.swift` defines the canonical event names, property keys, scalar values, privacy allowlist, and coarse buckets.
- `AnalyticsManager` validates events, adds shared app/OS/language/authentication context, and fans the same canonical event out to every configured provider.
- Authentication identity is synchronized at the app root with the opaque Plainstride account ID and cleared when the authenticated user disappears.
- Authentication recovery emits `authentication_session_recovered` with only a bounded recovery reason so rotation races and preserved transient failures can be monitored without sending credentials, account details, or raw errors.
- The activity flow emits setup exposure, configuration, start/pause/resume/finish/save/discard, goal-threshold, music, route-selection, shoe-selection, photo, and group-run events.
- Confirmed history deletion emits `activity_deleted` with only the history source and a coarse deleted-count bucket; it never includes activity identifiers or details.
- Live Guidance emits bounded semantic moment, spoken-cue, evaluated-outcome, challenge-selection, and post-run-feedback events. It never sends generated coaching text or exact pace, distance, or time values.
- Live Guidance model experiments also emit only coarse provider source (`remote` or `local`) and result (`success` or `fallback`); model IDs and prompts are excluded.
- Push tap routing emits `push_notification_opened` with only the share-safe notification type and coarse destination; it never sends notification, actor, connection, activity, or device identifiers.
- Product events currently flow to Firebase when configured and to the no-op diagnostic provider otherwise. The no-op provider logs only event names and parameter counts, never payload values.

The legacy provider methods still accept vendor-facing string names after the manager boundary, but product surfaces emit typed events and values. New product instrumentation must use the typed contract rather than arbitrary event strings or `[String: Any]` dictionaries.

## Measurement Model

### Core Activity Funnel

Track:

1. activity setup viewed;
2. configuration changed;
3. activity started;
4. paused, resumed, or finished;
5. saved or discarded.

`activity_started` should carry bounded configuration rather than separate events for every selected setup control:

- `entry_source`: quick start, Today workout, Me suggestion, route, group invitation;
- `goal_type`: freestyle, distance, time, calories, workout;
- `target_bucket`: coarse distance, duration, or calorie range; never the exact target;
- `music_enabled`;
- `route_selected`;
- `shoe_selected`;
- `pre_run_photo_added`;
- `group_run_enabled`;
- `live_share_enabled`;
- `indoor`.

`activity_saved` may add coarse duration, distance, goal-completion, and photo-count buckets. Keep exact activity facts in the activity record, not general product analytics.

### Feature Funnels

| Feature | Recommended sequence |
| --- | --- |
| Music | setup exposed -> authorization requested/result -> quick pick selected -> playback started -> control used or playback failed -> activity saved with music |
| Routes | owner Save Route exposed -> publish started -> publish completed/failed -> optional publication removal; library exposed -> searched/imported -> bookmark saved/removed -> route selected -> route displayed -> Route Guidance started -> 25/50/75/100% progress -> wrong-way or deviation/rejoin when applicable -> arrival/recovery when applicable -> activity saved with route outcome |
| Distance/time goals | goal control exposed -> type/preset/custom selected -> activity started -> progress bucket reached -> activity saved |
| Shoes | gear entry exposed -> shoe added/defaulted -> shoe selected -> activity saved with shoe -> retirement reminder acted on |
| Photos | capture entry exposed -> capture attempted/succeeded (including whether a coordinate was attached, never the coordinate itself) -> retained or deleted -> activity saved with photo -> explicitly shared |
| Group runs | group control exposed -> create/join attempted -> invitation shared/opened -> joined -> activity started -> activity saved |
| Live Guidance | coaching level selected -> semantic moment detected -> cue spoken -> cue outcome evaluated -> optional challenge completed -> post-run feedback submitted |

Exposure matters: a missing action means something only when the runner actually saw the relevant control. Use explicit exposure events for optional features and compare exposed users with adopters.

Avoid continuous progress telemetry. Emit at most one event for each meaningful activity goal threshold, such as 25, 50, 75, and 100 percent.

Route Guidance follows the same bounded rule. Its events may contain source (`community` or `imported`), intended direction, coarse progress percent, coarse distance bucket, and a semantic outcome. They must never contain raw route ID, route name, geometry, coordinates, or exact remaining distance. Recovery suppresses already-fired progress, deviation, wrong-way, and arrival events.

Live Guidance uses semantic values such as moment type, coaching contract, outcome, and a coarse cue-count bucket. Generated speech, prompts, snapshot history, exact pace, exact distance, and exact elapsed time stay on device. Evaluated cue outcomes update local aggregate evidence used to reduce repeatedly unhelpful Responsive cues; post-run feedback is stored only as aggregate preference evidence.

### Questions And Dashboards

- Weekly active runners and saved activities.
- Start-to-save conversion and discard stage.
- First-activity completion and 7-day/30-day retention.
- Feature discovery, adoption, successful use, and repeat use.
- Permission denial and operational failure rate by feature.
- Goal completion by goal type and coarse target bucket.
- Feature combinations used at activity start and their relationship to save and repeat-run rates.
- Group-run create/join conversion and participant-count buckets.

Do not treat correlation between a feature and retention as proof that the feature caused retention.

## Event Contract

### Canonical Types

Product code should emit a typed, provider-independent value:

```swift
struct ProductAnalyticsEvent: Sendable {
    let name: ProductEventName
    let schemaVersion: Int
    let properties: [ProductPropertyKey: AnalyticsValue]
}

enum AnalyticsValue: Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
}
```

The exact Swift shape may differ during implementation, but preserve these rules:

- Event names, keys, and enumerated values are centrally defined.
- Values are scalar and explicitly supported; no `Any`, nested objects, dates, URLs, or model serialization.
- Each event has an owner, purpose, trigger, required properties, optional properties, and schema version in one event catalog.
- Feature code emits domain meaning such as `music_playback_started`; it never imports or names Firebase, PostHog, Amplitude, or Mixpanel.
- Provider adapters perform the final naming, length, and capability mapping.

### Shared Context

The manager may add a small, centrally controlled context to every event:

- app version and build;
- operating-system major version;
- locale language;
- measurement system;
- authenticated or anonymous state;
- analytics schema version.

Do not let each feature assemble these properties. Avoid device fingerprinting, exact timestamps as custom properties, and user properties that merely duplicate event facts.

### Identity

- Use a stable opaque Plainstride account identifier after authentication, never email, display name, provider subject, or contact data.
- Reset provider identity on logout.
- Keep anonymous pre-login identity provider-independent. If anonymous-to-known merging is needed, define its semantics in the manager and test every adapter.
- Treat user properties as a small governed allowlist, not an alternate user database.

## Privacy And Governance

Never send:

- GPS coordinates, route geometry, precise start/end locations, or route names;
- photo contents, filenames, captions, or metadata;
- playlist, album, artist, track, or shoe names and notes;
- contact, group, participant, or invitation identifiers;
- free text, assistant prompts, reflection text, or error messages that may contain user data;
- raw health, reproductive-health, cycle, symptom, readiness, or private adjustment data.

Use coarse buckets for distance, duration, participant count, photo count, goal progress, and error category. Maintain an allowlist sanitizer and reject unknown keys in development. Production should drop invalid properties and record only a local diagnostic.

Before release, decide and document:

- whether collection is opt-in or opt-out and where the control lives;
- what is collected before authentication;
- retention period and regional storage;
- deletion behavior after account deletion;
- App Store privacy disclosures;
- who can access raw events and dashboards.

Do not enable session replay, autocaptured UI text, or automatic interaction tracking by default. A fitness app has too many sensitive surfaces for indiscriminate capture.

## Framework Evaluation

Evaluated against official vendor documentation on 2026-08-21. Pricing and plan limits change frequently and must be rechecked before procurement.

Identity completion during onboarding emits `onboarding_identity_prompt_viewed` and `onboarding_identity_completed`. Both include only boolean `missing_display_name` and `missing_email` properties; names, usernames, and email addresses are never included.

`activity_feed_loaded` includes `timestamp_source` (`activity_start`, `post_created_fallback`, `mixed`, or `empty`) so rollout of exact activity-time display can be monitored without sending activity dates or other personal data.

`paginated_list_page_loaded` records successful additional-page loads for `activity_history` and `connections`. It includes only the list source, a coarse count bucket for newly revealed rows, and a coarse page-depth bucket; activity facts, connection identities, cursors, and exact totals are excluded.

| Provider | Strengths for Plainstride | Tradeoffs | Fit now |
| --- | --- | --- | --- |
| Firebase Analytics | Already linked; minimal implementation work; familiar iOS SDK; automatic baseline events; custom events; direct BigQuery export for SQL and long-term ownership | Console analysis is less product-focused than dedicated tools; custom parameters need console registration for standard reports; GA naming and reporting constraints can leak into a poorly designed taxonomy | Best initial provider |
| PostHog | Strong funnels, retention, paths, stickiness, lifecycle, SQL, flags, experiments, and optional replay in one product; iOS SDK queues offline events; cloud and self-hosting paths | Adding the SDK and a new data processor increases operational/privacy work; powerful autocapture and replay require strict disabling or masking; self-hosting is real infrastructure ownership | Best next provider to trial |
| Amplitude | Mature product analytics, cohorts, funnels, experimentation, and broad Swift support; current Swift SDK has a plugin architecture | More platform surface and governance overhead than needed for the first beta; experimentation/replay integrations increase coupling if called directly | Strong alternative for deeper product analysis |
| Mixpanel | Mature event analytics and funnels; maintained Swift SDK; explicit controls for opt-out, regional endpoint, IP geolocation, and automatic events | Another SDK and processor; provider-specific identity, profiles, timing, and flags should remain outside feature code | Strong alternative, especially for straightforward event analytics |

Relevant official documentation:

- [Firebase iOS event logging and event-type limits](https://firebase.google.com/docs/analytics/ios/events)
- [Firebase Analytics export to BigQuery](https://firebase.google.com/docs/projects/bigquery-export)
- [PostHog iOS SDK, identity, and offline queue](https://posthog.com/docs/libraries/ios)
- [PostHog product analytics capabilities](https://posthog.com/docs/product-analytics)
- [Amplitude SDK capabilities and Swift support](https://amplitude.com/docs/sdks)
- [Mixpanel Swift SDK configuration and privacy controls](https://docs.mixpanel.com/docs/tracking-methods/sdks/swift)

### Recommendation

Use Firebase Analytics for the first instrumentation pass because it is already present. Design dashboards around the canonical event catalog and enable BigQuery export when raw analysis becomes useful.

Trial PostHog only after the core events have real volume and Firebase demonstrably blocks a needed analysis, such as fast exploratory paths, behavioral cohorts, or integrated flags. Run both providers through `AnalyticsManager` for a time-boxed comparison using identical canonical events. Do not rewrite feature instrumentation for the trial.

## Provider-Neutral Architecture

Use four boundaries:

1. **Domain event catalog**: typed names, values, descriptions, and privacy classification.
2. **Analytics client/manager**: consent, identity, common context, validation, and fan-out.
3. **Provider adapter**: vendor SDK initialization and canonical-to-vendor mapping.
4. **Destination configuration**: selects zero, one, or multiple adapters without changing product features.

Keep vendor-only capabilities behind separate optional protocols, for example `AnalyticsFlushing`, rather than expanding the core contract until every feature depends on the richest provider. Feature flags, experiments, crash reporting, and session replay are separate products and should not be placed on `AnalyticsService` merely because one vendor bundles them.

Provider adapters should own:

- SDK imports and credentials;
- event/key sanitization and vendor limits;
- consent enable/disable calls;
- identity/reset semantics;
- offline/flush behavior;
- regional endpoints and IP/geolocation settings;
- translation of screen events if screens remain part of the canonical catalog.

The central manager should own:

- schema validation and privacy allowlists;
- shared context;
- sampling policy, if ever needed;
- dispatch to all configured providers;
- debug inspection with no production payload logging.

### Switching Or Comparing Providers

1. Add a new adapter that passes the same contract checks.
2. Dual-write a controlled percentage or internal cohort to old and new providers.
3. Compare event counts, identities, funnel conversion, latency, deletion, and consent behavior.
4. Resolve semantic differences in the adapter, not in feature code.
5. Stop registering the old adapter after the comparison window.
6. Remove its SDK and credentials only after its local queue is flushed or intentionally abandoned.

Historical dashboards do not migrate automatically just because the client adapter changes. BigQuery export or a first-party event pipeline is the stronger long-term portability layer if historical continuity becomes important.

## Delivery Sequence

1. Approve product questions, privacy policy, naming convention, and event catalog.
2. Replace free-form calls at the product boundary with typed canonical events and values.
3. Instrument the core setup-to-save funnel.
4. Add music, route, goal, shoe, photo, and group-run funnels.
5. Add development validation and a provider contract check without sending private payloads to logs.
6. Validate Firebase DebugView and initial dashboards with internal activity sessions.
7. Review data after two to four weeks; delete unused events before expanding.
8. Re-evaluate PostHog or another provider only against concrete unanswered questions.
