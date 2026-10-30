#!/usr/bin/env python3
"""Builds the Windows exe and writes release_manifest.json next to it (roadmap V2.5). The owner runs it on Windows.

    python tools/build_release.py --channel alpha     build, then write the manifest (channel is dev, alpha or release)
    python tools/build_release.py --godot PATH        use this Godot (remembered, the same file as run_checks.py)
    python tools/build_release.py --allow-dirty       build even though there are uncommitted changes
    python tools/build_release.py --self-test         check this script with a fake Godot in a throw-away folder

What it does, in this order:
  1. refuses a dirty tree for the channels alpha and release (the manifest says which commit the file was made from,
     so the commit must be the whole truth); --allow-dirty overrides it and the file name gets "-dirty",
  2. writes build_info.json (tools/make_build_info.py, V2.1),
  3. imports the project and exports the preset "Windows Desktop" with `--export-release`, while the Windows file
     information of the preset is filled (tools/windows_version_info.py, V2.4; the preset is put back afterwards),
  4. copies the exe into releases/<name>/ as FB3D-<version>-<hash>.exe and writes release_manifest.json beside it:
     manifest_version, product, version, commit, short, dirty, channel, built_utc, file, size and sha256.
V4.3 (the website's Release model), V6.2 (the installer) and V6.4 (the signed manifest) build on that file.

Needs Godot 4.7 or newer WITH THE EXPORT TEMPLATES installed (Godot: Editor > Manage Export Templates). The releases/
folder is untracked (.gitignore). No key or secret is written anywhere by this script.
Only the Python standard library is used. Exit code: 0 = built, 1 = self-test failed, 2 = the build failed.
"""

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

import make_build_info
import run_checks
import windows_version_info

PRODUCT = "FB3D"
PRESET_NAME = "Windows Desktop"
RELEASES_FOLDER = "releases"
MANIFEST_NAME = "release_manifest.json"
MANIFEST_VERSION = 1
CHANNELS_THAT_NEED_A_CLEAN_TREE = ["alpha", "release"]
IMPORT_TIMEOUT_SECONDS = 20 * 60
EXPORT_TIMEOUT_SECONDS = 30 * 60
HASH_CHUNK = 1024 * 1024
OUTPUT_TAIL_LINES = 25


class BuildError(Exception):
    """The build cannot go on. Nothing half-finished is left in the releases folder."""


def release_name(info: dict) -> str:
    # 0.3.0-alpha and a1b2c3d give FB3D-0.3.0-alpha-a1b2c3d (with -dirty added for a dirty tree)
    name = PRODUCT + "-" + info["version"] + "-" + info["short"]
    if info["dirty"]:
        name = name + "-dirty"
    return name


