extends SceneTree
# Checks RESET ALL PROGRESS, the red row at the bottom of the settings panel (title screen and pause menu):
#   - the row is the last one, a button (not a slider or a switch), set apart from the settings and on screen,
#   - Enter, gamepad A and a click open a first warning, Left / Right do nothing on the row,
#   - NO, Esc and gamepad B go back to the settings on both warnings and wipe nothing,
#   - YES on the first warning opens the second ("ARE YOU ABSOLUTELY SURE?") and still wipes nothing,
#   - YES ignores input for a moment after each warning opens (a double click cannot skip through),
#   - YES on the second warning deletes meta.json, scores.json, run.json, hi.dat and every .bak copy of them,
#     empties coins, unlocks, loadout, challenge counts, XP, the leaderboard, the HI score and the saved run in memory,
#     keeps settings.cfg, and shows "ALL PROGRESS WIPED" on the settings page of the title screen,
#   - started from the pause menu it drops the run in progress too and lands on the title screen,
#   - the mouse works on the row and on NO / YES, and the pages draw at two window sizes.
# It keeps the real save files in memory first and puts them back at the end, so running it never costs a player's
# progress (the runner also gives every check its own empty save folder).
# Run from the project folder:
#   godot --headless --path . --script res://tools/progress_reset_check.gd
# Exits with status 1 and prints the problems when a check fails.

const ProgressReset = preload("res://scripts/progress_reset.gd")
const SEED = 0x2468ACE1
const SETTINGS_PATH = "user://settings.cfg"
# the progress files and backup copies `_make_progress` writes
const MADE = [
	"meta.json",
	"scores.json",
	"run.json",
	"hi.dat",
	"meta.json.bad.bak",
	"scores.json.reset.bak",
	"run.json.replaced.bak",
	"run.json.v2.bak"
]

var problems = []
var main
var kept = {}  # file name in the save folder -> its bytes, the files that were there before the check


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	main.hud.size = Vector2(1280.0, 720.0)
	_check_file_names()
	await _check_title()
	await _check_pause()
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	problems.append(text)


