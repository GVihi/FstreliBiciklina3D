extends RefCounted
# Compares two game versions (roadmap V2.3). The same rules as tools/version_compare.py and the website's code; the
# rules and the test cases are in tools/version_compare_cases.json, and `python tools/run_checks.py version_compare`
# runs every case against this file.
#   - a version is MAJOR.MINOR.PATCH (numbers without leading zeros), optionally -pre.release: 0.10.0 is newer than
#     0.9.0, and 0.3.0-alpha is older than 0.3.0,
#   - anything else is not a version: compare() answers INVALID, and the update check (V4.4) shows "unknown" for it
#     and never "up to date". No regular expressions on purpose, so the three implementations parse the same way.

const OLDER = -1
const EQUAL = 0
const NEWER = 1
const INVALID = -99
const MAX_DIGITS = 9
const DIGITS = "0123456789"
const LETTERS_AND_DIGITS = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz"


# OLDER when a is older than b, EQUAL, NEWER, or INVALID when either one is not a valid version.
static func compare(a: String, b: String) -> int:
	var parsed_a = parse(a)
	var parsed_b = parse(b)
	if parsed_a.is_empty() or parsed_b.is_empty():
		return INVALID
	var numbers_a: Array = parsed_a["numbers"]
	var numbers_b: Array = parsed_b["numbers"]
	for i in range(3):
		if numbers_a[i] < numbers_b[i]:
			return OLDER
		if numbers_a[i] > numbers_b[i]:
			return NEWER
	# same numbers: a version without a pre-release is the newer one
	var pre_a: Array = parsed_a["pre"]
	var pre_b: Array = parsed_b["pre"]
	if pre_a.is_empty() and pre_b.is_empty():
		return EQUAL
	if pre_a.is_empty():
		return NEWER
	if pre_b.is_empty():
		return OLDER
	var shared = mini(pre_a.size(), pre_b.size())
	for i in range(shared):
		var result = _compare_identifiers(str(pre_a[i]), str(pre_b[i]))
		if result != EQUAL:
			return result
	# all shared identifiers are equal: more identifiers is newer
	if pre_a.size() < pre_b.size():
		return OLDER
	if pre_a.size() > pre_b.size():
		return NEWER
	return EQUAL


static func is_valid(version: String) -> bool:
	return not parse(version).is_empty()


# {"numbers": [major, minor, patch], "pre": [identifiers as text]} or {} when the text is not a valid version.
static func parse(version: String) -> Dictionary:
	if version.is_empty():
		return {}
	var core = version
	var pre_text = ""
	var has_pre = false
	var dash = version.find("-")
	if dash != -1:
		core = version.substr(0, dash)
		pre_text = version.substr(dash + 1)
		has_pre = true
	var core_parts = core.split(".")
	if core_parts.size() != 3:
		return {}
	var numbers = []
	for part in core_parts:
		if not _is_number_text(part):
			return {}
		numbers.append(int(part))
	var pre = []
	if has_pre:
		for identifier in pre_text.split("."):
			if identifier.is_empty():
				return {}
			if not _only_chars(identifier, LETTERS_AND_DIGITS):
				return {}
			# an identifier made only of digits is a number: no leading zero
			if _only_chars(identifier, DIGITS) and not _is_number_text(identifier):
				return {}
			pre.append(identifier)
	return {"numbers": numbers, "pre": pre}


static func _compare_identifiers(a: String, b: String) -> int:
	var a_is_number = _only_chars(a, DIGITS)
	var b_is_number = _only_chars(b, DIGITS)
	if a_is_number and b_is_number:
		if int(a) < int(b):
			return OLDER
		if int(a) > int(b):
			return NEWER
		return EQUAL
	# a number is older than a text
	if a_is_number:
		return OLDER
	if b_is_number:
		return NEWER
	# two texts: ASCII order (capitals before small letters), compared letter by letter
	var length = mini(a.length(), b.length())
	for i in range(length):
		var code_a = a.unicode_at(i)
		var code_b = b.unicode_at(i)
		if code_a < code_b:
			return OLDER
		if code_a > code_b:
			return NEWER
	if a.length() < b.length():
		return OLDER
	if a.length() > b.length():
		return NEWER
	return EQUAL


# 0 is fine, 03 is not; at most MAX_DIGITS digits; digits only
static func _is_number_text(text: String) -> bool:
	if text.is_empty() or text.length() > MAX_DIGITS:
		return false
	if not _only_chars(text, DIGITS):
		return false
	if text.length() > 1 and text[0] == "0":
		return false
	return true


# true when every character of `text` is one of `allowed` (an empty text is true)
static func _only_chars(text: String, allowed: String) -> bool:
	for i in range(text.length()):
		if allowed.find(text[i]) == -1:
			return false
	return true
