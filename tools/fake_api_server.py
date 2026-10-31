#!/usr/bin/env python3
"""A pretend website for the game's web checks (roadmap V4.2). It plays the API of docs/WEBSITE_API.md on this computer.

    python tools/fake_api_server.py --ready-file PATH [--lifetime SECONDS]   serve until stopped (the checks start it so)
    python tools/fake_api_server.py --key SOMETHING                          the same, with a key you chose (by hand)
    python tools/fake_api_server.py --self-test                              test the server itself (no Godot, no network)

Why it exists: every web check from here on (V4.7, V5.8, V6.7, V8.8) runs headless against this server instead of the
real website, so a check never needs a key, a network or the owner's server. Only the Python standard library is used,
so it runs on Windows too. Exit code: 0 = ended normally, 1 = the self-test failed, 2 = it could not start.

How a check uses it
  1. Start it: `--ready-file PATH` (a file in the check's own temporary folder) and `--lifetime 120`, so that it ends
     by itself even when the check crashes. It listens on 127.0.0.1 only, on a free port (`--port 0`).
  2. Wait for the ready file. It holds one JSON object: {"port", "base_url", "root_url", "key", "pid"}. `base_url`
     is `http://127.0.0.1:PORT/fb3d/api/v1/`, the address the game accepts from `--dev-api` or `WebApi.use_config`
     in an editor run. `key` is the one key this server accepts. The key is **made up for each run, starts with
     `fb3dtest_`, and is never printed**. The server refuses a `--key` that looks like a real game key.
  3. Pick what it does with `POST {root_url}__fake__/scenario` and read what it got with `GET {root_url}__fake__/stats`
     (the paths are made of the characters `WebApi.is_valid_path` allows, so the game's own `WebApi` can make these
     calls with `root_url` as its base). Control calls are not counted as requests.
  4. Stop it: `POST {root_url}__fake__/stop`, or kill the process.

Scenarios (`POST __fake__/scenario` with {"scenario": NAME, ...}; the start is `current`)
  current         what the real site does, for `ping` and `releases/current`: the key is checked first, then the
                  version headers, then the method (the order of docs/WEBSITE_API.md), and `update` is worked out
                  with tools/version_compare.py from the caller's `X-FB3D-Version`. Also settable here:
                  "release_version" (the published release, null for none; start 0.3.1) and "minimum_version"
                  (start 0.0.0, so nothing is required). Every error has the one error shape.
  wrong_key       every call answers 403 key_rejected, whatever key was sent.
  slow            the honest answer after "delay_seconds" (start 2.0, at most 60). More than the game's timeout (5 s)
                  is a server that accepts the connection and says nothing.
  server_error    every call answers 500 server_error.
  damaged_json    every call answers 200 with a JSON body that is cut off in the middle.
  dead_connection the request is read and the connection is closed without any answer.
`POST __fake__/reset` puts the scenario, the delay and the versions back to the start and zeroes the counters.
More answers (login, saves, ...) are added next to `_answer_ping` when the item that needs them is built.

What it counts: every request that is not a control call, also one that got no answer. `stats` has the total, a
count per path and the last 100 requests: method, path, scenario, the status sent (0 = none, null = still being
answered), whether the key was ok, wrong or missing, whether an Authorization header came, the version and build
headers, the names of all headers and the size of the body. **No key, token, password or body is ever kept or printed**,
so a check can read `stats` aloud without leaking anything; the self-test proves it.

This is a test tool. It is not a model of the real site's security: it has no throttling, no database and no tokens.
"""

import argparse
import hashlib
import hmac
import http.client
import json
import os
import secrets
import socket
import subprocess
import sys
import tempfile
import threading
import time
from collections import deque
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

TOOLS_FOLDER = os.path.dirname(os.path.abspath(__file__))
if TOOLS_FOLDER not in sys.path:
    sys.path.insert(0, TOOLS_FOLDER)
import version_compare  # noqa: E402  (the same comparison the game and the site use, tools/version_compare.py)

HOST = "127.0.0.1"
API_PREFIX = "/fb3d/api/v1/"
CONTROL_PREFIX = "/__fake__/"
API_VERSION = 1

SCENARIOS = ("current", "wrong_key", "slow", "server_error", "damaged_json", "dead_connection")
DEFAULT_SCENARIO = "current"
DEFAULT_DELAY = 2.0
MAX_DELAY = 60.0
DEFAULT_RELEASE = "0.3.1"
DEFAULT_MINIMUM = "0.0.0"

MAX_BODY = 307200  # nginx client_max_body_size 300k (docs/WEBSITE_API.md, Limits): a bigger body is refused unread
MAX_CONTROL_BODY = 4096
RECENT_LIMIT = 100
MAX_PATH_KEYS = 100
MAX_HEADER_NAMES = 30
SOCKET_TIMEOUT = 30
DEFAULT_LIFETIME = 300.0

KEY_PREFIX = "fb3dtest_"
REAL_KEY_PREFIX = "fb3dk_"  # the shape of a real game key (docs/WEBSITE_API.md): never accepted here
MAX_KEY_LENGTH = 128  # the game's own limit (scripts/web_api.gd)
PLACEHOLDER_WORDS = ("fake", ".invalid", "replace-me")  # the game ignores a key that holds one of these
BUILD_CHARACTERS = "0123456789abcdefghijklmnopqrstuvwxyz"

RELEASE_SIZE = 94371840
RELEASE_PUBLISHED = "2026-11-05T09:00:00Z"
RELEASE_NOTES = "A pretend release made by tools/fake_api_server.py."
DAMAGED_BODY = b'{"update": "available", "minimum_version": "0.3.0", "current": {"version": "0.3.'

