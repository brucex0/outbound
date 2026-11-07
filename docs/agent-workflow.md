# Coding Agent Workflow

Use this for tool selection, Codex reasoning presets, task briefs, and handoffs. `AGENTS.md` remains the canonical project policy.

## Tool Ownership

| Work | Starting tool |
| --- | --- |
| Small, well-defined edits, documentation, repetitive changes, focused code discovery | Codex Simple (GPT-6 Luna), or Freebuff |
| Routine implementation with clear acceptance criteria | Codex Routine |
| Ambiguous bugs, architecture, authentication, persistence, cross-platform contracts, consequential review | Codex Deep |
| Unresolved reasoning-heavy investigation | Codex Deep with Extra High override |

- Keep one editing owner per worktree. Do not send every task through every tool.
- Freebuff and OpenCode use the root `AGENTS.md`; `CLAUDE.md` directs Claude-compatible tools to the same rules. OpenCode is optional; this setup adds no provider credentials or paid plan.
- Give a new tool the specific task and a compact handoff. After one failed correction cycle, reassess or escalate instead of repeating blind retries.
- Use Standard service normally. Choose Fast explicitly when the saved waiting time justifies its additional usage.

## Local Codex Presets

The user config keeps `gpt-6.1-sol` and defaults to Medium reasoning with Standard service. The installed CLI uses separate profile files:

- `~/.codex/simple.config.toml`: GPT-6 Luna, Low reasoning, Standard service; use for small, well-defined tasks.
- `~/.codex/routine.config.toml`: GPT-6.1 Sol, Medium reasoning, Standard service.
- `~/.codex/deep.config.toml`: High reasoning, Standard service.
- CLI: `codex --profile simple`, `codex --profile routine`, or `codex --profile deep` from the project directory.
- Start simple tasks with Simple; move to Routine or Deep when scope or uncertainty grows, or after one unsuccessful correction cycle.
- For an unusually demanding task: `codex --profile deep -c 'model_reasoning_effort="xhigh"'`.
- In the desktop app, select the equivalent model, reasoning, and Standard speed in the chat controls. Existing chats may retain their settings; CLI profiles are not desktop preset buttons.

These personal settings are outside Git. Other contributors can create equivalent profile files using:

```toml
model = "gpt-6-luna" # Use "gpt-6.1-sol" for routine/deep.
model_reasoning_effort = "low" # Use "medium" for routine, "high" for deep.
service_tier = "default"
```

Profile syntax: [official Codex configuration](https://learn.chatgpt.com/docs/config-file/config-advanced). Freebuff discovery: [project instructions](https://www.codebuff.com/docs/help/faq).

## Automatic Routing

The routing criteria and worker ownership rules live in `AGENTS.md`. Instructions request model-specific execution; they do not change the desktop model selector.

### Desktop

1. Open this repository in the app and start a new chat so the updated project instructions load.
2. Leave GPT-6.1 Sol selected as coordinator (Medium reasoning and Standard speed are a reasonable starting point).
3. Submit tasks normally. The coordinator requests a Luna/Low worker for simple repository tasks and a Sol/High worker for complex tasks, or executes directly when already using the required model and effort.
4. Inspect the worker activity to confirm the requested model was used. If the runtime disallows delegation or lacks model access, it must report the limitation. A higher-priority runtime restriction can override this project policy.

The coordinator still consumes tokens. Short conversational answers stay in the main chat to avoid worker overhead. Current chats may retain earlier instructions; this is an instruction-driven workflow, not guaranteed product-level automatic routing.

### Terminal launcher

From the repository root:

```sh
./scripts/codex-auto.py "Fix the typo in the setup instructions"
./scripts/codex-auto.py "Investigate why offline sessions fail to sync"
./scripts/codex-auto.py --task-file /path/to/task.txt
```

- Requires Python 3 and the signed-in Codex CLI on `PATH`. Existing account model access and usage limits apply; no separate API key is added.
- A tool-disabled, read-only, ephemeral Luna call classifies the task text outside the repository. It adds a small model call before execution. It does not inspect source or carry this chat's history, so include necessary context in the task.
- The launcher prints the route and opens interactive Codex with an explicit model, reasoning effort, and Standard service. Existing authentication and permission settings remain in force. Repository worktree/commit rules still apply.
- Classification failures, invalid output, or a 60-second timeout fall back to Sol with a diagnostic. An unavailable execution model is reported by Codex; the launcher does not silently substitute another model.
- Routing happens once per launch. Follow-ups remain in that interactive session. If scope grows, the project delegation policy requests a Sol handoff; this is not an automatic change to the primary session's model.
- To inspect a decision without executing the task: `./scripts/codex-auto.py --route-only "your task"` (still makes the classification call).
- To bypass classification explicitly: `./scripts/codex-auto.py --route simple "your task"` or `--route complex`.
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
- Review the diff, run appropriate build/static checks, and inspect affected behavior. State any runtime or visual checks that could not be performed. A successful build does not establish behavioral equivalence.
- Use an additional strong-model review for consequential changes or unresolved concerns. Do not repeat completed verification without a new change, failure, or concern.
- A handoff includes the branch/worktree, outcome, changed files or diff, decisions, verification results, and one unresolved issue. Omit full conversation history and redundant logs.
- Compare accepted changes per elapsed hour and per Codex allowance, including correction rounds. Keep a cheaper tool only where it improves those results.
