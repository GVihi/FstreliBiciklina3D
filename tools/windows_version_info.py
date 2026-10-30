#!/usr/bin/env python3
"""Fills the Windows file information of the export preset from the build info (roadmap V2.4).

    python tools/windows_version_info.py --show         print what a build of this checkout would put in the exe
    python tools/windows_version_info.py --self-test    check this script in a throw-away folder

The export preset (export_presets.cfg) has three fields that Windows shows in the exe's Properties window:
    application/file_version      four whole numbers, for example 0.3.0.0 (Godot's rule: every one of the four is
                                  required, 0.3.0 would make rcedit fail and the exe would lose its icon too)
    application/product_version   the same four numbers
    application/file_description  free text, "FB3D 0.3.0-alpha (a1b2c3d)" (the hash has no place in the numbers,
                                  and a pre-release such as -alpha cannot be written in them either)
tools/build_release.py (roadmap V2.5) calls temporary_version_info() around the export: the fields are filled for the
export and the preset is put back exactly as it was afterwards, even when the export fails. The tracked file keeps the
fields empty on purpose, so no build leaves a changed file behind and a hash never lands in a commit. The preset must
never hold a key (README "Secrets and credentials"); nothing here writes one.

Only the Python standard library is used, so it runs on Windows too. Line endings of the preset are kept as they are.
Exit code: 0 = ok, 1 = self-test failed, 2 = could not run.
"""

import argparse
import contextlib
import os
import shutil
import sys
import tempfile

import version_compare

PRESET_NAME = "export_presets.cfg"
OPTIONS_SECTION = "[preset.0.options]"
KEY_FILE_VERSION = "application/file_version"
KEY_PRODUCT_VERSION = "application/product_version"
KEY_FILE_DESCRIPTION = "application/file_description"
PRODUCT_NAME = "FB3D"
# Windows stores each of the four numbers in 16 bits
MAX_NUMBER = 65535


class VersionInfoError(Exception):
    """The preset or the version cannot be used and nothing was changed."""


def four_numbers(version: str) -> str:
    """0.3.0 and 0.3.0-alpha both give 0.3.0.0 (the fourth number is the build, always 0 for now)."""
    parsed = version_compare.parse(version)
    if parsed is None:
        raise VersionInfoError("not a valid version: " + version)
    numbers = parsed[0]
    for number in numbers:
        if number > MAX_NUMBER:
            raise VersionInfoError("a Windows file version number is at most 65535: " + version)
    return str(numbers[0]) + "." + str(numbers[1]) + "." + str(numbers[2]) + ".0"


def description(info: dict) -> str:
    text = PRODUCT_NAME + " " + info["version"] + " (" + info["short"]
    if info["dirty"]:
        text = text + "+"
    return text + ")"


def make_fields(info: dict) -> dict:
    numbers = four_numbers(info["version"])
    fields = {
        KEY_FILE_VERSION: numbers,
        KEY_PRODUCT_VERSION: numbers,
        KEY_FILE_DESCRIPTION: description(info),
    }
    for value in fields.values():
        if '"' in value or "\n" in value or "\r" in value:
            raise VersionInfoError("a value for the preset has a quote or a line break in it")
    return fields


def read_text(path: str) -> str:
    # newline="" keeps the line endings exactly as they are in the file
    with open(path, encoding="utf-8", newline="") as preset_file:
        return preset_file.read()


def write_text(path: str, text: str) -> None:
    temp_path = path + ".tmp"
    with open(temp_path, "w", encoding="utf-8", newline="") as preset_file:
        preset_file.write(text)
    os.replace(temp_path, path)


def set_fields(text: str, fields: dict) -> str:
    """The preset text with the given keys set inside [preset.0.options]; every other line stays as it was."""
    lines = text.splitlines(keepends=True)
    in_options = False
    found = []
    result = []

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("["):
            in_options = stripped == OPTIONS_SECTION
        if in_options and "=" in stripped:
            key = stripped.split("=", 1)[0]
            if key in fields:
                text_length = len(line.rstrip("\r\n"))
                ending = line[text_length:]
                line = key + '="' + fields[key] + '"' + ending
                found.append(key)
        result.append(line)

    for key in fields:
        if found.count(key) != 1:
            raise VersionInfoError(key + " was found " + str(found.count(key)) + " times in " + OPTIONS_SECTION)
    return "".join(result)


@contextlib.contextmanager
def temporary_version_info(preset_path: str, info: dict):
    """Fills the three fields while the block runs and puts the preset back afterwards, whatever happens."""
    original = read_text(preset_path)
    changed = set_fields(original, make_fields(info))
    write_text(preset_path, changed)
    try:
        yield changed
    finally:
        write_text(preset_path, original)


# ---------------------------------------------------------------- self-test

SAMPLE_PRESET = (
    '[preset.0]\n\nname="Windows Desktop"\ninclude_filter="data/*.json,build_info.json"\n\n'
    "[preset.0.options]\n\n"
    'application/icon="res://assets/icon/icon.ico"\n'
    'application/file_version=""\n'
    'application/product_version=""\n'
    'application/company_name=""\n'
    'application/product_name="FB3D"\n'
    'application/file_description=""\n'
    'application/copyright=""\n'
)

