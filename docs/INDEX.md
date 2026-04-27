# Documentation Index

Read this after `CLAUDE.md`. Open only the detail docs needed for the current task.

## Current Product Shape

Outbound is an iOS fitness recording app. Login is currently bypassed so feature work can continue without Firebase Auth blocking the app.

Primary flow:

1. App launches directly into `MainTabView`.
2. Record tab shows a Start button.
3. Start requests location/camera permissions, starts `ActivityRecorder`, activates `VirtualCoach`, and opens the live camera.
4. `CameraHUDView` displays a full-screen camera preview with a translucent bottom overlay: elapsed time, distance, pace, heart-rate placeholder, a round photo thumbnail stack pinned to the right edge of the activity overlay, capture, map toggle, and Finish.
5. GPS is recorded in activity/photo metadata but is not displayed in the overlay.
6. Finish stops recording and presents Save Activity / Discard.
7. Save writes the activity manifest, track points, photo metadata, and JPEG files locally through `LocalActivityStore`.

## Open Docs By Task

| Task | Open | Contains |
| --- | --- | --- |
| App flow, Swift files, recording, camera, persistence, coach analysis | `docs/ios-architecture.md` | Source layout, module responsibilities, current recording and AI coach shape |
| Firebase Auth, Google project setup, Firebase plist, REST inspection | `docs/firebase.md` | Project IDs, app IDs, callback scheme, auth/provider notes, REST pattern |
| Builds, tests, device install, signing, simulator IDs | `docs/build-test-device.md` | Build-only checks, test commands, device IDs, entitlement constraints |

## Documentation Rules

- Keep this index short enough to scan quickly.
- Add new docs only when a topic is large or frequently reused.
- Do not move volatile implementation details into multiple docs. Link to one source of truth instead.
- For command output, document the command and expected result, not a full transcript.
