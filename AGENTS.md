# Project Instructions

This is a personal project.

Do not run the test suite unless the user explicitly asks. A build-only compile check is acceptable when needed to validate code changes.

When user ask questions or brain storm, always answer in concise bullet points

## Scope And Behavior Preservation

- Keep changes within the user's requested scope. Do not bundle unrelated fixes, cleanup, or behavior changes into the task.
- Refactors and optimizations must preserve existing behavior unless the user explicitly requests a behavior change. Choosing a different implementation does not authorize dropping existing guarantees.
- Before replacing an API or implementation, identify its implicit guarantees and preserve them in the replacement. For image handling, this includes EXIF orientation, mirroring, aspect ratio, image quality, and metadata handling.
- Verify behavioral equivalence with representative inputs across affected consumers, including edge cases and cached/uncached paths where relevant. A passing build alone is insufficient evidence for visual or runtime behavior. Continue to honor the restriction on running tests without an explicit request.
- Before merging, review the diff for unrelated changes and report any behavioral verification that could not be completed. Do not claim unverified behavior is confirmed.
- The Pre-Publish Data Policy permits the documented data resets and migrations described below; it does not authorize unrelated changes to current product behavior.

## Completion And Commits

- For every code change, create and work in a Git worktree under this repository's `worktrees/<task>` directory. Do not use `~/.codex/worktrees`. After basic verification succeeds, squash and merge the worktree branch back into main branch, then remove the worktree and delete its branch.
- After completing repository changes, run a basic verification appropriate to the affected scope without running the test suite unless the user explicitly requested tests.
- If the basic verification succeeds, commit the completed changes before handing the task back to the user.
- Keep unrelated user files, generated artifacts, temporary directories, and agent metadata out of the commit.
- If verification or committing is blocked, report the blocker instead of claiming the task is complete.

## Android Release Status And Compatibility

- Android has **not released**. Keep this policy in force until Bruce explicitly says Android has released; release-build variants, internal testing, or Play setup do not change that status.
- Do not add or retain Android app-version compatibility layers, schema/data migrations, legacy payload readers, or obsolete storage adapters. Use the current model and reset/reseed local databases, preferences, journals, or caches when their shape changes.
- Use a schema-versioned local database name, keep only the current exported Room schema, and document resets. Do not migrate or copy data from older Android app versions.
- Current backend/iOS interoperability, supported Android OS APIs, normal offline fallback, and genuinely optional sensor data remain product requirements, not historical Android app compatibility.

## Pre-Publish Data Policy

Outbound has shipped publicly but with very few users. Do not spend implementation effort preserving backward compatibility for training plans, seed data, local files, caches, or local/backend database rows unless the user explicitly requests it. Prefer the cleanest current model even when adopting it requires destructive migration or data loss. It is acceptable to reset, reseed, or rebuild the local/backend database when schemas, plan IDs, template shape, or seed content changes, as long as the change is documented and the required rebuild command is clear.

## UI Feedback

- Launch dock options/settings use text-only pills; sport-type selectors use icons only with localized accessibility labels. Follow `docs/activity-launch-live-ux.md` when changing these controls.

- Show transient API results, such as save success or failure, with temporary toast-style feedback instead of inserting status text into the page layout. Use inline status only when the result must remain visible or requires an action from the user.

## Error Diagnostics

- When adding or changing error handling, emit a useful diagnostic for each handled failure. Include the operation and safe technical context such as HTTP status, network error code, or decoding path so device logs can identify the failure.
- Do not log credentials, tokens, request or response bodies, personal data, or user-entered content. Keep expected cancellation and other normal control flow out of error logs.
- Do not silently swallow unexpected errors; if an error is intentionally ignored, document why it is expected.

## Analytics Instrumentation

- For every new feature or behavior change, add or update the appropriate analytics instrumentation in the same change. Verify that event names, properties, and privacy handling remain consistent with the product analytics contract.

## iOS Localization

- Whenever adding or changing iOS user-facing strings, make them localizable. Do not introduce hard-coded display text that bypasses the app's localization system.
- Translate localized strings yourself; do not use word-for-word output from Google Translate or similar machine-translation tools. Translations must reflect the product context and be culturally appropriate, natural, and faithful to the intended meaning.

## Documentation Discipline

Treat documents like code:

- Keep documents small, scoped, accurate, and reviewable.
- Update docs in the same change as code when behavior, setup, commands, architecture, or ownership changes.
- Start each task by reading this file and `docs/INDEX.md` only. Then open the specific detail doc needed for the task.
- Do not bulk-load the whole `docs/` directory into context. Use the index as the routing table.
- When adding a new document, add it to `docs/INDEX.md` with when to open it and what it contains.
- Prefer stable headings, concise bullets, and copy-pasteable commands over pasted logs or long transcripts.
- Avoid duplicating facts across docs. Put fast-start routing in the index and detailed facts in the relevant focused doc.

## Fast Start

- Product and doc map: `docs/INDEX.md`
- Before any iOS publish, upload retry, or stalled-delivery recovery, read `docs/app-store-release.md`, including its retained incident lessons. Update that runbook and relevant script guards when a new release incident teaches us something.
- iOS architecture and file map: `docs/ios-architecture.md`
- Firebase and Google Cloud setup: `docs/firebase.md`
- Build, test, signing, and device commands: `docs/build-test-device.md`

## Repo Layout

- `ios/Outbound/Outbound.xcodeproj`: main Xcode project.
- `android/`: native Kotlin/Compose phone and Wear OS apps; see `docs/android-port.md` and `docs/android-build.md`.
- `ios/Outbound/Outbound`: iOS app source. Xcode uses file-system-synchronized groups, so new Swift files under this folder are picked up automatically.
- `ios/Outbound/SupportFiles`: app plist and entitlements.
- `Tests/OutboundSessionAnalysisTests`: Swift Package tests for the on-device session-analysis module.
- `Package.swift`: exposes only the session-analysis subset as `OutboundSessionAnalysis` for lightweight package testing outside the full iOS app target.
- `docs/`: task-routed project documentation. Start with `docs/INDEX.md`.
- `scripts/build-install-bruce-main.sh`: builds and installs the app on Bruce main, with `--build-only` and `--launch` options.
Local `.Codex/`, `.codex/`, and `ios/.codex/` worktree directories are agent metadata. Do not commit them.
