extends SceneTree
# Checks the directional rider warning sounds (README Milestone E, Accessibility: scripts/rider_warning.gd, the bell in
# scripts/sfx.gd `play_warning`, the RIDER WARNING SOUNDS row of the settings and `warn_level` in scripts/main.gd):
#   - the rules: only a rider rings, only when it is near (RANGE), closing (MIN_CLOSING) and not ahead of the player
#     (FRONT_DEG); a rider that rides away, a far one, one in front, a boss and a phone are silent,
#   - the bearing is symmetric (left and right the same), 0 ahead and 180 behind, for any way the player looks,
#   - the loudness grows as a rider gets nearer and as it closes faster, the interval gets shorter as it gets nearer,
#     the volume follows the setting (OFF is silent, QUIET is quieter than NORMAL), and a rider behind rings lower,
#   - with real riders on a generated arena: a rider behind rings, at most MAX_BELLS ring however many are close, the
#     rings keep their rhythm (never faster than INTERVAL_NEAR), the bell comes from the rider's position (so Godot
#     pans it), the same situation gives the same bells (nothing is random), and nothing rings with the setting OFF,
#     while the sound is muted, or outside a round,
#   - the setting: the row is there, it is a three-way choice, a new game has it on NORMAL, Left, Right and Enter step it,
#     it is saved as `[game] rider_warning` and loaded again, and a damaged value loads as the default,
#   - the settings panel with the extra row still fits the window at three window sizes.
# Changing the setting saves `user://settings.cfg`, so the check keeps the real file and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/rider_warning_check.gd
# or with `python tools/run_checks.py rider_warning`. Exits with status 1 and prints the problems when a check fails.

const SettingsScript = preload("res://scripts/settings.gd")
const RiderWarning = preload("res://scripts/rider_warning.gd")
const SETTINGS_PATH = "user://settings.cfg"
const SEED = 0x51F7A3C1
const SIZES = [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(800.0, 450.0)]

var problems = []
var main
var kept = PackedByteArray()
var had_file = false


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_bearing()
	_check_rules()
	_check_loudness_and_pitch()
	_check_row_and_default()
	_check_save_load()
	await _check_panel_keys()
	_check_layout()
	await _check_in_round()
	_restore_user_files()
	_finish()


func _fail(text: String) -> void:
	if problems.size() < 40:
		problems.append(text)


func _remove_file() -> void:
	if FileAccess.file_exists(SETTINGS_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SETTINGS_PATH))


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
	else:
		_remove_file()


func _key(code: int) -> void:
	var e = InputEventKey.new()
	e.pressed = true
	e.keycode = code
	main.input_sys.handle_input(e)


# a threat entry like Main.threat_list makes (only the fields the warning reads)
func _threat(kind: String, pos: Vector3, dist: float, closing: float) -> Dictionary:
	return {"pos": pos, "kind": kind, "urg": 0.4, "dist": dist, "closing": closing}


# ---------------------------------------------------------------- the pure rules
func _check_bearing() -> void:
	var from = Vector3(5.0, 0.0, 5.0)
	# at yaw 0 the player looks along -z
	var ahead = RiderWarning.bearing_deg(from, 0.0, from + Vector3(0.0, 0.0, -10.0))
	var behind = RiderWarning.bearing_deg(from, 0.0, from + Vector3(0.0, 0.0, 10.0))
	var left = RiderWarning.bearing_deg(from, 0.0, from + Vector3(-10.0, 0.0, 0.0))
	var right = RiderWarning.bearing_deg(from, 0.0, from + Vector3(10.0, 0.0, 0.0))
	if absf(ahead) > 0.01:
		_fail("a rider straight ahead has bearing %.2f, expected 0" % ahead)
	if absf(behind - 180.0) > 0.01:
		_fail("a rider straight behind has bearing %.2f, expected 180" % behind)
	if absf(left - 90.0) > 0.01 or absf(right - 90.0) > 0.01:
		_fail(
			"a rider to the side has bearings %.2f and %.2f, expected 90 for both" % [left, right]
		)
	# turning the player turns the bearing with them: a rider on +x is ahead when the player looks along +x
	var yaw_east = -PI * 0.5  # (-sin(yaw), -cos(yaw)) = (1, 0)
	var east = RiderWarning.bearing_deg(from, yaw_east, from + Vector3(10.0, 0.0, 0.0))
	if absf(east) > 0.01:
		_fail("a rider east of a player looking east has bearing %.2f, expected 0" % east)
	var on_top = RiderWarning.bearing_deg(from, 0.0, from)
	if on_top < RiderWarning.FRONT_DEG:
		_fail(
			(
				"a rider on top of the player counts as ahead (bearing %.1f), so it would never ring"
				% on_top
			)
		)