# The fixed texts of the error answers this server sends (docs/WEBSITE_API.md, "The one error shape"). The game never
# shows them, it maps `code`.
MESSAGES = {
    "bad_request": "A required header is missing or malformed.",
    "key_missing": "No game key was sent.",
    "key_rejected": "The game key was not accepted.",
    "not_found": "No such path.",
    "method_not_allowed": "Wrong method for this path.",
    "payload_too_large": "The request body is too large.",
    "server_error": "An error on the server.",
}


def error_body(code: str) -> dict:
    return {"error": {"code": code, "message": MESSAGES[code], "retry_after": None}}


def safe_text(text, limit: int) -> str:
    """Printable ASCII only and at most `limit` characters, so nothing a client sends can fill a log or a record."""
    out = []
    for letter in str(text)[:limit]:
        out.append(letter if 33 <= ord(letter) <= 126 else "?")
    return "".join(out)


def is_valid_build(text: str) -> bool:
    """What the game sends in X-FB3D-Build: a short hash or `dev`, and a `+` after it for a dirty build."""
    core = text[:-1] if text.endswith("+") else text
    if core == "" or len(core) > 15:
        return False
    for letter in core:
        if letter not in BUILD_CHARACTERS:
            return False
    return True


def make_test_key() -> str:
    while True:
        key = KEY_PREFIX + secrets.token_urlsafe(32)
        lowered = key.lower()
        if not any(word in lowered for word in PLACEHOLDER_WORDS):
            return key


def check_key_text(key: str) -> str:
    """"" when `key` may be used with this server, else why not (never the key itself)."""
    if key.startswith(REAL_KEY_PREFIX):
        return "that looks like a real game key; this server never takes one"
    if key == "" or len(key) > MAX_KEY_LENGTH:
        return "the key must be 1 to " + str(MAX_KEY_LENGTH) + " characters"
    for letter in key:
        if ord(letter) <= 32 or ord(letter) >= 127:
            return "the key must be printable ASCII without a space"
    if any(word in key.lower() for word in PLACEHOLDER_WORDS):
        return "the game ignores a key that holds " + ", ".join(PLACEHOLDER_WORDS) + ", so it could never be sent"
    return ""


def update_state(caller: str, release, minimum) -> str:
    """`none`, `available` or `required` for a build with version `caller` (a valid version)."""
    if minimum is not None and version_compare.compare(caller, minimum) == -1:
        return "required"
    if release is not None and version_compare.compare(caller, release) == -1:
        return "available"
    return "none"


def release_object(version: str, port: int) -> dict:
    commit = hashlib.sha1(("fb3d-pretend-release-" + version).encode("utf-8")).hexdigest()
    file_name = "FB3D-" + version + "-" + commit[:7] + ".exe"
    return {
        "version": version,
        "channel": "release",
        "commit": commit,
        "published_utc": RELEASE_PUBLISHED,
        "file_name": file_name,
        "size": RELEASE_SIZE,
        "sha256": hashlib.sha256(file_name.encode("utf-8")).hexdigest(),
        "download_url": "http://" + HOST + ":" + str(port) + "/media/fb3d/releases/" + file_name,
        "notes": RELEASE_NOTES,
    }


# ------------------------------------------------------------------------------------------- the answers


def _answer_ping(owner: "FakeApiServer", caller: str) -> tuple:
    settings = owner.settings()
    return 200, {
        "status": "ok",
        "api_version": API_VERSION,
        "server_time": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "update": update_state(caller, settings["release_version"], settings["minimum_version"]),
    }


def _answer_release(owner: "FakeApiServer", caller: str) -> tuple:
    settings = owner.settings()
    release = settings["release_version"]
    return 200, {
        "update": update_state(caller, release, settings["minimum_version"]),
        "minimum_version": settings["minimum_version"],
        "current": None if release is None else release_object(release, owner.port),
    }


# path after the base path -> (method, function). A new call of the API is one more line here.
ROUTES = {
    "ping": ("GET", _answer_ping),
    "releases/current": ("GET", _answer_release),
}


# ------------------------------------------------------------------------------------------- the server


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    block_on_close = False
    allow_reuse_address = False
    request_queue_size = 16
    owner = None

    def handle_error(self, request, client_address):
        # A client that gave up (a timeout in the game) is normal. Anything else is named by class only, never printed
        # with a traceback, which could show a header.
        error = sys.exc_info()[1]
        if isinstance(error, (ConnectionError, TimeoutError, socket.timeout)):
            return
        print("fake api server: handler error " + type(error).__name__, file=sys.stderr, flush=True)


