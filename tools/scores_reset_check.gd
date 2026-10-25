extends SceneTree
# Checks RESET LEADERBOARD on the High Scores page of the title screen (README Milestone A, High Scores):
#   - Delete opens a confirmation, and it does nothing when the list is empty,
#   - NO and Esc go back to the list without touching it, NO is the default, YES ignores input for a moment,
#   - YES erases the list, saves the empty list and keeps a .reset.bak copy of the old file,
#   - the mouse works on the RESET LEADERBOARD button and on NO / YES.
# It saves the real scores.json first and puts it back at the end, so running it never costs a player's scores.
# Run from the project folder:
#   godot --headless --path . --script res://tools/scores_reset_check.gd
# or with tools\run_scores_reset_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main
var saved_scores = PackedByteArray()
var had_scores = false
var had_backup = false
var saved_backup = PackedByteArray()


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	main.go_to_title()
	main.hud.size = Vector2(1280.0, 720.0)
	var scores_item = -1
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == "scores":
			scores_item = i
	if scores_item < 0:
		_fail("the title menu has no HIGH SCORES entry")
		_finish()
		return

	# an empty list has nothing to reset: Delete does nothing
	main.scores.entries = []
	main.input_sys.title_activate(scores_item)
	_press(KEY_DELETE)
	if main.title_page != "scores":
		_fail("Delete on an empty list opened '%s'" % main.title_page)

	# a list with two runs
	_fill_list()
	_press(KEY_DELETE)
	if main.title_page != "scores_confirm" or main.confirm_sel != 0:
		_fail(
			(
				"Delete did not open the confirmation with NO selected (page '%s', sel %d)"
				% [main.title_page, main.confirm_sel]
			)
		)
	# Enter on the default NO, and Esc, go back with the list unchanged
	_press(KEY_ENTER)
	if main.title_page != "scores" or main.scores.entries.size() != 2:
		_fail("NO did not go back to the list unchanged (page '%s')" % main.title_page)
	_press(KEY_DELETE)
	_press(KEY_ESCAPE)
	if main.title_page != "scores" or main.scores.entries.size() != 2:
		_fail("Esc on the confirmation did not go back to the list (page '%s')" % main.title_page)

	# YES right after the page opens is ignored (a double click must not erase the list)
	_press(KEY_DELETE)
	_press(KEY_RIGHT)
	if main.confirm_sel != 1:
		_fail("Right did not move the highlight to YES")
	_press(KEY_ENTER)
	if main.title_page != "scores_confirm" or main.scores.entries.size() != 2:
		_fail("YES worked in the first 0.3 s after the page opened")
	# YES after the delay erases and saves
	main.time += 0.5
	_press(KEY_ENTER)
	if main.scores.entries.size() != 0 or main.title_page != "scores":
		_fail(
			(
				"YES did not erase the list (entries %d, page '%s')"
				% [main.scores.entries.size(), main.title_page]
			)
		)
	main.scores.load_scores()
	if main.scores.entries.size() != 0:
		_fail("the saved scores file still has %d entries" % main.scores.entries.size())
	if not FileAccess.file_exists(main.scores.PATH + ".reset.bak"):
		_fail("no scores.json.reset.bak copy of the old list was kept")
	else:
		var old = JSON.parse_string(FileAccess.get_file_as_string(main.scores.PATH + ".reset.bak"))
		if not (old is Dictionary) or (old.get("entries", []) as Array).size() != 2:
			_fail("the .reset.bak copy does not hold the two old entries")

	# the mouse. The click handler reads the real mouse position, which a headless run cannot move, so this checks
	# what a click uses: where the buttons are, what is under a point, and the hover highlight
	_fill_list()
	var rr = main.hud.scores_reset_rect()
	if rr.position.x < 0.0 or rr.end.x > 1280.0 or rr.end.y > 720.0 * 0.94 - 18.0:
		_fail("the RESET LEADERBOARD button is not clear of the screen edge and the hint line")
	var last_row_y = 720.0 * 0.27 + 10.0 * 34.0
	if rr.position.y < last_row_y:
		_fail("the RESET LEADERBOARD button overlaps the tenth row of the list")
	if main.hud.scores_confirm_at(Vector2(640.0, 360.0)) != -1:
		_fail("scores_confirm_at answers on the list page")
	main.input_sys.scores_reset_open()  # what a click on the button calls
	if main.title_page != "scores_confirm":
		_fail("scores_reset_open did not open the confirmation")
	var no_pos = main.hud.confirm_rect(0).get_center()
	var yes_pos = main.hud.confirm_rect(1).get_center()
	if main.hud.scores_confirm_at(no_pos) != 0 or main.hud.scores_confirm_at(yes_pos) != 1:
		_fail("scores_confirm_at does not find the NO and YES buttons")
	if main.hud.scores_confirm_at(Vector2(5.0, 5.0)) != -1:
		_fail("scores_confirm_at answers away from the buttons")
	main.input_sys.hover_menu(yes_pos)
	if main.confirm_sel != 1:
		_fail("hovering YES did not highlight it")
	main.input_sys.scores_confirm_activate(0)  # what a click on NO calls
	if main.title_page != "scores" or main.scores.entries.size() != 2:
		_fail("NO did not go back with the list unchanged")
	main.input_sys.scores_reset_open()
	main.time += 0.5
	main.input_sys.scores_confirm_activate(1)  # what a click on YES calls
	if main.scores.entries.size() != 0:
		_fail("YES did not erase the list")
	# gamepad X opens it too, and B goes back
	_fill_list()
	main.input_sys.on_pad_button(JOY_BUTTON_X)
	if main.title_page != "scores_confirm":
		_fail("gamepad X did not open the confirmation")
	main.input_sys.on_pad_button(JOY_BUTTON_B)
	if main.title_page != "scores" or main.scores.entries.size() != 2:
		_fail("gamepad B did not go back to the list")
	_restore_user_files()
	_finish()


func _finish() -> void:
	_restore_user_files()
	if problems.is_empty():
		print(
			"scores_reset_check: RESET LEADERBOARD asks first, keeps a backup, erases and saves as it should"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("scores_reset_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _fill_list() -> void:
	main.scores.entries = [
		{"name": "AAA", "score": 900, "round": 3, "kills": 20, "time": 300, "date": "2026-01-01"},
		{"name": "BBB", "score": 500, "round": 2, "kills": 10, "time": 150, "date": "2026-01-02"}
	]
	main.scores.save_scores()
	main.title_page = "scores"


func _press(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


# the real save files are kept in memory and written back at the end
func _keep_user_files() -> void:
	var path = main.scores.PATH
	had_scores = FileAccess.file_exists(path)
	if had_scores:
		saved_scores = FileAccess.get_file_as_bytes(path)
	had_backup = FileAccess.file_exists(path + ".reset.bak")
	if had_backup:
		saved_backup = FileAccess.get_file_as_bytes(path + ".reset.bak")


func _restore_user_files() -> void:
	var path = main.scores.PATH
	_put(path, had_scores, saved_scores)
	_put(path + ".reset.bak", had_backup, saved_backup)
	main.scores.load_scores()


func _put(path: String, existed: bool, bytes: PackedByteArray) -> void:
	if existed:
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(bytes)
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
