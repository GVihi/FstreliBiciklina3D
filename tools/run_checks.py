#!/usr/bin/env python3
"""Runs every headless check in tools/ and prints PASSED or FAILED for each, and why.

    python tools/run_checks.py                  run all checks
    python tools/run_checks.py unlocks xp       only checks whose name contains "unlocks" or "xp"
    python tools/run_checks.py --list           list the checks and stop
    python tools/run_checks.py --godot PATH     use this Godot (remembered for next time)
    python tools/run_checks.py --fail-fast      stop at the first failure
    python tools/run_checks.py --full           the bigger seed and arena counts (takes much longer)
    python tools/run_checks.py --lint           also run gdlint and gdformat --check when installed

On Windows, tools\\run_checks.bat does the same (double click it, or pass the same arguments).

What it does for you:
  * Finds Godot by itself: --godot, the GODOT environment variable, the path saved by an earlier run
    (tools/godot_path.local.txt, not committed), PATH, the Steam folder, Program Files, Downloads and
    /Applications. The first time a path is found it is saved, so you never type it again.
  * Finds the checks by itself: every tools/*_check.gd is run, so a new check is picked up without
    editing a list. Checks that need an argument are in CHECK_ARGS below.
  * Keeps your real saves safe: every check runs with its own empty save folder (APPDATA / XDG_DATA_HOME
    / HOME point at a temporary folder), so no check can touch settings, scores, meta coins or a saved
    run. Use --real-saves to turn that off.
  * Never hangs: a check that does not finish in its time limit is killed and reported as FAILED (TIMEOUT).
    A check that crashes in a script error and "exits 0" is reported as FAILED too.
  * Writes the full output of every check to check_logs/<name>.log and the summary to
    check_logs/summary.txt (not committed), so a failure can be sent back as one file.

Exit code: 0 when every check passed, 1 when any failed, 2 when Godot could not be found.
"""

import argparse
import os
import platform
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
TOOLS = ROOT / "tools"
LOG_DIR = ROOT / "check_logs"
SAVED_PATH_FILE = TOOLS / "godot_path.local.txt"

MIN_GODOT = (4, 7)  # config/features in project.godot

# Extra arguments after "--" for checks that take them. The normal run uses the quick numbers (the same defaults as
# the checks' .bat files where there is one); --full uses the bigger numbers the README items were signed off with.
# arena_generated_check takes about 6 seconds per arena since the arena became 144 m wide, so its own default of 200
# arenas is 20 minutes and prints nothing until it is done.
CHECK_ARGS = {
    "generated_run_check": ["4"],  # seeds, 30 s of scripted play each
    "pickup_placement_check": ["20"],  # generated arenas
    "arena_generated_check": ["30"],  # arenas
}
CHECK_ARGS_FULL = {
    "generated_run_check": ["12"],
    "pickup_placement_check": ["60"],
    "arena_generated_check": [],  # the check's own 200
}

# Seconds before a check is killed. Everything not listed gets DEFAULT_TIMEOUT.
DEFAULT_TIMEOUT = 600
CHECK_TIMEOUT = {
    "generated_run_check": 1500,
    "arena_generated_check": 2400,
    "arena_gen_check": 1500,
    "map_check": 1200,
    "world_dress_check": 1200,
    "world_gen_check": 1200,
    "pedestrian_check": 1200,
}

# Output that means the script itself broke, even when Godot exits with 0.
SCRIPT_BROKEN = re.compile(r"Parse Error|Failed to load script|SCRIPT ERROR")
ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]")


class Colours:
    def __init__(self, on):
        self.on = on

    def _c(self, code, text):
        return "\033[%sm%s\033[0m" % (code, text) if self.on else text

    def green(self, t):
        return self._c("32;1", t)

    def red(self, t):
        return self._c("31;1", t)

    def grey(self, t):
        return self._c("90", t)


def say(text=""):
    print(text, flush=True)


# ---------------------------------------------------------------- finding Godot


