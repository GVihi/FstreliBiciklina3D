#!/usr/bin/env python3
"""Writes build_info.json into the project root (roadmap V2.1).

    python tools/make_build_info.py                    write build_info.json (channel dev)
    python tools/make_build_info.py --channel alpha    channel is dev, alpha or release
    python tools/make_build_info.py --output PATH      write somewhere else (used by the self-test)
    python tools/make_build_info.py --self-test        run the checks of this script in a throw-away git repository

The file holds: version, commit, short, dirty, built_utc, channel.
The game reads it (scripts/build_info.gd, roadmap V2.2). The file is generated and never tracked (.gitignore),
and it is listed in the export preset's include_filter so that it ends up in the exe.

Exit code: 0 = written (or self-test passed), 1 = self-test failed, 2 = the file could not be made.
Only the Python standard library is used, so it runs on Windows too.
"""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone

import version_compare  # tools/version_compare.py: the one definition of a valid version (roadmap V2.3)

CHANNELS = ["dev", "alpha", "release"]
DEFAULT_CHANNEL = "dev"
OUTPUT_NAME = "build_info.json"
SHORT_LENGTH = 7

COMMIT_PATTERN = re.compile(r"^[0-9a-f]{40}$")


class BuildInfoError(Exception):
    """Something is wrong and no file should be written."""


def project_root() -> str:
    # tools/ leži v korenu projekta, zato je koren eno mapo više
    tools_folder = os.path.dirname(os.path.abspath(__file__))
    return os.path.dirname(tools_folder)


def run_git(root: str, args: list[str]) -> str:
    try:
        result = subprocess.run(
            ["git", "-C", root] + args,
            capture_output=True,
            text=True,
            check=False,
        )
    except FileNotFoundError:
        raise BuildInfoError("git was not found. Install git and try again.")
    if result.returncode != 0:
        message = result.stderr.strip()
        raise BuildInfoError("git " + " ".join(args) + " failed: " + message)
    return result.stdout


def read_version(root: str) -> str:
    # config/version v project.godot ostane edino mesto, kjer je verzija zapisana
    path = os.path.join(root, "project.godot")
    if not os.path.isfile(path):
        raise BuildInfoError("project.godot not found in " + root)

    version = None
    in_application = False
    with open(path, encoding="utf-8") as project_file:
        for line in project_file:
            line = line.strip()
            if line.startswith("["):
                in_application = line == "[application]"
                continue
            if in_application and line.startswith("config/version="):
                version = line.split("=", 1)[1].strip().strip('"')
                break

    if version is None:
        raise BuildInfoError("config/version not found in the [application] section of project.godot")
    if not version_compare.is_valid(version):
        raise BuildInfoError("config/version is not like 0.3.0 or 0.3.0-alpha: " + version)
    return version


def read_commit(root: str) -> str:
    commit = run_git(root, ["rev-parse", "HEAD"]).strip()
    if not COMMIT_PATTERN.fullmatch(commit):
        raise BuildInfoError("git gave something that is not a commit hash")
    return commit


def is_dirty(root: str) -> bool:
    # Tudi nova datoteka, ki je git še ne pozna, pomeni, da build ni natanko ta commit
    # (izvoz vzame vse vire). Ignorirane datoteke (build_info.json, build/) se ne štejejo.
    status = run_git(root, ["status", "--porcelain"])
    return status.strip() != ""


def make_info(root: str, channel: str) -> dict:
    if channel not in CHANNELS:
        raise BuildInfoError("channel must be one of " + ", ".join(CHANNELS))

    commit = read_commit(root)
    now = datetime.now(timezone.utc).replace(microsecond=0)

    info = {
        "version": read_version(root),
        "commit": commit,
        "short": commit[:SHORT_LENGTH],
        "dirty": is_dirty(root),
        "built_utc": now.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "channel": channel,
    }
    return info


def write_info(info: dict, output_path: str) -> None:
    # najprej v začasno datoteko, da pol zapisana datoteka nikoli ne konča v buildu
    temp_path = output_path + ".tmp"
    with open(temp_path, "w", encoding="utf-8", newline="\n") as temp_file:
        json.dump(info, temp_file, indent=2)
        temp_file.write("\n")
    os.replace(temp_path, output_path)


# ---------------------------------------------------------------- self-test


def git_in(folder: str, args: list[str]) -> None:
    subprocess.run(["git", "-C", folder] + args, check=True, capture_output=True)


def make_test_repo(folder: str, version_line: str) -> None:
    git_in(folder, ["init", "-q"])
    git_in(folder, ["config", "user.email", "test@example.com"])
    git_in(folder, ["config", "user.name", "Test"])
    git_in(folder, ["config", "commit.gpgsign", "false"])
    with open(os.path.join(folder, "project.godot"), "w", encoding="utf-8") as project_file:
        project_file.write('config_version=5\n\n[application]\n\nconfig/name="X"\n' + version_line + "\n")
    with open(os.path.join(folder, ".gitignore"), "w", encoding="utf-8") as ignore_file:
        ignore_file.write("build_info.json\n")
    git_in(folder, ["add", "-A"])
    git_in(folder, ["commit", "-q", "-m", "first"])


