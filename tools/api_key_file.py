#!/usr/bin/env python3
"""Writes and reads api_key.bin, the file that carries the game's API key into an exported build (roadmap V4.1).

    python tools/api_key_file.py --self-test     check the format against tools/api_key_file_cases.json and more

Who uses it: tools/build_release.py writes the file from the environment variables FB3D_API_KEY and FB3D_API_BASE_URL
just before the export and deletes it again afterwards. The game reads it with scripts/api_key_file.gd.
The file is generated and never tracked (`api_key.*` in .gitignore), and `api_key.bin` is in the export preset's
include_filter so that it ends up in the exe.

THIS IS OBFUSCATION, NOT PROTECTION. The goal (Milestone N "Store the key encrypted") is that the key is not a readable
string inside the exe, a script or project.godot, so a text search or a casual look does not find it. Anyone who
runs the game and has the file can get the key out, and docs/WEBSITE_API.md says so: the server never trusts the
key alone.

Format, version 1 (the same rules are in scripts/api_key_file.gd; both are tested against the same cases file):
    bytes 0-3     the letters FB3K
    byte  4       the format version, 1
    bytes 5-20    nonce, 16 random bytes
    bytes 21-..   the text, UTF-8 JSON {"base_url": "...", "key": "..."}, XOR the key stream
    last 8 bytes  check: the first 8 bytes of SHA-256(SALT + nonce + plain text), so a damaged file is noticed
The key stream is SHA-256(SALT + nonce + block number as 4 bytes, big endian) for block 0, 1, 2 ... (32 bytes each).
SALT is the ASCII text in SALT below; it is public on purpose.

Only the Python standard library is used, so it runs on Windows too. Exit code: 0 = ok, 1 = self-test failed.
"""

import hashlib
import json
import os
import re
import secrets
import struct
import sys
import tempfile

OUTPUT_NAME = "api_key.bin"
CASES_NAME = "api_key_file_cases.json"
MAGIC = b"FB3K"
FORMAT_VERSION = 1
NONCE_LENGTH = 16
MAC_LENGTH = 8
SALT = b"fb3d-api-key-file-v1"
BLOCK_LENGTH = 32
HEADER_LENGTH = len(MAGIC) + 1 + NONCE_LENGTH
MAX_FILE = 2048

# What the real key looks like (docs/WEBSITE_API.md, "As built (V3.4)"): fb3dk_ and 43 URL-safe characters.
KEY_PATTERN = re.compile(r"^fb3dk_[A-Za-z0-9_-]{43}$")
PLACEHOLDER_WORDS = ["fake", ".invalid", "replace-me"]
MAX_URL_LENGTH = 256


class ApiKeyFileError(Exception):
    """The key file cannot be made or read."""


def key_stream(nonce: bytes, length: int) -> bytes:
    stream = b""
    block = 0
    while len(stream) < length:
        stream += hashlib.sha256(SALT + nonce + struct.pack(">I", block)).digest()
        block += 1
    return stream[:length]


def xor_bytes(data: bytes, stream: bytes) -> bytes:
    out = bytearray()
    for index in range(len(data)):
        out.append(data[index] ^ stream[index])
    return bytes(out)


def encode(base_url: str, key: str, nonce: bytes = b"") -> bytes:
    """The bytes of the file. No checks of the values here (see check_values); a test may give a fixed nonce."""
    if nonce == b"":
        nonce = secrets.token_bytes(NONCE_LENGTH)
    if len(nonce) != NONCE_LENGTH:
        raise ApiKeyFileError("the nonce must be " + str(NONCE_LENGTH) + " bytes")
    plain = json.dumps({"base_url": base_url, "key": key}, separators=(",", ":")).encode("utf-8")
    cipher = xor_bytes(plain, key_stream(nonce, len(plain)))
    mac = hashlib.sha256(SALT + nonce + plain).digest()[:MAC_LENGTH]
    return MAGIC + bytes([FORMAT_VERSION]) + nonce + cipher + mac


