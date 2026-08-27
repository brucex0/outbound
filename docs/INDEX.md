# Documentation Index

Read this after `CLAUDE.md`. Open only the detail docs needed for the current task.

## Current Product Shape

Plainstride (internally still named Outbound in targets and source paths) is an iOS fitness recording app. Login uses Firebase-backed Apple and Google provider accounts when the app has a local `GoogleService-Info.plist`.

Primary flow:

1. App launches into the production `Social · Today · Me` shell, centered on Today.
2. New authenticated accounts see the simplified runner intake, editable understanding, calibration, and first-plan onboarding; completed accounts skip it.
3. Today combines an inspirational spark, one AI-adjusted workout, vertical workout detail, readiness, Quick Start, and a Together invitation.
4. Me includes a local-first Progress entry with Strava-style weekly totals, four-week trends, PR history, race predictions, shoe mileage, recent activity stat highlights, and one lightweight momentum note derived from saved activities.
5. Me launches suggested sessions directly, while the bottom-row activity button quick-starts into the shared freestyle start page and returns to live sessions when one is already active.
6. During an activity, the camera/map experience uses a compact bottom status card with Pause while active, then Resume and Finish once paused; if `Share live run` was armed, a private live link is created for the default trusted contact, server SMS/push delivery is stubbed, the system Share Sheet opens with the link, and updates stream from live location snapshots.
7. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
8. Finish stops recording and presents a motivation reflection above the Save Activity / Discard flow, then returns to Me.
9. Save writes the activity manifest, source/gear/indoor metadata, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.
10. Social is always available through authenticated, share-safe connections, groups, group runs, invitations, and activity posts; private plan and health causes remain outside social responses.
11. Me consolidates plan progress, weekly totals, learned runner insights, history, measurement settings, and optional cycle-aware guidance.

## Open Docs By Task