func _check_rules() -> void:
	var rule = RiderWarning.rings
	var near_side = _threat("rider", Vector3.ZERO, 10.0, 8.0)
	if not rule.call(near_side, 90.0):
		_fail("a rider 10 m away closing at 8 m/s at the player's side does not ring")
	if not rule.call(near_side, 180.0):
		_fail("a rider right behind the player does not ring")
	if rule.call(near_side, RiderWarning.FRONT_DEG - 1.0):
		_fail("a rider just inside the front cone rings, but it is on the screen")
	if not rule.call(near_side, RiderWarning.FRONT_DEG):
		_fail("a rider exactly at the edge of the front cone does not ring")
	if rule.call(_threat("rider", Vector3.ZERO, RiderWarning.RANGE + 0.5, 8.0), 120.0):
		_fail("a rider beyond RANGE rings")
	if not rule.call(_threat("rider", Vector3.ZERO, RiderWarning.RANGE, 8.0), 120.0):
		_fail("a rider exactly at RANGE does not ring")
	if rule.call(_threat("rider", Vector3.ZERO, 10.0, RiderWarning.MIN_CLOSING - 0.1), 120.0):
		_fail("a rider closing slower than MIN_CLOSING rings")
	if rule.call(_threat("rider", Vector3.ZERO, 10.0, -6.0), 120.0):
		_fail("a rider that rides away rings")
	if rule.call(_threat("boss", Vector3.ZERO, 10.0, 8.0), 120.0):
		_fail("a boss rings the bike bell")
	if rule.call(_threat("phone", Vector3.ZERO, 10.0, 8.0), 120.0):
		_fail("a phone rings the bike bell")
	# ranked(): the riders that ring, the loudest first, a tie keeps the order of the list
	var from = Vector3.ZERO
	var list = [
		_threat("rider", Vector3(0.0, 0.0, 25.0), 25.0, 8.0),  # behind, far
		_threat("rider", Vector3(0.0, 0.0, -10.0), 10.0, 8.0),  # ahead: silent
		_threat("rider", Vector3(0.0, 0.0, 8.0), 8.0, 8.0),  # behind, near
		_threat("boss", Vector3(0.0, 0.0, 6.0), 6.0, 0.0),  # silent
		_threat("rider", Vector3(12.0, 0.0, 0.0), 12.0, 8.0),  # to the side
		_threat("rider", Vector3(0.0, 0.0, 14.0), 14.0, -3.0)  # riding away: silent
	]
	var r = RiderWarning.ranked(list, from, 0.0)
	if r.size() != 3:
		_fail(
			(
				"ranked() gave %d riders, expected 3 (the far one behind, the near one behind, the one at the side)"
				% r.size()
			)
		)
		return
	if r[0]["dist"] != 8.0 or r[1]["dist"] != 12.0 or r[2]["dist"] != 25.0:
		_fail(
			(
				"ranked() order is %s m, expected the nearest first: 8, 12, 25"
				% str([r[0]["dist"], r[1]["dist"], r[2]["dist"]])
			)
		)
	var tie = [
		_threat("rider", Vector3(0.0, 0.0, 10.0), 10.0, 8.0),
		_threat("rider", Vector3(0.0, 0.0, 10.0), 10.0, 8.0)
	]
	tie[1]["urg"] = 0.9
	var rt = RiderWarning.ranked(tie, from, 0.0)
	if rt.size() != 2 or rt[0]["order"] != 0 or rt[1]["order"] != 1:
		_fail("two equally loud riders were not kept in the order of the list")