func _key(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


func _write(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


# which file names count as progress: the four files and their .bak copies, nothing else
func _check_file_names() -> void:
	for n in [
		"meta.json",
		"scores.json",
		"run.json",
		"hi.dat",
		"meta.json.bad.bak",
		"scores.json.reset.bak",
		"run.json.replaced.bak",
		"run.json.v2.bak"
	]:
		if not ProgressReset.is_progress_file(n):
			_fail("%s is not counted as a progress file" % n)
	for n in [
		"settings.cfg",
		"settings.cfg.bad.bak",
		"other.json",
		"meta.jsonx",
		"xmeta.json",
		"scores.json.txt",
		"meta.json.bak.txt"
	]:
		if ProgressReset.is_progress_file(n):
			_fail("%s is counted as a progress file" % n)


# the player has progress: coins, unlocks, a loadout, challenge counts, XP, a leaderboard, a saved run, old backups
func _make_progress() -> void:
	var m = main.meta
	m.balance = 42
	m.total_earned = 100
	m.owned = {"some_unlock": true}
	m.start_perk = "some_unlock"
	m.weapon_choice = {"primary": "dart_gun"}
	m.challenge_counts = {"some_challenge": 2}
	m.xp = 500
	m.save_meta()
	main.scores.entries = [
		{"name": "AAA", "score": 900, "round": 3, "kills": 20, "time": 300, "date": "2026-01-01"}
	]
	main.scores.save_scores()
	main.hi = 900
	_write("user://run.json", '{"version": 1, "run": {"run_seed": 1}}')
	_write("user://hi.dat", "900")
	_write("user://meta.json.bad.bak", "old")
	_write("user://scores.json.reset.bak", "old")
	_write("user://run.json.replaced.bak", "old")
	_write("user://run.json.v2.bak", "old")
	main.settings.save_settings()  # settings.cfg has to be there, to show the wipe keeps it
	main.saved_run = {"run_seed": 1}


func _expect_progress_there(where: String) -> void:
	for n in MADE:
		if not FileAccess.file_exists("user://" + n):
			_fail("%s: %s was deleted before the second YES" % [where, n])
	if main.meta.balance != 42 or main.meta.xp != 500 or main.scores.entries.size() != 1:
		_fail("%s: progress was changed before the second YES" % where)
	if not FileAccess.file_exists(SETTINGS_PATH):
		_fail("%s: settings.cfg is missing" % where)


func _expect_wiped(where: String) -> void:
	var left = ProgressReset.find_files()
	if not left.is_empty():
		_fail("%s: progress files are still in the save folder: %s" % [where, left])
	var m = main.meta
	if m.balance != 0 or m.total_earned != 0 or m.xp != 0 or m.start_perk != "":
		_fail("%s: coins, XP or the start perk were not reset" % where)
	if (
		not m.owned.is_empty()
		or not m.weapon_choice.is_empty()
		or not m.challenge_counts.is_empty()
	):
		_fail("%s: unlocks, loadout or challenge counts were not reset" % where)
	if not main.scores.entries.is_empty() or main.hi != 0:
		_fail("%s: the leaderboard or the HI score was not reset" % where)
	if not main.saved_run.is_empty():
		_fail("%s: the saved run is still there (CONTINUE would show)" % where)
	if not FileAccess.file_exists(SETTINGS_PATH):
		_fail("%s: settings.cfg was deleted, it is not progress" % where)
	if main.progress_wipe_failed != 0 or main.time - main.progress_wiped_t0 > 6.0:
		_fail("%s: the wipe did not report that it is done" % where)
	# nothing comes back from disk
	m.load_meta()
	main.scores.load_scores()
	if m.balance != 0 or m.xp != 0 or not main.scores.entries.is_empty():
		_fail("%s: progress came back from the files after a reload" % where)
	main.refresh_saved_run()
	if not main.saved_run.is_empty():
		_fail("%s: a saved run came back from run.json" % where)


# the same walk through the two warnings for both places the panel lives (the caller has opened the panel); `page` is
# the variable that holds the page (title_page or pause_page) and `opened` the page the first warning opens;
# NO and Esc go back to "settings". The walk ends with the final YES, which wipes.
func _warnings(where: String, on_pause: bool, pad: bool) -> void:
	var inp = main.input_sys
	var page = "pause_page" if on_pause else "title_page"
	var opened = "confirm" if on_pause else "reset_confirm"
	var n = main.hud.setting_rows().size()
	main.setting_sel = n - 1
	_make_progress()

	# Left / Right do nothing on the button, and the panel stays open
	_key(KEY_RIGHT)
	_key(KEY_LEFT)
	if main.get(page) != "settings":
		_fail("%s: Left / Right on the button changed the page to '%s'" % [where, main.get(page)])

	# Enter opens the first warning with NO picked, and wipes nothing
	_key(KEY_ENTER)
	if main.get(page) != opened or main.confirm_id != "reset1" or main.confirm_sel != 0:
		_fail("%s: Enter on the button did not open the first warning with NO picked" % where)
	_expect_progress_there(where + ", first warning open")
	# the pages draw at two window sizes
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		main.hud.queue_redraw()
		await process_frame
	main.hud.size = Vector2(1280.0, 720.0)

	# Enter on the default NO, and Esc, go back to the settings
	_key(KEY_ENTER)
	if main.get(page) != "settings":
		_fail(
			(
				"%s: NO on the first warning did not go back to the settings (page '%s')"
				% [where, main.get(page)]
			)
		)
	_key(KEY_ENTER)
	_key(KEY_ESCAPE)
	if main.get(page) != "settings":
		_fail(
			(
				"%s: Esc on the first warning did not go back to the settings (page '%s')"
				% [where, main.get(page)]
			)
		)
	_expect_progress_there(where + ", after NO")

	# the first YES, right after the page opens, is ignored (a double click)
	_key(KEY_ENTER)
	_key(KEY_RIGHT)
	if main.confirm_sel != 1:
		_fail("%s: Right did not move the highlight to YES" % where)
	_key(KEY_ENTER)
	if main.confirm_id != "reset1" or main.get(page) != opened:
		_fail("%s: YES worked in the first 0.3 s after the first warning opened" % where)
	# after the delay YES shows the second warning, NO picked again, and still wipes nothing
	main.time += 0.5
	_key(KEY_ENTER)
	if main.confirm_id != "reset2" or main.get(page) != opened or main.confirm_sel != 0:
		_fail(
			(
				"%s: YES on the first warning did not open the second with NO picked (id '%s', sel %d)"
				% [where, main.confirm_id, main.confirm_sel]
			)
		)
	_expect_progress_there(where + ", second warning open")

	# the second YES, right after the second warning opens, is ignored too (no frame is awaited before it, so
	# less than 0.3 s have passed)
	_key(KEY_RIGHT)
	_key(KEY_ENTER)
	if main.confirm_id != "reset2" or main.get(page) != opened:
		_fail("%s: YES worked in the first 0.3 s after the second warning opened" % where)
	_expect_progress_there(where + ", early YES")
	main.hud.queue_redraw()  # the second warning draws
	await process_frame
	# Esc on the second warning goes back to the settings and wipes nothing
	_key(KEY_ESCAPE)
	if main.get(page) != "settings":
		_fail("%s: Esc on the second warning did not go back to the settings" % where)
	_expect_progress_there(where + ", Esc on the second warning")

	# the gamepad: A opens, the D-pad moves to YES, B goes back
	if pad:
		inp.on_pad_button(JOY_BUTTON_A)
		if main.get(page) != opened or main.confirm_id != "reset1":
			_fail("%s: gamepad A on the button did not open the first warning" % where)
		inp.on_pad_button(JOY_BUTTON_DPAD_DOWN)  # the two buttons are stacked, so Up / Down move between them
		if main.confirm_sel != 1:
			_fail("%s: the D-pad did not move the highlight to YES" % where)
		inp.on_pad_button(JOY_BUTTON_B)
		if main.get(page) != "settings":
			_fail("%s: gamepad B on the first warning did not go back to the settings" % where)
		_expect_progress_there(where + ", after gamepad B")

	# the mouse: where the row and the buttons are, and what a click on them calls
	var hud = main.hud
	var row = hud.row_rect(n - 1)
	var pr = hud.panel_rect()
	if row.end.y > pr.end.y or row.position.y < hud.row_rect(n - 2).end.y + 4.0:
		_fail(
			(
				"%s: the red row is not set apart from the last setting or sticks out of the panel"
				% where
			)
		)
	if hud.setting_at(row.get_center()) != "reset_progress" or not hud.is_action("reset_progress"):
		_fail("%s: a point on the red row does not find the button" % where)
	if hud.is_toggle("reset_progress"):
		_fail("%s: the button is treated as a switch" % where)
	if hud.confirm_at(Vector2(640.0, 360.0)) != -1:
		_fail("%s: confirm_at answers while the settings are showing" % where)
	if not main.settings.click_setting("reset_progress") or main.get(page) != opened:
		_fail("%s: a click on the red row did not open the first warning" % where)
	var no_pos = hud.confirm_rect(0).get_center()
	var yes_pos = hud.confirm_rect(1).get_center()
	if (
		hud.confirm_at(no_pos) != 0
		or hud.confirm_at(yes_pos) != 1
		or hud.confirm_at(Vector2(5.0, 5.0)) != -1
	):
		_fail("%s: confirm_at does not find the NO and YES buttons" % where)
	inp.hover_menu(yes_pos)
	if main.confirm_sel != 1:
		_fail("%s: hovering YES did not highlight it" % where)
	inp.confirm_activate(0)  # what a click on NO calls
	if main.get(page) != "settings":
		_fail("%s: a click on NO did not go back to the settings" % where)
	_expect_progress_there(where + ", after a click on NO")

	# the whole way through with clicks and keys: first YES, second YES, wipe
	_key(KEY_ENTER)
	_key(KEY_RIGHT)
	main.time += 0.5
	_key(KEY_ENTER)
	_key(KEY_RIGHT)
	main.time += 0.5
	if main.confirm_id != "reset2":
		_fail("%s: the second warning did not open before the final YES" % where)
	_key(KEY_ENTER)


func _check_title() -> void:
	main.go_to_title()
	main.title_page = "settings"
	await process_frame
	# the button is the last row, and a button, not a setting
	var rows = main.hud.setting_rows()
	var last = rows[rows.size() - 1]
	if (
		last["id"] != "reset_progress"
		or not last.get("action", false)
		or not last.get("danger", false)
	):
		_fail("the last row of the settings panel is not the red RESET ALL PROGRESS button")
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		var pr = main.hud.panel_rect()
		if pr.position.y < 0.0 or pr.end.y > s.y * 0.88:  # the hint lines start at 0.89 of the height
			_fail("the settings panel does not fit the window at %s" % s)
		main.setting_sel = rows.size() - 1
		main.hud.queue_redraw()
		await process_frame
	main.hud.size = Vector2(1280.0, 720.0)
	await _warnings("title", false, true)
	if main.state != "title" or main.title_page != "settings":
		_fail(
			(
				"title: after the wipe the player is not on the settings page (page '%s')"
				% main.title_page
			)
		)
	_expect_wiped("title")
	main.hud.queue_redraw()
	await process_frame


func _check_pause() -> void:
	main.start_game(false, SEED)
	if main.state == "map":
		main.pick_node(0)
	# headless Godot cannot capture the mouse, so the test hook plays the round
	main.force_captured = true
	await process_frame
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		return
	main.pause_on_focus_loss()
	await process_frame
	await process_frame
	if not main.paused:
		_fail("could not pause the round")
		return
	main.pause_page = "settings"
	await process_frame
	await _warnings("pause", true, true)
	await process_frame
	if main.state != "title" or main.title_page != "settings":
		_fail(
			(
				"pause: after the wipe the run was not dropped and the player is not on the title settings (state '%s', page '%s')"
				% [main.state, main.title_page]
			)
		)
	_expect_wiped("pause")


# the real save files are kept in memory and written back at the end
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
	main.meta.load_meta()
	main.scores.load_scores()


func _finish() -> void:
	if problems.is_empty():
		print(
			"progress_reset_check: RESET ALL PROGRESS asks twice, wipes only after the second YES, keeps the settings and works from the title screen and the pause menu"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("progress_reset_check: " + line)
		quit(1)
