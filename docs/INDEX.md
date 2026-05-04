# Documentation Index

Read this after `CLAUDE.md`. Open only the detail docs needed for the current task.

## Current Product Shape

Outbound is an iOS fitness recording app. Login uses Firebase-backed Apple and Google provider accounts when the app has a local `GoogleService-Info.plist`.

Primary flow:

1. App launches directly into `MainTabView`.
2. Me tab is the first tab and now centers a compact coach-led `Now` moment: spark card, one main action card, recent activity, and optional momentum.
3. Me launches suggested sessions directly, while a floating activity button on Me and Social quick-starts into the shared freestyle start page and returns to live sessions when one is already active.
4. During an activity, the camera/map experience uses a compact bottom status card with Pause while active, then Resume and Finish once paused.
5. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
6. Finish stops recording and presents a motivation reflection above the Save Activity / Discard flow, then returns to Me.
7. Save writes the activity manifest, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.
8. Social remains a separate tab with Squad, Clubs, and Rivals loops backed by local seeded state.
9. Coach customization lives under Settings, where the user can choose a predefined coach and tune voice, face, style, and nudge frequency.

## Open Docs By Task

| Task | Open | Contains |
| --- | --- | --- |
| App flow, Swift files, recording, camera, persistence, coach analysis | `docs/ios-architecture.md` | Source layout, module responsibilities, current recording and AI coach shape |
| In-app AI assistant UX, prompt flows, and local response strategy | `docs/assistant.md` | Assistant goals, file map, persistence, capabilities, and extension ideas |
| Backend deployment, Cloud Run setup, and assistant-server rollout | `docs/backend-deploy.md` | GCP project, required APIs, deploy command, and app base-URL wiring |
| Backend architecture, server boundaries, auth model, and implementation sequencing | `docs/backend-architecture.md` | Current server assessment, target modular-monolith design, domain ownership, and phased implementation plan |
| Coaching plans, multi-sport personalization, backend/client split, rollout plan | `docs/coaching-plans.md` | Product spec for adaptive plans, plan APIs, domain model, and phased implementation |
| Adaptive planning engine, generated workouts, plan adjustment tables, sport adapters | `docs/adaptive-planning-engine.md` | Smart-planner architecture, table design, adaptation loop, and multi-sport scalability model |
| Active-session voice commands, spoken coach Q&A, and workout conversation scope | `docs/session-voice-control.md` | Product and implementation spec for tap-to-talk commands, live stats Q&A, and coach replies during activities |
| Product strategy, competitor scan, feature gaps, roadmap priorities | `docs/product-strategy.md` | Category landscape, Outbound strengths/weaknesses, recommended feature set, and phased roadmap |
| Device, wearable, HealthKit, and third-party app integration planning | `docs/device-integration.md` | Feasible integration paths, vendor/app coverage, current signing constraints, and recommended rollout order |
| Apple Music, Spotify, playback UX, and music-provider rollout planning | `docs/music-integration.md` | Concrete music integration plan, provider constraints, Swift module boundaries, plist/auth changes, and phased delivery |
| Motivation UX, daily coach loops, comeback flows, and home-screen engagement | `docs/motivation-ux.md` | UX spec for daily spark, compact `Now` action, momentum states, and post-activity reflection |
| Badge strategy, recognition UX, unlock rules, and reward system rollout | `docs/recognition-rewards.md` | Product spec for Outbound's recognition layer, V1 badge families, unlock logic, and Me/post-run/Social placement |
| Goal setting, weekly progress, and coach-led focus flows | `docs/goals-progress.md` | Product and implementation spec for local-first goals, progress tracking, and conversational setup |
| Saved routes, route export, sharing requirements, storage efficiency | `docs/route-saving-sharing.md` | Product requirements for canonical route data, saved-route UX, sharing modes, and route simplification/storage rules |
| Social tab, feed, clubs, relays, challenges, rivalry loops | `docs/social.md` | Social product loops, current local UI shape, future backend contracts |
| Firebase Auth, Google project setup, Firebase plist, REST inspection | `docs/firebase.md` | Project IDs, app IDs, callback scheme, auth/provider notes, REST pattern |
| Builds, tests, device install, signing, simulator IDs | `docs/build-test-device.md` | Build-only checks, test commands, device IDs, entitlement constraints |

## Documentation Rules

- Keep this index short enough to scan quickly.
- Add new docs only when a topic is large or frequently reused.
- Do not move volatile implementation details into multiple docs. Link to one source of truth instead.
- For command output, document the command and expected result, not a full transcript.