func _check_loudness_and_pitch() -> void:
	var l = RiderWarning.loudness
	if l.call(RiderWarning.NEAR, RiderWarning.FULL_CLOSING) < 0.999:
		_fail(
			(
				"a rider at NEAR closing at full speed is not at full loudness (%.3f)"
				% l.call(RiderWarning.NEAR, RiderWarning.FULL_CLOSING)
			)
		)
	if l.call(4.0, RiderWarning.FULL_CLOSING) > 1.0001:
		_fail("loudness goes above 1 for a very near rider")
	var prev = 2.0
	for d in [6.0, 10.0, 15.0, 20.0, 25.0, 30.0]:
		var v: float = l.call(d, 8.0)
		if v >= prev:
			_fail(
				(
					"loudness does not fall as the rider gets farther (%.0f m: %.3f, before %.3f)"
					% [d, v, prev]
				)
			)
		prev = v
	prev = -1.0
	for c in [3.0, 5.0, 8.0, 12.0, 16.0]:
		var v: float = l.call(12.0, c)
		if v < prev:
			_fail(
				(
					"loudness falls as the rider closes faster (%.0f m/s: %.3f, before %.3f)"
					% [c, v, prev]
				)
			)
		prev = v
	if l.call(RiderWarning.RANGE, RiderWarning.MIN_CLOSING) < 0.05:
		_fail("the weakest bell is almost silent: a rider that rings must be heard")
	# the interval gets shorter as the rider gets nearer, within INTERVAL_NEAR .. INTERVAL_FAR
	var iv = RiderWarning.interval
	if absf(iv.call(2.0) - RiderWarning.INTERVAL_NEAR) > 0.001:
		_fail("a rider closer than NEAR does not ring at INTERVAL_NEAR")
	if absf(iv.call(RiderWarning.RANGE) - RiderWarning.INTERVAL_FAR) > 0.001:
		_fail("a rider at RANGE does not ring at INTERVAL_FAR")
	if iv.call(10.0) >= iv.call(20.0):
		_fail("a nearer rider does not ring faster than a farther one")
	# the volume follows the setting
	if RiderWarning.volume_db(1.0, 0) > -60.0:
		_fail("level OFF still has an audible volume (%.1f dB)" % RiderWarning.volume_db(1.0, 0))
	var quiet = RiderWarning.volume_db(0.8, 1)
	var normal = RiderWarning.volume_db(0.8, 2)
	if quiet >= normal - 3.0:
		_fail("QUIET (%.1f dB) is not clearly quieter than NORMAL (%.1f dB)" % [quiet, normal])
	if RiderWarning.volume_db(0.3, 2) >= RiderWarning.volume_db(0.9, 2):
		_fail("a less loud bell is not quieter in dB")
	# a rider behind rings lower, and the second bell is not the same pitch as the first
	if RiderWarning.pitch_for(0, 170.0) >= RiderWarning.pitch_for(0, 90.0):
		_fail("a rider behind does not ring lower than one at the side")
	if RiderWarning.pitch_for(0, 90.0) == RiderWarning.pitch_for(1, 90.0):
		_fail("the two bells have the same pitch, so they cannot be told apart")


# ---------------------------------------------------------------- the setting
func _fresh() -> void:
	_remove_file()
	main.warn_level = RiderWarning.DEFAULT_LEVEL


func _saved_level():
	var cf = ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return null
	return cf.get_value("game", "rider_warning", null)


func _check_row_and_default() -> void:
	var found = {}
	for row in main.hud.ALL_SETTING_ROWS:
		if row["id"] == "warn":
			found = row
	if found.is_empty():
		_fail("the settings have no RIDER WARNING SOUNDS row (id warn)")
		return
	if not found.has("choices") or found["choices"].size() != 3:
		_fail("the RIDER WARNING SOUNDS row is not a three-way choice")
	elif found["choices"] != RiderWarning.LEVEL_NAMES:
		_fail(
			(
				"the row's choices %s are not the names in rider_warning.gd %s"
				% [str(found["choices"]), str(RiderWarning.LEVEL_NAMES)]
			)
		)
	_fresh()
	if main.warn_level != 2 or main.settings.get_setting("warn") != 2:
		_fail("a new game does not have RIDER WARNING on NORMAL")
	if _saved_level() != null:
		_fail("a fresh game wrote rider_warning before anything was changed")


