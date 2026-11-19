# Plainstride UX QA

Every UX change receives an independent review. UX includes visual layout and components, strings/localization, interaction/navigation/forms/keyboard, accessibility, themes/shared components, and visible behavior, including backend-driven states. Review runs in parallel with basic verification, device installation, and merge/completion; `AGENTS.md` defines this workflow and reviewer routing. QA is required but does not gate merge/completion.

## Reviewer setup

- The canonical custom-agent definition is `config/codex/agents/plainstride-ux-qa.toml`. Install it in personal Codex configuration with:

  ```sh
  python3 scripts/install-plainstride-ux-qa.py
  ```

- The installer uses Python 3.11 or newer for the standard-library `tomllib` parser.
- Installation targets `~/.codex/agents/plainstride-ux-qa.toml`, is repeatable, and refuses to replace different content unless explicitly passed `--force`. Use `--destination /tmp/agents` to inspect or verify an isolated installation.
- Start a fresh Codex session so it discovers the personal agent definition. If the named agent is unavailable, the coordinator may spawn a configured GPT-6.1 Sol reviewer at Medium reasoning with this same contract. Record the actual model and reviewer path. If that model is unavailable, report the review limitation and leave review outstanding; do not substitute or claim an independent review. Continue the authorized implementation/merge workflow.
- Spawn with `fork_turns="none"`, `model="gpt-6.1-sol"`, and `reasoning_effort="medium"`. Supply a self-contained handoff and the tracked agent instructions if using the fallback. Verify the actual session model/effort: a full-history fork can inherit the coordinator's settings even when a custom role was selected.

## Handoff and report

Dispatch the reviewer as soon as implementation has a stable exact revision, in parallel with basic build/diff verification, device installation, and merge. Give the reviewer the exact base and review revision, worktree or durable commit reference, and diff fingerprint; affected platforms and screens; relevant contracts; expected behavior; and available runtime, fixture, device, or screenshot evidence. Keep one editing owner. The reviewer does not edit application code or recursively delegate. The reviewer may run targeted UI checks and `python3 scripts/check-design-system.py --base <pre-change-commit>`, but never the full test suite or production data changes.

Prefer committed revisions so review remains reproducible after the implementation worktree is removed. If reviewing a dirty snapshot, include staged and unstaged changes and new untracked source files in its scope and fingerprint, and preserve the snapshot until review finishes. Any later UX edit invalidates the affected part of the report and requires a follow-up review of that exact revision; it does not delay merge. Record the reviewed commit and the resulting merge commit so findings can be traced to shipped code.

The report must state one status: `Pass`, `Issues found`, or `Incomplete`, using this precedence: report `Issues found` when any actionable defect or source-level risk remains, even if evidence is also missing; otherwise report `Incomplete` when applicable evidence is missing; report `Pass` only when there are no unresolved findings and all applicable checks have adequate evidence. Runtime simulator/emulator checks are not part of the default workflow; run them only when Bruce explicitly requests them. Without runtime evidence, mark applicable runtime checks `Not run` and do not claim runtime behavior is verified. Include:

- Exact base/revision and diff fingerprint, affected platforms/screens, and contracts reviewed.
- Evidence inspected and each relevant check's result; mark checks `N/A` with a reason or `Not run` with its blocker.
- Findings with severity, reproducible steps, expected behavior, and actual behavior. Separate observed defects from source-level risks.
- Remaining unperformed checks and their limits.

Review the implementation owner's exact diff. The coordinator does not wait for QA to merge or complete the implementation task: pending review, missing applicable evidence, `Incomplete`, actionable findings, or reviewer unavailability do not create a merge/completion gate or require a waiver. Basic build/diff verification, design-system checks, and applicable device-installation obligations remain in force. Source review and builds alone never prove runtime behavior.

Report the status available at handoff, including `Pending` when no report has arrived (this is a coordinator progress label, not a reviewer verdict), and identify unchecked behavior. Keep an outstanding review running through completion and surface its report when it arrives. Address actionable findings promptly in the current task when practical or a clearly identified follow-up task, and independently re-review affected fixes. Preserve an honest `Issues found` or `Incomplete` status until its criteria are resolved; parallel delivery never turns missing evidence into a QA pass.

## Check matrix

Apply relevant checks to every affected screen and platform; explain each `N/A`.

| Area | Review |
| --- | --- |
| Project contracts | Shared components/tokens, semantic colors, typography, spacing, hierarchy, localization, feature-specific contracts, and the automated design-system guardrail. |
| Layout and themes | Narrow and largest accessibility text size together; long translated strings; light and dark appearance, bright and dark themes, and reactive theme changes; clipping, wrapping, scrolling, and reachable actions. |
| Accessibility | Names/labels, focus order and visibility, touch targets, contrast, and meaning that does not rely on color alone. |
| Keyboard and input | Focus, input, scrolling, dismissal, save/cancel reachability, and preservation of edits where applicable. |
| Interaction and states | Navigation and relevant loading, empty, error, offline, retry, save, and cancel behavior. Use source review for default review; simulator/emulator or representative-runtime checks are opt-in when Bruce explicitly requests them. |

Do not report a runtime check as passed from code inspection or compilation. If Bruce requests runtime checks but evidence is unavailable, state what was not checked and why; use `Incomplete` unless actionable findings require `Issues found`. The coordinator reports these limits while the parallel delivery workflow continues; no QA waiver is required.

## Setup dry run — 2026-11-09

- A fresh Codex CLI session discovered the installed `plainstride_ux_qa` custom role. The reviewer session recorded `gpt-6.1-sol` with `medium` effort.
- The first full-history fork inherited Luna/Low. The corrected fresh-context spawn with explicit model/effort was verified; use that launch pattern above.
- An isolated editing-sheet fixture returned `Issues found`: Save only dismissed, fixed dimensions and disabled keyboard avoidance risked reachability, text/control sizing risked accessibility, and translations were missing. No fixture was added to application code.
- A retrospective source review of iOS Today change `ce2cdc29..aa406891` also returned `Issues found`, flagging shared-primary-button reuse and step-level pace-removal disclosure. Those concerns remain follow-up items; runtime reachability was not established and this setup did not change that implementation.
- Both reports explicitly marked applicable device/layout/keyboard checks unperformed. This verified reviewer discovery, routing, and source-review reporting, not runtime UX correctness. No app builds, test suite, device changes, production access, or CI changes were performed.
