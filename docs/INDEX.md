# Documentation Index

Read this after `CLAUDE.md`. Open only the detail docs needed for the current task.

## Current Product Shape

Plainstride (internally still named Outbound in targets and source paths) is an iOS fitness recording app. Login uses Firebase-backed Apple and Google provider accounts when the app has a local `GoogleService-Info.plist`.

Primary flow:

1. App launches into the production `Together · Today · Me` shell, centered on Today.
2. New authenticated accounts see the simplified runner intake, editable understanding, calibration, and first-plan onboarding; completed accounts skip it.
3. Today combines an inspirational spark, one AI-adjusted workout, vertical workout detail, readiness, Quick Run, and a Together invitation.
4. Me includes a local-first Progress entry with Strava-style weekly totals, four-week trends, PR history, race predictions, shoe mileage, recent activity stat highlights, and one lightweight momentum note derived from saved activities.
5. Me launches suggested sessions directly, while the bottom-row activity button quick-starts into the shared freestyle start page and returns to live sessions when one is already active.
6. During an activity, the camera/map experience uses a compact bottom status card with Pause while active, then Resume and Finish once paused; if `Share live run` was armed, a private live link is created for the default trusted contact, server SMS/push delivery is stubbed, the system Share Sheet opens with the link, and updates stream from live location snapshots.
7. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
8. Finish stops recording and presents a motivation reflection above the Save Activity / Discard flow, then returns to Me.
9. Save writes the activity manifest, source/gear/indoor metadata, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.
10. Together is always available through authenticated, share-safe connections, clubs, group runs, invitations, and activity posts; private plan and health causes remain outside social responses.
11. Me consolidates plan progress, weekly totals, learned runner insights, history, measurement settings, and optional cycle-aware coaching.

## Open Docs By Task