func _check_save_load() -> void:
	_fresh()
	main.settings.set_setting("warn", 0)
	if main.warn_level != 0 or main.settings.get_setting("warn") != 0:
		_fail("set_setting('warn', 0) did not switch the warning off")
	if _saved_level() != 0:
		_fail("OFF was not saved as [game] rider_warning = 0 (got %s)" % str(_saved_level()))
	main.warn_level = 2
	main.settings.load_settings()
	if main.warn_level != 0:
		_fail("the saved OFF did not load again (got %d)" % main.warn_level)
	main.settings.set_setting("warn", 1)
	main.warn_level = 2
	main.settings.load_settings()
	if main.warn_level != 1:
		_fail("the saved QUIET did not load again (got %d)" % main.warn_level)
	# the choice is clamped, and a value that is not a whole number loads as the default (NORMAL)
	main.settings.set_setting("warn", 99)
	if main.warn_level != 2:
		_fail("set_setting('warn', 99) gave %d, expected the highest level 2" % main.warn_level)
	main.settings.set_setting("warn", -4)
	if main.warn_level != 0:
		_fail("set_setting('warn', -4) gave %d, expected the lowest level 0" % main.warn_level)
	for bad in ["loud", 1.5, true, ""]:
		var cf = ConfigFile.new()
		cf.load(SETTINGS_PATH)
		cf.set_value("game", "rider_warning", bad)
		cf.save(SETTINGS_PATH)
		main.warn_level = 0
		main.settings.load_settings()
		if main.warn_level != 2:
			_fail(
				(
					"rider_warning = %s loaded as %d, not as the default NORMAL"
					% [var_to_str(bad), main.warn_level]
				)
			)
	for big in [7, -1]:
		var cf2 = ConfigFile.new()
		cf2.load(SETTINGS_PATH)
		cf2.set_value("game", "rider_warning", big)
		cf2.save(SETTINGS_PATH)
		main.warn_level = 1
		main.settings.load_settings()
		if main.warn_level < 0 or main.warn_level > 2:
			_fail("rider_warning = %d loaded as %d, outside 0 to 2" % [big, main.warn_level])
	var cf3 = ConfigFile.new()
	cf3.load(SETTINGS_PATH)
	cf3.erase_section_key("game", "rider_warning")
	cf3.save(SETTINGS_PATH)
	main.warn_level = 0
	main.settings.load_settings()
	if main.warn_level != 2:
		_fail(
			"a file without rider_warning loaded as %d, not as the default NORMAL" % main.warn_level
		)


# the settings panel is open on the title screen: Right steps up, Left steps down, Enter goes round
func _check_panel_keys() -> void:
	_fresh()
	main.state = "title"
	main.title_page = "settings"
	main.paused = false
	var rows = main.hud.setting_rows()
	var idx = -1
	for i in range(rows.size()):
		if rows[i]["id"] == "warn":
			idx = i
	if idx < 0:
		_fail("the RIDER WARNING SOUNDS row is not among the visible rows")
		return
	main.setting_sel = idx
	main.warn_level = 1
	_key(KEY_RIGHT)
	if main.warn_level != 2:
		_fail("Right on QUIET gave level %d, expected NORMAL (2)" % main.warn_level)
	_key(KEY_LEFT)
	_key(KEY_LEFT)
	if main.warn_level != 0:
		_fail("Left twice from NORMAL gave level %d, expected OFF (0)" % main.warn_level)
	main.warn_level = 2
	_key(KEY_ENTER)
	if main.warn_level != 0:
		_fail("Enter on NORMAL gave level %d, expected it to go round to OFF (0)" % main.warn_level)
	_key(KEY_ENTER)
	if main.warn_level != 1:
		_fail("Enter on OFF gave level %d, expected QUIET (1)" % main.warn_level)
	if _saved_level() != 1:
		_fail("the level stepped with the keys was not saved (got %s)" % str(_saved_level()))
	main.title_page = ""
	await process_frame


