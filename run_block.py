#!/usr/bin/env python3
"""
run_block.py — run a multi-line shell script from stdin or a file.

Features:
- Reads script from stdin (default) or --file path.
- Runs in /bin/bash (default) or any shell via --shell.
- Optional --strict to enable: set -euo pipefail
- Optional --xtrace to echo commands: set -x
- Optional --cwd to change working directory first.
- Optional --env KEY=VAL (repeatable) to inject env vars.

Usage examples:
  echo "echo hi" | python3 run_block.py
  python3 run_block.py --strict --xtrace <<'CMDS'
  echo "Hello"
  ls -la
  CMDS
  python3 run_block.py --file ./commands.sh --cwd infra/docker --env FOO=bar
"""

import argparse
import os
import sys
import subprocess
from typing import List, Dict

def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(add_help=True)
    p.add_argument("-f", "--file", help="Path to a file containing the script (otherwise read from stdin).")
    p.add_argument("--shell", default="/bin/bash", help="Shell to use (default: /bin/bash).")
    p.add_argument("--strict", action="store_true", help="Enable 'set -euo pipefail'.")
    p.add_argument("--xtrace", action="store_true", help="Enable 'set -x' (echo commands).")
    p.add_argument("--cwd", default=None, help="Change to this directory before running.")
    p.add_argument("--env", action="append", default=[], help="Environment variable KEY=VAL (repeatable).")
    p.add_argument("--dry-run", action="store_true", help="Print the final script and exit.")
    return p.parse_args()

def read_script(args: argparse.Namespace) -> str:
    if args.file:
        with open(args.file, "r", encoding="utf-8") as f:
            return f.read()
    if sys.stdin.isatty():
        print("Waiting for script on stdin... (Ctrl+D to end)", file=sys.stderr)
    return sys.stdin.read()

def build_prelude(args: argparse.Namespace) -> str:
    parts: List[str] = []
    if args.strict:
        parts.append("set -euo pipefail")
    if args.xtrace:
        parts.append("set -x")
    return ("\n".join(parts) + "\n") if parts else ""

def build_env(args: argparse.Namespace) -> Dict[str, str]:
    env = os.environ.copy()
    for kv in args.env:
        if "=" not in kv:
            print(f"[warn] Ignoring malformed --env {kv!r}; expected KEY=VAL", file=sys.stderr)
            continue
        k, v = kv.split("=", 1)
        env[k] = v
    return env

def main() -> int:
    args = parse_args()
    script = read_script(args)
    prelude = build_prelude(args)
    final_script = prelude + script

    if args.cwd:
        os.chdir(args.cwd)

    if args.dry_run:
        print(final_script)
        return 0

    # Stream output directly (no buffering)
    proc = subprocess.Popen(
        [args.shell, "-lc", final_script],
        stdout=sys.stdout,
        stderr=sys.stderr,
        env=build_env(args),
        text=True,
    )
    return proc.wait()

if __name__ == "__main__":
    raise SystemExit(main())