def godot_candidates(cli_path):
    """Yields (where, path) in the order they are tried."""
    if cli_path:
        yield "--godot", Path(cli_path)
    for var in ("GODOT", "GODOT_PATH", "GODOT_BIN"):
        if os.environ.get(var):
            yield "$" + var, Path(os.environ[var])
    if SAVED_PATH_FILE.is_file():
        saved = SAVED_PATH_FILE.read_text(encoding="utf-8").strip()
        if saved:
            yield "saved path", Path(saved)
    for name in ("godot4", "godot", "godot.exe", "Godot"):
        found = shutil.which(name)
        if found:
            yield "PATH", Path(found)
    for folder in godot_folders():
        if not folder.is_dir():
            continue
        exes = sorted(
            (p for p in folder.glob("*") if looks_like_godot(p)),
            key=lambda p: ("console" not in p.name.lower(), p.name),  # console builds first
        )
        for exe in exes:
            yield "folder " + str(folder), exe


def godot_folders():
    home = Path.home()
    folders = []
    if os.name == "nt":
        for var in ("ProgramFiles(x86)", "ProgramFiles"):
            base = os.environ.get(var)
            if base:
                folders.append(Path(base) / "Steam" / "steamapps" / "common" / "Godot Engine")
                folders.append(Path(base) / "Godot")
        for letter in "CDEFG":
            folders.append(Path(letter + ":/SteamLibrary/steamapps/common/Godot Engine"))
            folders.append(Path(letter + ":/Program Files (x86)/Steam/steamapps/common/Godot Engine"))
        folders += [home / "Downloads", home / "Desktop", home / "Godot"]
    elif sys.platform == "darwin":
        folders += [Path("/Applications/Godot.app/Contents/MacOS"), home / "Downloads"]
    else:
        folders += [home / "godot", home / "Godot", home / "Downloads", Path("/usr/local/bin"), Path("/opt/godot")]
    # a Godot dropped next to the project (godot-bin/ is what the CI uses)
    folders += [ROOT / "godot-bin", ROOT.parent / "godot-bin", ROOT.parent]
    return folders


def looks_like_godot(path):
    name = path.name.lower()
    if not path.is_file() or "godot" not in name:
        return False
    if name.endswith((".zip", ".md", ".txt", ".pck", ".dll", ".json", ".tres")):
        return False
    return os.name != "nt" or name.endswith(".exe")


def godot_version(path):
    try:
        out = subprocess.run(
            [str(path), "--version"], capture_output=True, text=True, timeout=60
        ).stdout.strip()
    except (OSError, subprocess.SubprocessError):
        return None, ""
    m = re.match(r"(\d+)\.(\d+)", out)
    if not m:
        return None, out
    return (int(m.group(1)), int(m.group(2))), out


def find_godot(cli_path):
    tried = []
    for where, path in godot_candidates(cli_path):
        if not path.is_file():
            tried.append("%s: %s (not a file)" % (where, path))
            continue
        version, text = godot_version(path)
        if version is None:
            tried.append("%s: %s (did not answer --version)" % (where, path))
            continue
        if version < MIN_GODOT:
            tried.append("%s: %s is Godot %s, the project needs %d.%d or newer" % (where, path, text, *MIN_GODOT))
            continue
        return path, text, where, tried
    return None, "", "", tried


def remember_godot(path):
    try:
        SAVED_PATH_FILE.write_text(str(path) + "\n", encoding="utf-8")
    except OSError:
        pass


# ---------------------------------------------------------------- finding checks


def find_checks(filters):
    names = sorted(p.stem for p in TOOLS.glob("*_check.gd"))
    if filters:
        names = [n for n in names if any(f.lower() in n.lower() for f in filters)]
    return names


# ---------------------------------------------------------------- running one


def isolated_env(user_dir):
    """An environment where Godot's user:// folder is empty and temporary."""
    env = dict(os.environ)
    user_dir = str(user_dir)
    env["APPDATA"] = user_dir  # Windows
    env["XDG_DATA_HOME"] = user_dir  # Linux
    env["XDG_CONFIG_HOME"] = user_dir
    env["XDG_CACHE_HOME"] = user_dir
    if sys.platform == "darwin":
        env["HOME"] = user_dir
    return env


