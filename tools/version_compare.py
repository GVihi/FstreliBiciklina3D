#!/usr/bin/env python3
"""The version comparison in Python (roadmap V2.3). The same rules as scripts/version_compare.gd.

    python tools/version_compare.py 0.9.0 0.10.0   print -1, 0 or 1 (or "invalid")
    python tools/version_compare.py --self-test    run every case of tools/version_compare_cases.json

The rules are written in that JSON file. The website's code has its own copy of the comparison and runs the same
file, so the game and the site cannot disagree. Only the Python standard library is used, so it runs on Windows too.
No regular expressions on purpose: a text parser by hand gives the same answer in Python and in GDScript.
Exit code: 0 = ok, 1 = a case failed, 2 = could not run.
"""

import json
import os
import sys

MAX_DIGITS = 9
CASES_FILE = "version_compare_cases.json"
LETTERS_AND_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"
DIGITS = "0123456789"


def is_number_text(text: str) -> bool:
    if text == "" or len(text) > MAX_DIGITS:
        return False
    for letter in text:
        if letter not in DIGITS:
            return False
    # 0 is fine, 03 is not
    if len(text) > 1 and text[0] == "0":
        return False
    return True


def is_all_digits(text: str) -> bool:
    for letter in text:
        if letter not in DIGITS:
            return False
    return True


def parse(version: str):
    """Returns (numbers, pre_release_identifiers) or None when the text is not a valid version."""
    if version == "":
        return None

    core = version
    pre_release_text = None
    dash_position = version.find("-")
    if dash_position != -1:
        core = version[:dash_position]
        start = dash_position + 1
        pre_release_text = version[start:]

    core_parts = core.split(".")
    if len(core_parts) != 3:
        return None
    numbers = []
    for part in core_parts:
        if not is_number_text(part):
            return None
        numbers.append(int(part))

    identifiers = []
    if pre_release_text is not None:
        for identifier in pre_release_text.split("."):
            if identifier == "":
                return None
            for letter in identifier:
                if letter not in LETTERS_AND_DIGITS:
                    return None
            # an identifier made only of digits is a number: no leading zero
            if is_all_digits(identifier) and not is_number_text(identifier):
                return None
            identifiers.append(identifier)
        if len(identifiers) == 0:
            return None

    return (numbers, identifiers)


def is_valid(version: str) -> bool:
    return parse(version) is not None


def compare_identifiers(first: str, second: str) -> int:
    first_is_number = is_all_digits(first)
    second_is_number = is_all_digits(second)

    if first_is_number and second_is_number:
        if int(first) < int(second):
            return -1
        if int(first) > int(second):
            return 1
        return 0
    # a number is older than a text
    if first_is_number:
        return -1
    if second_is_number:
        return 1
    # two texts: ASCII order (capitals before small letters)
    if first < second:
        return -1
    if first > second:
        return 1
    return 0


def compare(first: str, second: str):
    """-1 when first is older, 0 when equal, 1 when first is newer, None when either is not a valid version."""
    parsed_first = parse(first)
    parsed_second = parse(second)
    if parsed_first is None or parsed_second is None:
        return None

    numbers_first, pre_first = parsed_first
    numbers_second, pre_second = parsed_second

    for index in range(3):
        if numbers_first[index] < numbers_second[index]:
            return -1
        if numbers_first[index] > numbers_second[index]:
            return 1

    # same numbers: a version without a pre-release is the newer one
    if len(pre_first) == 0 and len(pre_second) == 0:
        return 0
    if len(pre_first) == 0:
        return 1
    if len(pre_second) == 0:
        return -1

    shared = min(len(pre_first), len(pre_second))
    for index in range(shared):
        result = compare_identifiers(pre_first[index], pre_second[index])
        if result != 0:
            return result

    # all shared identifiers are equal: more identifiers is newer
    if len(pre_first) < len(pre_second):
        return -1
    if len(pre_first) > len(pre_second):
        return 1
    return 0


def run_cases(cases_path: str) -> int:
    with open(cases_path, encoding="utf-8") as cases_file:
        cases = json.load(cases_file)

    problems = []
    checked = 0

    for case in cases["compare"]:
        first = case["a"]
        second = case["b"]
        expected = case["expect"]
        checked += 1
        if compare(first, second) != expected:
            problems.append("compare(" + first + ", " + second + ") is not " + str(expected))
        # the other way round must give the opposite answer
        checked += 1
        if compare(second, first) != -expected:
            problems.append("compare(" + second + ", " + first + ") is not " + str(-expected))

    for version in cases["valid"]:
        checked += 1
        if not is_valid(version):
            problems.append(repr(version) + " should be valid")

    for version in cases["invalid"]:
        checked += 1
        if is_valid(version):
            problems.append(repr(version) + " should be invalid")
        checked += 1
        if compare(version, "0.3.0") is not None or compare("0.3.0", version) is not None:
            problems.append("compare with the invalid " + repr(version) + " should have no answer")

    for pair in cases["invalid_pairs"]:
        checked += 1
        if compare(pair["a"], pair["b"]) is not None:
            problems.append("compare(" + repr(pair["a"]) + ", " + repr(pair["b"]) + ") should have no answer")

    for problem in problems:
        print("  FAIL  " + problem)
    if problems:
        print("VERSION COMPARE FAILED: " + str(len(problems)) + " of " + str(checked) + " checks")
        return 1
    print("VERSION COMPARE PASSED: " + str(checked) + " checks")
    return 0


def main() -> int:
    tools_folder = os.path.dirname(os.path.abspath(__file__))
    cases_path = os.path.join(tools_folder, CASES_FILE)

    if len(sys.argv) == 2 and sys.argv[1] == "--self-test":
        try:
            return run_cases(cases_path)
        except (OSError, ValueError, KeyError) as error:
            print("version_compare: " + str(error), file=sys.stderr)
            return 2

    if len(sys.argv) == 3:
        result = compare(sys.argv[1], sys.argv[2])
        if result is None:
            print("invalid")
        else:
            print(result)
        return 0

    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main())
