#!/usr/bin/env python3
"""RouteNote supervisor agent — a dev-machine QA loop (safe build).

This is a DEVELOPMENT-TIME tool, not part of the Flutter app (which stays
zero-backend and offline-first). It watches a *sanitized* diagnostics file
(JSON array or JSON-lines), asks Gemini to diagnose issues against
RouteNote's constraints (zero-backend, Hive CE, Riverpod, i18n) and hands
the resulting fix instructions to a developer CLI (default: Claude Code)
without ever going through a shell.

Security properties (AGENT_SKILLS.md §2.3 applies here too):
  * No credentials in this file. GEMINI_API_KEY must come from the
    environment (put it in tool/.env, which is git-ignored).
  * The model's output never becomes shell text: it is passed to a known
    binary as a SINGLE argv element (subprocess ..., shell=False).
  * Input is redacted (API keys, tokens, emails) and truncated before it
    is sent. Raw stack traces should never be in the input in the first
    place — AppObserverService only writes sanitized events to Hive.
  * Nothing is deleted: reports go to tool/reports/, the input file is
    never modified.

Usage:
  export GEMINI_API_KEY=...                     # or use tool/.env (ignored)
  python tool/supervisor_agent.py --input routenote_diagnostics.json --check
  python tool/supervisor_agent.py --input routenote_diagnostics.json --dry-run
  python tool/supervisor_agent.py --input routenote_diagnostics.json --yes
  python tool/supervisor_agent.py --watch --interval 15 --input routenote_diagnostics.json

  # Telegram control bridge (dev-machine remote control):
  python tool/supervisor_agent.py --telegram-check   # validate token/chat id
  python tool/supervisor_agent.py --telegram         # run the polling loop

Environment (put secrets in tool/.env — it is git-ignored):
  GEMINI_API_KEY           required model API key
  SUPERVISOR_GEMINI_MODEL  model id (default gemini-1.5-pro)
  DEV_AGENT_CMD            dev agent binary (default claude)
  DEV_AGENT_EXTRA_ARGS     optional JSON list of extra argv for the dev
                           agent (never contains model-generated text)
  TELEGRAM_BOT_TOKEN       BotFather token for the control bot
  TELEGRAM_CHAT_ID         the ONLY chat/user id the bot will obey
"""

from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple

DEFAULT_MODEL = "gemini-1.5-pro"
DEFAULT_INPUT = "routenote_diagnostics.json"
DEFAULT_MAX_CHARS = 60_000
MAX_LINE_CHARS = 500

# Telegram control bridge.
TELEGRAM_API_BASE = "https://api.telegram.org"
TELEGRAM_LONG_POLL_SECONDS = 25
TELEGRAM_MAX_MESSAGE_CHARS = 4_000  # Telegram hard limit is 4096
GIT_TIMEOUT_SECONDS = 30
DEVICES_TIMEOUT_SECONDS = 60
TEST_TIMEOUT_SECONDS = 1_800
DEV_AGENT_TIMEOUT_SECONDS = 1_800

SYSTEM_PROMPT = (
    "You are the Autonomous Chief Quality & Architecture Agent for 'RouteNote', "
    "a Flutter app. RouteNote's hard constraints are: zero-backend / "
    "offline-first (local Hive CE persistence only), Riverpod state "
    "management, full EN/AR localization, silent Google auth, sign-out keeps "
    "local data, and a privacy rule that allows only anonymous aggregate "
    "diagnostics off-device. "
    "You are given SANITIZED app diagnostics. Tasks: "
    "1) Analyze the signs of crashes/performance/sync/parsing problems. "
    "2) Determine the most probable root cause against RouteNote's "
    "constraints — never invent data that is not in the excerpt. "
    "3) Produce a precise, step-by-step fix instruction prompt for a "
    "developer agent (Claude Code / Cursor) that names the exact file(s), "
    "the change(s), and the verification commands to run (flutter analyze, "
    "flutter test). "
    "Rules: never echo credentials or raw stack traces; keep the instruction "
    "actionable and bounded; if the excerpt is ambiguous, say so and ask for "
    "a fuller sanitized export instead of guessing."
)