def run_check(godot, name, timeout, real_saves, extra_args, full=False):
    cmd = [str(godot), "--headless", "--path", str(ROOT), "--script", "res://tools/%s.gd" % name]
    args = (CHECK_ARGS_FULL if full else CHECK_ARGS).get(name, CHECK_ARGS.get(name, [])) + extra_args
    if args:
        cmd += ["--"] + args
    user_dir = None
    env = None
    if not real_saves:
        user_dir = tempfile.mkdtemp(prefix="fb3d_check_")
        env = isolated_env(user_dir)
    started = time.time()
    timed_out = False
    try:
        proc = subprocess.Popen(
            cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=env, cwd=str(ROOT)
        )
        try:
            raw, _ = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            proc.kill()
            raw, _ = proc.communicate()
        code = proc.returncode
    except OSError as e:
        raw, code = ("could not start Godot: %s" % e).encode(), -1
    finally:
        if user_dir:
            shutil.rmtree(user_dir, ignore_errors=True)
    text = ANSI.sub("", raw.decode("utf-8", errors="replace")).replace("\r\n", "\n")
    return {
        "name": name,
        "code": code,
        "timed_out": timed_out,
        "seconds": time.time() - started,
        "output": text,
        "cmd": cmd,
    }


def verdict(result):
    """(passed, short reason)"""
    if result["timed_out"]:
        return False, "TIMEOUT: still running after the time limit (a script error before quit() does this)"
    if result["code"] != 0:
        return False, "exit code %s" % result["code"]
    if SCRIPT_BROKEN.search(result["output"]):
        return False, "exit code 0, but the output has a script error"
    return True, ""


def reason_lines(result, limit=12):
    """The lines that explain a failure."""
    lines = [l.rstrip() for l in result["output"].split("\n") if l.strip()]
    prefix = result["name"] + ":"
    own = [l for l in lines if l.startswith(prefix)]
    if own:
        return own[:limit]
    hits = [l for l in lines if re.search(r"FAIL|SCRIPT ERROR|Parse Error|Failed to load|ERROR:", l)]
    if hits:
        return hits[:limit]
    return lines[-limit:]


# ---------------------------------------------------------------- lint


def run_lint(c):
    """gdlint and gdformat --check on the folders the CI checks. Returns a list of (name, passed, text)."""
    out = []
    for tool, args in (("gdlint", ["scripts/", "tools/viewer/"]), ("gdformat", ["--check", "scripts/", "tools/viewer/"])):
        exe = shutil.which(tool)
        if not exe:
            out.append((tool, None, "not installed (pip install gdtoolkit==4.5.0)"))
            continue
        p = subprocess.run([exe] + args, capture_output=True, text=True, cwd=str(ROOT))
        text = (p.stdout + p.stderr).strip()
        out.append((tool, p.returncode == 0, text))
    return out


# ---------------------------------------------------------------- main


