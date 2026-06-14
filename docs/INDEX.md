# Documentation Index

Read this after `CLAUDE.md`. Open only the detail docs needed for the current task.

## Current Product Shape

Outbound is an iOS fitness recording app. Login uses Firebase-backed Apple and Google provider accounts when the app has a local `GoogleService-Info.plist`.

Primary flow:

1. App launches directly into `MainTabView`.
2. New authenticated accounts see the first-win onboarding flow before normal use; completed accounts skip it.
3. Me tab is the first tab and now centers a compact coach-led `Now` moment: spark card, one main action card, Progress, and recent activity.
4. Me includes a local-first Progress entry with Strava-style weekly totals, four-week trends, PR history, race predictions, shoe mileage, recent activity stat highlights, and one lightweight momentum note derived from saved activities.
5. Me launches suggested sessions directly, while the bottom-row activity button quick-starts into the shared freestyle start page and returns to live sessions when one is already active.
6. During an activity, the camera/map experience uses a compact bottom status card with Pause while active, then Resume and Finish once paused; if `Share live run` was armed, a private live link is shared through the system Share Sheet and updated from live location snapshots.
7. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
8. Finish stops recording and presents a motivation reflection above the Save Activity / Discard flow, then returns to Me.
9. Save writes the activity manifest, source/gear/indoor metadata, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.
10. Social is isolated behind the `OUTBOUND_ENABLE_SOCIAL` compilation condition; default beta builds omit the Social tab, Social stores, Social recognition state, and Social assistant copy.
11. Coach customization and shoe tracking live under Settings; the user can choose a predefined coach, tune voice/face/style/nudge frequency, and add or retire running shoes.

## Open Docs By Task

| Task | Open | Contains |
| --- | --- | --- |
| App flow, Swift files, recording, camera, persistence, coach analysis | `docs/ios-architecture.md` | Source layout, module responsibilities, current recording and AI coach shape |
| New user onboarding, first-win setup, debug replay | `docs/new-user-onboarding.md` | Product flow, account-scoped persistence, SwiftUI surfaces, and Settings debug trigger |
| In-app AI assistant UX, prompt flows, and local response strategy | `docs/assistant.md` | Assistant goals, file map, persistence, capabilities, and extension ideas |
| Backend deployment, Cloud Run setup, and assistant-server rollout | `docs/backend-deploy.md` | GCP project, required APIs, deploy command, and app base-URL wiring |
| Backend architecture, server boundaries, auth model, and implementation sequencing | `docs/backend-architecture.md` | Current server assessment, target modular-monolith design, domain ownership, and phased implementation plan |
| Coaching plans, multi-sport personalization, backend/client split, rollout plan | `docs/coaching-plans.md` | Product spec for adaptive plans, activity suggestions, plan APIs, domain model, and phased implementation |
| Adaptive planning engine, activity suggestions, generated workouts, plan adjustment tables, sport adapters | `docs/adaptive-planning-engine.md` | Smart-planner architecture, activity-suggestion endpoint design, table design, adaptation loop, and multi-sport scalability model |
| Active-session voice commands, spoken coach Q&A, and workout conversation scope | `docs/session-voice-control.md` | Product and implementation spec for tap-to-talk commands, live stats Q&A, and coach replies during activities |
| Product strategy, competitor scan, feature gaps, roadmap priorities | `docs/product-strategy.md` | Category landscape, Outbound strengths/weaknesses, recommended feature set, and phased roadmap |
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
| Activity start screen polish, goal chips, setup card hierarchy | `docs/superpowers/specs/2026-05-30-start-activity-polish-design.md` | Focused design for fixing wrapped goal chips and tightening the start activity setup UI |
| Activity start screen polish implementation steps | `docs/superpowers/plans/2026-05-30-start-activity-polish.md` | Scoped plan for the selected start activity polish pass in `RecordView` |
| Live coach announcement cadence and moment direction | `docs/superpowers/specs/2026-05-30-coach-moment-director-design.md` | Lightweight design for making spoken live coach nudges feel high-presence without repetitive stat recaps |
| Coach moment director implementation steps | `docs/superpowers/plans/2026-05-30-coach-moment-director.md` | Scoped plan for the in-place `VirtualCoach` moment-direction pass |
| Firebase Auth, Google project setup, Firebase plist, REST inspection | `docs/firebase.md` | Project IDs, app IDs, callback scheme, auth/provider notes, REST pattern |
| Builds, tests, device install, signing, simulator IDs | `docs/build-test-device.md` | Build-only checks, test commands, device IDs, entitlement constraints |

## Documentation Rules

- Keep this index short enough to scan quickly.
- Add new docs only when a topic is large or frequently reused.
- Do not move volatile implementation details into multiple docs. Link to one source of truth instead.
- For command output, document the command and expected result, not a full transcript.