# Redaction patterns (defense-in-depth on top of the app's sanitized events).
_REDACTORS: List[Tuple[re.Pattern[str], str]] = [
    (re.compile(r"AIza[0-9A-Za-z\-_]{20,}"), "[redacted:google_api_key]"),
    (re.compile(r"[Bb]earer\s+[A-Za-z0-9\-._~+/]+=*"), "[redacted:bearer]"),
    (
        re.compile(
            r"(?:x-goog-api-key|api[_-]?key|token|authorization)\s*[:=]\s*[^\s,;]+",
            re.IGNORECASE,
        ),
        "[redacted:key]",
    ),
    (re.compile(r"[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}"), "[redacted:email]"),
    (re.compile(r"[A-Za-z0-9+/]{32,}={0,2}"), "[redacted:token]"),
]


def redact(text: str) -> str:
    """Redact credential-like patterns. Best-effort, defense-in-depth."""
    for pattern, replacement in _REDACTORS:
        text = pattern.sub(replacement, text)
    return text


# Terminal color/style escape sequences (the dev-agent CLI emits these).
_ANSI_ESCAPE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")


def strip_ansi(text: str) -> str:
    """Remove ANSI escape sequences so chat replies are clean text."""
    return _ANSI_ESCAPE.sub("", text)


def make_console_utf8_safe() -> None:
    """Best-effort: never crash printing Unicode to a legacy (cp1252) console.

    The tool prints Gemini-generated text, which may contain arbitrary
    Unicode. On Windows consoles that cannot render it, a hard failure would
    abort the loop; replacing the unrenderable characters keeps the pipeline
    alive.
    """
    for stream in (sys.stdout, sys.stderr):
        try:
            kwargs = {"errors": "replace"}
            if stream is sys.stdout:
                # A bot runs for a long time; line buffering makes its banner
                # and event logs visible immediately instead of at exit.
                kwargs["line_buffering"] = True
            stream.reconfigure(**kwargs)
        except Exception:  # noqa: BLE001 - best effort, never fatal
            pass


def load_env_files() -> None:
    """Load KEY=VALUE pairs from tool/.env, then the repo-root .env.

    Existing environment variables always win, so an explicit `export` still
    overrides the file. Kept stdlib-only on purpose (no python-dotenv
    dependency). The files are git-ignored; secrets never live in this script.
    """
    here = Path(__file__).resolve().parent
    for path in (here / ".env", here.parent / ".env"):
        if not path.is_file():
            continue
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, _, value = line.partition("=")
            key = key.strip()
            value = value.strip().strip('"').strip("'")
            if key and key not in os.environ:
                os.environ[key] = value


def load_lines(path: Path) -> List[str]:
    """Read a diagnostics file as sanitizable text lines.

    Accepts either a single JSON array or one JSON object/primitive per
    line (JSON-lines). Returns one string per record.
    """
    raw = path.read_text(encoding="utf-8", errors="replace")
    stripped = raw.strip()
    if not stripped:
        return []

    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        parsed = None

    if isinstance(parsed, list):
        lines: List[str] = []
        for item in parsed:
            if isinstance(item, str):
                lines.append(item)
            else:
                lines.append(json.dumps(item, ensure_ascii=False, separators=(",", ":")))
        return lines

    lines = []
    for line in raw.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            lines.append(line)
            continue
        if isinstance(item, list):
            for sub in item:
                if isinstance(sub, str):
                    lines.append(sub)
                else:
                    lines.append(json.dumps(sub, ensure_ascii=False, separators=(",", ":")))
        elif isinstance(item, str):
            lines.append(item)
        else:
            lines.append(json.dumps(item, ensure_ascii=False, separators=(",", ":")))
    return lines


def sanitize_lines(lines: Iterable[str]) -> List[str]:
    """Truncate line width and redact credentials."""
    return [redact(line)[:MAX_LINE_CHARS] for line in lines]


