#!/usr/bin/env python3
"""Stops a commit that would put a secret into this public repository (roadmap V1.4).

    python tools/secrets_check.py                 scan the staged changes (what `git commit` is about to record)
    python tools/secrets_check.py --self-test     run the scanner on made-up secrets it must catch and on clean
                                                  text it must pass, then end to end in a throw-away git repository
    python tools/secrets_check.py --install-hook  install it as this clone's pre-commit hook (once per clone)
    python tools/secrets_check.py --range BASE..HEAD  scan every commit in a range, one by one (CI, roadmap V1.5)

Exit code: 0 = nothing found, 1 = something key-like was found (the commit is stopped), 2 = it could not run.

What it looks for, in the lines a commit ADDS (a deleted or unchanged line is not looked at):
  * a private key block (`BEGIN ... PRIVATE KEY`),
  * a name that says secret (`api_key`, `password`, `SECRET_KEY`, `token`, the `X-FB3D-Key` header ...) given a literal
    value (`name = "value"`, `NAME=value`, `name: value`); a value that is a placeholder (fake, example, changeme,
    <key>, ${KEY}, a call or a variable) or too short is not counted,
  * the well-known key formats (AWS, GitHub, Slack, Google, Stripe, JSON Web Tokens),
  * a password inside a URL (`scheme://user:password@host`),
  * a long random-looking string (32 or more characters of base64 or hex-like text with high entropy),
  * a staged FILE whose name says it is a key or a secret (`.env`, `*.pem`, `secrets.local.cfg` ...), which means
    someone forced it past .gitignore.
It prints the file, the line number and the KIND of finding, never the line and never the value. A line that is
meant to look like a secret (a test, an example) can carry the words `secrets-check: ignore` in a comment.

This is one layer: it can be skipped (`git commit --no-verify`), so GitHub push protection (V1.3) and the same scan in
CI (V1.5) back it up, and a key that reached the repository anyway is handled by the leak procedure in README.md
("Secrets and credentials"). Only the Python standard library is used, so it runs on Windows too.
"""

import math
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

IGNORE_MARK = "secrets-check: ignore"

# Files that are generated or binary-like text and hold long machine-made strings that are not secrets.
SKIP_SUFFIXES = (".import", ".uid", ".tscn", ".tres", ".scn", ".res", ".svg", ".lock")
SKIP_PREFIXES = ("docs/baseline_f1/",)

# A staged file with one of these names is a finding on its own (templates are fine).
SECRET_FILE_PATTERNS = [
    re.compile(r"(^|/)\.env(\.[^/]*)?$"),
    re.compile(r"(^|/)secrets\.local\.[^/]*$"),
    re.compile(r"\.(pem|key|pfx|p12|crt)$"),
    re.compile(r"(^|/)id_(rsa|ed25519|ecdsa|dsa)[^/]*$"),
    re.compile(r"(^|/)(export_credentials\.cfg|local_settings\.py|credentials\.(json|cfg)|tokens?\.json)$"),
    re.compile(r"\.token$"),
    re.compile(r"(^|/)api_key\.[^/]*$"),
]
SECRET_FILE_ALLOWED = re.compile(r"(^|/)\.env\.example$")

PRIVATE_KEY = re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----")

# Well-known formats: (kind, regex). The hit itself is never printed.
KNOWN_FORMATS = [
    ("an AWS access key id", re.compile(r"(?<![A-Za-z0-9])(AKIA|ASIA)[0-9A-Z]{16}(?![A-Za-z0-9])")),
    ("a GitHub token", re.compile(r"(?<![A-Za-z0-9])(gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})")),
    ("a Slack token", re.compile(r"(?<![A-Za-z0-9])xox[abeoprs]-[A-Za-z0-9-]{10,}")),
    ("a Google API key", re.compile(r"(?<![A-Za-z0-9])AIza[0-9A-Za-z_-]{35}(?![A-Za-z0-9_-])")),
    ("a Stripe key", re.compile(r"(?<![A-Za-z0-9])[sr]k_live_[0-9A-Za-z]{16,}")),
    (
        "a JSON Web Token",
        re.compile(r"(?<![A-Za-z0-9_-])eyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}"),
    ),
]

URL_PASSWORD = re.compile(r"[A-Za-z][A-Za-z0-9+.-]*://[^\s/:@]+:(?P<pw>[^\s/@]{4,})@")

