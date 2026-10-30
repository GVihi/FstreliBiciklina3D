extends SceneTree
# Checks the version comparison (roadmap V2.3): scripts/version_compare.gd against the shared cases in
# tools/version_compare_cases.json, the same file tools/version_compare.py and the website's code run.
#   - every pair in "compare" gives the expected answer and the opposite one the other way round,
#   - every text in "valid" is valid and every text in "invalid" is not, and an invalid text never has an answer,
#   - the pairs in "invalid_pairs" have no answer,
#   - the cases file itself is complete (so an empty file cannot pass by checking nothing).
# Run from the project folder:
#   godot --headless --path . --script res://tools/version_compare_check.gd
# or: python tools/run_checks.py version_compare
# Exits with status 1 and prints the problems when a check fails.

const VersionCompare = preload("res://scripts/version_compare.gd")
const CASES = "res://tools/version_compare_cases.json"
const MIN_COMPARE_CASES = 20
const MIN_VALID = 5
const MIN_INVALID = 20

var problems = []
var checked = 0


func _initialize() -> void:
	var cases = _load_cases()
	if not cases.is_empty():
		_check_compare(cases["compare"])
		_check_valid(cases["valid"])
		_check_invalid(cases["invalid"])
		_check_invalid_pairs(cases["invalid_pairs"])
	_finish()


func _load_cases() -> Dictionary:
	var file = FileAccess.open(CASES, FileAccess.READ)
	if file == null:
		_fail("cannot open " + CASES)
		return {}
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		_fail("%s is not valid JSON" % CASES)
		return {}
	if typeof(json.data) != TYPE_DICTIONARY:
		_fail("%s does not hold an object" % CASES)
		return {}
	var data: Dictionary = json.data
	for key in ["compare", "valid", "invalid", "invalid_pairs"]:
		if not data.has(key) or typeof(data[key]) != TYPE_ARRAY:
			_fail("%s has no list called '%s'" % [CASES, key])
			return {}
	if data["compare"].size() < MIN_COMPARE_CASES:
		_fail(
			(
				"only %d compare cases, expected at least %d"
				% [data["compare"].size(), MIN_COMPARE_CASES]
			)
		)
	if data["valid"].size() < MIN_VALID or data["invalid"].size() < MIN_INVALID:
		_fail("the valid or invalid list is too short")
	return data


func _check_compare(list: Array) -> void:
	for case in list:
		var a = str(case["a"])
		var b = str(case["b"])
		var expected = int(case["expect"])
		_expect(
			VersionCompare.compare(a, b) == expected, "compare(%s, %s) is not %d" % [a, b, expected]
		)
		_expect(
			VersionCompare.compare(b, a) == -expected,
			"compare(%s, %s) is not %d" % [b, a, -expected]
		)


func _check_valid(list: Array) -> void:
	for version in list:
		_expect(VersionCompare.is_valid(str(version)), "'%s' should be valid" % version)


func _check_invalid(list: Array) -> void:
	for version in list:
		var text = str(version)
		_expect(not VersionCompare.is_valid(text), "'%s' should be invalid" % text)
		var forward = VersionCompare.compare(text, "0.3.0")
		var backward = VersionCompare.compare("0.3.0", text)
		_expect(
			forward == VersionCompare.INVALID and backward == VersionCompare.INVALID,
			"compare with the invalid '%s' should have no answer" % text
		)


func _check_invalid_pairs(list: Array) -> void:
	for pair in list:
		var result = VersionCompare.compare(str(pair["a"]), str(pair["b"]))
		_expect(
			result == VersionCompare.INVALID,
			"compare('%s', '%s') should have no answer" % [pair["a"], pair["b"]]
		)


func _expect(condition: bool, text: String) -> void:
	checked += 1
	if not condition:
		_fail(text)


func _finish() -> void:
	if problems.is_empty():
		print("version_compare_check: %d checks passed against the shared cases" % checked)
		quit(0)
	else:
		for line in problems.slice(0, 20):
			printerr("version_compare_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