def compose_excerpt(lines: Sequence[str], max_chars: int) -> Tuple[str, int]:
    """Keep the tail of the log within max_chars. Returns (text, kept_bytes)."""
    total = 0
    kept: List[str] = []
    for line in reversed(lines):
        cost = len(line) + 1  # +1 for the newline
        if total + cost > max_chars and kept:
            break
        kept.append(line)
        total += cost
    kept.reverse()
    return "\n".join(kept), total


def check_runtime(args: argparse.Namespace) -> int:
    """Validate environment + input without any network call."""
    problems: List[str] = []
    if not os.environ.get("GEMINI_API_KEY"):
        problems.append("GEMINI_API_KEY is not set (put it in tool/.env or export it)")
    input_path = Path(args.input)
    if not input_path.exists():
        problems.append(f"input file not found: {input_path}")
    else:
        try:
            lines = sanitize_lines(load_lines(input_path))
            if not lines:
                problems.append("input file contains no diagnostics records")
        except Exception as exc:  # noqa: BLE001 - report any parse problem
            problems.append(f"could not parse input file: {exc}")
    try:
        import google.generativeai as _genai  # noqa: F401
    except ImportError:
        problems.append(
            "google.generativeai is not installed (pip install google-generativeai)"
        )
    for problem in problems:
        print(f"  ! {problem}", file=sys.stderr)
    if problems:
        print("check failed.", file=sys.stderr)
        return 1
    print("check ok: env key set, input parses, gemini SDK importable.")
    return 0


def call_gemini(excerpt: str, model_id: str) -> str:
    """Send the excerpt to Gemini and return the diagnostic text."""
    key = os.environ.get("GEMINI_API_KEY")
    if not key:
        raise RuntimeError(
            "GEMINI_API_KEY is not set — put it in tool/.env or export it first"
        )
    import google.generativeai as genai

    genai.configure(api_key=key)
    model = genai.GenerativeModel(model_name=model_id, system_instruction=SYSTEM_PROMPT)
    response = model.generate_content(
        f"SANITIZED ROUTENOTE DIAGNOSTICS\n\n{excerpt}"
    )
    return response.text


def dev_agent_argv(instructions: str) -> List[str]:
    """Build the dev-agent argv. Model text is one element, never a shell."""
    cmd = os.environ.get("DEV_AGENT_CMD", "claude")
    extra_env = os.environ.get("DEV_AGENT_EXTRA_ARGS", "[]")
    try:
        extra = json.loads(extra_env)
    except json.JSONDecodeError:
        extra = []
    if not isinstance(extra, list):
        extra = []
    return [cmd, *[str(arg) for arg in extra], instructions]


def run_dev_agent(
    instructions: str, timeout: Optional[float] = None
) -> subprocess.CompletedProcess[str]:
    argv = dev_agent_argv(instructions)
    print(f"🤖 running dev agent: {argv[0]} (prompt passed as one argv element)")
    return subprocess.run(
        argv,
        shell=False,
        check=False,
        text=True,
        capture_output=True,
        timeout=timeout,
        cwd=str(repo_root()),
        encoding="utf-8",
        errors="replace",
    )


def write_report(reports_dir: Path, excerpt: str, instructions: str, input_name: str) -> Path:
    reports_dir.mkdir(parents=True, exist_ok=True)
    stamp = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    report = reports_dir / f"supervisor_{stamp}.md"
    report.write_text(
        (
            f"# RouteNote supervisor report ({stamp})\n\n"
            f"- Input: `{input_name}`\n"
            f"- Excerpt bytes: {len(excerpt)}\n\n"
            f"## Sentinel diagnostics (sanitized)\n\n"
            f"```\n{excerpt}\n```\n\n"
            f"## Fix instructions for the dev agent\n\n{instructions}\n"
        ),
        encoding="utf-8",
    )
    return report