# name = value, name: value, NAME=value, "name": "value", X-FB3D-Key: value
ASSIGNMENT = re.compile(r"""(?ix)
    (?<![A-Za-z0-9])
    (?P<name>[A-Za-z0-9_-]*(?P<word>api[_-]?key|secret|passw(?:or)?d|passphrase|token|private[_-]?key|x-fb3d-key)[A-Za-z0-9_-]*)
    ["']?\s*(?::=|=|:)\s*(?:bearer\s+)?
    (?P<quote>["']?)
    (?P<value>[^\s"'`<>{}()\[\],;#]{6,})
    (?![A-Za-z0-9_.(\[-])
    """)

PLACEHOLDER_WORDS = (
    "fake",
    "example",
    "changeme",
    "change-me",
    "change_me",
    "replace",
    "your",
    "placeholder",
    "dummy",
    "sample",
    "redacted",
    "xxxx",
    "todo",
    "none",
    "null",
    "undefined",
)
KEYWORD_VALUES = ("password", "passwd", "passphrase", "secret", "token", "apikey", "api_key", "api-key", "key")
PASSWORD_WORD = re.compile(r"(?i)passw|passphrase")
SNAKE_WORDS = re.compile(r"^[a-z]+(_[a-z]+)*$")
RANDOM_TOKEN = re.compile(r"(?<![A-Za-z0-9+_=./:\\,-])[A-Za-z0-9+_=-]{32,}(?![A-Za-z0-9+_=-])")


def entropy(text):
    """Shannon entropy in bits per character."""
    if not text:
        return 0.0
    counts = {}
    for ch in text:
        counts[ch] = counts.get(ch, 0) + 1
    return -sum(n / len(text) * math.log2(n / len(text)) for n in counts.values())


def longest_run(text):
    """The longest stretch of characters that each follow the one before in the character table (abcdefgh, 012345)."""
    best = run = 1
    for a, b in zip(text, text[1:]):
        run = run + 1 if ord(b) == ord(a) + 1 else 1
        best = max(best, run)
    return best


def looks_random(token):
    """A 32+ character string that looks machine-made (a key) and not like a word, a path or a checksum."""
    if len(token) < 32:
        return False
    if longest_run(token) >= 8:
        return False  # a character set written out (abcdefgh..., 01234567...), not a key
    # Hex text (a git SHA-1, a SHA-256 checksum, which docs write on purpose) has only two classes, so it passes here;
    # a hex key is found by its name (see ASSIGNMENT), not by this rule.
    classes = sum(
        [
            any(c.islower() for c in token),
            any(c.isupper() for c in token),
            any(c.isdigit() for c in token),
            any(c in "+_=-" for c in token),
        ]
    )
    return classes >= 3 and entropy(token) >= 4.2


def is_placeholder(value):
    v = value.lower()
    if any(w in v for w in PLACEHOLDER_WORDS):
        return True
    if v in KEYWORD_VALUES:  # password = "password"
        return True
    if value.startswith(("$", "%", "@", "<", "{")):
        return True
    if len(set(value)) <= 3:  # xxxxxxxx, 00000000, ********
        return True
    return False


def value_is_secret_like(word, quote, value):
    """Decides whether the literal after a secret-sounding name is a real-looking secret."""
    if is_placeholder(value):
        return False
    if "://" in value or value.startswith(("/", "./", "../", "res:", "user:")):
        return False  # a URL or a path; a password inside a URL has its own rule
    is_password = bool(PASSWORD_WORD.search(word))
    if quote:
        if len(value) < (6 if is_password else 8):
            return False
        if not is_password and SNAKE_WORDS.match(value):
            return False  # "refresh_token" as the name of a field, not a token
        return True
    # unquoted (a .cfg, .env or shell line, or a bare identifier in code): only long, mixed text counts
    if len(value) < 12:
        return False
    if not (any(c.isdigit() for c in value) and any(c.isalpha() for c in value)):
        return False
    if SNAKE_WORDS.match(value.rstrip("0123456789")):
        return False  # an identifier such as token_input2
    return entropy(value) >= 3.0