class _Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "FB3DFakeApi"
    sys_version = ""
    timeout = SOCKET_TIMEOUT

    def log_message(self, *args):
        pass  # the server's own log line (verbose mode) never holds a header or a body

    def do_GET(self):
        self._serve()

    do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_GET

    def send_error(self, code, message=None, explain=None):
        # Called by http.server for a request it cannot read; the real API never answers with HTML.
        if code == 413:
            self._send_error_code(413, "payload_too_large")
        elif code == 501:
            self._send_error_code(405, "method_not_allowed")
        else:
            self._send_error_code(400, "bad_request")

    # ---------------------------------------------------------------- one request

    def _serve(self):
        owner = self.server.owner
        path = urlsplit(self.path).path
        if path.startswith(CONTROL_PREFIX):
            self._control(path[len(CONTROL_PREFIX) :])
            return
        length = self._content_length()
        too_large = length > MAX_BODY
        body_bytes = 0
        if not too_large and length > 0:
            body_bytes = len(self.rfile.read(length))
        scenario, delay = owner.behaviour()
        entry = owner.begin_request(
            self.command,
            path,
            scenario,
            {
                "key": owner.key_state(self.headers.get("X-FB3D-Key")),
                "has_token": self.headers.get("Authorization") is not None,
                "version": safe_text(self.headers.get("X-FB3D-Version", ""), 40),
                "build": safe_text(self.headers.get("X-FB3D-Build", ""), 40),
                "header_names": sorted({name.lower() for name in self.headers.keys()})[:MAX_HEADER_NAMES],
                "body_bytes": body_bytes if not too_large else length,
            },
        )
        status = 0
        try:
            if scenario == "dead_connection":
                self._drop()
            elif scenario == "wrong_key":
                status = self._send_error_code(403, "key_rejected")
            elif scenario == "server_error":
                status = self._send_error_code(500, "server_error")
            elif scenario == "damaged_json":
                status = self._send_bytes(200, DAMAGED_BODY)
            else:
                if scenario == "slow":
                    owner.pause(delay)
                status = self._honest(path, too_large)
        finally:
            owner.finish_request(entry, status)

    def _honest(self, path: str, too_large: bool) -> int:
        """The order of docs/WEBSITE_API.md: an unknown path and a body over the hard limit need no key, then the key,
        then the version headers, then the method."""
        route = ROUTES.get(path[len(API_PREFIX) :]) if path.startswith(API_PREFIX) else None
        if route is None:
            return self._send_error_code(404, "not_found")
        if too_large:
            return self._send_error_code(413, "payload_too_large")
        state = self.server.owner.key_state(self.headers.get("X-FB3D-Key"))
        if state == "missing":
            return self._send_error_code(401, "key_missing")
        if state == "wrong":
            return self._send_error_code(403, "key_rejected")
        caller = self.headers.get("X-FB3D-Version", "")
        if not version_compare.is_valid(caller) or not is_valid_build(self.headers.get("X-FB3D-Build", "")):
            return self._send_error_code(400, "bad_request")
        method, answer = route
        if self.command != method:
            return self._send_error_code(405, "method_not_allowed", {"Allow": method})
        status, body = answer(self.server.owner, caller)
        return self._send_json(status, body)

    def _drop(self):
        """Close without a word. The request was read, so the client sees a connection that ended, not a refusal."""
        self.close_connection = True
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass

    # ---------------------------------------------------------------- control calls (not counted)

    def _control(self, name: str):
        owner = self.server.owner
        length = self._content_length()
        if length > MAX_CONTROL_BODY:
            self._send_error_code(413, "payload_too_large")
            return
        raw = self.rfile.read(length) if length > 0 else b""
        if self.command == "GET" and name == "stats":
            self._send_json(200, owner.stats())
            return
        if self.command != "POST" or name not in ("reset", "scenario", "stop"):
            self._send_error_code(404, "not_found")
            return
        fields = {}
        if raw.strip() != b"":
            try:
                fields = json.loads(raw.decode("utf-8"))
            except ValueError:
                fields = None
            if not isinstance(fields, dict):
                self._send_error_code(400, "bad_request")
                return
        if name == "reset":
            owner.reset()
            self._send_json(200, owner.settings())
        elif name == "stop":
            self._send_json(200, {"stopping": True})
            owner.request_stop()
        else:
            problem = owner.set_scenario(fields)
            if problem != "":
                body = error_body("bad_request")
                body["error"]["message"] = problem
                self._send_json(400, body)
            else:
                self._send_json(200, owner.settings())

    # ---------------------------------------------------------------- writing answers

    def _content_length(self) -> int:
        try:
            return max(0, int(self.headers.get("Content-Length", "0")))
        except ValueError:
            return 0

    def _send_error_code(self, status: int, code: str, extra=None) -> int:
        return self._send_json(status, error_body(code), extra)

    def _send_json(self, status: int, body: dict, extra=None) -> int:
        return self._send_bytes(status, json.dumps(body).encode("utf-8"), extra)

    def _send_bytes(self, status: int, data: bytes, extra=None) -> int:
        self.close_connection = True
        if getattr(self, "request_version", "HTTP/0.9") == "HTTP/0.9":
            # http.server writes no status line and no headers for a request it takes for HTTP/0.9, which is also what
            # a request it cannot read looks like. The answer is always a full HTTP/1.1 one.
            self.request_version = "HTTP/1.1"
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")
        for name, value in (extra or {}).items():
            self.send_header(name, value)
        self.end_headers()
        if getattr(self, "command", "") != "HEAD":
            self.wfile.write(data)
        return status


