# Coding Agent Workflow

Use this for tool selection, Codex reasoning presets, task briefs, and handoffs. `AGENTS.md` remains the canonical project policy.

## Tool Ownership

| Work | Starting tool |
| --- | --- |
| Coordinator and initial execution for every substantive task | GPT-6.1 Sol at Medium reasoning |
| Explicit or evidence-based escalation | GPT-6.1 Sol at High reasoning, using a compact handoff when ownership changes |

The root coordinator starts at Medium for analysis and planning, then gives the worker an outcome, acceptance criteria, behavior to preserve, and permitted verification. Start every worker with Sol/Medium regardless of initial ambiguity. Never start automatically with GPT-6.0 Sol, Luna, or High reasoning. Use High only when explicitly requested or after concrete complexity or an unsuccessful correction cycle warrants escalation.

- Keep one editing owner per worktree. Do not send every task through every tool.
- OpenCode uses the root `AGENTS.md`; `CLAUDE.md` directs Claude-compatible tools to the same rules. OpenCode is optional; this setup adds no provider credentials or paid plan.
- Give a new tool the specific task and a compact handoff. After one failed correction cycle, reassess or escalate instead of repeating blind retries.
- Use Standard service normally. Choose Fast explicitly when the saved waiting time justifies its additional usage.

## Local Codex Presets

The user config keeps `gpt-6.1-sol` and defaults to Medium reasoning with Standard service. The installed CLI uses separate profile files:

- `~/.codex/simple.config.toml`: GPT-6.1 Sol, Medium reasoning, Standard service; initial execution preset.
- `~/.codex/routine.config.toml`: GPT-6.1 Sol, Medium reasoning, Standard service; equivalent routine/coordinator preset.
- `~/.codex/deep.config.toml`: GPT-6.1 Sol, High reasoning, Standard service; reserve for explicit or evidence-based escalation.
- CLI: `codex --profile simple`, `codex --profile routine`, or (after escalation) `codex --profile deep` from the project directory.
- Use Simple or Routine for initial execution. Move to Deep only when explicitly requested or after concrete complexity or an unsuccessful correction cycle warrants it; pass a compact handoff if ownership changes.
- In the desktop app, select the equivalent model, reasoning, and Standard speed in the chat controls. Existing chats may retain their settings; CLI profiles are not desktop preset buttons.

These personal settings are outside Git. Other contributors can create equivalent profile files using:

```toml
model = "gpt-6.1-sol"
model_reasoning_effort = "medium" # Use "high" only for the deep escalation preset.
service_tier = "default"
```

Profile syntax: [official Codex configuration](https://developers.openai.com/codex/config-reference/).

## Automatic Routing

The routing criteria and worker ownership rules live in `AGENTS.md`. The coordinator and every execution worker start with Sol/Medium. Escalate to Sol/High only when explicitly requested or after evidence of concrete complexity or an unsuccessful correction cycle. Instructions do not change the desktop model selector.

Independent UX QA is normally a merge gate, not an implementation handoff: `plainstride_ux_qa` uses GPT-6.1 Sol at Medium reasoning as documented in `AGENTS.md`. If Bruce explicitly says to merge immediately, proceed after basic build/diff verification without waiting; let review finish separately and report findings and unchecked behavior honestly. Simulator/emulator runtime checks run only when Bruce explicitly requests them. Follow `docs/ux-qa.md` for setup and the evidence-based review contract. The agent's TOML template is tracked at `config/codex/agents/plainstride-ux-qa.toml`; install it in personal Codex configuration with `scripts/install-plainstride-ux-qa.py`. Start a fresh Codex session to discover it. If it is not exposed, a configured Sol/Medium reviewer can be spawned using the same contract; report the actual model and path. If model/delegation is unavailable, report the blocker. Do not replace this independent reviewer with an implementation worker or self-review.

Use a fresh-context reviewer with explicit model/effort, as described in `docs/ux-qa.md`; a full-history fork can inherit the coordinator's settings. Confirm the actual session settings before accepting the review.

### Desktop

1. Open this repository in the app and start a new chat so the updated project instructions load.
2. Start the coordinator with GPT-6.1 Sol at Medium reasoning.
3. For substantive tasks, provide a clear brief and dispatch the first execution to a Sol/Medium worker. Use High only when explicitly requested or after concrete complexity emerges or a correction attempt fails; pass a compact handoff and let the initial worker relinquish worktree ownership first.
4. Inspect the worker activity to confirm the requested model was used. If the runtime disallows delegation or lacks model access, it must report the limitation. A higher-priority runtime restriction can override this project policy.

The coordinator still consumes tokens. Short conversational answers stay in the main chat to avoid worker overhead. Current chats may retain earlier instructions; this is an instruction-driven workflow, not guaranteed product-level automatic routing.

### Terminal launcher

From the repository root:

```sh
./scripts/codex-auto.py "Fix the typo in the setup instructions"
./scripts/codex-auto.py "Investigate why offline sessions fail to sync"
./scripts/codex-auto.py --task-file /path/to/task.txt
```

- Requires Python 3 and the signed-in Codex CLI. The launcher checks `PATH`, then the standard ChatGPT app CLI paths on macOS. Existing account model access and usage limits apply; no separate API key is added.
- Every launch starts GPT-6.1 Sol at Medium reasoning with Standard service. There is no classifier call. Include necessary task context because the new session does not carry this chat's history.
- The launcher prints the route and opens interactive Codex with explicit model, reasoning effort, and service tier. Existing authentication and permission settings remain in force. Repository worktree/commit rules still apply.
- Legacy `--route auto`, `--route simple`, and `--route complex` arguments are retained; all use the same Sol/Medium initial settings. An unavailable execution model is reported by Codex; the launcher does not silently substitute another model.
- Routing happens once per launch. Follow-ups remain in that interactive session. If escalation is explicitly requested or concrete complexity or a failed correction warrants it, prepare a compact handoff before changing ownership. The launcher does not change the primary session's model automatically.
- To inspect a decision without executing the task or making any model call: `./scripts/codex-auto.py --route-only "your task"`.
- Use `codex resume` for an existing CLI conversation. Run the launcher again for a new, independently routed task.

The launcher uses the same model settings as the personal presets but passes them explicitly, so it works without installing profile files.

Official reference: [model-specific subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents#choosing-models-and-reasoning).

## Task Brief

```text
Outcome:
Affected component and likely files:
Behavior to preserve:
Acceptance criteria:
Permitted verification (no test suite unless explicitly requested):
```

Infer routine details from the repository; ask only for missing decisions that affect the result. Keep follow-ups for the same outcome in the same chat. Start a fresh chat when the objective changes.

## Verification and Handoff

- Follow the worktree and scoped-commit rules in `AGENTS.md` for every code change.
- Review the diff, run appropriate build/static checks, and inspect affected behavior. Simulator/emulator runtime checks are opt-in and run only when Bruce explicitly requests them. State any runtime or visual checks that could not be performed. A successful build does not establish behavioral equivalence.
- For iOS code changes, finish by installing the updated app on Bruce main for Bruce's own verification. Use the physical-device flow in `docs/build-test-device.md`; report a concrete blocker if the phone cannot be reached or signing fails.
- Use an additional strong-model review for consequential changes or unresolved concerns. Do not repeat completed verification without a new change, failure, or concern.
- A handoff includes the branch/worktree, outcome, changed files or diff, decisions, verification results, and one unresolved issue. Omit full conversation history and redundant logs.
- Compare accepted changes per elapsed hour and per Codex allowance, including correction rounds. Keep a cheaper tool only where it improves those results.