def scan_line(line):
    """Returns the kinds of finding in one added line (a list of short texts; never the matched text)."""
    if IGNORE_MARK in line:
        return []
    found = []
    if PRIVATE_KEY.search(line):
        found.append("a private key block")
    for kind, rx in KNOWN_FORMATS:
        if rx.search(line):
            found.append(kind)
    for m in URL_PASSWORD.finditer(line):
        if not is_placeholder(m.group("pw")):
            found.append("a credential inside a URL")
            break
    for m in ASSIGNMENT.finditer(line):
        if value_is_secret_like(m.group("word"), m.group("quote"), m.group("value")):
            found.append("a value given to a name that says secret, key, token or password")
            break
    if not found:
        for m in RANDOM_TOKEN.finditer(line):
            if looks_random(m.group(0)):
                found.append("a long random-looking string")
                break
    return found


def skipped_path(path):
    low = path.lower()
    return low.endswith(SKIP_SUFFIXES) or low.startswith(SKIP_PREFIXES)


def is_secret_file(path):
    if SECRET_FILE_ALLOWED.search(path):
        return False
    return any(rx.search(path) for rx in SECRET_FILE_PATTERNS)


def parse_diff(text):
    """Yields (path, line_number, line) for every added line of a unified diff made with -U0."""
    path = None
    new_line = 0
    for raw in text.split("\n"):
        if raw.startswith("+++ "):
            name = raw[4:].strip()
            if name == "/dev/null":
                path = None
            else:
                name = name.strip('"')
                path = name[2:] if name.startswith("b/") else name
        elif raw.startswith("@@"):
            m = re.search(r"\+(\d+)", raw)
            new_line = int(m.group(1)) if m else 0
        elif raw.startswith("+") and not raw.startswith("+++") and path is not None:
            yield path, new_line, raw[1:]
            new_line += 1


def scan_diff(text, names=()):
    """Scans a diff and a list of changed file names. Returns [(path, line_number_or_0, kind)]."""
    findings = []
    for name in names:
        if is_secret_file(name):
            findings.append((name, 0, "a file whose name says it holds a key or a secret"))
    seen = set()
    for path, number, line in parse_diff(text):
        if skipped_path(path):
            continue
        for kind in scan_line(line):
            if (path, number, kind) not in seen:
                seen.add((path, number, kind))
                findings.append((path, number, kind))
    return findings


def git(args, cwd=None):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false"] + args,
        cwd=cwd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        universal_newlines=True,
        encoding="utf-8",
        errors="replace",
    )


def scan_staged(cwd=None):
    diff = git(["diff", "--cached", "--no-color", "--no-ext-diff", "-U0", "--diff-filter=ACMR"], cwd)
    names = git(["diff", "--cached", "--name-only", "--no-color", "--diff-filter=ACMR"], cwd)
    if diff.returncode != 0 or names.returncode != 0:
        raise RuntimeError("git could not list the staged changes: " + (diff.stderr or names.stderr).strip()[:200])
    return scan_diff(diff.stdout, [n for n in names.stdout.split("\n") if n])


def scan_range(rev_range, cwd=None):
    """Scan what each commit in `rev_range` (for example origin/main..HEAD) ADDS, one commit at a time, so a key that
    was added in one commit and removed in the next is still found (it stays in the history). Returns a list of
    (path, line, kind) with the short commit hash put in front of the path."""
    commits = git(["rev-list", "--no-merges", "--reverse", rev_range], cwd)
    if commits.returncode != 0:
        raise RuntimeError("git could not list the commits of %r: %s" % (rev_range, commits.stderr.strip()[:200]))
    findings = []
    for commit in [c for c in commits.stdout.split("\n") if c]:
        flags = ["--format=", "--no-color", "--no-ext-diff", "--diff-filter=ACMR", "--root"]
        diff = git(["show", "-U0"] + flags + [commit], cwd)
        names = git(["show", "--name-only"] + flags + [commit], cwd)
        if diff.returncode != 0 or names.returncode != 0:
            raise RuntimeError("git could not read commit %s: %s" % (commit[:7], (diff.stderr or names.stderr)[:200]))
        for path, number, kind in scan_diff(diff.stdout, [n for n in names.stdout.split("\n") if n]):
            findings.append(("%s %s" % (commit[:7], path), number, kind))
    return findings