def main():
    ap = argparse.ArgumentParser(description="Run every headless check in tools/.", add_help=True)
    ap.add_argument("filters", nargs="*", help="only checks whose name contains one of these words")
    ap.add_argument("--godot", help="path to the Godot executable (remembered for next time)")
    ap.add_argument("--list", action="store_true", help="list the checks and stop")
    ap.add_argument("--fail-fast", action="store_true", help="stop at the first failure")
    ap.add_argument("--full", action="store_true", help="bigger seed and arena counts for the slow checks")
    ap.add_argument("--timeout", type=int, help="seconds per check, overrides the built-in limits")
    ap.add_argument("--real-saves", action="store_true", help="let the checks use your real save folder")
    ap.add_argument("--lint", action="store_true", help="also run gdlint and gdformat --check (needs gdtoolkit)")
    ap.add_argument("--no-colour", action="store_true")
    ap.add_argument("--verbose", "-v", action="store_true", help="print the full output of every check")
    ap.add_argument("--args", nargs=argparse.REMAINDER, default=[], help="extra arguments for the checks, after --")
    opts = ap.parse_args()

    if os.name == "nt":
        os.system("")  # lets the Windows console show colours
    c = Colours(sys.stdout.isatty() and not opts.no_colour and not os.environ.get("NO_COLOR"))

    checks = find_checks(opts.filters)
    if opts.list:
        for n in checks:
            say("%s%s" % (n, "  -- " + " ".join(CHECK_ARGS[n]) if n in CHECK_ARGS else ""))
        say("%d checks" % len(checks))
        return 0
    if not checks:
        say("No check matches %s." % opts.filters)
        return 2

    godot, version_text, where, tried = find_godot(opts.godot)
    if opts.godot and where != "--godot":
        # the path that was asked for is no good: say so instead of quietly using another Godot
        say(c.red("The Godot given with --godot does not work."))
        for t in tried:
            say("  " + t)
        return 2
    if not godot:
        say(c.red("Could not find Godot %d.%d or newer." % MIN_GODOT))
        for t in tried:
            say("  tried " + t)
        say("Run once with the path, and it is remembered:")
        say('  python tools/run_checks.py --godot "C:\\path\\to\\Godot_console.exe"')
        return 2
    if opts.godot or where != "saved path":
        remember_godot(godot)
    say("Godot %s" % version_text)
    say("  %s (from %s)" % (godot, where))
    say("%d checks%s%s" % (len(checks), "" if opts.real_saves else ", each with its own empty save folder", ""))
    say()

    LOG_DIR.mkdir(exist_ok=True)
    results = []
    started = time.time()
    width = max(len(n) for n in checks)
    for i, name in enumerate(checks, 1):
        limit = opts.timeout or CHECK_TIMEOUT.get(name, DEFAULT_TIMEOUT)
        say("[%2d/%d] %-*s ..." % (i, len(checks), width, name))
        r = run_check(godot, name, limit, opts.real_saves, opts.args, opts.full)
        ok, why = verdict(r)
        r["ok"], r["why"] = ok, why
        results.append(r)
        (LOG_DIR / (name + ".log")).write_text(
            "$ %s\nexit code: %s%s\n\n%s" % (" ".join(r["cmd"]), r["code"], " (timeout)" if r["timed_out"] else "", r["output"]),
            encoding="utf-8",
        )
        tag = c.green("PASSED") if ok else c.red("FAILED")
        say("        %s  %s  %s" % (tag, c.grey("%.1fs" % r["seconds"]), why))
        if not ok:
            for line in reason_lines(r):
                say("          | " + line[:200])
        elif opts.verbose:
            say(r["output"])
        if opts.verbose and not ok:
            say(r["output"])
        if not ok and opts.fail_fast:
            break

    lint = run_lint(c) if opts.lint else []
    for tool, ok, text in lint:
        if ok is None:
            say("%s: %s" % (tool, text))
        else:
            say("%s: %s" % (tool, c.green("PASSED") if ok else c.red("FAILED")))
            if not ok:
                for line in text.split("\n")[:12]:
                    say("          | " + line)

    failed = [r for r in results if not r["ok"]]
    lint_failed = [t for t, ok, _ in lint if ok is False]
    total = time.time() - started
    summary = []
    summary.append("%d of %d checks passed in %.0fs" % (len(results) - len(failed), len(results), total))
    if failed:
        summary.append("FAILED:")
        for r in failed:
            summary.append("  %s  (%s)" % (r["name"], r["why"]))
            for line in reason_lines(r, 4):
                summary.append("      " + line[:200])
    if lint_failed:
        summary.append("LINT FAILED: " + ", ".join(lint_failed))
    skipped = len(checks) - len(results)
    if skipped:
        summary.append("%d checks not run (--fail-fast)" % skipped)
    summary.append("Full output of each check: %s" % (LOG_DIR / "<name>.log"))
    text = "\n".join(summary)
    (LOG_DIR / "summary.txt").write_text(text + "\n", encoding="utf-8")

    say()
    say("=" * 70)
    if failed or lint_failed:
        say(c.red(text.split("\n")[0]))
        say("\n".join(summary[1:]))
        say("=" * 70)
        return 1
    say(c.green("ALL PASSED: " + text.split("\n")[0]))
    say("=" * 70)
    return 0


if __name__ == "__main__":
    sys.exit(main())
