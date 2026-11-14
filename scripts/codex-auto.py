#!/usr/bin/env python3
"""Open an Outbound task in GPT-6.1 Sol with Medium reasoning."""
import argparse
import os
from pathlib import Path
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MODEL = "gpt-6.1-sol"
DEFAULT_EFFORT = "medium"
ROUTES = ("auto", "simple", "complex")
APP_CLI_CANDIDATES = (
    Path("/Applications/ChatGPT.app/Contents/Resources/codex-cli/codex-path/codex"),
    Path("/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"),
)


def find_codex():
    executable = shutil.which("codex")
    if executable:
        return executable
    for candidate in APP_CLI_CANDIDATES:
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return str(candidate)
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("task", nargs="*", help="Task to start")
    parser.add_argument("--task-file", type=Path, help="Read a longer task from a UTF-8 file")
    parser.add_argument("--route", choices=ROUTES, default="auto",
                        help="Legacy route names; all start GPT-6.1 Sol with Medium reasoning")
    parser.add_argument("--route-only", action="store_true",
                        help="Print routing decision without starting an execution session")
    args = parser.parse_args()
    if args.task_file and args.task:
        parser.error("use a task argument or --task-file, not both")
    task = args.task_file.read_text() if args.task_file else " ".join(args.task)
    if not task:
        task = input("Task: ").strip()
    if not task.strip():
        parser.error("task must not be empty")
    codex = find_codex()
    if not codex:
        parser.error("Codex CLI is not on PATH; install it or add the app's CLI to PATH")
    route = args.route
    model, effort = DEFAULT_MODEL, DEFAULT_EFFORT
    print(f"Route: {route} → {model} / {effort} / Standard", flush=True)
    if args.route_only:
        return
    if not sys.stdin.isatty():
        parser.error("execution needs an interactive terminal; use --task-file for long prompts")
    prompt = (
        f"The launcher selected {model} with {effort} reasoning for this task. "
        "You are the execution owner; do not delegate merely to repeat this initial routing. "
        "Follow AGENTS.md. Use its escalation policy when concrete evidence warrants High reasoning.\n\n"
        + task
    )
    # Preserve the user's existing authentication, permission, and approval settings.
    os.execv(codex, [codex, "--cd", str(ROOT), "--model", model,
                    "-c", f'model_reasoning_effort="{effort}"',
                    "-c", 'service_tier="default"', prompt])


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
    except OSError as error:
        print(f"Launcher failed ({type(error).__name__}, errno={error.errno}).", file=sys.stderr)
        sys.exit(1)