def report(findings, out=sys.stdout, what="the staged changes, commit stopped."):
    for path, number, kind in findings:
        where = "%s:%d" % (path, number) if number else path
        print("%s: %s" % (where, kind), file=out)
    if findings:
        print(
            "\nsecrets_check: %d possible secret(s) in %s" % (len(findings), what),
            "Nothing above shows the value. Take it out, keep it in an environment variable or in secrets.local.cfg",
            "(README.md, 'Secrets and credentials'). If a real key was already pushed anywhere, it is burned:",
            "replace it first. If this is a false alarm (a test or an example), put 'secrets-check: ignore' in a",
            "comment on that line.",
            sep="\n",
            file=out,
        )


HOOK_MARK = "# FB3D secrets check (tools/secrets_check.py --install-hook)"
HOOK_TEXT = (
    "#!/bin/sh\n"
    + HOOK_MARK
    + "\n"
    + "# the first Python that really runs (on Windows a Store stub can hide behind the name python3)\n"
    + "for PY in python3 python py; do\n"
    + '  if "$PY" -c "import sys" >/dev/null 2>&1; then exec "$PY" tools/secrets_check.py; fi\n'
    + "done\n"
    + 'echo "secrets_check: no working Python found, so the secrets scan did NOT run; commit stopped." >&2\n'
    + 'echo "Install Python, or skip this check once with: git commit --no-verify" >&2\n'
    + "exit 1\n"
)


def _say(text, quiet, stream=None):
    if not quiet:
        print(text, file=stream or sys.stdout)


def install_hook(cwd=None, quiet=False):
    top = git(["rev-parse", "--show-toplevel"], cwd)
    where = git(["rev-parse", "--git-path", "hooks"], cwd)
    if top.returncode != 0 or where.returncode != 0:
        _say("secrets_check: this is not a git repository.", quiet, sys.stderr)
        return 2
    root = top.stdout.strip()
    hooks = where.stdout.strip()
    if not os.path.isabs(hooks):
        hooks = os.path.join(cwd or root, hooks) if cwd else os.path.join(root, hooks)
    os.makedirs(hooks, exist_ok=True)
    path = os.path.join(hooks, "pre-commit")
    if os.path.exists(path):
        with open(path, encoding="utf-8", errors="replace") as f:
            current = f.read()
        if HOOK_MARK in current:
            _say("secrets_check: the pre-commit hook is already installed (%s)." % path, quiet)
            return 0
        _say(
            "secrets_check: there is already a different pre-commit hook (%s); not touching it. "
            "Add the line  python tools/secrets_check.py  to it yourself." % path,
            quiet,
            sys.stderr,
        )
        return 2
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(HOOK_TEXT)
    os.chmod(path, 0o755)
    _say("secrets_check: installed the pre-commit hook (%s)." % path, quiet)
    return 0


# ---------------------------------------------------------------------------------------------------------------
# Self test. The made-up secrets are built from pieces at run time, so this file never holds one that the scanner
# would stop, and so a real scan of this file stays clean.
# ---------------------------------------------------------------------------------------------------------------

ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"


def _rand(rng, n, alphabet=ALPHABET):
    return "".join(rng.choice(alphabet) for _ in range(n))


def _must_catch(rng):
    key = _rand(rng, 28)
    long_b64 = _rand(rng, 44)
    cases = {
        "a private key block": "-----BEGIN " + "PRIVATE KEY-----",
        "an RSA private key block": "-----BEGIN RSA " + "PRIVATE KEY-----",
        "a key in code": 'var api_key = "' + key + '"',
        "a key in an env file": "FB3D_API_" + "KEY=" + key,
        "a config line": 'password = "' + _rand(rng, 12) + '"',
        "a short password": "pass" + 'word: "hunter22"',
        "Django SECRET_KEY": "SECRET_" + "KEY = 'django-insecure-" + _rand(rng, 40) + "'",
        "a JSON field": '"access_token": "' + _rand(rng, 36) + '"',
        "a header with the game key": "X-FB3D-" + "Key: " + key,
        "a bearer header": "Authorization: Bearer " + _rand(rng, 40),
        "an unquoted token in a shell script": "export API_TOKEN=" + _rand(rng, 24),
        "an AWS key id": "AKIA" + _rand(rng, 16, "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"),
        "a GitHub token": "ghp_" + _rand(rng, 36),
        "a fine-grained GitHub PAT": "github_pat_" + _rand(rng, 40),
        "a Slack token": "xox" + "b-" + _rand(rng, 24, "0123456789abcdef"),
        "a Google key": "AIza" + _rand(rng, 35),
        "a Stripe key": "sk_" + "live_" + _rand(rng, 24),
        "a JSON Web Token": "eyJ" + _rand(rng, 20) + ".eyJ" + _rand(rng, 20) + "." + _rand(rng, 20),
        "a password in a URL": "postgres://admin:" + _rand(rng, 14) + "@db.internal/fb3d",
        "a bare random string": "see " + long_b64 + " for details",
        "a random string in a comment": "# " + _rand(rng, 40),
    }
    return cases