def self_test() -> int:
    problems = []

    def expect(name: str, condition: bool) -> None:
        if condition:
            print("  ok    " + name)
        else:
            print("  FAIL  " + name)
            problems.append(name)

    def expect_error(name: str, root: str, channel: str = DEFAULT_CHANNEL) -> None:
        try:
            make_info(root, channel)
        except BuildInfoError:
            expect(name, True)
            return
        expect(name, False)

    work = tempfile.mkdtemp(prefix="fb3d_build_info_")
    try:
        repo = os.path.join(work, "repo")
        os.makedirs(repo)
        make_test_repo(repo, 'config/version="0.3.0"')

        info = make_info(repo, "alpha")
        expect("version is read from project.godot", info["version"] == "0.3.0")
        expect("commit is 40 hex characters", COMMIT_PATTERN.fullmatch(info["commit"]) is not None)
        expect("short is the first 7 characters", info["short"] == info["commit"][:7])
        expect("a clean tree is not dirty", info["dirty"] is False)
        expect("channel is kept", info["channel"] == "alpha")
        time_pattern = r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$"
        expect("built_utc has the Z format", re.match(time_pattern, info["built_utc"]) is not None)

        output = os.path.join(repo, OUTPUT_NAME)
        write_info(info, output)
        with open(output, encoding="utf-8") as output_file:
            loaded = json.load(output_file)
        expect("written file reads back the same", loaded == info)
        expect("the written file does not make the tree dirty", make_info(repo, "dev")["dirty"] is False)
        expect("no .tmp file is left behind", not os.path.exists(output + ".tmp"))

        with open(os.path.join(repo, "extra.txt"), "w", encoding="utf-8") as extra_file:
            extra_file.write("new file")
        expect("a new untracked file makes it dirty", make_info(repo, "dev")["dirty"] is True)
        os.remove(os.path.join(repo, "extra.txt"))

        with open(os.path.join(repo, "project.godot"), "a", encoding="utf-8") as project_file:
            project_file.write("\n")
        expect("a changed tracked file makes it dirty", make_info(repo, "dev")["dirty"] is True)
        git_in(repo, ["checkout", "--", "project.godot"])

        expect_error("an unknown channel is refused", repo, "nightly")

        prerelease = os.path.join(work, "prerelease")
        os.makedirs(prerelease)
        make_test_repo(prerelease, 'config/version="0.3.0-alpha"')
        expect("a pre-release version is accepted", make_info(prerelease, "dev")["version"] == "0.3.0-alpha")

        broken = os.path.join(work, "broken")
        os.makedirs(broken)
        make_test_repo(broken, 'config/version="three"')
        expect_error("a damaged version is refused", broken)

        missing = os.path.join(work, "missing")
        os.makedirs(missing)
        make_test_repo(missing, "")
        expect_error("a missing version is refused", missing)

        not_git = os.path.join(work, "not_git")
        os.makedirs(not_git)
        with open(os.path.join(not_git, "project.godot"), "w", encoding="utf-8") as project_file:
            project_file.write('[application]\nconfig/version="0.3.0"\n')
        expect_error("a folder that is not a git repository is refused", not_git)
    finally:
        shutil.rmtree(work, ignore_errors=True)

    if problems:
        print("SELF-TEST FAILED: " + str(len(problems)) + " problem(s)")
        return 1
    print("SELF-TEST PASSED")
    return 0


# --------------------------------------------------------------------- main


def main() -> int:
    parser = argparse.ArgumentParser(description="Write build_info.json (roadmap V2.1).")
    parser.add_argument("--channel", default=DEFAULT_CHANNEL, choices=CHANNELS)
    parser.add_argument("--output", default=None, help="where to write the file (default: project root)")
    parser.add_argument("--self-test", action="store_true", help="check this script in a throw-away git repository")
    args = parser.parse_args()

    if args.self_test:
        return self_test()

    root = project_root()
    output_path = args.output
    if output_path is None:
        output_path = os.path.join(root, OUTPUT_NAME)

    try:
        info = make_info(root, args.channel)
        write_info(info, output_path)
    except (BuildInfoError, OSError) as error:
        print("make_build_info: " + str(error), file=sys.stderr)
        return 2

    dirty_mark = ""
    if info["dirty"]:
        dirty_mark = "+"
    print("Wrote " + output_path)
    print("FB3D " + info["version"] + " (" + info["short"] + dirty_mark + ") channel " + info["channel"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
