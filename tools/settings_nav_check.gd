extends SceneTree
# Checks keyboard and gamepad navigation of the settings panel (README Milestone A, menu follow-ups). Run from the
# project folder:
#   godot --headless --path . --script res://tools/settings_nav_check.gd
# or with tools\run_settings_nav_check.bat on Windows.
#
# On the title screen and on the pause menu: Up / Down (and the D-pad) pick a row and wrap round, Left / Right change
# it (a slider moves one twentieth of its range and stops at its ends, a switch goes off / on, GRAPHICS steps through
# its choices), Enter and A flip a switch or step GRAPHICS and do nothing on a slider, none of them close the panel,
# Esc closes it, the mouse moving over a row picks it, and the panel draws at two window sizes. The keys do nothing
# while the panel is not showing.
# Changing a setting saves `user://settings.cfg`, so the check puts the real file back at the end.
# Exits with status 1 and prints the problems when a check fails.

const SEED = 0x2468ACE1
const SETTINGS_PATH = "user://settings.cfg"

var problems = []
var main
var kept = PackedByteArray()
var had_file = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
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


func _row_of(id: String) -> int:
	var rows = main.hud.setting_rows()
	for i in range(rows.size()):
		if rows[i]["id"] == id:
			return i
	_fail("the settings panel has no %s row" % id)
	return 0


func _near(a: float, b: float) -> bool:
	return absf(a - b) < 0.0001


# the same checks for both places the panel lives (the caller has opened it); `pad` also presses the D-pad and A
func _check_panel(where: String, pad: bool) -> void:
	var hud = main.hud
	var inp = main.input_sys
	var sets = main.settings
	var n = hud.setting_rows().size()
	if not hud.settings_visible():
		_fail("%s: the settings panel is not showing" % where)
		return
	# Up / Down pick a row and wrap round
	main.setting_sel = 0
	_key(KEY_DOWN)
	if main.setting_sel != 1:
		_fail("%s: Down did not move to row 1 (row %d)" % [where, main.setting_sel])
	_key(KEY_UP)
	_key(KEY_UP)
	if main.setting_sel != n - 1:
		_fail(
			(
				"%s: Up from the first row did not wrap to the last (row %d)"
				% [where, main.setting_sel]
			)
		)
	_key(KEY_DOWN)
	if main.setting_sel != 0:
		_fail(
			(
				"%s: Down from the last row did not wrap to the first (row %d)"
				% [where, main.setting_sel]
			)
		)
	if pad:
		inp.on_pad_button(JOY_BUTTON_DPAD_DOWN)
		if main.setting_sel != 1:
			_fail("%s: D-pad down did not move to row 1 (row %d)" % [where, main.setting_sel])
		inp.on_pad_button(JOY_BUTTON_DPAD_UP)
		if main.setting_sel != 0:
			_fail("%s: D-pad up did not move back to row 0 (row %d)" % [where, main.setting_sel])
	# a slider: Left / Right move it by a twentieth of its range, and it stops at its ends
	main.setting_sel = _row_of("fov")
	sets.set_setting("fov", 80.0)
	_key(KEY_RIGHT)
	if not _near(main.fov_hip, 82.25):
		_fail("%s: Right on FIELD OF VIEW gave %.3f, not 82.25" % [where, main.fov_hip])
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	if not _near(main.fov_hip, 77.75):
		_fail("%s: Left twice on FIELD OF VIEW gave %.3f, not 77.75" % [where, main.fov_hip])
	sets.set_setting("fov", 105.0)
	_key(KEY_RIGHT)
	if not _near(main.fov_hip, 105.0):
		_fail("%s: Right at the top of FIELD OF VIEW gave %.3f, not 105" % [where, main.fov_hip])
	if pad:
		sets.set_setting("fov", 80.0)
		inp.on_pad_button(JOY_BUTTON_DPAD_RIGHT)
		if not _near(main.fov_hip, 82.25):
			_fail("%s: D-pad right on FIELD OF VIEW gave %.3f, not 82.25" % [where, main.fov_hip])
		inp.on_pad_button(JOY_BUTTON_DPAD_LEFT)
		if not _near(main.fov_hip, 80.0):
			_fail("%s: D-pad left on FIELD OF VIEW gave %.3f, not 80" % [where, main.fov_hip])
	# Enter does nothing on a slider and does not close the panel
	_key(KEY_ENTER)
	if not _near(main.fov_hip, 80.0 if pad else 105.0) or not hud.settings_visible():
		_fail("%s: Enter on a slider changed it or closed the panel" % where)
	# a switch: Right is on, Left is off, Enter flips
	main.setting_sel = _row_of("tads")
	sets.set_setting("tads", false)
	_key(KEY_RIGHT)
	if not main.toggle_ads:
		_fail("%s: Right on TOGGLE AIM did not switch it on" % where)
	_key(KEY_RIGHT)
	if not main.toggle_ads:
		_fail("%s: Right on a switch that is already on switched it off" % where)
	_key(KEY_LEFT)
	if main.toggle_ads:
		_fail("%s: Left on TOGGLE AIM did not switch it off" % where)
	_key(KEY_ENTER)
	if not main.toggle_ads or not hud.settings_visible():
		_fail("%s: Enter on TOGGLE AIM did not flip it, or closed the panel" % where)
	if pad:
		inp.on_pad_button(JOY_BUTTON_A)
		if main.toggle_ads or not hud.settings_visible():
			_fail("%s: A on TOGGLE AIM did not flip it, or closed the panel" % where)
	# GRAPHICS steps through its choices
	main.setting_sel = _row_of("quality")
	sets.set_setting("quality", 0)
	_key(KEY_RIGHT)
	if main.quality != 1:
		_fail("%s: Right on GRAPHICS gave %d, not 1" % [where, main.quality])
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	if main.quality != 2:
		_fail("%s: Left from the first GRAPHICS choice gave %d, not 2" % [where, main.quality])
	_key(KEY_ENTER)
	if main.quality != 0:
		_fail("%s: Enter on GRAPHICS gave %d, not 0" % [where, main.quality])
	sets.set_setting("quality", 0)
	# the mouse picks a row
	hud.size = Vector2(1280.0, 720.0)
	var target = _row_of("vol")
	inp.hover_menu(hud.row_rect(target).get_center())
	if main.setting_sel != target:
		_fail(
			"%s: the mouse over the VOLUME row did not pick it (row %d)" % [where, main.setting_sel]
		)
	# the panel draws at two window sizes, with a switch, a choice and a slider picked
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		hud.size = s
		for row_id in ["tads", "quality", "vol"]:
			main.setting_sel = _row_of(row_id)
			hud.queue_redraw()
			await process_frame
	hud.size = Vector2(1280.0, 720.0)