| Task | Open | Contains |
| --- | --- | --- |
| App flow, Swift files, recording, camera, persistence, coach analysis | `docs/ios-architecture.md` | Source layout, module responsibilities, current recording and AI coach shape |
| App localization, translations, formatting, backend locale, speech | `docs/localization.md` | English, Simplified Chinese, and Spanish localization architecture, rollout, and acceptance criteria |
| New user onboarding, first-win setup, debug replay | `docs/new-user-onboarding.md` | Product flow, account-scoped persistence, SwiftUI surfaces, and Settings debug trigger |
| Signup and onboarding flow prototype | `docs/prototypes/outbound-onboarding-flow.html` | Clickable welcome, authentication, intake, editable understanding, calibration, first-plan, social connection, and Today wireframe |
| In-app AI assistant UX, prompt flows, and local response strategy | `docs/assistant.md` | Assistant goals, file map, persistence, capabilities, and extension ideas |
| Coherent AI companion architecture, memory, context budgets, situational signals, and permissioned actions | `docs/superpowers/specs/2026-08-09-coherent-ai-running-companion-design.md` | Approved design for the unified companion kernel, Context Compiler, runner model, decision policies, cross-surface behavior, and delivery slices |
| Coherent AI companion implementation sequence | `docs/superpowers/plans/2026-08-09-coherent-ai-running-companion.md` | File-level plan for companion persistence, context compilation, actions, iOS integration, build verification, and deployment |
| Backend deployment, Cloud Run setup, and assistant-server rollout | `docs/backend-deploy.md` | GCP project, required APIs, deploy command, and app base-URL wiring |
| Backend architecture, server boundaries, auth model, and implementation sequencing | `docs/backend-architecture.md` | Current server assessment, target modular-monolith design, domain ownership, and phased implementation plan |
| Coaching plans, multi-sport personalization, backend/client split, rollout plan | `docs/coaching-plans.md` | Product spec for adaptive plans, activity suggestions, plan APIs, domain model, and phased implementation |
| Adaptive planning engine, activity suggestions, generated workouts, plan adjustment tables, sport adapters | `docs/adaptive-planning-engine.md` | Smart-planner architecture, activity-suggestion endpoint design, table design, adaptation loop, and multi-sport scalability model |
| Personalized runner intake, calibration, feedback, runner model, and adaptation delivery | `docs/personalized-running-companion.md` | Product learning loop plus coordinated client/backend slices, contracts, data model, and acceptance criteria |
| Menstrual-cycle logging, symptom-led workout adaptations, privacy, and health safeguards | `docs/cycle-aware-coaching.md` | Product and data rules for optional cycle-aware coaching without universal phase-based programming |
| Cycle-aware coaching flow prototype | `docs/prototypes/outbound-cycle-aware-flow.html` | Clickable setup, logging, Today adjustment, learned-pattern, and weekly-plan wireframe |
| Active-session voice commands, spoken coach Q&A, and workout conversation scope | `docs/session-voice-control.md` | Product and implementation spec for tap-to-talk commands, live stats Q&A, and coach replies during activities |
| Product strategy, competitor scan, feature gaps, roadmap priorities | `docs/product-strategy.md` | Category landscape, Outbound strengths/weaknesses, recommended feature set, and phased roadmap |
| Simplified product UX, primary navigation, AI role, plan presentation, and social model | `docs/simplified-product-ux.md` | Target direction for Together, Today, Me, coaching behavior, workout flows, and recent activity cards |
| Engineering handoff for simplified product, onboarding, and cycle-aware UI | `docs/product-ui-engineering-handoff.md` | Shared SwiftUI component contracts, screen states, accessibility, privacy, analytics, and acceptance criteria |
| Client/backend replacement strategy and vertical migration sequence | `docs/simplified-product-refactor-plan.md` | Keep/replace/delete decisions, target modules and APIs, database reset, effort, risks, and cutover plan |
| Simplified product flow prototype | `docs/prototypes/outbound-major-flow.html` | Clickable wireframe for Today, quick-run goals, readiness, workout detail, live run, feedback, learned insights, Together, club runs, and Me |
| Device, wearable, HealthKit, and third-party app integration planning | `docs/device-integration.md` | Feasible integration paths, vendor/app coverage, current signing constraints, and recommended rollout order |
| Safety, trusted contacts, live location sharing, and route privacy | `docs/safety-live-tracking.md` | Product scope, privacy rules, backend shape, iOS modules, and rollout plan for live tracking |
| Runner utilities, gear, PRs, race predictions, indoor/manual sessions, and source attribution | `docs/runner-utilities.md` | Practical runner feature sequencing, data model direction, UX surfaces, and metric rules |
| Apple Music, Spotify, playback UX, and music-provider rollout planning | `docs/music-integration.md` | Concrete music integration plan, provider constraints, Swift module boundaries, plist/auth changes, and phased delivery |
| Motivation UX, daily coach loops, comeback flows, and home-screen engagement | `docs/motivation-ux.md` | UX spec for daily spark, compact `Now` action, momentum states, and post-activity reflection |
| Badge strategy, recognition UX, unlock rules, and reward system rollout | `docs/recognition-rewards.md` | Product spec for Outbound's recognition layer, V1 badge families, unlock logic, and Me/post-run/Social placement |
| Goal setting, weekly progress, and coach-led focus flows | `docs/goals-progress.md` | Product and implementation spec for local-first goals, progress tracking, and conversational setup |
| Saved routes, route export, sharing requirements, storage efficiency | `docs/route-saving-sharing.md` | Product requirements for canonical route data, saved-route UX, sharing modes, and route simplification/storage rules |
| Activity detail page, maps, elevation, splits, route controls | `docs/activity-detail.md` | Current activity-detail layout, data model needs, elevation-profile behavior, and rollout notes |
| Social tab, feed, clubs, relays, challenges, rivalry loops | `docs/social.md` | Social product loops, current local UI shape, future backend contracts |
| Live group run sharing with friend pins on the in-session map | `docs/superpowers/specs/2026-06-20-live-group-run-sharing-design.md` | Product and architecture design for invite-link mutual group sharing, participant presence, map overlays, and rollout |
| Live group run sharing implementation steps | `docs/superpowers/plans/2026-06-20-live-group-run-sharing.md` | Scoped implementation plan for backend live group sessions, iOS group store, setup controls, and map overlays |
| Activity start screen polish, goal chips, setup card hierarchy | `docs/superpowers/specs/2026-05-30-start-activity-polish-design.md` | Focused design for fixing wrapped goal chips and tightening the start activity setup UI |
| Activity start screen polish implementation steps | `docs/superpowers/plans/2026-05-30-start-activity-polish.md` | Scoped plan for the selected start activity polish pass in `RecordView` |
| Live coach announcement cadence and moment direction | `docs/superpowers/specs/2026-05-30-coach-moment-director-design.md` | Lightweight design for making spoken live coach nudges feel high-presence without repetitive stat recaps |
| Coach moment director implementation steps | `docs/superpowers/plans/2026-05-30-coach-moment-director.md` | Scoped plan for the in-place `VirtualCoach` moment-direction pass |
| Firebase Auth, Google project setup, Firebase plist, REST inspection | `docs/firebase.md` | Project IDs, app IDs, callback scheme, auth/provider notes, REST pattern |
| Builds, tests, device install, signing, simulator IDs | `docs/build-test-device.md` | Build-only checks, test commands, device IDs, entitlement constraints |
| TestFlight, App Store archive, metadata, privacy, submission | `docs/app-store-release.md` | Release build checklist, App Store Connect inputs, privacy review, and owner decisions |
| TestFlight 1.0 submission copy and owner fill-ins | `docs/testflight-1.0.md` | Copy-ready beta description, test instructions, review notes, privacy draft, and upload checklist |

## Documentation Rules

- Keep this index short enough to scan quickly.
- Add new docs only when a topic is large or frequently reused.
- Do not move volatile implementation details into multiple docs. Link to one source of truth instead.
- For command output, document the command and expected result, not a full transcript.
