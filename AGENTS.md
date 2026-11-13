# Project Instructions

This is a personal project.

Do not run the test suite unless the user explicitly asks. A build-only compile check is acceptable when needed to validate code changes.

When user ask questions or brain storm, always answer in concise bullet points

## Efficient Execution

- Use one editing owner per worktree. Keep each task focused on one coherent outcome.
- Search with `rg` first, batch independent reads, and keep command output bounded. Load only the relevant docs and source sections; summarize long diagnostics instead of repeatedly loading full logs.
- For straightforward changes, implement directly with a brief plan. For ambiguous or consequential changes, establish acceptance criteria and behavior to preserve before editing.
- After one unsuccessful correction cycle, reassess the cause. When handing work to another tool, provide the diff, failure, attempted fix, and remaining uncertainty instead of replaying the whole conversation.
- Always review the scoped diff and perform the required verification. Reserve an additional model review for consequential changes or unresolved concerns.
- Read `docs/agent-workflow.md` when choosing a tool or reasoning preset, preparing a handoff, or defining a task brief.

## Automatic Model Routing

- For substantive repository tasks, the root coordinator performs high-effort analysis and planning, then writes a clear worker brief with the outcome, acceptance criteria, affected scope, behavior to preserve, and permitted verification. The coordinator owns planning and review; one worker owns execution in the task worktree.
- Start every worker with GPT-6 Luna (`gpt-6-luna`) at Low reasoning, even when the task initially appears ambiguous or consequential. Do not route a task directly to a Sol worker based only on initial classification. Use the configured Luna worker for initial execution.
- Escalate only when the worker uncovers concrete complexity that warrants it or has an unsuccessful correction cycle. The Luna worker then stops editing and gives the coordinator a compact handoff describing the evidence, current diff, attempted correction, verification, and remaining uncertainty. The coordinator may assign a GPT-6.1 Sol (`gpt-6.1-sol`) worker at High reasoning to continue in the same worktree after Luna relinquishes ownership.
- Keep brief conversational answers in the main chat; do not spawn workers just to acknowledge or classify a request.
- Higher-priority runtime restrictions and explicit user instructions take precedence. If model-specific delegation is unavailable, state that limitation; do not claim the model switched.
- Keep one editing owner per worktree. The coordinator must not edit while a worker owns execution. Workers must not recursively delegate for model routing.
- The desktop selector remains the coordinator's model, and coordination consumes tokens. See `docs/agent-workflow.md` for desktop setup and the automatic CLI launcher.

## Mandatory UX QA

- Every UX change requires an independent `plainstride_ux_qa` review after implementation, normally before merge or completion; Bruce's explicit immediate-merge instruction is the exception below. UX scope includes visual layout and components, user-facing strings and localization, interaction/navigation/forms/keyboard, accessibility, themes/shared components, and user-visible behavior including backend-driven states.
- The reviewer must use the tracked contract in `docs/ux-qa.md`, inspect the exact proposed revision and diff, and return its required `Pass`, `Issues found`, or `Incomplete` report. Wait for that report; fix findings and re-review affected diffs. Unresolved findings or missing applicable runtime evidence block a QA pass and merge/completion unless Bruce explicitly accepts a documented waiver.
- The dedicated reviewer uses GPT-6.1 Sol at Medium reasoning. This is a deliberate exception only for independent UX QA; implementation workers still follow the routing rules above. If the named agent is not exposed, the coordinator may use a configured Sol/Medium reviewer with the same contract and report that fallback. If the model or delegation is unavailable, report the blocker; do not silently substitute another model or claim independent review.
- Spawn the reviewer with fresh context (`fork_turns="none"`), explicit `model="gpt-6.1-sol"` and `reasoning_effort="medium"`, and a self-contained handoff. Full-history forks can inherit the coordinator's model/effort; verify the actual reviewer settings instead of assuming the agent name guarantees them.
- The reviewer does not edit application code, delegate recursively, change production data, or run the full test suite. Targeted UI checks and the design-system checker are permitted. Simulator/emulator runtime checks are opt-in and run only when Bruce explicitly requests them; source review or a build alone cannot establish runtime behavior.
- If Bruce explicitly says to merge immediately, complete the basic build/diff verification and merge without waiting for UX review. The review may finish separately; report any unresolved findings and unchecked behavior, and never claim `Pass` without the required evidence. Otherwise, retain the normal QA gate, without requiring default simulator/emulator checks.
- See `docs/ux-qa.md` for installation, review evidence, and the check matrix.

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
- After finishing iOS code changes, build and install the updated app on Bruce main so Bruce can verify it on his phone. Launch it when practical. If the phone is unavailable, report the specific connection or signing blocker and keep the install as an outstanding step; a compile-only build is not a substitute for installation.
- If the basic verification succeeds, commit the completed changes before handing the task back to the user.
- Keep unrelated user files, generated artifacts, temporary directories, and agent metadata out of the commit.
- Split changes to `backend/`, `android/`, and `ios/` into separate focused commits. Prefix their titles with `[BE]`, `[Droid]`, or `[iOS]` respectively; never combine these scopes in one commit.
- If verification or committing is blocked, report the blocker instead of claiming the task is complete.

## Android Release Status And Compatibility

- Android has **not released**. Keep this policy in force until Bruce explicitly says Android has released; release-build variants, internal testing, or Play setup do not change that status.
- Do not add or retain Android app-version compatibility layers, schema/data migrations, legacy payload readers, or obsolete storage adapters. Use the current model and reset/reseed local databases, preferences, journals, or caches when their shape changes.
- Use a schema-versioned local database name, keep only the current exported Room schema, and document resets. Do not migrate or copy data from older Android app versions.
- Current backend/iOS interoperability, supported Android OS APIs, normal offline fallback, and genuinely optional sensor data remain product requirements, not historical Android app compatibility.

## Pre-Publish Data Policy

Outbound has shipped publicly but with very few users. Do not spend implementation effort preserving backward compatibility for training plans, seed data, local files, caches, or local/backend database rows unless the user explicitly requests it. Prefer the cleanest current model even when adopting it requires destructive migration or data loss. It is acceptable to reset, reseed, or rebuild the local/backend database when schemas, plan IDs, template shape, or seed content changes, as long as the change is documented and the required rebuild command is clear.

## Design System

- Before any iOS or Android UI change, read `docs/design-system.md` and its review checklist. Follow the linked theme and feature contracts.
- Run `python3 scripts/check-design-system.py --base <base-commit>` before merging UI changes. Review every exception and report visual checks that were not performed.

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
Local `.claude/`, `.Codex/`, `.codex/`, and `ios/.codex/` worktree directories are agent metadata. Do not commit them.