def decode(data: bytes) -> dict:
    """{"base_url": ..., "key": ...}, or ApiKeyFileError when the file is damaged."""
    if len(data) > MAX_FILE or len(data) < HEADER_LENGTH + 2 + MAC_LENGTH:
        raise ApiKeyFileError("the file has a wrong size")
    if data[:4] != MAGIC or data[4] != FORMAT_VERSION:
        raise ApiKeyFileError("the file is not a version " + str(FORMAT_VERSION) + " key file")
    nonce = data[5:HEADER_LENGTH]
    cipher = data[HEADER_LENGTH:-MAC_LENGTH]
    mac = data[-MAC_LENGTH:]
    plain = xor_bytes(cipher, key_stream(nonce, len(cipher)))
    if hashlib.sha256(SALT + nonce + plain).digest()[:MAC_LENGTH] != mac:
        raise ApiKeyFileError("the check of the file does not match")
    try:
        table = json.loads(plain.decode("utf-8"))
    except ValueError:
        raise ApiKeyFileError("the text of the file is not JSON")
    if not isinstance(table, dict) or not isinstance(table.get("base_url"), str) or not isinstance(table.get("key"), str):
        raise ApiKeyFileError("the text of the file has the wrong shape")
    return {"base_url": table["base_url"], "key": table["key"]}


def is_placeholder(text: str) -> bool:
    lowered = text.strip().lower()
    for word in PLACEHOLDER_WORDS:
        if word in lowered:
            return True
    return lowered == ""


def check_values(base_url: str, key: str) -> None:
    """Refuses a key or an address that cannot be right, so a typo is found at build time and not on a player's PC."""
    if is_placeholder(key) or KEY_PATTERN.match(key) is None:
        raise ApiKeyFileError("FB3D_API_KEY does not look like a game key (fb3dk_ and 43 characters)")
    if is_placeholder(base_url) or len(base_url) > MAX_URL_LENGTH:
        raise ApiKeyFileError("FB3D_API_BASE_URL is empty, too long or still a template value")
    if not base_url.startswith("https://") or not base_url.endswith("/"):
        raise ApiKeyFileError("FB3D_API_BASE_URL must start with https:// and end with / (the version path)")
    host = base_url[len("https://") :].split("/")[0]
    forbidden = set(" \t\r\n\\@?#")
    if host == "" or any(c in forbidden for c in base_url):
        raise ApiKeyFileError("FB3D_API_BASE_URL has no host, or holds a space, @, ? or #")


def write_key_file(root: str, base_url: str, key: str, nonce: bytes = b"") -> str:
    """Checks the values, writes <root>/api_key.bin and returns its path."""
    check_values(base_url, key)
    path = os.path.join(root, OUTPUT_NAME)
    temp_path = path + ".tmp"
    with open(temp_path, "wb") as key_file:
        key_file.write(encode(base_url, key, nonce))
    os.replace(temp_path, path)
    return path


def remove_key_file(root: str) -> None:
    """Deletes the file if it is there (a build must never leave a key lying in the project folder)."""
    for name in [OUTPUT_NAME, OUTPUT_NAME + ".tmp"]:
        path = os.path.join(root, name)
        if os.path.isfile(path):
            os.remove(path)


def cases_path() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), CASES_NAME)


# ---------------------------------------------------------------- self-test