def sha256_of(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as exe_file:
        while True:
            chunk = exe_file.read(HASH_CHUNK)
            if chunk == b"":
                break
            digest.update(chunk)
    return digest.hexdigest()


def read_export_path(root: str) -> str:
    # the preset says where Godot writes the exe (build/windows/FB3D.exe), so the script does not guess
    preset_path = os.path.join(root, windows_version_info.PRESET_NAME)
    in_preset = False
    with open(preset_path, encoding="utf-8") as preset_file:
        for line in preset_file:
            line = line.strip()
            if line.startswith("["):
                in_preset = line == "[preset.0]"
                continue
            if in_preset and line.startswith("export_path="):
                value = line.split("=", 1)[1].strip().strip('"')
                if value != "":
                    return os.path.join(root, value.replace("/", os.sep))
    raise BuildError("export_path of [preset.0] not found in " + preset_path)


def run_godot(godot: str, arguments: list[str], timeout: int, label: str) -> str:
    """Runs Godot and returns what it printed. A failure stops the build with the end of its output."""
    print(label + " ...", flush=True)
    try:
        result = subprocess.run(
            [godot] + arguments,
            capture_output=True,
            text=True,
            errors="replace",
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        raise BuildError(label + " took longer than " + str(timeout // 60) + " minutes and was stopped")
    except OSError as error:
        raise BuildError("could not start Godot: " + str(error))

    output = result.stdout + "\n" + result.stderr
    if result.returncode != 0:
        raise BuildError(label + " failed (exit code " + str(result.returncode) + ")\n" + tail(output))
    return output


def tail(text: str) -> str:
    lines = text.strip().splitlines()
    return "\n".join(lines[-OUTPUT_TAIL_LINES:])


def godot_export(godot: str, root: str, export_path: str) -> None:
    """The real export: import the project, then export the preset. Replaced by a fake in the self-test."""
    os.makedirs(os.path.dirname(export_path), exist_ok=True)
    run_godot(godot, ["--headless", "--path", root, "--import"], IMPORT_TIMEOUT_SECONDS, "Importing the project")
    output = run_godot(
        godot,
        ["--headless", "--path", root, "--export-release", PRESET_NAME, export_path],
        EXPORT_TIMEOUT_SECONDS,
        "Exporting " + PRESET_NAME,
    )
    # Godot can end with exit code 0 although the export failed, so its messages are read too
    for line in output.splitlines():
        templates_missing = "No export template found" in line
        if "export templates" in line.lower() and "ERROR" in line:
            templates_missing = True
        if templates_missing:
            raise BuildError("the export templates are missing: Godot, Editor > Manage Export Templates\n" + line)
        if line.startswith("ERROR:") and "export" in line.lower():
            raise BuildError("Godot reported an export error:\n" + tail(output))


def build(root: str, channel: str, allow_dirty: bool, exporter, godot: str = "") -> str:
    """Builds and returns the folder with the exe and the manifest.

    `exporter(godot, root, export_path)` makes the exe (godot_export, or a fake one in the self-test).
    """
    try:
        info = make_build_info.make_info(root, channel)
    except make_build_info.BuildInfoError as error:
        raise BuildError(str(error))

    if info["dirty"] and channel in CHANNELS_THAT_NEED_A_CLEAN_TREE and not allow_dirty:
        raise BuildError(
            "there are uncommitted changes and the channel is " + channel + ". Commit them, or build with "
            "--allow-dirty (the file name will say -dirty)."
        )

    make_build_info.write_info(info, os.path.join(root, make_build_info.OUTPUT_NAME))
    export_path = read_export_path(root)
    started = time.time()
    preset_path = os.path.join(root, windows_version_info.PRESET_NAME)

    try:
        with windows_version_info.temporary_version_info(preset_path, info):
            exporter(godot, root, export_path)
    except windows_version_info.VersionInfoError as error:
        raise BuildError(str(error))

    if not os.path.isfile(export_path):
        raise BuildError("the export did not make " + export_path)
    if os.path.getmtime(export_path) < started - 2:
        raise BuildError("the export did not make a new " + export_path + " (it is older than this run)")
    size = os.path.getsize(export_path)
    if size == 0:
        raise BuildError("the exported file is empty: " + export_path)

    name = release_name(info)
    folder = os.path.join(root, RELEASES_FOLDER, name)
    exe_name = name + ".exe"
    os.makedirs(folder, exist_ok=True)
    shutil.copyfile(export_path, os.path.join(folder, exe_name))

    # the hash is taken from the copy in the releases folder: that is the file that will be published
    manifest = {
        "manifest_version": MANIFEST_VERSION,
        "product": PRODUCT,
        "version": info["version"],
        "commit": info["commit"],
        "short": info["short"],
        "dirty": info["dirty"],
        "channel": info["channel"],
        "built_utc": info["built_utc"],
        "file": exe_name,
        "size": os.path.getsize(os.path.join(folder, exe_name)),
        "sha256": sha256_of(os.path.join(folder, exe_name)),
    }
    manifest_path = os.path.join(folder, MANIFEST_NAME)
    temp_path = manifest_path + ".tmp"
    with open(temp_path, "w", encoding="utf-8", newline="\n") as manifest_file:
        json.dump(manifest, manifest_file, indent=2)
        manifest_file.write("\n")
    os.replace(temp_path, manifest_path)
    return folder


# ---------------------------------------------------------------- self-test

FAKE_EXE_BYTES = b"MZ fake exe for the self-test " * 100

SAMPLE_PRESET = (
    '[preset.0]\n\nname="Windows Desktop"\nexport_path="build/windows/FB3D.exe"\n\n'
    "[preset.0.options]\n\n"
    'application/file_version=""\napplication/product_version=""\napplication/file_description=""\n'
)


def git_in(folder: str, args: list[str]) -> None:
    subprocess.run(["git", "-C", folder] + args, check=True, capture_output=True)


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
        except BuildError:
            expect(name, True)
            return
        expect(name, False)

    seen_inside = {}

    def good_exporter(godot: str, root: str, export_path: str) -> None:
        # the fake exe, and what the preset looked like while "Godot" ran
        with open(os.path.join(root, windows_version_info.PRESET_NAME), encoding="utf-8") as preset_file:
            seen_inside["preset"] = preset_file.read()
        seen_inside["build_info_exists"] = os.path.isfile(os.path.join(root, make_build_info.OUTPUT_NAME))
        os.makedirs(os.path.dirname(export_path), exist_ok=True)
        with open(export_path, "wb") as exe_file:
            exe_file.write(FAKE_EXE_BYTES)

    def nothing_exporter(godot: str, root: str, export_path: str) -> None:
        pass

    def failing_exporter(godot: str, root: str, export_path: str) -> None:
        raise BuildError("the fake Godot failed")

    def empty_exporter(godot: str, root: str, export_path: str) -> None:
        os.makedirs(os.path.dirname(export_path), exist_ok=True)
        open(export_path, "wb").close()

    work = tempfile.mkdtemp(prefix="fb3d_build_release_")
    try:
        repo = os.path.join(work, "repo")
        os.makedirs(repo)
        make_build_info.make_test_repo(repo, 'config/version="0.3.0"')
        preset_path = os.path.join(repo, windows_version_info.PRESET_NAME)
        with open(preset_path, "w", encoding="utf-8", newline="") as preset_file:
            preset_file.write(SAMPLE_PRESET)
        with open(os.path.join(repo, ".gitignore"), "a", encoding="utf-8") as ignore_file:
            ignore_file.write("build/\nreleases/\n")
        git_in(repo, ["add", "-A"])
        git_in(repo, ["commit", "-q", "-m", "preset"])

        folder = build(repo, "alpha", False, good_exporter)
        info = make_build_info.make_info(repo, "alpha")
        short = info["short"]
        expected_name = "FB3D-0.3.0-" + short
        expect("the release folder is named version and hash", os.path.basename(folder) == expected_name)
        expect("the exe is in it under the same name", os.path.isfile(os.path.join(folder, expected_name + ".exe")))

        with open(os.path.join(folder, MANIFEST_NAME), encoding="utf-8") as manifest_file:
            manifest = json.load(manifest_file)
        same_identity = manifest["version"] == "0.3.0" and manifest["commit"] == info["commit"]
        expect("manifest: version, commit and channel", same_identity and manifest["channel"] == "alpha")
        expect("manifest: file name", manifest["file"] == expected_name + ".exe")
        expect("manifest: size", manifest["size"] == len(FAKE_EXE_BYTES))
        expect("manifest: sha256", manifest["sha256"] == hashlib.sha256(FAKE_EXE_BYTES).hexdigest())
        expect("manifest: not dirty", manifest["dirty"] is False)
        expect("manifest: format version is 1", manifest["manifest_version"] == 1)
        expect("manifest: build time", manifest["built_utc"].endswith("Z"))
        expect("manifest has no secret-looking key", "key" not in manifest and "token" not in manifest)

        expect("version info filled while Godot ran", 'application/file_version="0.3.0.0"' in seen_inside["preset"])
        expect("the description holds the hash", "FB3D 0.3.0 (" + short + ")" in seen_inside["preset"])
        expect("build_info.json existed while Godot ran", seen_inside["build_info_exists"] is True)
        with open(preset_path, encoding="utf-8", newline="") as preset_file:
            expect("the preset is put back afterwards", preset_file.read() == SAMPLE_PRESET)
        expect("the tree is still clean after a build", make_build_info.make_info(repo, "dev")["dirty"] is False)

        expect_error("an exporter that fails stops the build", lambda: build(repo, "dev", False, failing_exporter))
        with open(preset_path, encoding="utf-8", newline="") as preset_file:
            expect("the preset is put back after a failed export", preset_file.read() == SAMPLE_PRESET)

        # an old exe left over from an earlier build must not be taken for a new one
        os.utime(os.path.join(repo, "build", "windows", "FB3D.exe"), (1000000000, 1000000000))
        expect_error("an export that makes nothing is noticed", lambda: build(repo, "dev", False, nothing_exporter))
        os.remove(os.path.join(repo, "build", "windows", "FB3D.exe"))
        expect_error("an empty exe is refused", lambda: build(repo, "dev", False, empty_exporter))

        with open(os.path.join(repo, "notes.txt"), "w", encoding="utf-8") as notes_file:
            notes_file.write("uncommitted")
        expect_error("a dirty tree is refused for alpha", lambda: build(repo, "alpha", False, good_exporter))
        expect_error("a dirty tree is refused for release", lambda: build(repo, "release", False, good_exporter))
        dirty_folder = build(repo, "dev", False, good_exporter)
        expect("a dirty dev build is allowed and says so", os.path.basename(dirty_folder).endswith("-dirty"))
        forced_folder = build(repo, "alpha", True, good_exporter)
        expect("--allow-dirty builds an alpha and says so", os.path.basename(forced_folder).endswith("-dirty"))
        with open(os.path.join(forced_folder, MANIFEST_NAME), encoding="utf-8") as manifest_file:
            expect("the manifest of a dirty build says dirty", json.load(manifest_file)["dirty"] is True)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if problems:
        print("SELF-TEST FAILED: " + str(len(problems)) + " problem(s)")
        return 1
    print("SELF-TEST PASSED")
    return 0


# --------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Windows exe and its release manifest (roadmap V2.5).")
    parser.add_argument("--channel", default=make_build_info.DEFAULT_CHANNEL, choices=make_build_info.CHANNELS)
    parser.add_argument("--godot", default=None, help="path to Godot (remembered for the next time)")
    parser.add_argument("--allow-dirty", action="store_true", help="build alpha or release with uncommitted changes")
    parser.add_argument("--self-test", action="store_true", help="check this script with a fake Godot")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    godot_path, godot_text, where, tried = run_checks.find_godot(args.godot)
    if godot_path is None:
        print("build_release: no Godot 4.7 or newer was found.", file=sys.stderr)
        for line in tried:
            print("  " + line, file=sys.stderr)
        print('Pass it once: python tools/build_release.py --godot "C:\\path\\to\\Godot_console.exe"', file=sys.stderr)
        return 2
    run_checks.remember_godot(godot_path)
    print("Using Godot " + godot_text + " (" + where + "): " + str(godot_path))

    root = make_build_info.project_root()
    try:
        folder = build(root, args.channel, args.allow_dirty, godot_export, str(godot_path))
    except BuildError as error:
        print("build_release: " + str(error), file=sys.stderr)
        return 2

    print("Done. Folder: " + folder)
    with open(os.path.join(folder, MANIFEST_NAME), encoding="utf-8") as manifest_file:
        manifest = json.load(manifest_file)
    print("File:   " + manifest["file"] + " (" + str(manifest["size"]) + " bytes)")
    print("SHA-256: " + manifest["sha256"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