def process_once(path: Path, args: argparse.Namespace) -> int:
    lines = sanitize_lines(load_lines(path))
    if not lines:
        print("no diagnostics records found — nothing to do.")
        return 0

    excerpt, kept = compose_excerpt(lines, args.max_chars)
    print(
        f"⚠️ {len(lines)} diagnostic record(s) loaded; "
        f"sending {kept} characters to Gemini ({args.model})."
    )

    if not args.dry_run and not args.yes and not args.consented:
        if not sys.stdin.isatty():
            print("input is not a TTY and --yes was not given — aborting.", file=sys.stderr)
            return 2
        answer = input("Proceed? [y/N] ").strip().lower()
        if answer not in ("y", "yes"):
            print("aborted.")
            return 0
        # Grant for the rest of this run (watch mode keeps appending batches).
        args.consented = True

    if args.dry_run:
        print("\n--- dry run: composed prompt (redacted excerpt) ---\n")
        print(excerpt)
        print("\n--- end dry run ---")
        return 0

    instructions = call_gemini(excerpt, args.model)
    report = write_report(
        Path(args.reports_dir), excerpt, instructions, path.name
    )
    print(f"💡 diagnostic written to {report}")

    if args.no_run:
        print("(--no-run: not invoking the dev agent)")
        return 0

    result = run_dev_agent(instructions)
    print(f"dev agent exit code: {result.returncode}")
    if result.stdout:
        print(result.stdout)
    if result.stderr:
        print(result.stderr, file=sys.stderr)
    return 0


def watch_loop(path: Path, args: argparse.Namespace) -> int:
    """Poll for newly appended diagnostic records (like the original sketch)."""
    seen = 0
    print(f"👀 watching {path} every {args.interval}s (Ctrl+C to stop)...")
    while True:
        try:
            lines = sanitize_lines(load_lines(path))
            count = len(lines)
            if count > seen:
                if seen > 0:
                    print(f"⚠️ {count - seen} new record(s) detected.")
                seen = count
                process_once(path, args)
        except FileNotFoundError:
            pass
        except Exception as exc:  # noqa: BLE001 - keep the watcher alive
            print(f"! watch error: {exc}", file=sys.stderr)
        time.sleep(args.interval)


# --- Telegram control bridge -------------------------------------------------
#
# A tiny, dependency-free long-polling bridge so the dev machine can be driven
# from a Telegram chat. Security properties mirror the rest of this tool:
#   * the token lives only in tool/.env (git-ignored), never in the source;
#   * ONLY TELEGRAM_CHAT_ID is obeyed — every other sender is ignored;
#   * commands are fixed argv lists run with shell=False (no shell injection);
#   * text sent back is redacted first (defense-in-depth).
# `/prompt` reuses the same dev-agent hand-off as the automated loop: the
# instruction is passed as a SINGLE argv element, never parsed by a shell.

BOT_COMMANDS: List[Dict[str, str]] = [
    {"command": "status", "description": "system, Git branch and connected device"},
    {"command": "test", "description": "run flutter test and report the summary"},
    {"command": "prompt", "description": "forward an instruction to the dev agent"},
    {"command": "help", "description": "show the control menu"},
]

HELP_TEXT = (
    "🤖 RouteNote supervisor bot\n\n"
    "Available commands:\n"
    "/status — system status, Git branch and connected device (REA NX9)\n"
    "/test — run `flutter test` and report the summary\n"
    "/prompt <instruction> — forward the instruction to the dev agent\n"
    "/help — show this menu\n"
    "/start — same as /help"
)


def repo_root() -> Path:
    """The Flutter project root (this file lives in <root>/tool/)."""
    return Path(__file__).resolve().parent.parent


def chunk_text(text: str, limit: int = TELEGRAM_MAX_MESSAGE_CHARS) -> List[str]:
    """Split long text into Telegram-sized chunks, preferring line breaks."""
    if len(text) <= limit:
        return [text]
    chunks: List[str] = []
    remaining = text
    while len(remaining) > limit:
        cut = remaining.rfind("\n", 0, limit)
        if cut <= 0:
            cut = limit
        chunks.append(remaining[:cut])
        remaining = remaining[cut:].lstrip("\n")
    if remaining:
        chunks.append(remaining)
    return chunks