def self_test() -> int:
    problems = []

    def expect(name: str, condition: bool) -> None:
        if condition:
            print("  ok    " + name)
        else:
            print("  FAIL  " + name)
            problems.append(name)

    def expect_error(name: str, action) -> None:
        try:
            action()
        except ApiKeyFileError:
            expect(name, True)
            return
        expect(name, False)

    with open(cases_path(), encoding="utf-8") as cases_file:
        cases = json.load(cases_file)
    expect("the cases file has cases", len(cases["cases"]) >= 3)
    for case in cases["cases"]:
        nonce = bytes.fromhex(case["nonce_hex"])
        expected = bytes.fromhex(case["file_hex"])
        expect("case '" + case["name"] + "': encoding gives the stored bytes", encode(case["base_url"], case["key"], nonce) == expected)
        expect("case '" + case["name"] + "': decoding gives the values back", decode(expected) == {"base_url": case["base_url"], "key": case["key"]})

    # the key must not be readable in the file
    good_key = "fb3dk_" + "A" * 43
    good_url = "https://example.org/fb3d/api/v1/"
    data = encode(good_url, good_key)
    expect("the key is not a readable string in the file", good_key.encode() not in data and b"fb3dk_" not in data)
    expect("the address is not a readable string in the file", b"example.org" not in data)
    expect("two files with the same values differ (random nonce)", encode(good_url, good_key) != data)
    expect("the file is small", len(data) < MAX_FILE)

    first = bytearray(data)
    first[-1] ^= 1
    expect_error("a changed check byte is noticed", lambda: decode(bytes(first)))
    middle = bytearray(data)
    middle[HEADER_LENGTH + 3] ^= 1
    expect_error("a changed text byte is noticed", lambda: decode(bytes(middle)))
    expect_error("a cut file is noticed", lambda: decode(data[:-1]))
    expect_error("an empty file is noticed", lambda: decode(b""))
    expect_error("a wrong magic is noticed", lambda: decode(b"XXXX" + data[4:]))
    expect_error("a wrong format version is noticed", lambda: decode(data[:4] + bytes([2]) + data[5:]))
    expect_error("an oversized file is noticed", lambda: decode(data + b"0" * MAX_FILE))

    # a value with a quote, a backslash and non-ASCII text survives
    odd = decode(encode('https://x.org/a"b\\c/', "kčž"))
    expect("odd characters survive", odd == {"base_url": 'https://x.org/a"b\\c/', "key": "kčž"})

    # the values are checked before anything is written
    expect_error("a placeholder key is refused", lambda: check_values(good_url, "fake-key-replace-me-0000"))
    expect_error("a key of the wrong shape is refused", lambda: check_values(good_url, "fb3dk_short"))
    expect_error("an empty key is refused", lambda: check_values(good_url, ""))
    expect_error("a key with a newline is refused", lambda: check_values(good_url, good_key[:-1] + "\n"))
    expect_error("plain http is refused", lambda: check_values("http://example.org/fb3d/api/v1/", good_key))
    expect_error("an address without the closing slash is refused", lambda: check_values("https://example.org/fb3d/api/v1", good_key))
    expect_error("the template address is refused", lambda: check_values("https://fb3d.invalid/fb3d/api/v1/", good_key))
    expect_error("an address with a password in it is refused", lambda: check_values("https://user:pw@example.org/v1/", good_key))
    expect_error("an address with no host is refused", lambda: check_values("https:///v1/", good_key))
    check_values(good_url, good_key)

    work = tempfile.mkdtemp(prefix="fb3d_api_key_file_")
    try:
        path = write_key_file(work, good_url, good_key)
        expect("write: the file is named api_key.bin", os.path.basename(path) == OUTPUT_NAME)
        with open(path, "rb") as key_file:
            expect("write: the file reads back", decode(key_file.read()) == {"base_url": good_url, "key": good_key})
        expect("write: no temporary file is left", not os.path.exists(path + ".tmp"))
        remove_key_file(work)
        expect("remove: the file is gone", not os.path.exists(path))
        remove_key_file(work)
        expect("remove: a second remove does nothing", True)
        expect_error("write: a bad key writes nothing", lambda: write_key_file(work, good_url, "nope"))
        expect("write: a bad key leaves no file", not os.path.exists(path))
    finally:
        for name in os.listdir(work):
            os.remove(os.path.join(work, name))
        os.rmdir(work)

    if problems:
        print("SELF-TEST FAILED: " + str(len(problems)) + " problem(s)")
        return 1
    print("SELF-TEST PASSED")
    return 0


def main() -> int:
    if "--self-test" in sys.argv[1:]:
        return self_test()
    print(__doc__)
    return 0


if __name__ == "__main__":
    sys.exit(main())