func _check_layout() -> void:
	main.state = "title"
	main.title_page = "settings"
	var hud = main.hud
	for s in SIZES:
		hud.size = s
		var pr: Rect2 = hud.panel_rect()
		var last: Rect2 = hud.row_rect(hud.setting_rows().size() - 1)
		if pr.position.y < 0.0 or pr.end.y > s.y:
			_fail(
				(
					"at %dx%d the settings panel (%.0f to %.0f) does not fit the window"
					% [s.x, s.y, pr.position.y, pr.end.y]
				)
			)
		if last.end.y > pr.end.y + 0.5:
			_fail("at %dx%d the last settings row ends below the panel" % [s.x, s.y])
		for i in range(hud.setting_rows().size() - 1):
			if hud.row_rect(i).end.y > hud.row_rect(i + 1).position.y + 0.5:
				_fail("at %dx%d settings rows %d and %d overlap" % [s.x, s.y, i, i + 1])
	main.title_page = ""
	hud.size = SIZES[0]


# ---------------------------------------------------------------- real riders on a generated arena
func _rider(pos: Vector3, toward: Vector3, speed: float) -> Dictionary:
	var rs = main.rider_sys
	var r = rs.spawn_rider(0, 1)
	r["can_throw"] = false
	r["pos"] = pos
	r["yaw"] = rs.yaw_of(toward)
	r["hidden"] = false
	r["entered"] = true
	r["mode"] = "fly"
	r["ride_speed"] = speed
	return r


# a stand-in for the sound system that only records the bells it is asked for
class FakeSfx:
	extends Node
	var muted = false
	var bells = []

	func play_warning(pos: Vector3, vol_db: float, pitch: float = 1.0) -> void:
		bells.append({"pos": pos, "db": vol_db, "pitch": pitch})


func _setup_round() -> FakeSfx:
	main.start_game(false, SEED)
	main.state = "check"
	main.clear_riders()
	main.clear_bosses()
	main.player.position = main.arena.start_position()
	main.yaw = 0.0
	var fake = FakeSfx.new()
	main.warn_sys.g = main
	main.warn_sys.reset()
	return fake


func _run_frames(fake: FakeSfx, seconds: float, step: float = 0.05) -> void:
	var real = main.sfx
	main.sfx = fake
	var t = 0.0
	while t < seconds:
		main.warn_sys.update(step)
		t += step
	main.sfx = real


