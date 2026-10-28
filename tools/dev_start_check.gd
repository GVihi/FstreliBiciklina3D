extends SceneTree
# Checks the developer start options (roadmap alpha D2.1, scripts/dev_start.gd):
#   - the arguments are read: --dev-coins=N, --dev-unlocks=id,id and --dev-unlocks=all; a wrong value is left out and
#     named, and never stops anything; planned unlocks are never granted, not even by `all`,
#   - without an argument nothing changes and nothing is switched on,
#   - with an argument the coins and the unlocks are set in memory and the session is read-only: meta.json, scores.json,
#     run.json and settings.cfg keep their exact bytes through every writer (save, buy, clear, reset, backup), no
#     backup copy appears, and the Unlocks page can still buy in memory,
#   - the switch is the only thing that blocks the writers: with it off they write again,
#   - the options are honoured only where `DevStart.allowed()` says so (the Godot editor binary; this check runs in it,
#     so the refusal in an exported game cannot be run here).
# It keeps the real save files in memory first and puts them back at the end, so running it never costs a player's
# progress (the runner also gives every check its own empty save folder).
# Run from the project folder:
#   godot --headless --path . --script res://tools/dev_start_check.gd
# Exits with status 1 and prints the problems when a check fails.

const DevStart = preload("res://scripts/dev_start.gd")
const Unlocks = preload("res://scripts/unlocks.gd")
const SaveUtil = preload("res://scripts/save_util.gd")
const RunSave = preload("res://scripts/run_save.gd")
const ProgressReset = preload("res://scripts/progress_reset.gd")
const SETTINGS_PATH = "user://settings.cfg"
# the files the writers could touch, each with a marker text that is not valid for any of the formats
const SENTINELS = {
	"meta.json": "SENTINEL meta",
	"scores.json": "SENTINEL scores",
	"run.json": "SENTINEL run",
	"settings.cfg": "SENTINEL settings"
}

var problems = []
var main
var table = []
var kept = {}  # file name in the save folder -> its bytes, the files that were there before the check


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	table = Unlocks.load_table()["unlocks"]
	_keep_user_files()
	_check_parse()
	_check_no_arguments()
	_check_read_only_session()
	SaveUtil.read_only = false
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


# ---- the arguments
func _check_parse() -> void:
	var some = _first_free_ids(2)
	if some.size() < 2:
		_fail(
			"the unlock table has fewer than two unlocks that are in the game, the check cannot run"
		)
		return
	var none = DevStart.parse(PackedStringArray(), table)
	if (
		none["active"]
		or none["coins"] != -1
		or not none["unlocks"].is_empty()
		or not none["problems"].is_empty()
	):
		_fail("no arguments should give an inactive result, got %s" % str(none))
	var other = DevStart.parse(
		PackedStringArray(["--roundabout", "--dev-coin=5", "--dev-unlocks"]), table
	)
	if other["active"]:
		_fail(
			(
				"other arguments, and names that only look alike, must not switch the options on: %s"
				% str(other)
			)
		)
	var coins = DevStart.parse(PackedStringArray(["--dev-coins=500"]), table)
	if not coins["active"] or coins["coins"] != 500 or not coins["unlocks"].is_empty():
		_fail("--dev-coins=500 should set 500 coins and no unlocks, got %s" % str(coins))
	var zero = DevStart.parse(PackedStringArray(["--dev-coins=0"]), table)
	if not zero["active"] or zero["coins"] != 0:
		_fail("--dev-coins=0 is a valid balance, got %s" % str(zero))
	for bad in ["abc", "-5", "1000001", "", "1.5", "12x"]:
		var r = DevStart.parse(PackedStringArray(["--dev-coins=" + bad]), table)
		if not r["active"] or r["coins"] != -1 or r["problems"].size() != 1:
			_fail(
				(
					"--dev-coins=%s should be left out with one problem and still count as given, got %s"
					% [bad, str(r)]
				)
			)
	var ids = DevStart.parse(
		PackedStringArray(["--dev-unlocks=%s,%s,%s" % [some[0], some[1], some[0]]]), table
	)
	if ids["unlocks"] != some or not ids["problems"].is_empty():
		_fail("two ids (one twice) should give those two once each, got %s" % str(ids))
	var spaced = DevStart.parse(
		PackedStringArray(["--dev-unlocks= %s , %s ,," % [some[0], some[1]]]), table
	)
	if spaced["unlocks"] != some:
		_fail("spaces and empty items in the list should be ignored, got %s" % str(spaced))
	var unknown = DevStart.parse(
		PackedStringArray(["--dev-unlocks=%s,no_such_unlock" % some[0]]), table
	)
	if unknown["unlocks"] != [some[0]] or unknown["problems"].size() != 1:
		_fail("an unknown id should be left out and named, the rest kept, got %s" % str(unknown))
	var planned_id = _first_planned_id()
	if planned_id != "":
		var planned = DevStart.parse(PackedStringArray(["--dev-unlocks=" + planned_id]), table)
		if not planned["unlocks"].is_empty() or planned["problems"].size() != 1:
			_fail("a planned unlock must not be granted, got %s" % str(planned))
	var all = DevStart.parse(PackedStringArray(["--dev-unlocks=all"]), table)
	var expected = _first_free_ids(table.size())
	if all["unlocks"] != expected or not all["problems"].is_empty():
		_fail(
			(
				"`all` should give every unlock that is not planned (%d), got %s"
				% [expected.size(), str(all)]
			)
		)
	var both = DevStart.parse(
		PackedStringArray(["--dev-coins=90", "--dev-unlocks=" + some[0]]), table
	)
	if both["coins"] != 90 or both["unlocks"] != [some[0]]:
		_fail("both arguments together should both count, got %s" % str(both))