func _check_title() -> void:
	main.go_to_title()
	main.title_page = "settings"
	await process_frame
	# the keys do nothing to the settings while the panel is closed
	main.title_page = ""
	var fov_before = main.fov_hip
	main.setting_sel = main.hud.setting_rows().size() - 1
	_key(KEY_RIGHT)
	if (
		not _near(main.fov_hip, fov_before)
		or main.setting_sel != main.hud.setting_rows().size() - 1
	):
		_fail("title: Right or Down changed the settings with the panel closed")
	main.title_page = "settings"
	await _check_panel("title", true)
	_key(KEY_ESCAPE)
	if main.title_page != "":
		_fail("title: Escape did not close the settings panel (page '%s')" % main.title_page)


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
	await _check_panel("pause", true)
	if main.pause_page != "settings":
		_fail("pause: the panel closed while it was being used (page '%s')" % main.pause_page)
	_key(KEY_ESCAPE)
	if main.pause_page != "" or not main.paused:
		_fail("pause: Escape did not go back to the pause menu (page '%s')" % main.pause_page)
	# on the pause menu itself Left / Right and the D-pad do not touch the settings
	var fov_before = main.fov_hip
	_key(KEY_RIGHT)
	main.input_sys.on_pad_button(JOY_BUTTON_DPAD_RIGHT)
	if not _near(main.fov_hip, fov_before):
		_fail("pause: Left / Right changed a setting on the pause menu")


func _keep_user_files() -> void:
	had_file = FileAccess.file_exists(SETTINGS_PATH)
	if had_file:
		kept = FileAccess.get_file_as_bytes(SETTINGS_PATH)


func _restore_user_files() -> void:
	if had_file:
		var f = FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(kept)
			f.close()
	elif FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


func _finish() -> void:
	if problems.is_empty():
		print(
			"settings_nav_check: the settings panel works with the keyboard and the gamepad on the title screen and the pause menu"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("settings_nav_check: " + line)
		quit(1)