def run_command(args: Sequence[str], timeout: int) -> Tuple[int, str, str]:
    """Run a FIXED command (no shell) from the repo root; capture output.

    Returns (returncode, stdout, stderr). Executables are resolved through
    PATH; on Windows a `.bat`/`.cmd` (e.g. flutter.bat) is launched via the
    command interpreter because CreateProcess cannot run batch files directly.
    `args` are never user-controlled text.
    """
    if not args:
        return 2, "", "no command given"
    exe = shutil.which(args[0]) or args[0]
    argv = [exe, *args[1:]]
    if os.name == "nt" and exe.lower().endswith((".bat", ".cmd")):
        argv = ["cmd", "/c", *argv]
    try:
        result = subprocess.run(
            argv,
            shell=False,
            check=False,
            text=True,
            capture_output=True,
            timeout=timeout,
            cwd=str(repo_root()),
            encoding="utf-8",
            errors="replace",
        )
    except FileNotFoundError:
        return 127, "", f"command not found: {args[0]}"
    except subprocess.TimeoutExpired:
        return 124, "", f"timed out after {timeout}s: {' '.join(args)}"
    return result.returncode, result.stdout or "", result.stderr or ""


class TelegramClient:
    """Minimal Telegram Bot API client over urllib (no extra dependency)."""

    def __init__(self, token: str) -> None:
        self._root = f"{TELEGRAM_API_BASE}/bot{token}"

    def _call(
        self, method: str, params: Optional[dict] = None, timeout: float = 30.0
    ) -> object:
        request = urllib.request.Request(
            f"{self._root}/{method}",
            data=json.dumps(params or {}).encode("utf-8"),
            headers={"Content-Type": "application/json"},
        )
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                payload = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            try:
                detail = json.loads(body).get("description", body)
            except json.JSONDecodeError:
                detail = body
            raise RuntimeError(f"telegram {method} HTTP {exc.code}: {detail}") from exc
        if not payload.get("ok"):
            raise RuntimeError(
                f"telegram {method} failed: {payload.get('description')}"
            )
        return payload.get("result")

    def get_me(self) -> dict:
        return self._call("getMe", timeout=15.0)  # type: ignore[return-value]

    def get_updates(self, offset: Optional[int], timeout: int) -> List[dict]:
        return self._call(  # type: ignore[return-value]
            "getUpdates",
            {
                "offset": offset,
                "timeout": timeout,
                "allowed_updates": ["message", "edited_message"],
            },
            timeout=timeout + 10,
        )

    def set_my_commands(self, commands: List[Dict[str, str]]) -> None:
        self._call("setMyCommands", {"commands": commands})

    def send_message(self, chat_id: str, text: str) -> None:
        for chunk in chunk_text(text):
            self._call(
                "sendMessage",
                {
                    "chat_id": chat_id,
                    "text": chunk,
                    "disable_web_page_preview": True,
                },
            )


def _git_branch() -> Tuple[str, str]:
    """Return (branch, working-tree summary) for the repo."""
    rc, out, err = run_command(["git", "rev-parse", "--abbrev-ref", "HEAD"], GIT_TIMEOUT_SECONDS)
    branch = out.strip() if rc == 0 else f"(unknown: {(err or out).strip()[:120]})"
    rc, out, _ = run_command(["git", "status", "--short"], GIT_TIMEOUT_SECONDS)
    if rc != 0:
        tree = "(unknown)"
    elif not out.strip():
        tree = "clean"
    else:
        tree = f"{len(out.splitlines())} changed file(s)"
    return branch, tree