| Task | Open | Contains |
| --- | --- | --- |
| App flow, Swift files, recording, camera, persistence, guide analysis | `docs/ios-architecture.md` | Source layout, module responsibilities, current recording and AI guide shape |
| App themes, palette contract, theme picker, discovery tip | `docs/themes.md` | Nine theme definitions, adaptive colors, reactive application rules, and extension checklist |
| App localization, translations, formatting, backend locale, speech | `docs/localization.md` | English, Simplified Chinese, and Spanish localization architecture, rollout, and acceptance criteria |
| Future mainland China launch, login availability, backend reachability, Android push channels | `docs/mainland-china-readiness.md` | Deferred-market decision, authentication findings, infrastructure risks, notification-provider strategy, and revisit sequence |
| Rendered localization QA findings and release blockers | `docs/localization-qa.md` | Screen coverage, mixed-language defects, terminology issues, and remaining verification matrix |
| New user onboarding, first-win setup, debug replay | `docs/new-user-onboarding.md` | Product flow, account-scoped persistence, SwiftUI surfaces, and Settings debug trigger |
| Signup and onboarding flow prototype | `docs/prototypes/outbound-onboarding-flow.html` | Clickable welcome, authentication, intake, editable understanding, calibration, first-plan, social connection, and Today wireframe |
| In-app AI assistant UX, prompt flows, and local response strategy | `docs/assistant.md` | Assistant goals, file map, persistence, capabilities, and extension ideas |
| Coherent AI companion architecture, memory, context budgets, situational signals, and permissioned actions | `docs/superpowers/specs/2026-08-09-coherent-ai-running-companion-design.md` | Approved design for the unified companion kernel, Context Compiler, runner model, decision policies, cross-surface behavior, and delivery slices |
| Coherent AI companion implementation sequence | `docs/superpowers/plans/2026-08-09-coherent-ai-running-companion.md` | File-level plan for companion persistence, context compilation, actions, iOS integration, build verification, and deployment |
| Backend deployment, Cloud Run setup, and assistant-server rollout | `docs/backend-deploy.md` | GCP project, required APIs, deploy command, and app base-URL wiring |
| Backend public-release readiness and estimated operating costs | `docs/backend-release-readiness.md` | Current infrastructure assessment, recommended launch setup, scaling path, and monthly cost ranges |
| Backend architecture, server boundaries, auth model, and implementation sequencing | `docs/backend-architecture.md` | Current server assessment, target modular-monolith design, domain ownership, and phased implementation plan |
| Guidance plans, multi-sport personalization, backend/client split, rollout plan | `docs/guidance-plans.md` | Product spec for adaptive plans, activity suggestions, plan APIs, domain model, and phased implementation |
| Adaptive planning engine, activity suggestions, generated workouts, plan adjustment tables, sport adapters | `docs/adaptive-planning-engine.md` | Smart-planner architecture, activity-suggestion endpoint design, table design, adaptation loop, and multi-sport scalability model |
| Personalized runner intake, calibration, feedback, runner model, and adaptation delivery | `docs/personalized-running-companion.md` | Product learning loop plus coordinated client/backend slices, contracts, data model, and acceptance criteria |
| Menstrual-cycle logging, symptom-led workout adaptations, privacy, and health safeguards | `docs/cycle-aware-guidance.md` | Product and data rules for optional cycle-aware guidance without universal phase-based programming |
| Cycle-aware guidance flow prototype | `docs/prototypes/outbound-cycle-aware-flow.html` | Clickable setup, logging, Today adjustment, learned-pattern, and weekly-plan wireframe |
| Active-session voice commands, spoken guide Q&A, and workout conversation scope | `docs/session-voice-control.md` | Product and implementation spec for tap-to-talk commands, live stats Q&A, and guide replies during activities |
| Product strategy, competitor scan, feature gaps, roadmap priorities | `docs/product-strategy.md` | Category landscape, Outbound strengths/weaknesses, recommended feature set, and phased roadmap |
| Zero-budget public launch, early-runner recruitment, outreach copy, and launch measurement | `docs/zero-budget-launch.md` | Positioning, first-30-day actions, relationship-calibrated messages, interview prompts, scorecard, and funding gate |
| Simplified product UX, primary navigation, AI role, plan presentation, and social model | `docs/simplified-product-ux.md` | Target direction for Together, Today, Me, guidance behavior, workout flows, and recent activity cards |
| Engineering handoff for simplified product, onboarding, and cycle-aware UI | `docs/product-ui-engineering-handoff.md` | Shared SwiftUI component contracts, screen states, accessibility, privacy, analytics, and acceptance criteria |
| Product behavior, feature adoption, event taxonomy, analytics privacy, and provider selection | `docs/product-analytics.md` | Core and feature funnels, framework evaluation, provider-neutral event contract, migration strategy, and rollout sequence |
| Client/backend replacement strategy and vertical migration sequence | `docs/simplified-product-refactor-plan.md` | Keep/replace/delete decisions, target modules and APIs, database reset, effort, risks, and cutover plan |
| Simplified product flow prototype | `docs/prototypes/outbound-major-flow.html` | Clickable wireframe for Today, quick-run goals, readiness, workout detail, live run, feedback, learned insights, Together, club runs, and Me |
| Activity start and live-run prototype | `docs/prototypes/activity-start-live-wireframe.html` | Clickable ready-to-run direction with a center Run action, progressive setup, countdown, live metrics, and expandable map |
| Social MVP wireframe | `docs/prototypes/social-mvp-wireframe.html` | Focused Social tab, connections entry, groups, notifications, and feed wireframe captured before implementation |
| Device, wearable, HealthKit, and third-party app integration planning | `docs/device-integration.md` | Feasible integration paths, vendor/app coverage, current signing constraints, and recommended rollout order |
| Safety, trusted contacts, live location sharing, and route privacy | `docs/safety-live-tracking.md` | Product scope, privacy rules, backend shape, iOS modules, and rollout plan for live tracking |
| Runner utilities, gear, PRs, race predictions, indoor/manual sessions, and source attribution | `docs/runner-utilities.md` | Practical runner feature sequencing, data model direction, UX surfaces, and metric rules |
| Apple Music, Spotify, playback UX, and music-provider rollout planning | `docs/music-integration.md` | Concrete music integration plan, provider constraints, Swift module boundaries, plist/auth changes, and phased delivery |
| Motivation UX, daily guide loops, comeback flows, and home-screen engagement | `docs/motivation-ux.md` | UX spec for daily spark, compact `Now` action, momentum states, and post-activity reflection |
| Badge strategy, recognition UX, unlock rules, and reward system rollout | `docs/recognition-rewards.md` | Product spec for Outbound's recognition layer, V1 badge families, unlock logic, and Me/post-run/Social placement |
| Goal setting, weekly progress, and guide-led focus flows | `docs/goals-progress.md` | Product and implementation spec for local-first goals, progress tracking, and conversational setup |
| Community route discovery, owner publishing, bookmarks, import/export, route privacy | `docs/route-saving-sharing.md` | Public route-library UX, backend model/API, safety trimming, GPX/GeoJSON preparation, and route-guided recording |
| Activity detail page, maps, elevation, splits, route controls | `docs/activity-detail.md` | Current activity-detail layout, data model needs, elevation-profile behavior, and rollout notes |
| Social tab, feed, clubs, relays, challenges, rivalry loops | `docs/social.md` | Social product loops, current local UI shape, future backend contracts |
| Activity-event creation, invitations, discovery, recording, and results | `docs/social.md` | Durable event model, lifecycle, owner/participant behavior, personal activity links, and rollout |
| Original activity-event interaction wireframe | `docs/prototypes/future-activities-e2e.html` | Early organizer and invitee flow; use as a reference rather than a naming or data-model contract |
| Social regression status and defect log | `docs/social-qa.md` | Latest seeded UI and real-server Social test coverage, findings, and remaining gaps |
| In-app inbox, push delivery, device registration, payloads, routing, rollout | `docs/notifications.md` | Shared backend/iOS notification contract, configuration, privacy rules, and deferred scope |
| Live group run sharing with friend pins on the in-session map | `docs/superpowers/specs/2026-06-20-live-group-run-sharing-design.md` | Product and architecture design for invite-link mutual group sharing, participant presence, map overlays, and rollout |
| Live group run sharing implementation steps | `docs/superpowers/plans/2026-06-20-live-group-run-sharing.md` | Scoped implementation plan for backend live group sessions, iOS group store, setup controls, and map overlays |
| Activity start screen polish, goal chips, setup card hierarchy | `docs/superpowers/specs/2026-05-30-start-activity-polish-design.md` | Focused design for fixing wrapped goal chips and tightening the start activity setup UI |
| Activity start screen polish implementation steps | `docs/superpowers/plans/2026-05-30-start-activity-polish.md` | Scoped plan for the selected start activity polish pass in `RecordView` |
| Live guide announcement cadence and moment direction | `docs/superpowers/specs/2026-05-30-guide-moment-director-design.md` | Lightweight design for making spoken live guide nudges feel high-presence without repetitive stat recaps |
| Guide moment director implementation steps | `docs/superpowers/plans/2026-05-30-guide-moment-director.md` | Scoped plan for the in-place `VirtualGuide` moment-direction pass |
| Remaining Firebase services and legacy-auth migration | `docs/firebase.md` | Analytics, Messaging, storage, plist, legacy bearer toggle, debug personas |
| First-party Apple authentication and sessions | `docs/superpowers/specs/2026-08-20-first-party-auth-sessions-design.md` | Approved identity, token, refresh, migration, and iOS security contract |
| First-party auth implementation steps | `docs/superpowers/plans/2026-08-20-first-party-auth-sessions.md` | Backend, iOS, tooling, documentation, and verification tasks |
| Builds, tests, device install, signing, simulator IDs | `docs/build-test-device.md` | Build-only checks, test commands, device IDs, entitlement constraints |
| TestFlight, App Store archive, metadata, privacy, submission | `docs/app-store-release.md` | Release build checklist, App Store Connect inputs, privacy review, and owner decisions |
| TestFlight 1.0 submission copy and owner fill-ins | `docs/testflight-1.0.md` | Copy-ready beta description, test instructions, review notes, privacy draft, and upload checklist |

## Documentation Rules

- Keep this index short enough to scan quickly.
- Add new docs only when a topic is large or frequently reused.
- Do not move volatile implementation details into multiple docs. Link to one source of truth instead.
- For command output, document the command and expected result, not a full transcript.