# ---- a normal start
func _check_no_arguments() -> void:
	var balance = main.meta.balance
	var owned = main.meta.owned.duplicate()
	var r = main.start_dev_options(PackedStringArray())
	if r["active"] or r["applied"] or SaveUtil.read_only:
		_fail(
			(
				"without arguments the options must stay off, got %s and read_only %s"
				% [str(r), SaveUtil.read_only]
			)
		)
	if main.meta.balance != balance or main.meta.owned != owned:
		_fail("without arguments the coins and unlocks must not change")
	var r2 = main.start_dev_options(PackedStringArray(["--roundabout"]))
	if r2["applied"] or SaveUtil.read_only:
		_fail("an unrelated argument must not switch the options on")


# ---- a test session
func _check_read_only_session() -> void:
	var some = _first_free_ids(2)
	if some.size() < 2:
		return
	if not DevStart.allowed():
		_fail("this check has to run with the Godot editor binary: DevStart.allowed() is false")
		return
	_write_sentinels()
	var r = main.start_dev_options(
		PackedStringArray(["--dev-coins=700", "--dev-unlocks=%s,%s" % [some[0], some[1]]])
	)
	if not r["applied"]:
		_fail("the options were not applied: %s" % str(r))
	if main.meta.balance != 700:
		_fail("the balance should be 700, it is %d" % main.meta.balance)
	if not main.meta.owns(some[0]) or not main.meta.owns(some[1]):
		_fail("the two unlocks should be owned")
	if not SaveUtil.read_only:
		_fail("the session should be read-only")
	# every writer, one after the other
	main.meta.save_meta()
	main.scores.save_scores()
	main.settings.save_settings()
	if RunSave.write_file({"x": 1}):
		_fail("RunSave.write_file should refuse in a read-only session")
	RunSave.clear()
	RunSave.backup_before_replace()
	SaveUtil.backup("user://meta.json", "check")
	var failed = ProgressReset.delete_files()
	if not failed.is_empty():
		_fail(
			"delete_files should report nothing failed in a read-only session, got %s" % str(failed)
		)
	main.meta.choose_start_perk("")
	var bought = _buy_something()
	if bought == "":
		_fail("buying in memory should still work in a test session")
	for n in SENTINELS:
		var path = "user://" + n
		if not FileAccess.file_exists(path):
			_fail("%s was deleted in a read-only session" % n)
		elif FileAccess.get_file_as_string(path) != SENTINELS[n]:
			_fail("%s was changed in a read-only session" % n)
	for n in ProgressReset.find_files():
		if not SENTINELS.has(n):
			_fail("%s appeared in a read-only session (a backup or a new file)" % n)
	# the switch is the only thing that blocks the writers
	SaveUtil.read_only = false
	main.meta.save_meta()
	if FileAccess.get_file_as_string("user://meta.json") == SENTINELS["meta.json"]:
		_fail("with the switch off, save_meta should write again")


# ---- helpers
func _first_free_ids(count: int) -> Array:
	var out = []
	for u in table:
		if not bool(u["planned"]) and out.size() < count:
			out.append(str(u["id"]))
	return out


func _first_planned_id() -> String:
	for u in table:
		if bool(u["planned"]):
			return str(u["id"])
	return ""


# buys the first unlock that is in the game, not owned and affordable; returns its id or ""
func _buy_something() -> String:
	for u in table:
		if main.meta.owns(str(u["id"])) or bool(u["planned"]) or int(u["cost"]) > main.meta.balance:
			continue
		if main.meta.buy(u) == "bought":
			return str(u["id"])
	return ""


func _write_sentinels() -> void:
	for n in SENTINELS:
		var f = FileAccess.open("user://" + n, FileAccess.WRITE)
		if f:
			f.store_string(SENTINELS[n])
			f.close()


func _keep_user_files() -> void:
	var names = ProgressReset.find_files()
	if FileAccess.file_exists(SETTINGS_PATH):
		names.append("settings.cfg")
	for n in names:
		kept[n] = FileAccess.get_file_as_bytes("user://" + n)


func _restore_user_files() -> void:
	for n in ProgressReset.find_files():
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://" + n))
	for n in kept:
		var f = FileAccess.open("user://" + n, FileAccess.WRITE)
		if f:
			f.store_buffer(kept[n])
			f.close()
	if not kept.has("settings.cfg") and FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _finish() -> void:
	if problems.is_empty():
		print(
			"dev_start_check: the start options set coins and unlocks in memory, never write a save file and ignore wrong values"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("dev_start_check: " + line)
		quit(1)