def status_report() -> str:
    """System status, Git branch and connected device (REA NX9)."""
    stamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC")
    branch, tree = _git_branch()

    lines = [
        "🖥️ RouteNote supervisor status",
        f"- Time: {stamp}",
        f"- Git branch: {branch}",
        f"- Working tree: {tree}",
    ]

    rc, out, err = run_command(["flutter", "devices"], DEVICES_TIMEOUT_SECONDS)
    if rc == 0:
        rea_connected = "REA NX9" in out
        lines.append(f"- REA NX9 connected: {'yes ✅' if rea_connected else 'no ❌'}")
        device_lines = [l.rstrip() for l in out.splitlines() if "•" in l]
        if device_lines:
            lines.append("- Flutter devices:")
            lines.extend(f"    {l.strip()}" for l in device_lines[:8])
    else:
        lines.append(f"- flutter devices failed: {(err or out).strip()[:200]}")

    return redact(strip_ansi("\n".join(lines)))


def test_report() -> str:
    """Run `flutter test` and return a concise summary."""
    rc, out, err = run_command(["flutter", "test"], TEST_TIMEOUT_SECONDS)
    combined = strip_ansi((out + ("\n" + err if err else "")).rstrip())
    verdict = "✅ passed" if rc == 0 else f"❌ failed (exit {rc})"
    tail = [l for l in combined.splitlines() if l.strip()][-15:]
    body = "\n".join(tail) if tail else "(no output)"
    return redact(f"🧪 flutter test: {verdict}\n\n{body}")


def prompt_report(instruction: str) -> str:
    """Forward `/prompt <instruction>` to the dev agent (single argv element)."""
    if not instruction.strip():
        return "Usage: /prompt <instruction>"
    try:
        result = run_dev_agent(instruction, timeout=DEV_AGENT_TIMEOUT_SECONDS)
    except FileNotFoundError:
        return (
            "❌ dev agent not found. Set DEV_AGENT_CMD (default `claude`) in "
            "tool/.env to a binary on PATH."
        )
    except subprocess.TimeoutExpired:
        return f"⌛ dev agent timed out after {DEV_AGENT_TIMEOUT_SECONDS}s."
    body = strip_ansi(
        (result.stdout or "") + (("\n" + result.stderr) if result.stderr else "")
    ).strip() or "(no output)"
    return redact(f"🤖 dev agent exit code: {result.returncode}\n\n{body[-3_000:]}")


def handle_update(client: TelegramClient, update: dict, allowed_chat_id: str) -> None:
    """Dispatch one Telegram update — only for the authorized user id."""
    message = update.get("message") or update.get("edited_message")
    if not isinstance(message, dict):
        return

    sender = message.get("from") or {}
    chat = message.get("chat") or {}
    user_id = str(sender.get("id", ""))
    chat_id = str(chat.get("id", ""))

    if user_id != allowed_chat_id:
        print(f"! ignored message from unauthorized user {user_id!r}", file=sys.stderr)
        return

    text = (message.get("text") or "").strip()
    command = text.split(" ", 1)[0].split("@", 1)[0].lower()
    argument = text[len(text.split(" ", 1)[0]):].strip()

    if command in ("/start", "/help", ""):
        client.send_message(chat_id, HELP_TEXT)
        return

    if command == "/status":
        client.send_message(chat_id, status_report())
        return

    if command == "/test":
        client.send_message(chat_id, "🧪 Running `flutter test`… (this can take a few minutes)")
        client.send_message(chat_id, test_report())
        return

    if command == "/prompt":
        client.send_message(chat_id, prompt_report(argument))
        return

    client.send_message(chat_id, f"Unknown command: {command}\n\n{HELP_TEXT}")


def telegram_check() -> int:
    """Validate the Telegram token + chat id without starting the loop."""
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    allowed = os.environ.get("TELEGRAM_CHAT_ID")
    problems: List[str] = []
    if not token:
        problems.append("TELEGRAM_BOT_TOKEN is not set (put it in tool/.env)")
    if not allowed:
        problems.append("TELEGRAM_CHAT_ID is not set (put it in tool/.env)")
    if problems:
        for problem in problems:
            print(f"  ! {problem}", file=sys.stderr)
        return 1
    try:
        me = TelegramClient(token).get_me()
    except Exception as exc:  # noqa: BLE001 - report any network/auth problem
        print(f"  ! telegram check failed: {exc}", file=sys.stderr)
        return 1
    print(
        f"telegram check ok: @{me.get('username')} (id {me.get('id')}), "
        f"authorized chat id {allowed}"
    )
    return 0