class FakeApiServer:
    """The server and its state. Use it from Python (the self-test does) or through main()."""

    def __init__(
        self, key: str = "", port: int = 0, lifetime: float = 0.0, verbose: bool = False, ready_file: str = ""
    ):
        self.key = key if key != "" else make_test_key()
        self.port = port
        self._lifetime = lifetime
        self._verbose = verbose
        self._ready_file = ready_file
        self._key_bytes = self.key.encode("utf-8")
        self._lock = threading.Lock()
        self._stopping = threading.Event()
        self._stopped = threading.Event()
        self._stop_started = False
        self._server = None
        self._thread = None
        self._start = {
            "scenario": DEFAULT_SCENARIO,
            "delay_seconds": DEFAULT_DELAY,
            "release_version": DEFAULT_RELEASE,
            "minimum_version": DEFAULT_MINIMUM,
        }
        self._settings = dict(self._start)
        self._count = 0
        self._by_path = {}
        self._recent = deque(maxlen=RECENT_LIMIT)

    @property
    def root_url(self) -> str:
        return "http://" + HOST + ":" + str(self.port) + "/"

    @property
    def base_url(self) -> str:
        return self.root_url + API_PREFIX.lstrip("/")

    # ---------------------------------------------------------------- life

    def start(self) -> None:
        self._server = _Server((HOST, self.port), _Handler)
        self._server.owner = self
        self.port = self._server.server_address[1]
        self._thread = threading.Thread(target=self._server.serve_forever, kwargs={"poll_interval": 0.1}, daemon=True)
        self._thread.start()
        if self._lifetime > 0:
            timer = threading.Timer(self._lifetime, self.stop)
            timer.daemon = True
            timer.start()
        if self._ready_file != "":
            self._write_ready_file()

    def stop(self) -> None:
        with self._lock:
            if self._stop_started:
                return
            self._stop_started = True
        self._stopping.set()
        if self._server is not None:
            self._server.shutdown()
            self._server.server_close()
        if self._ready_file != "":
            try:
                os.remove(self._ready_file)
            except OSError:
                pass
        self._stopped.set()

    def request_stop(self) -> None:
        """For the stop call: ends the server from another thread, after the answer was written."""
        threading.Thread(target=self.stop, daemon=True).start()

    def wait_stopped(self, seconds: float) -> bool:
        return self._stopped.wait(seconds)

    def pause(self, seconds: float) -> None:
        """The slow scenario's wait; ends early when the server is being stopped."""
        self._stopping.wait(seconds)

    def _write_ready_file(self) -> None:
        info = {"port": self.port, "base_url": self.base_url, "root_url": self.root_url, "key": self.key, "pid": os.getpid()}
        temporary = self._ready_file + ".tmp"
        with open(temporary, "w", encoding="utf-8") as ready:
            json.dump(info, ready)
        os.replace(temporary, self._ready_file)

    # ---------------------------------------------------------------- state

    def key_state(self, provided) -> str:
        if provided is None or provided == "":
            return "missing"
        if hmac.compare_digest(provided.encode("utf-8"), self._key_bytes):
            return "ok"
        return "wrong"

    def settings(self) -> dict:
        with self._lock:
            return dict(self._settings)

    def behaviour(self) -> tuple:
        with self._lock:
            return self._settings["scenario"], float(self._settings["delay_seconds"])

    def set_scenario(self, fields: dict) -> str:
        """Changes the settings named in `fields`; "" when done, else why not (nothing is changed then)."""
        for name in fields:
            if name not in self._settings:
                return "unknown field"
        changed = dict(self._settings)
        if "scenario" in fields:
            if not isinstance(fields["scenario"], str) or fields["scenario"] not in SCENARIOS:
                return "scenario must be one of: " + ", ".join(SCENARIOS)
            changed["scenario"] = fields["scenario"]
        if "delay_seconds" in fields:
            delay = fields["delay_seconds"]
            if isinstance(delay, bool) or not isinstance(delay, (int, float)) or not 0 <= delay <= MAX_DELAY:
                return "delay_seconds must be a number from 0 to " + str(int(MAX_DELAY))
            changed["delay_seconds"] = float(delay)
        if "release_version" in fields:
            release = fields["release_version"]
            if release is not None and (not isinstance(release, str) or not version_compare.is_valid(release)):
                return "release_version must be a valid version or null"
            changed["release_version"] = release
        if "minimum_version" in fields:
            minimum = fields["minimum_version"]
            if not isinstance(minimum, str) or not version_compare.is_valid(minimum):
                return "minimum_version must be a valid version"
            changed["minimum_version"] = minimum
        with self._lock:
            self._settings = changed
        return ""

    def keep_settings_as_start(self) -> None:
        """The command line options become the settings that `reset` goes back to."""
        with self._lock:
            self._start = dict(self._settings)

    def reset(self) -> None:
        with self._lock:
            self._settings = dict(self._start)
            self._count = 0
            self._by_path = {}
            self._recent.clear()

    def begin_request(self, method: str, path: str, scenario: str, seen: dict) -> dict:
        shown = safe_text(path, 128)
        # the path below the base path ("releases/current"); a path outside it is shown whole
        name = shown[len(API_PREFIX) :] if shown.startswith(API_PREFIX) else shown
        with self._lock:
            self._count += 1
            counted = name
            if counted not in self._by_path and len(self._by_path) >= MAX_PATH_KEYS:
                counted = "(other)"
            self._by_path[counted] = self._by_path.get(counted, 0) + 1
            entry = {"n": self._count, "method": safe_text(method, 16), "path": name, "scenario": scenario, "status": None}
            entry.update(seen)
            self._recent.append(entry)
            return entry

    def finish_request(self, entry: dict, status: int) -> None:
        with self._lock:
            entry["status"] = status
        if self._verbose:
            print(
                "fake api: %s %s -> %d (%s)" % (entry["method"], entry["path"], status, entry["scenario"]),
                flush=True,
            )

    def stats(self) -> dict:
        with self._lock:
            body = dict(self._settings)
            body["requests"] = self._count
            body["by_path"] = dict(self._by_path)
            body["recent"] = [dict(entry) for entry in self._recent]
            return body


# ------------------------------------------------------------------------------------------- command line


def parse_arguments(argv):
    parser = argparse.ArgumentParser(description="A pretend website for the game's web checks (roadmap V4.2).")
    parser.add_argument("--self-test", action="store_true", help="test the server itself and stop")
    parser.add_argument("--port", type=int, default=0, help="port on 127.0.0.1 (default: a free one)")
    parser.add_argument("--key", default="", help="the key to accept (by hand; a check uses --ready-file instead)")
    parser.add_argument("--ready-file", default="", help="write the port and the key here as JSON once it listens")
    parser.add_argument("--lifetime", type=float, default=DEFAULT_LIFETIME, help="stop by itself after N seconds (0 = never)")
    parser.add_argument("--scenario", default=DEFAULT_SCENARIO, choices=SCENARIOS)
    parser.add_argument("--delay", type=float, default=DEFAULT_DELAY, help="seconds for the slow scenario")
    parser.add_argument("--release", default=DEFAULT_RELEASE, help='the published release version, or "none"')
    parser.add_argument("--minimum", default=DEFAULT_MINIMUM, help="the minimum supported version")
    parser.add_argument("--verbose", action="store_true", help="one line per request (never a header or a body)")
    return parser.parse_args(argv)