def _must_pass(rng):
    sha1 = "".join(rng.choice("0123456789abcdef") for _ in range(40))
    sha256 = "".join(rng.choice("0123456789abcdef") for _ in range(64))
    return {
        "empty line": "",
        "plain code": "var speed = 12.5  # metres per second",
        "a password field read": "var password = password_field.text",
        "a token from a response": 'var token = response["token"]',
        "a call": 'var api_key = Secrets.get_value("api", "key")',
        "a call, unquoted": "api_key = load_api_key_from_disk_value()",
        "an env lookup": 'SECRET_KEY = os.environ["SECRET_KEY"]',
        "an env lookup, quoted name": "SECRET_KEY = env('SECRET_KEY')",
        "an empty value": 'password = ""',
        "the template's fake key": 'key="fake-key-replace-me-0000"',
        "the template's fake url": 'base_url="https://fb3d.invalid/fb3d/api/v1/"',
        "a placeholder": "api_key = <your key here>",
        "a shell variable": "API_KEY=${FB3D_API_KEY}",
        "a field name": '"token": "refresh_token"',
        "docs naming the header": "Send the key in the X-FB3D-Key header.",
        "docs naming a variable": "Set `FB3D_API_KEY` in the environment, never `api_key=` in a file.",
        "xxxxxxxx": 'password = "xxxxxxxxxx"',
        "a git SHA-1": "commit " + sha1,
        "a SHA-256 checksum": "sha256: " + sha256,
        "a long url": "https://github.com/GVihi/FstreliBiciklina3D/pull/new/roadmap/v1-1-gitignore-and-more",
        "a long res path": 'const M = preload("res://assets/models/riders/rider_armoured_tough_variant_v2.glb")',
        "a long identifier": "func _check_a_template_value_in_the_environment_does_not_hide_a_real_one() -> void:",
        "a base64 data uri": "data:image/png;base64," + _rand(rng, 60),
        "a deliberate test value": 'var api_key = "' + _rand(rng, 28) + '"  # ' + IGNORE_MARK,
        "a url without a password": "https://user@host.example.org/path",
    }


# Cases that one particular rule must catch (the generic random-string rule could also catch some of them, which
# would hide a broken specific rule): the text that must be in the kind of the first finding.
EXPECTED_KIND = {
    "a private key block": "private key",
    "an RSA private key block": "private key",
    "an AWS key id": "AWS",
    "a GitHub token": "GitHub",
    "a fine-grained GitHub PAT": "GitHub",
    "a Slack token": "Slack",
    "a Google key": "Google",
    "a Stripe key": "Stripe",
    "a JSON Web Token": "JSON Web Token",
    "a password in a URL": "URL",
    "a key in code": "name that says",
    "a config line": "name that says",
}


def _selftest_lines():
    rng = random.Random(20261029)
    problems = []
    for name, line in _must_catch(rng).items():
        got = scan_line(line)
        if not got:
            problems.append("must catch, but passed: " + name)
        elif name in EXPECTED_KIND and EXPECTED_KIND[name] not in got[0]:
            problems.append(
                "must be caught by its own rule (%s), but the first finding was: %s" % (EXPECTED_KIND[name], got[0])
            )
    for name, line in _must_pass(rng).items():
        got = scan_line(line)
        if got:
            problems.append("must pass, but stopped (%s): %s" % (got[0], name))
    return problems


def _selftest_own_file():
    """This file is committed through the hook it installs, so it must pass its own scan."""
    problems = []
    with open(os.path.abspath(__file__), encoding="utf-8") as f:
        for number, line in enumerate(f, 1):
            found = scan_line(line.rstrip("\n"))
            if found:
                problems.append("this file would stop its own scan at line %d (%s)" % (number, found[0]))
    return problems