def telegram_bot_loop() -> int:
    """Run the Telegram control-bot long-polling loop until Ctrl+C."""
    token = os.environ.get("TELEGRAM_BOT_TOKEN")
    allowed_chat_id = os.environ.get("TELEGRAM_CHAT_ID")
    problems: List[str] = []
    if not token:
        problems.append("TELEGRAM_BOT_TOKEN is not set (put it in tool/.env)")
    if not allowed_chat_id:
        problems.append("TELEGRAM_CHAT_ID is not set (put it in tool/.env)")
    if problems:
        for problem in problems:
            print(f"  ! {problem}", file=sys.stderr)
        return 1

    client = TelegramClient(token)
    try:
        me = client.get_me()
    except Exception as exc:  # noqa: BLE001 - fail fast with a clear message
        print(f"! could not reach Telegram: {exc}", file=sys.stderr)
        return 1

    print(
        f"✅ @{me.get('username')} online — authorized chat id {allowed_chat_id} "
        f"(Ctrl+C to stop)"
    )
    try:
        client.set_my_commands(BOT_COMMANDS)
    except Exception as exc:  # noqa: BLE001 - non-fatal convenience only
        print(f"! setMyCommands failed: {exc}", file=sys.stderr)

    offset: Optional[int] = None
    try:
        while True:
            try:
                updates = client.get_updates(offset, TELEGRAM_LONG_POLL_SECONDS)
            except Exception as exc:  # noqa: BLE001 - keep polling
                print(f"! poll error: {exc}", file=sys.stderr)
                time.sleep(3)
                continue
            for update in updates:
                offset = int(update.get("update_id", 0)) + 1
                try:
                    handle_update(client, update, allowed_chat_id)
                except Exception as exc:  # noqa: BLE001 - one bad update never kills the bot
                    print(f"! handler error: {exc}", file=sys.stderr)
    except KeyboardInterrupt:
        print("\n👋 bot stopped.")
        return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--input", default=DEFAULT_INPUT, help="diagnostics input file")
    parser.add_argument(
        "--model",
        default=os.environ.get("SUPERVISOR_GEMINI_MODEL", DEFAULT_MODEL),
        help="Gemini model id",
    )
    parser.add_argument("--max-chars", type=int, default=DEFAULT_MAX_CHARS)
    parser.add_argument("--reports-dir", default="tool/reports", help="report output dir")
    parser.add_argument("--yes", action="store_true", help="skip the consent prompt")
    parser.add_argument("--dry-run", action="store_true", help="compose only, call nothing")
    parser.add_argument("--no-run", action="store_true", help="analyze + report, skip dev agent")
    parser.add_argument("--check", action="store_true", help="validate env/input; no network")
    parser.add_argument("--watch", action="store_true", help="poll for new records")
    parser.add_argument("--interval", type=int, default=10, help="watch poll seconds")
    parser.add_argument(
        "--telegram", action="store_true", help="run the Telegram control-bot polling loop"
    )
    parser.add_argument(
        "--telegram-check",
        action="store_true",
        help="validate the Telegram token/chat id; no polling",
    )
    parser.set_defaults(consented=False)
    return parser


def main(argv: Optional[Sequence[str]] = None) -> int:
    load_env_files()
    make_console_utf8_safe()
    args = build_parser().parse_args(argv)

    if args.telegram_check:
        return telegram_check()
    if args.telegram:
        return telegram_bot_loop()

    if args.check:
        return check_runtime(args)

    path = Path(args.input)
    if not path.exists():
        print(f"input file not found: {path}", file=sys.stderr)
        return 1

    if args.watch:
        return watch_loop(path, args)
    return process_once(path, args)


if __name__ == "__main__":
    sys.exit(main())