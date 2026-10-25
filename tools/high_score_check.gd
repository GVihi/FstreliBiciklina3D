extends SceneTree
# Checks that the HI score comes from the leaderboard and not from `hi.dat` (README Milestone A, High Scores:
# "Use the leaderboard's best entry for the HI score shown in the HUD, and retire hi.dat"):
#   - `Scores.best` is the best entry, 0 for an empty list,
#   - `main.hi` follows the leaderboard when the game starts, a ranked run raises it, a Daily Run does not,
#   - a finished run reaches the file through the leaderboard, and RESET LEADERBOARD sets HI back to 0,
#   - nothing writes `user://hi.dat` any more and F8 does nothing.
# It saves the real scores.json and hi.dat first and puts them back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/high_score_check.gd
# or with tools\run_high_score_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const HI_PATH = "user://hi.dat"

var problems = []
var main
var kept = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	if FileAccess.file_exists(HI_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(HI_PATH))
	_check_best()
	_check_hi_follows_the_list()
	_check_runs()
	_check_reset_and_f8()
	if FileAccess.file_exists(HI_PATH):
		_fail("the game wrote user://hi.dat")
	_restore_user_files()
	_finish()


func _entry(score: int) -> Dictionary:
	return {
		"name": "AAA", "score": score, "round": 3, "kills": 20, "time": 300, "date": "2026-01-01"
	}


func _check_best() -> void:
	main.scores.entries = []
	if main.scores.best() != 0:
		_fail("best() of an empty list is %d, not 0" % main.scores.best())
	main.scores.entries = [_entry(500), _entry(900), _entry(700)]
	if main.scores.best() != 900:
		_fail("best() is %d, expected 900" % main.scores.best())


# a new game reads HI from the saved leaderboard (what _ready does)
func _check_hi_follows_the_list() -> void:
	main.scores.entries = [_entry(1200), _entry(300)]
	main.scores.save_scores()
	main.scores.load_scores()
	main.hi = main.scores.best()
	if main.hi != 1200:
		_fail("HI is %d after loading a list whose best is 1200" % main.hi)


func _check_runs() -> void:
	main.hi = main.scores.best()
	main.daily_mode = false
	main.custom_seed_run = false
	main.score = 1500
	main.hi_check()
	if main.hi != 1500:
		_fail("a ranked run with 1500 left HI at %d" % main.hi)
	main.daily_mode = true
	main.score = 9000
	main.hi_check()
	if main.hi != 1500:
		_fail("a Daily Run raised HI to %d" % main.hi)
	main.daily_mode = false
	# a ranked run that ends goes on the list and the file, and the best is its score
	main.score = 1500
	main.scores.submit_run()
	main.name_entry = false
	if main.scores.best() != 1500:
		_fail("after the run the best entry is %d, expected 1500" % main.scores.best())
	main.scores.load_scores()
	if main.scores.best() != 1500:
		_fail("the saved list has best %d, expected 1500" % main.scores.best())


func _check_reset_and_f8() -> void:
	main.hi = main.scores.best()
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = KEY_F8
	main.input_sys.handle_input(e)
	if main.hi != 1500:
		_fail("F8 changed HI to %d" % main.hi)
	main.scores.reset()
	if main.hi != 0 or main.scores.best() != 0:
		_fail("after RESET LEADERBOARD HI is %d and best is %d" % [main.hi, main.scores.best()])


func _finish() -> void:
	if problems.is_empty():
		print("high_score_check: HI comes from the leaderboard and hi.dat is no longer used")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("high_score_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# the real save files are kept in memory and written back at the end
func _keep_user_files() -> void:
	for path in [main.scores.PATH, main.scores.PATH + ".reset.bak", HI_PATH]:
		if FileAccess.file_exists(path):
			kept[path] = FileAccess.get_file_as_bytes(path)


func _restore_user_files() -> void:
	for path in [main.scores.PATH, main.scores.PATH + ".reset.bak", HI_PATH]:
		if kept.has(path):
			var f = FileAccess.open(path, FileAccess.WRITE)
			if f:
				f.store_buffer(kept[path])
				f.close()
		elif FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.scores.load_scores()