def _selftest_diff():
    """The diff reading: file names, line numbers, deleted lines, a new file, a deleted file."""
    problems = []
    secret = 'password = "' + _rand(random.Random(7), 14) + '"'
    diff = "\n".join(
        [
            "diff --git a/scripts/a.gd b/scripts/a.gd",
            "--- a/scripts/a.gd",
            "+++ b/scripts/a.gd",
            "@@ -3,0 +4,2 @@",
            "+var ok = 1",
            "+" + secret,
            "@@ -20 +22 @@",
            "-" + secret,
            "+var fine = 2",
            "diff --git a/old.gd b/old.gd",
            "--- a/old.gd",
            "+++ /dev/null",
            "@@ -1 +0,0 @@",
            "-" + secret,
            "diff --git a/data/x.import b/data/x.import",
            "--- /dev/null",
            "+++ b/data/x.import",
            "@@ -0,0 +1 @@",
            "+" + secret,
            "diff --git a/docs/baseline_f1/r.md b/docs/baseline_f1/r.md",
            "--- /dev/null",
            "+++ b/docs/baseline_f1/r.md",
            "@@ -0,0 +1 @@",
            "+" + secret,
        ]
    )
    got = scan_diff(diff)
    if [(p, n) for p, n, _ in got] != [("scripts/a.gd", 5)]:
        problems.append("diff reading: expected only scripts/a.gd line 5, got %s" % [(p, n) for p, n, _ in got])
    for name, expect in [
        (".env", True),
        ("sub/.env.production", True),
        (".env.example", False),
        ("secrets.local.cfg", True),
        ("secrets.example.cfg", False),
        ("server.pem", True),
        ("keys/signing.key", True),
        ("cert.pfx", True),
        ("id_rsa", True),
        ("export_credentials.cfg", True),
        ("scripts/secrets.gd", False),
        ("tools/secrets_check.py", False),
        ("docs/SECRETS.md", False),
    ]:
        if is_secret_file(name) != expect:
            problems.append("file name rule: %s should be %s" % (name, "stopped" if expect else "allowed"))
    if not scan_diff("", [".env"]):
        problems.append("a staged .env was not stopped")
    return problems


