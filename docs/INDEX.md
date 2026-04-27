# Documentation Index

Read this after `CLAUDE.md`. Open only the detail docs needed for the current task.

## Current Product Shape

Outbound is an iOS fitness recording app. Login is currently bypassed so feature work can continue without Firebase Auth blocking the app.

Primary flow:

1. App launches directly into `MainTabView`.
2. Social tab is the first tab and shows Squad, Clubs, and Rivals loops with local seeded social state.
3. Record tab shows a Start button.
4. Start requests location/camera permissions, starts `ActivityRecorder`, activates `VirtualCoach` with the selected coach persona, and opens the live camera.
5. During an activity, the camera/map experience uses a compact bottom status card with Pause while active, then Resume and Finish once paused.
6. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
7. Finish stops recording and presents Save Activity / Discard.
8. Save writes the activity manifest, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.
9. The Me tab lets the user choose a predefined coach and customize voice, face, style, and nudge frequency.

## Open Docs By Task

| Task | Open | Contains |
| --- | --- | --- |
| App flow, Swift files, recording, camera, persistence, coach analysis | `docs/ios-architecture.md` | Source layout, module responsibilities, current recording and AI coach shape |
| Saved routes, route export, sharing requirements, storage efficiency | `docs/route-saving-sharing.md` | Product requirements for canonical route data, saved-route UX, sharing modes, and route simplification/storage rules |
| Social tab, feed, clubs, relays, challenges, rivalry loops | `docs/social.md` | Social product loops, current local UI shape, future backend contracts |
| Firebase Auth, Google project setup, Firebase plist, REST inspection | `docs/firebase.md` | Project IDs, app IDs, callback scheme, auth/provider notes, REST pattern |
| Builds, tests, device install, signing, simulator IDs | `docs/build-test-device.md` | Build-only checks, test commands, device IDs, entitlement constraints |

## Documentation Rules

- Keep this index short enough to scan quickly.
- Add new docs only when a topic is large or frequently reused.
- Do not move volatile implementation details into multiple docs. Link to one source of truth instead.
- For command output, document the command and expected result, not a full transcript.