def main(argv=None) -> int:
    args = parse_arguments(sys.argv[1:] if argv is None else argv)
    if args.self_test:
        return self_test()
    problem = ""
    if args.key == "" and args.ready_file == "":
        problem = "give --key KEY or --ready-file PATH, so that somebody knows the key (it is never printed)"
    elif args.key != "":
        problem = check_key_text(args.key)
    if problem == "" and not 1 <= args.port <= 65535 and args.port != 0:
        problem = "--port must be 0 or 1 to 65535"
    start = {
        "scenario": args.scenario,
        "delay_seconds": args.delay,
        "release_version": None if args.release == "none" else args.release,
        "minimum_version": args.minimum,
    }
    server = FakeApiServer(args.key, args.port, max(0.0, args.lifetime), args.verbose, args.ready_file)
    if problem == "":
        problem = server.set_scenario(start)
        server.keep_settings_as_start()
    if problem != "":
        print("fake api server: " + problem, file=sys.stderr)
        return 2
    try:
        server.start()
    except OSError as error:
        print("fake api server: cannot listen (" + type(error).__name__ + ")", file=sys.stderr)
        return 2
    print(
        "fake api server: listening on %s (scenario %s); the key is not printed" % (server.base_url, args.scenario),
        flush=True,
    )
    try:
        while not server.wait_stopped(0.5):
            pass
    except KeyboardInterrupt:
        server.stop()
    return 0


# ------------------------------------------------------------------------------------------- self-test


def _call(port: int, method: str, path: str, headers=None, body=None, timeout: float = 5.0) -> tuple:
    """One request. Returns (status, headers, bytes)."""
    connection = http.client.HTTPConnection(HOST, port, timeout=timeout)
    try:
        sent = dict(headers or {})
        payload = None
        if body is not None:
            payload = json.dumps(body).encode("utf-8")
            sent["Content-Type"] = "application/json"
        connection.request(method, path, body=payload, headers=sent)
        response = connection.getresponse()
        return response.status, dict(response.getheaders()), response.read()
    finally:
        connection.close()


def _json(data: bytes):
    try:
        return json.loads(data.decode("utf-8"))
    except ValueError:
        return None


def _raw(port: int, text: str, timeout: float = 5.0) -> bytes:
    """Sends text as it is and returns everything the server wrote before it closed."""
    connection = socket.create_connection((HOST, port), timeout=timeout)
    try:
        connection.sendall(text.encode("ascii"))
        chunks = []
        while True:
            try:
                part = connection.recv(4096)
            except socket.timeout:
                break
            if not part:
                break
            chunks.append(part)
        return b"".join(chunks)
    finally:
        connection.close()