def _selftest_git():
    """End to end in a throw-away repository: a real commit is stopped by the real hook, and a clean one is not."""
    problems = []
    here = os.path.dirname(os.path.abspath(__file__))
    tmp = tempfile.mkdtemp(prefix="fb3d_secrets_check_")
    try:
        os.makedirs(os.path.join(tmp, "tools"))
        shutil.copy(os.path.join(here, "secrets_check.py"), os.path.join(tmp, "tools", "secrets_check.py"))
        env = dict(os.environ, GIT_CONFIG_GLOBAL=os.devnull, GIT_CONFIG_SYSTEM=os.devnull)
        env.pop("GIT_DIR", None)
        env.pop("GIT_INDEX_FILE", None)

        def run(args, **kw):
            return subprocess.run(
                ["git", "-c", "user.name=t", "-c", "user.email=t@t.invalid"] + args,
                cwd=tmp,
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                universal_newlines=True,
                encoding="utf-8",
                errors="replace",
                **kw,
            )

        if run(["init", "-q"]).returncode != 0:
            return ["could not make a throw-away git repository (is git installed?)"]
        secret_value = _rand(random.Random(99), 30)
        with open(os.path.join(tmp, "bad.gd"), "w", encoding="utf-8") as f:
            f.write('var x = 1\nvar api_key = "' + secret_value + '"\n')
        with open(os.path.join(tmp, "good.gd"), "w", encoding="utf-8") as f:
            f.write('var x = 1\nvar api_key = Secrets.get_value("api", "key")\n')
        run(["add", "good.gd", "bad.gd"])
        findings = scan_staged(tmp)
        if [(p, n) for p, n, _ in findings] != [("bad.gd", 2)]:
            problems.append("staged scan: expected bad.gd line 2, got %s" % [(p, n) for p, n, _ in findings])
        # the program run as the hook runs it: exit code 1 and the value not in the output
        proc = subprocess.run(
            [sys.executable, os.path.join(tmp, "tools", "secrets_check.py")],
            cwd=tmp,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            encoding="utf-8",
            errors="replace",
        )
        if proc.returncode != 1:
            problems.append("the program exited with %d on a staged secret, expected 1" % proc.returncode)
        if secret_value in proc.stdout or "api_key" in proc.stdout:
            problems.append("the output shows part of the line or the value")
        if "bad.gd:2" not in proc.stdout:
            problems.append("the output does not name bad.gd:2")
        # the hook
        if install_hook(tmp, quiet=True) != 0:
            problems.append("--install-hook failed in the throw-away repository")
        if install_hook(tmp, quiet=True) != 0:
            problems.append("--install-hook is not safe to run twice")
        commit = run(["commit", "-q", "-m", "should be stopped"])
        if commit.returncode == 0:
            problems.append("the pre-commit hook let a commit with a secret through")
        if secret_value in commit.stdout:
            problems.append("the hook output shows the value")
        run(["reset", "-q", "bad.gd"])
        os.remove(os.path.join(tmp, "bad.gd"))
        commit = run(["commit", "-q", "-m", "clean"])
        if commit.returncode != 0:
            problems.append("the pre-commit hook stopped a clean commit: " + commit.stdout.strip()[:200])
        # a range: a secret added in one commit and removed in the next is still found, a clean range is not
        base = run(["rev-parse", "HEAD"]).stdout.strip()
        with open(os.path.join(tmp, "later.gd"), "w", encoding="utf-8") as f:
            f.write('var api_key = "' + secret_value + '"\n')
        run(["add", "later.gd"])
        run(["commit", "-q", "--no-verify", "-m", "adds a secret"])
        os.remove(os.path.join(tmp, "later.gd"))
        run(["add", "-A"])
        run(["commit", "-q", "--no-verify", "-m", "removes it again"])
        found = scan_range(base + "..HEAD", tmp)
        if [(p.split(" ", 1)[1], n) for p, n, _ in found] != [("later.gd", 1)]:
            problems.append("range scan: expected later.gd line 1, got %s" % found)
        proc = subprocess.run(
            [sys.executable, os.path.join(tmp, "tools", "secrets_check.py"), "--range", base + "..HEAD"],
            cwd=tmp,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            universal_newlines=True,
            encoding="utf-8",
            errors="replace",
        )
        if proc.returncode != 1 or secret_value in proc.stdout or "later.gd:1" not in proc.stdout:
            problems.append("--range on a bad range: exit %d, output %r" % (proc.returncode, proc.stdout[:120]))
        if scan_range("HEAD..HEAD", tmp) != []:
            problems.append("range scan: an empty range found something")
        if scan_range("HEAD~2", tmp) != []:  # the first (clean) commit alone, read with --root
            problems.append("range scan: the clean first commit was reported")
        try:
            scan_range("no-such-ref..HEAD", tmp)
            problems.append("range scan: a bad ref did not raise")
        except RuntimeError:
            pass
        # a different hook is never overwritten
        os.remove(os.path.join(tmp, ".git", "hooks", "pre-commit"))
        with open(os.path.join(tmp, ".git", "hooks", "pre-commit"), "w", encoding="utf-8") as f:
            f.write("#!/bin/sh\nexit 0\n")
        if install_hook(tmp, quiet=True) != 2:
            problems.append("--install-hook overwrote or accepted a different existing hook")
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    return problems


def self_test():
    problems = _selftest_lines() + _selftest_own_file() + _selftest_diff() + _selftest_git()
    if problems:
        for p in problems:
            print("secrets_check --self-test: " + p)
        return 1
    print(
        "secrets_check --self-test: made-up secrets are caught, clean text passes, "
        "the diff reading, the file names and the hook work"
    )
    return 0


def main(argv):
    args = argv[1:]
    if args == ["--self-test"]:
        return self_test()
    if args == ["--install-hook"]:
        return install_hook()
    if len(args) == 2 and args[0] == "--range" and not args[1].startswith("-"):
        try:
            findings = scan_range(args[1])
        except (RuntimeError, OSError) as e:
            print("secrets_check: " + str(e), file=sys.stderr)
            return 2
        report(findings, what="the commits of " + args[1] + ", the check fails.")
        return 1 if findings else 0
    if args:
        print(
            __doc__.split("\n\n")[0] + "\n\nUsage: secrets_check.py [--self-test | --install-hook | --range A..B]",
            file=sys.stderr,
        )
        return 2
    try:
        findings = scan_staged()
    except (RuntimeError, OSError) as e:
        print("secrets_check: " + str(e), file=sys.stderr)
        return 2
    report(findings)
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