SAMPLE_INFO = {"version": "0.3.0", "short": "a1b2c3d", "dirty": False}


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
        except VersionInfoError:
            expect(name, True)
            return
        expect(name, False)

    expect("0.3.0 gives four numbers", four_numbers("0.3.0") == "0.3.0.0")
    expect("a pre-release gives the same four numbers", four_numbers("0.3.0-alpha") == "0.3.0.0")
    expect("0.10.2 keeps its numbers", four_numbers("0.10.2") == "0.10.2.0")
    expect("65535 is the largest allowed number", four_numbers("65535.0.0") == "65535.0.0.0")
    expect_error("65536 is refused", lambda: four_numbers("65536.0.0"))
    expect_error("an invalid version is refused", lambda: four_numbers("three"))
    expect("description with the hash", description(SAMPLE_INFO) == "FB3D 0.3.0 (a1b2c3d)")
    dirty_info = {"version": "0.3.0-alpha", "short": "a1b2c3d", "dirty": True}
    expect("description of a dirty pre-release", description(dirty_info) == "FB3D 0.3.0-alpha (a1b2c3d+)")

    fields = make_fields(SAMPLE_INFO)
    changed = set_fields(SAMPLE_PRESET, fields)
    expect("file_version is set", 'application/file_version="0.3.0.0"\n' in changed)
    expect("product_version is set", 'application/product_version="0.3.0.0"\n' in changed)
    expect("file_description is set", 'application/file_description="FB3D 0.3.0 (a1b2c3d)"\n' in changed)
    changed_lines = 0
    for before, after in zip(SAMPLE_PRESET.splitlines(), changed.splitlines()):
        if before != after:
            changed_lines += 1
    expect("exactly three lines changed", changed_lines == 3)
    expect("the number of lines is the same", len(SAMPLE_PRESET.splitlines()) == len(changed.splitlines()))
    expect("a second set gives the same text", set_fields(changed, fields) == changed)

    windows_text = SAMPLE_PRESET.replace("\n", "\r\n")
    windows_changed = set_fields(windows_text, fields)
    same_endings = windows_changed.count("\r\n") == windows_text.count("\r\n")
    no_lone_newline = "\n" not in windows_changed.replace("\r\n", "")
    expect("Windows line endings are kept", same_endings and no_lone_newline)

    # a key of another section is left alone
    other_section = SAMPLE_PRESET.replace("[preset.0.options]", "[preset.1.options]")
    expect_error("the keys must be in [preset.0.options]", lambda: set_fields(other_section, fields))
    missing_key = SAMPLE_PRESET.replace('application/file_description=""\n', "")
    expect_error("a missing key is refused", lambda: set_fields(missing_key, fields))

    work = tempfile.mkdtemp(prefix="fb3d_version_info_")
    try:
        preset_path = os.path.join(work, PRESET_NAME)
        write_text(preset_path, SAMPLE_PRESET)

        with temporary_version_info(preset_path, SAMPLE_INFO):
            inside = read_text(preset_path)
        expect("the fields are filled inside the block", 'application/file_version="0.3.0.0"' in inside)
        expect("the preset is put back after the block", read_text(preset_path) == SAMPLE_PRESET)

        try:
            with temporary_version_info(preset_path, SAMPLE_INFO):
                raise RuntimeError("the export failed")
        except RuntimeError:
            pass
        expect("the preset is put back after a failure", read_text(preset_path) == SAMPLE_PRESET)
        expect("no .tmp file is left behind", not os.path.exists(preset_path + ".tmp"))

        def bad_version_block():
            with temporary_version_info(preset_path, {"version": "x", "short": "a1b2c3d", "dirty": False}):
                pass

        expect_error("a bad version stops before anything is written", bad_version_block)
        expect("the preset is untouched after that", read_text(preset_path) == SAMPLE_PRESET)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    # the real preset of this project: all three fields exist, and the tracked file holds no values
    project = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    real_path = os.path.join(project, PRESET_NAME)
    if os.path.isfile(real_path):
        real_text = read_text(real_path)
        try:
            set_fields(real_text, fields)
            expect("the real export preset has the three fields", True)
        except VersionInfoError:
            expect("the real export preset has the three fields", False)
        for key in (KEY_FILE_VERSION, KEY_PRODUCT_VERSION, KEY_FILE_DESCRIPTION):
            expect("the tracked preset keeps " + key + " empty", (key + '=""') in real_text)

    if problems:
        print("SELF-TEST FAILED: " + str(len(problems)) + " problem(s)")
        return 1
    print("SELF-TEST PASSED")
    return 0


# --------------------------------------------------------------------- main


def show() -> int:
    # import here: make_build_info needs git and the project, the self-test above does not
    import make_build_info

    try:
        root = make_build_info.project_root()
        info = make_build_info.make_info(root, make_build_info.DEFAULT_CHANNEL)
        fields = make_fields(info)
    except (make_build_info.BuildInfoError, VersionInfoError) as error:
        print("windows_version_info: " + str(error), file=sys.stderr)
        return 2
    for key in fields:
        print(key + '="' + fields[key] + '"')
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Windows file information of the export preset (roadmap V2.4).")
    parser.add_argument("--show", action="store_true", help="print the values a build of this checkout would use")
    parser.add_argument("--self-test", action="store_true", help="check this script in a throw-away folder")
    args = parser.parse_args()

    if args.self_test:
        return self_test()
    if args.show:
        return show()
    parser.print_help()
    return 2


if __name__ == "__main__":
    sys.exit(main())