def self_test() -> int:
    problems = []

    def expect(name: str, condition: bool) -> None:
        if condition:
            print("  ok    " + name)
        else:
            print("  FAIL  " + name)
            problems.append(name)

    server = FakeApiServer(lifetime=120.0)
    server.start()
    threads_while_running = threading.active_count()  # the server's thread and its lifetime timer
    port = server.port
    key = server.key
    bearer = secrets.token_urlsafe(24)

    def good(version: str = "0.3.0", build: str = "a1b2c3d") -> dict:
        return {"X-FB3D-Key": key, "X-FB3D-Version": version, "X-FB3D-Build": build}

    def api(method: str, route: str, headers=None, body=None, timeout: float = 5.0) -> tuple:
        status, response_headers, data = _call(port, method, API_PREFIX + route, headers, body, timeout)
        return status, response_headers, _json(data)

    def control(method: str, name: str, body=None) -> tuple:
        status, _, data = _call(port, method, CONTROL_PREFIX + name, None, body)
        return status, _json(data)

    def is_error(answer, code: str) -> bool:
        return (
            isinstance(answer, dict)
            and list(answer.keys()) == ["error"]
            and sorted(answer["error"].keys()) == ["code", "message", "retry_after"]
            and answer["error"]["code"] == code
            and answer["error"]["retry_after"] is None
            and isinstance(answer["error"]["message"], str)
            and key not in answer["error"]["message"]
        )

    try:
        # ---- the server itself
        expect("it listens on this computer only", server._server.server_address[0] == HOST)
        expect("the key is made up for this run and has the test prefix", key.startswith(KEY_PREFIX) and len(key) > 40)
        expect("two servers do not share a key", make_test_key() != make_test_key())
        expect("the key is never the shape of a real game key", not key.startswith(REAL_KEY_PREFIX))
        expect("a key of the real shape is refused for --key", check_key_text(REAL_KEY_PREFIX + "x" * 43) != "")
        expect("a key with a space is refused for --key", check_key_text("a b") != "")
        expect("an empty key is refused for --key", check_key_text("") != "")
        expect("a key the game would ignore as a template is refused for --key", check_key_text("Fake-key-1") != "")
        expect("a normal key is accepted for --key", check_key_text("my-own-test-value") == "")

        # ---- ping, the honest answer
        status, headers, answer = api("GET", "ping", good())
        expect("ping: 200", status == 200)
        expect("ping: JSON content type", headers.get("Content-Type") == "application/json")
        expect(
            "ping: the fields of docs/WEBSITE_API.md",
            isinstance(answer, dict)
            and sorted(answer.keys()) == ["api_version", "server_time", "status", "update"]
            and answer["status"] == "ok"
            and answer["api_version"] == 1,
        )
        try:
            datetime.strptime(answer["server_time"], "%Y-%m-%dT%H:%M:%SZ")
            time_ok = True
        except (TypeError, ValueError, KeyError):
            time_ok = False
        expect("ping: server_time is UTC ISO 8601 with a Z", time_ok)
        expect("ping: a query string is ignored", api("GET", "ping?x=1", good())[0] == 200)
        expect("ping: a dirty build is accepted", api("GET", "ping", good(build="a1b2c3d+"))[0] == 200)
        expect("ping: the dev build is accepted", api("GET", "ping", good(build="dev"))[0] == 200)

        # ---- releases/current and the update state
        control("POST", "scenario", {"release_version": "0.3.1", "minimum_version": "0.3.0"})
        for caller, expected in (
            ("0.2.0", "required"),
            ("0.3.0-alpha", "required"),
            ("0.3.0", "available"),
            ("0.3.1", "none"),
            ("0.3.2", "none"),
            ("0.4.0", "none"),
            ("0.10.0", "none"),
        ):
            expect(
                "update for " + caller + " is " + expected + " (release 0.3.1, minimum 0.3.0)",
                api("GET", "releases/current", good(caller))[2]["update"] == expected
                and api("GET", "ping", good(caller))[2]["update"] == expected,
            )
        release = api("GET", "releases/current", good("0.3.0"))[2]
        current = release["current"]
        expect("release: the fields of docs/WEBSITE_API.md", sorted(release.keys()) == ["current", "minimum_version", "update"])
        expect(
            "release: the release object has every field",
            sorted(current.keys())
            == ["channel", "commit", "download_url", "file_name", "notes", "published_utc", "sha256", "size", "version"],
        )
        expect("release: version, minimum and size", current["version"] == "0.3.1" and release["minimum_version"] == "0.3.0" and current["size"] == RELEASE_SIZE)
        expect("release: commit is 40 hex characters", len(current["commit"]) == 40 and set(current["commit"]) <= set("0123456789abcdef"))
        expect("release: sha256 is 64 hex characters", len(current["sha256"]) == 64 and set(current["sha256"]) <= set("0123456789abcdef"))
        expect("release: the file name carries the version and the short commit", current["file_name"] == "FB3D-0.3.1-" + current["commit"][:7] + ".exe")
        expect("release: the download address points at this server", current["download_url"].startswith(server.root_url + "media/fb3d/releases/"))
        control("POST", "scenario", {"release_version": None})
        release = api("GET", "releases/current", good("0.3.0"))[2]
        expect("no release: current is null", release["current"] is None)
        expect("no release: nothing is available", release["update"] == "none")
        expect("no release: the minimum still applies", api("GET", "ping", good("0.2.0"))[2]["update"] == "required")
        control("POST", "reset")
        expect("reset: the start settings are back", control("GET", "stats")[1]["release_version"] == DEFAULT_RELEASE)

        # ---- the order of the checks and the error shape
        status, _, answer = api("GET", "ping", {"X-FB3D-Version": "0.3.0", "X-FB3D-Build": "a1b2c3d"})
        expect("no key: 401 key_missing", status == 401 and is_error(answer, "key_missing"))
        wrong = good()
        wrong["X-FB3D-Key"] = key + "x"
        status, _, answer = api("GET", "ping", wrong)
        expect("wrong key: 403 key_rejected", status == 403 and is_error(answer, "key_rejected"))
        wrong["X-FB3D-Key"] = key[:-1]
        expect("a cut key: 403 key_rejected", api("GET", "ping", wrong)[0] == 403)
        empty = good()
        empty["X-FB3D-Key"] = ""
        expect("an empty key: 401 key_missing", api("GET", "ping", empty)[0] == 401)
        expect("no key and no version: key_missing comes first", is_error(api("GET", "ping")[2], "key_missing"))
        expect("no key, wrong method: key_missing comes first", is_error(api("POST", "ping", None, {})[2], "key_missing"))
        for name, version, build in (
            ("missing", None, "a1b2c3d"),
            ("empty", "", "a1b2c3d"),
            ("with a v", "v0.3.0", "a1b2c3d"),
            ("with two parts", "0.3", "a1b2c3d"),
            ("with build metadata", "0.3.0+abc", "a1b2c3d"),
            ("with a leading zero", "0.03.0", "a1b2c3d"),
        ):
            sent = {"X-FB3D-Key": key, "X-FB3D-Build": build}
            if version is not None:
                sent["X-FB3D-Version"] = version
            status, _, answer = api("GET", "ping", sent)
            expect("a version " + name + ": 400 bad_request", status == 400 and is_error(answer, "bad_request"))
        sent = {"X-FB3D-Key": key, "X-FB3D-Version": "0.3.0"}
        expect("no build header: 400 bad_request", is_error(api("GET", "ping", sent)[2], "bad_request"))
        sent["X-FB3D-Build"] = "A B"
        expect("a malformed build header: 400 bad_request", is_error(api("GET", "ping", sent)[2], "bad_request"))
        status, response_headers, answer = api("POST", "ping", good(), {})
        expect("wrong method: 405 method_not_allowed with Allow", status == 405 and is_error(answer, "method_not_allowed") and response_headers.get("Allow") == "GET")
        expect("PUT on releases/current: 405", api("PUT", "releases/current", good(), {})[0] == 405)
        status, _, answer = api("GET", "nothing/here", good())
        expect("unknown path: 404 not_found", status == 404 and is_error(answer, "not_found"))
        expect("unknown path needs no key", api("GET", "nothing/here")[0] == 404)
        expect("a trailing slash is another path: 404", api("GET", "ping/", good())[0] == 404)
        status, _, data = _call(port, "GET", "/", good())
        expect("a path outside the base path: 404 JSON", status == 404 and is_error(_json(data), "not_found"))
        status, _, data = _call(port, "TRACE", API_PREFIX + "ping", good())
        expect("a method the server does not know: 405 JSON, no HTML", status == 405 and is_error(_json(data), "method_not_allowed"))
        text = _raw(port, "POST " + API_PREFIX + "ping HTTP/1.1\r\nHost: x\r\nContent-Length: 999999\r\n\r\n")
        expect("a body over the hard limit: 413 payload_too_large, unread and without a key", b" 413 " in text.split(b"\r\n")[0] and b"payload_too_large" in text)
        text = _raw(port, "NOT A REQUEST\r\n\r\n")
        expect("a request that cannot be read: 400 JSON, no HTML", b" 400 " in text.split(b"\r\n")[0] and b"bad_request" in text and b"<html" not in text.lower())

        # ---- the failing scenarios
        control("POST", "reset")
        expect("control: an unknown scenario is refused", control("POST", "scenario", {"scenario": "nope"})[0] == 400)
        expect("control: an unknown field is refused", control("POST", "scenario", {"colour": "red"})[0] == 400)
        expect("control: a delay over the limit is refused", control("POST", "scenario", {"delay_seconds": MAX_DELAY + 1})[0] == 400)
        expect("control: a negative delay is refused", control("POST", "scenario", {"delay_seconds": -1})[0] == 400)
        expect("control: a delay that is a boolean is refused", control("POST", "scenario", {"delay_seconds": True})[0] == 400)
        expect("control: an invalid release version is refused", control("POST", "scenario", {"release_version": "v1"})[0] == 400)
        expect("control: an invalid minimum version is refused", control("POST", "scenario", {"minimum_version": None})[0] == 400)
        expect("control: a body that is not an object is refused", control("POST", "scenario", [1])[0] == 400)
        expect("control: a refused call changes nothing", control("GET", "stats")[1]["scenario"] == "current")
        expect("control: an unknown control path is 404", control("GET", "nothing")[0] == 404)
        expect("control: stats needs GET", control("POST", "stats", {})[0] == 404)

        control("POST", "scenario", {"scenario": "wrong_key"})
        status, _, answer = api("GET", "ping", good())
        expect("wrong_key: 403 key_rejected even with the right key", status == 403 and is_error(answer, "key_rejected"))
        control("POST", "scenario", {"scenario": "server_error"})
        status, _, answer = api("GET", "releases/current", good())
        expect("server_error: 500 server_error in the one error shape", status == 500 and is_error(answer, "server_error"))
        control("POST", "scenario", {"scenario": "damaged_json"})
        status, _, data = _call(port, "GET", API_PREFIX + "releases/current", good())
        expect("damaged_json: 200 with a body that is not JSON", status == 200 and len(data) > 10 and _json(data) is None)
        control("POST", "scenario", {"scenario": "dead_connection"})
        try:
            _call(port, "GET", API_PREFIX + "ping", good())
            dropped = False
        except (http.client.HTTPException, ConnectionError, OSError):
            dropped = True
        expect("dead_connection: the connection ends without an answer", dropped)

        control("POST", "scenario", {"scenario": "slow", "delay_seconds": 0.5})
        began = time.monotonic()
        status, _, answer = api("GET", "ping", good())
        waited = time.monotonic() - began
        expect("slow: the honest answer comes after the delay", status == 200 and answer["status"] == "ok" and 0.45 <= waited < 4.0)
        control("POST", "scenario", {"scenario": "slow", "delay_seconds": 30})
        began = time.monotonic()
        try:
            api("GET", "ping", good(), None, 0.4)
            timed_out = False
        except (socket.timeout, TimeoutError):
            timed_out = True
        expect("slow: a client with a short timeout gives up on time", timed_out and time.monotonic() - began < 3.0)
        began = time.monotonic()
        stats_while_waiting = control("GET", "stats")
        expect("slow: the server still answers while one call waits", stats_while_waiting[0] == 200 and time.monotonic() - began < 2.0)

        # ---- what it counts, and what it never keeps
        control("POST", "reset")
        api("GET", "ping", good())
        api("GET", "releases/current", good("0.3.1", "dev"))
        api("GET", "releases/current", {"X-FB3D-Version": "0.3.0", "X-FB3D-Build": "a1b2c3d"})
        wrong_key = good()
        wrong_key["X-FB3D-Key"] = "not-the-key"
        api("GET", "ping", wrong_key)
        with_token = good()
        with_token["Authorization"] = "Bearer " + bearer
        api("GET", "ping", with_token)
        api("GET", "nothing/here", good())
        control("POST", "scenario", {"scenario": "dead_connection"})
        try:
            _call(port, "GET", API_PREFIX + "ping", good())
        except (http.client.HTTPException, ConnectionError, OSError):
            pass
        control("POST", "scenario", {"scenario": "current"})
        report = control("GET", "stats")[1]
        expect("stats: seven requests, control calls are not counted", report["requests"] == 7)
        expect("stats: a count per path", report["by_path"] == {"ping": 4, "releases/current": 2, "nothing/here": 1})
        recent = report["recent"]
        expect("stats: one record per request, in order", [entry["n"] for entry in recent] == [1, 2, 3, 4, 5, 6, 7])
        expect("stats: the version and the build the game sent", recent[1]["version"] == "0.3.1" and recent[1]["build"] == "dev" and recent[0]["build"] == "a1b2c3d")
        expect("stats: the key was ok, missing or wrong", [entry["key"] for entry in recent[:4]] == ["ok", "ok", "missing", "wrong"])
        expect("stats: a token is noted as present, never kept", recent[4]["has_token"] is True and recent[0]["has_token"] is False)
        expect("stats: the names of the headers that came", "x-fb3d-key" in recent[0]["header_names"] and "authorization" in recent[4]["header_names"])
        expect("stats: the statuses sent", [entry["status"] for entry in recent] == [200, 200, 401, 403, 200, 404, 0])
        expect("stats: the scenario of each request", recent[0]["scenario"] == "current" and recent[6]["scenario"] == "dead_connection")
        everything = json.dumps(report)
        expect("stats: no key, wrong key or token anywhere", key not in everything and "not-the-key" not in everything and bearer not in everything)
        for number in range(RECENT_LIMIT + 5):
            api("GET", "ping", good())
        expect("stats: only the last 100 requests are kept", len(control("GET", "stats")[1]["recent"]) == RECENT_LIMIT)
        for number in range(MAX_PATH_KEYS + 5):
            api("GET", "unknown/" + str(number), good())
        expect("stats: the number of paths is limited", len(control("GET", "stats")[1]["by_path"]) <= MAX_PATH_KEYS + 1)
        expect("stats: the total is exact", control("GET", "stats")[1]["requests"] == 7 + RECENT_LIMIT + 5 + MAX_PATH_KEYS + 5)
        control("POST", "reset")
        expect("reset: the counters are zero", control("GET", "stats")[1]["requests"] == 0 and control("GET", "stats")[1]["recent"] == [])
    finally:
        began = time.monotonic()
        server.stop()
        expect("stop: it ends at once even with a slow call still waiting", time.monotonic() - began < 3.0)
        expect("stop: nothing listens afterwards", _refused(port))
        # The slow call (30 s) that was still waiting must be woken by the stop, or a handler thread outlives the server.
        wait_until = time.monotonic() + 3.0
        while threading.active_count() >= threads_while_running and time.monotonic() < wait_until:
            time.sleep(0.05)
        expect("stop: no handler thread is left behind", threading.active_count() < threads_while_running)

    # ---- as a program, the way a check starts it
    folder = tempfile.mkdtemp(prefix="fb3d_fake_api_")
    try:
        script = os.path.abspath(__file__)
        ready = os.path.join(folder, "ready.json")
        process = subprocess.Popen(
            [sys.executable, script, "--ready-file", ready, "--lifetime", "60", "--verbose"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        info = _wait_for_file(ready, 20.0)
        expect("program: the ready file appears", info is not None)
        if info is not None:
            expect(
                "program: the ready file holds port, addresses, key and pid",
                sorted(info.keys()) == ["base_url", "key", "pid", "port", "root_url"]
                and info["base_url"] == "http://127.0.0.1:" + str(info["port"]) + API_PREFIX
                and info["root_url"] == "http://127.0.0.1:" + str(info["port"]) + "/"
                and info["pid"] == process.pid,
            )
            sent = {"X-FB3D-Key": info["key"], "X-FB3D-Version": "0.3.0", "X-FB3D-Build": "a1b2c3d", "Authorization": "Bearer " + bearer}
            status, _, data = _call(info["port"], "GET", API_PREFIX + "ping", sent)
            expect("program: it answers a call with the key from the ready file", status == 200)
            status, _, data = _call(info["port"], "POST", CONTROL_PREFIX + "stop", None, {})
            expect("program: the stop call is answered", status == 200 and _json(data) == {"stopping": True})
        try:
            code = process.wait(10.0)
        except subprocess.TimeoutExpired:
            process.kill()
            code = -1
        out, err = process.communicate()
        expect("program: it ends with 0 after the stop call", code == 0)
        expect("program: the ready file is removed", not os.path.exists(ready))
        expect("program: the log line shows the call", b"GET ping -> 200" in out)
        expect("program: nothing it printed holds the key or the token", info is not None and info["key"].encode() not in out + err and bearer.encode() not in out + err)

        process = subprocess.Popen(
            [sys.executable, script, "--ready-file", ready, "--lifetime", "1.5"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        try:
            code = process.wait(15.0)
        except subprocess.TimeoutExpired:
            process.kill()
            code = -1
        process.communicate()
        expect("program: it ends by itself after its lifetime", code == 0)

        for name, extra in (
            ("without a key and a ready file", []),
            ("with a key of the real shape", ["--key", REAL_KEY_PREFIX + "x" * 43]),
            ("with an invalid release version", ["--ready-file", ready, "--release", "v1"]),
            ("with an unknown scenario", ["--ready-file", ready, "--scenario", "nope"]),
        ):
            result = subprocess.run([sys.executable, script] + extra, capture_output=True, timeout=30)
            expect("program: " + name + " it refuses to start (2)", result.returncode == 2 and b"x" * 43 not in result.stderr + result.stdout)

        process = subprocess.Popen(
            [sys.executable, script, "--ready-file", ready, "--lifetime", "60", "--scenario", "server_error", "--release", "none", "--minimum", "0.2.0"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        info = _wait_for_file(ready, 20.0)
        if info is not None:
            started = _json(_call(info["port"], "GET", CONTROL_PREFIX + "stats")[2])
            expect(
                "program: the start options set the scenario and the versions",
                started["scenario"] == "server_error" and started["release_version"] is None and started["minimum_version"] == "0.2.0",
            )
            _call(info["port"], "POST", CONTROL_PREFIX + "reset", None, {})
            reset = _json(_call(info["port"], "GET", CONTROL_PREFIX + "stats")[2])
            expect("program: reset goes back to the start options, not to the built-in ones", reset["scenario"] == "server_error" and reset["minimum_version"] == "0.2.0")
        else:
            expect("program: it started with the start options", False)
        process.kill()
        process.communicate()
    finally:
        for name in os.listdir(folder):
            os.remove(os.path.join(folder, name))
        os.rmdir(folder)

    if problems:
        print("SELF-TEST FAILED: " + str(len(problems)) + " problem(s)")
        return 1
    print("SELF-TEST PASSED")
    return 0


def _refused(port: int) -> bool:
    try:
        socket.create_connection((HOST, port), timeout=1.0).close()
    except OSError:
        return True
    return False


def _wait_for_file(path: str, seconds: float):
    """The JSON in `path` once it exists and is complete, else None."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if os.path.exists(path):
            try:
                with open(path, encoding="utf-8") as opened:
                    return json.load(opened)
            except (OSError, ValueError):
                pass
        time.sleep(0.05)
    return None


if __name__ == "__main__":
    sys.exit(main())
