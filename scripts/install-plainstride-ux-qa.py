#!/usr/bin/env python3
"""Install the tracked Plainstride UX QA agent into personal Codex config."""

import argparse
import difflib
import pathlib
import sys
import tomllib


ROOT = pathlib.Path(__file__).resolve().parents[1]
SOURCE = ROOT / "config/codex/agents/plainstride-ux-qa.toml"
REQUIRED = {
    "name": "plainstride_ux_qa",
    "model": "gpt-6.1-sol",
    "model_reasoning_effort": "medium",
}


def validate(content: str) -> None:
    try:
        config = tomllib.loads(content)
    except tomllib.TOMLDecodeError as exc:
        raise ValueError(f"invalid TOML: {exc}") from exc
    for key, expected in REQUIRED.items():
        if config.get(key) != expected:
            raise ValueError(f"{key} must be {expected!r}")
    for key in ("description", "developer_instructions"):
        if not isinstance(config.get(key), str) or not config[key].strip():
            raise ValueError(f"{key} must be a non-empty string")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--destination", type=pathlib.Path,
                        help="agent directory (default: ~/.codex/agents)")
    parser.add_argument("--force", action="store_true",
                        help="replace a differing existing agent definition")
    args = parser.parse_args()

    content = SOURCE.read_text(encoding="utf-8")
    try:
        validate(content)
    except ValueError as exc:
        parser.error(str(exc))

    destination = (args.destination or pathlib.Path.home() / ".codex/agents")
    target = destination / SOURCE.name
    if target.exists():
        existing = target.read_text(encoding="utf-8")
        if existing == content:
            print(f"Already current: {target}")
            return 0
        if not args.force:
            diff = "".join(difflib.unified_diff(
                existing.splitlines(keepends=True),
                content.splitlines(keepends=True),
                fromfile=str(target), tofile=str(SOURCE)))
            print(f"Refusing to overwrite differing agent file: {target}\n{diff}",
                  file=sys.stderr)
            print("Review the difference and rerun with --force to replace it.",
                  file=sys.stderr)
            return 2

    destination.mkdir(parents=True, exist_ok=True)
    target.write_text(content, encoding="utf-8")
    print(f"Installed Plainstride UX QA agent: {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