func _check_in_round() -> void:
	var fake = _setup_round()
	var behind = Vector3(0.0, 0.0, 1.0)  # the camera looks along -z at yaw 0, so +z is behind it
	var pp: Vector3 = main.player.position

	# one rider 12 m behind, riding at the player
	main.warn_level = 2
	var r1 = _rider(pp + behind * 12.0, -behind, 8.0)
	_run_frames(fake, 0.1)
	if fake.bells.size() != 1:
		_fail(
			"a rider 12 m behind rang %d bells in the first 0.1 s, expected 1" % fake.bells.size()
		)
	elif (
		Vector2(fake.bells[0]["pos"].x - r1["pos"].x, fake.bells[0]["pos"].z - r1["pos"].z).length()
		> 0.01
	):
		_fail("the bell does not come from the rider's position, so Godot cannot pan it")
	elif fake.bells[0]["pitch"] >= 1.0:
		_fail("a rider straight behind did not ring lower (pitch %.2f)" % fake.bells[0]["pitch"])

	# the rhythm: over 5 s the bell never rings faster than INTERVAL_NEAR, and does ring more than once
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 5.0)
	var max_rings = int(ceil(5.0 / RiderWarning.INTERVAL_NEAR)) + 1
	if fake.bells.size() < 3 or fake.bells.size() > max_rings:
		_fail(
			(
				"one close rider rang %d bells in 5 s, expected between 3 and %d"
				% [fake.bells.size(), max_rings]
			)
		)

	# ten riders close behind: at most MAX_BELLS ring at once, and over 5 s never more than MAX_BELLS rhythms
	main.clear_riders()
	for i in range(10):
		_rider(pp + behind * (8.0 + 2.0 * float(i)), -behind, 8.0)
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 0.1)
	if fake.bells.size() != RiderWarning.MAX_BELLS:
		_fail(
			(
				"ten riders behind rang %d bells at the start, expected %d"
				% [fake.bells.size(), RiderWarning.MAX_BELLS]
			)
		)
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 5.0)
	if fake.bells.size() > RiderWarning.MAX_BELLS * max_rings:
		_fail(
			(
				"ten riders rang %d bells in 5 s, more than %d bell places allow"
				% [fake.bells.size(), RiderWarning.MAX_BELLS * max_rings]
			)
		)

	# the same situation gives the same bells (no random numbers)
	var first = _record(fake)
	var second = _record(fake)
	if first != second:
		_fail("the same situation rang differently twice, so something in the warning is random")

	# a rider in front, one riding away, one far away: silent
	main.clear_riders()
	_rider(pp - behind * 12.0, behind, 8.0)  # in front of the player, riding at them
	_rider(pp + behind * 12.0, behind, 8.0)  # behind, riding away
	_rider(pp + behind * 50.0, -behind, 8.0)  # far
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 2.0)
	if fake.bells.size() != 0:
		_fail(
			(
				"a rider in front, one riding away and a far one rang %d bells, expected silence"
				% fake.bells.size()
			)
		)

	# turning round turns the rule: the rider that was in front is now behind and rings
	main.yaw = PI
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 0.1)
	if fake.bells.size() == 0:
		_fail("after the player turned round the rider that is now behind did not ring")
	main.yaw = 0.0

	# a rider to the side rings; the setting OFF, muted sound and a boss-only list are silent
	main.clear_riders()
	var side = Vector3(1.0, 0.0, 0.0)
	_rider(pp + side * 10.0, -side, 8.0)
	for case in ["off", "muted"]:
		fake.bells.clear()
		fake.muted = case == "muted"
		main.warn_level = 0 if case == "off" else 2
		main.warn_sys.reset()
		_run_frames(fake, 2.0)
		if fake.bells.size() != 0:
			_fail(
				(
					"the bell rang %d times with %s"
					% [fake.bells.size(), "the setting OFF" if case == "off" else "the sound muted"]
				)
			)
	fake.muted = false
	main.warn_level = 1
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 0.1)
	var quiet_db = fake.bells[0]["db"] if fake.bells.size() > 0 else 0.0
	main.warn_level = 2
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 0.1)
	if fake.bells.size() == 0:
		_fail("a rider at the side did not ring on NORMAL")
	elif quiet_db >= fake.bells[0]["db"]:
		_fail(
			(
				"QUIET (%.1f dB) was not quieter than NORMAL (%.1f dB) in play"
				% [quiet_db, fake.bells[0]["db"]]
			)
		)

	# a bell rung through the real sound system: no error, and no sound player is left behind once it is done
	main.warn_level = 2
	main.state = "play"
	main.force_captured = true
	main.warn_sys.reset()
	var before = main.sfx.get_child_count()
	main.sfx.play_warning(pp + behind * 5.0, -10.0, 1.0)
	if (
		main.sfx.streams.has("bell")
		and main.sfx.get_child_count() != before + 1
		and not main.sfx.muted
	):
		_fail(
			(
				"play_warning did not add one sound player (had %d, now %d)"
				% [before, main.sfx.get_child_count()]
			)
		)
	if not main.sfx.streams.has("bell"):
		_fail("the bell sample audio/bell.wav was not loaded by the sound system")
	main.state = "check"
	main.force_captured = false


# the bells of one run of 2 s: how many, and the volume and pitch of each, for comparing two runs
func _record(fake: FakeSfx) -> Array:
	fake.bells.clear()
	main.warn_sys.reset()
	_run_frames(fake, 2.0)
	var out = []
	for b in fake.bells:
		out.append([snappedf(b["db"], 0.001), snappedf(b["pitch"], 0.001), b["pos"]])
	return out


func _finish() -> void:
	if problems.is_empty():
		print(
			"rider_warning_check: close riders from behind or the side ring a bell, panned, at the chosen level, and the setting is saved"
		)
		quit(0)
	else:
		for line in problems.slice(0, 12):
			printerr("rider_warning_check: " + line)
		quit(1)
