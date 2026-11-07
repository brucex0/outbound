# Documentation Index

Read this after `AGENTS.md`. Open only the route needed for the current task.

## Common Routes

| Task | Open |
| --- | --- |
| Coding workflow, automatic model routing, Codex presets, Freebuff, handoffs, task template | `docs/agent-workflow.md` |
| Current product flow and terminology | `docs/product-overview.md` |
| iOS source layout, recording, camera, persistence, guide | `docs/ios-architecture.md` |
| iOS build, signing, simulator, device install | `docs/build-test-device.md` |
| iOS publishing, upload retry or stalled delivery | `docs/app-store-release.md` — read before every release/recovery |
| Android architecture, parity, release gates | `docs/android-port.md` |
| Android build, toolchain, variants | `docs/android-build.md` |
| Android navigation and Back behavior | `docs/android-navigation.md` |
| Backend architecture and boundaries | `docs/backend-architecture.md` |
| Backend deployment and Cloud Run | `docs/backend-deploy.md` |
| Production logs and database diagnostics | `docs/production-diagnostics.md` |
| Firebase configuration and remaining services | `docs/firebase.md` |
| Localization and translation | `docs/localization.md` |
| Analytics events and privacy | `docs/product-analytics.md` |
| Any iOS or Android UI change | `docs/design-system.md` — design contracts, review checklist, automated checks |
| Activity launch dock and live recording UX | `docs/activity-launch-live-ux.md` |
| Onboarding and plan setup | `docs/new-user-onboarding.md` |
| Guidance plans and adaptation | `docs/guidance-plans.md`, `docs/adaptive-planning-engine.md` |
| Live coaching operations and audio | `docs/live-coach-operations.md` |
| Stretch catalog, editor, generation | `docs/stretch-routines.md` |
| Groups, membership approval, member invitations, weekly recurrence, and Social | `docs/run-groups.md`, `docs/social.md` |
| Account preferences and statistics | `docs/account-preferences.md`, `docs/account-statistics.md` |
| Git transport problems | `docs/git-transport.md` |
| Any other feature, historical plan, prototype, or handoff | Search `docs/reference-map.md` |

## Find a Specific Route

The detailed map retains all feature routes and descriptions. Search it before opening a matching document; do not load the whole map by default.

```sh
rg -n -i 'route|subscription|notification' docs/reference-map.md
```

Replace the example keywords with the task's terms. If a route is missing, use `rg --files docs` to locate a specific file.

## Documentation Rules

- Add new documents here with when to open them and what they contain; use the detailed map for less common routes.
- Keep this entry point concise. Keep product facts and implementation detail in their focused documents.
- Update docs with code when behavior, commands, setup, architecture, or ownership changes.
- Document commands and expected results instead of pasted logs.
