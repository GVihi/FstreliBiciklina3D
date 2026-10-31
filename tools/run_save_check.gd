extends SceneTree
# Checks the saved run and the CONTINUE button (README Milestone A, Menu follow-ups: "Continue" button to resume an
# interrupted run):
#   - a checkpoint is written every time the map screen opens, only in the game itself and never in a check,
#   - CONTINUE puts back everything the run had (hearts, cash, perks, upgrades, packs, score, times, challenges ...)
#     on the same map and lands on the map screen,
#   - a lost run, a won run and a failed round clear the saved run, and a new run keeps the old one as a .bak file,
#   - a damaged, too new or hand-edited file never crashes the game and never gives an unplayable run,
#   - the title menu shows CONTINUE above PLAY only while a run is saved: layout at two window sizes, the mouse,
#     the keyboard order and Enter.
# It uses its own file (user://run_save_check.json) and never touches the real user://run.json.
# Run from the project folder:
#   godot --headless --path . --script res://tools/run_save_check.gd
# or with tools\run_run_save_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const RunSave = preload("res://scripts/run_save.gd")
const MapGen = preload("res://scripts/map_gen.gd")
const TEST_PATH = "user://run_save_check.json"
const SEED_A = 0x1234ABCD
const SEED_B = 0x0BADF00D

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	RunSave.test_path = TEST_PATH
	_remove_test_files()
	_check_not_in_a_check()
	main.run_save_enabled = true
	_check_checkpoint_and_continue()
	_check_end_paths()
	_check_replace_backup()
	_check_bad_files()
	await _check_title_menu()
	_remove_test_files()
	RunSave.test_path = ""
	_finish()


# a main built by a check (not the running scene) writes no checkpoint, so running checks never costs the player a run
func _check_not_in_a_check() -> void:
	if main.run_save_enabled:
		_fail("a main made by a check has run_save_enabled on")
	main.start_game(false, SEED_A)
	if FileAccess.file_exists(TEST_PATH):
		_fail("a run in a check wrote a checkpoint")
	main.refresh_saved_run()
	if not main.saved_run.is_empty():
		_fail("saved_run is not empty with saving off")


func _set_run_state() -> void:
	main.perks = {"check_perk_a": true, "check_perk_b": true}
	main.cash = 777
	main.hearts = 2
	main.MAXHEARTS = 4
	main.MAXSHELLS = 8
	main.pump_base = 0.31
	main.pump_dur = 0.17
	main.style = 42.5
	main.up["wide"] = 2
	main.up["luck"] = 0.25
	main.shop_lvl = {"check_tier": 2}
	main.shop_buys = 5
	main.pending["rapid"] = 6.0
	main.pending["shield"] = true
	main.pending["free"] = 2
	main.buffs["slow"] = 3.5
	main.free_shots = 3
	main.hype = 40.0
	main.hype_gain = 1.5
	main.equip_melee("melee")  # a new player's slot is empty; the run being saved holds the worm
	main.melee = true
	main.score = 12345
	main.combo = 4
	main.best_combo = 9
	main.kills = 17
	main.best_rank = 3
	main.play_time = 321.5
	main.shop_time = 44.0
	main.round_times = [100.5, 120.25]
	main.shots_fired = 50
	main.shots_hit = 30
	main.civs_hit = 1
	main.perfect_dodges = 4
	main.meta.boss_coins = 5
	main.meta.xp_boss = 25
	main.challenges.done["check_challenge"] = true
	main.challenges.streak = 2
	main.challenges.best_streak = 3


func _scramble_run_state() -> void:
	main.reset_run()
	main.perks = {}
	main.hearts = 1
	main.MAXHEARTS = 3
	main.MAXSHELLS = 6
	main.score = 0
	main.kills = 0
	main.round_n = 1
	main.map_floor = -1
	main.map_path = []
	main.round_times = []
	main.play_time = 0.0
	main.shop_time = 0.0
	main.meta.boss_coins = 0
	main.meta.xp_boss = 0
	main.challenges.done.clear()
	main.challenges.streak = 0
	main.challenges.best_streak = 0
	main.run_seed = 0
	main.custom_seed_run = false
	main.daily_mode = false


func _check_checkpoint_and_continue() -> void:
	main.start_game(false, SEED_A)
	if not FileAccess.file_exists(TEST_PATH):
		_fail("starting a run did not write a checkpoint at its first map screen")
	main.refresh_saved_run()
	if main.saved_run.is_empty() or main.saved_run["run_seed"] != SEED_A:
		_fail("the first checkpoint was not loaded back (saved_run %s)" % str(main.saved_run))
		return
	if main.saved_run["map_floor"] != -1 or not main.saved_run["map_path"].is_empty():
		_fail("the first checkpoint is not on the map screen before floor 1")
	# play two rounds' worth of map and shop, then come back to the map screen
	main.state_t = 1.0
	main.pick_node(0)
	main.round_n = main.map_floor + 1
	main.enter_map()
	main.state_t = 1.0
	main.pick_node(0)
	main.enter_map()
	_set_run_state()
	main.save_checkpoint()
	var map_text = MapGen.to_text(main.run_map)
	var choices = main.map_choices.duplicate()
	var lane = main.map_lane
	var path = main.map_path.duplicate()
	var floor_now = main.map_floor
	var round_now = main.round_n
	main.refresh_saved_run()
	if main.saved_run.is_empty():
		_fail("the checkpoint after two rounds is not playable")
		return
	if main.saved_run_rounds != main.run_map["floors"].size():
		_fail(
			(
				"saved_run_rounds is %d, the map has %d floors"
				% [main.saved_run_rounds, main.run_map["floors"].size()]
			)
		)
	_scramble_run_state()
	main.continue_run()
	if main.state != "map":
		_fail("CONTINUE did not land on the map screen (state %s)" % main.state)
	if MapGen.to_text(main.run_map) != map_text:
		_fail("the continued run has another map than the saved one")
	if main.run_seed != SEED_A or not main.custom_seed_run or main.daily_mode:
		_fail(
			(
				"seed / mode wrong after CONTINUE: %d custom %s daily %s"
				% [main.run_seed, main.custom_seed_run, main.daily_mode]
			)
		)
	if main.ranked_run():
		_fail("a continued custom-seed run is ranked")
	if main.map_floor != floor_now or main.map_lane != lane or main.map_path != path:
		_fail(
			(
				"map position wrong after CONTINUE: floor %d lane %d path %s"
				% [main.map_floor, main.map_lane, str(main.map_path)]
			)
		)
	if main.map_choices != choices:
		_fail(
			(
				"the choices on the map screen are %s, expected %s"
				% [str(main.map_choices), str(choices)]
			)
		)
	if main.round_n != round_now or main.MAX_ROUNDS != main.run_map["floors"].size():
		_fail(
			(
				"round %d of %d after CONTINUE, expected round %d"
				% [main.round_n, main.MAX_ROUNDS, round_now]
			)
		)
	_same("hearts", main.hearts, 2)
	_same("MAXHEARTS", main.MAXHEARTS, 4)
	_same("MAXSHELLS", main.MAXSHELLS, 8)
	_same("shells", main.shells, 8)
	_same("cash", main.cash, 777)
	_same("score", main.score, 12345)
	_same("kills", main.kills, 17)
	_same("combo", main.combo, 4)
	_same("best_combo", main.best_combo, 9)
	_same("best_rank", main.best_rank, 3)
	_same("shop_buys", main.shop_buys, 5)
	_same("free_shots", main.free_shots, 3)
	_same("shots_fired", main.shots_fired, 50)
	_same("shots_hit", main.shots_hit, 30)
	_same("civs_hit", main.civs_hit, 1)
	_same("perfect_dodges", main.perfect_dodges, 4)
	_same("pump_base", main.pump_base, 0.31)
	_same("pump_dur", main.pump_dur, 0.17)
	_same("style", main.style, 42.5)
	_same("hype", main.hype, 40.0)
	_same("hype_gain", main.hype_gain, 1.5)
	_same("play_time", main.play_time, 321.5)
	_same("shop_time", main.shop_time, 44.0)
	_same("up.wide", main.up["wide"], 2)
	_same("up.luck", main.up["luck"], 0.25)
	_same("shop_lvl", main.shop_lvl.get("check_tier", -1), 2)
	_same("pending.rapid", main.pending["rapid"], 6.0)
	_same("pending.shield", main.pending["shield"], true)
	_same("pending.free", main.pending["free"], 2)
	_same("buffs.slow", main.buffs["slow"], 3.5)
	_same("melee", main.melee, true)
	_same("round_times", main.round_times, [100.5, 120.25])
	_same("boss_coins", main.meta.boss_coins, 5)
	_same("xp_boss", main.meta.xp_boss, 25)
	_same("streak", main.challenges.streak, 2)
	_same("best_streak", main.challenges.best_streak, 3)
	if (
		not main.perks.has("check_perk_a")
		or not main.perks.has("check_perk_b")
		or main.perks.size() != 2
	):
		_fail("perks after CONTINUE: %s" % str(main.perks))
	if not main.challenges.done.has("check_challenge"):
		_fail("a challenge done before the quit is gone after CONTINUE")
	if main.meta.awarded:
		_fail("the continued run is already paid out")
	# types: ints stay ints, so a level or a count is never a float in the game
	if (
		typeof(main.hearts) != TYPE_INT
		or typeof(main.up["wide"]) != TYPE_INT
		or typeof(main.cash) != TYPE_INT
	):
		_fail("hearts, upgrade levels or cash came back as a float")
	if typeof(main.pending["free"]) != TYPE_INT:
		_fail("pending free darts came back as a float")
	# the run goes on: the next pick starts a round, and the checkpoint on the map screen is again the same run
	main.refresh_saved_run()
	if main.saved_run.is_empty() or main.saved_run["score"] != 12345:
		_fail("CONTINUE did not leave a checkpoint of the continued run")
	main.state_t = 1.0
	main.pick_node(0)
	if main.state != "play":
		_fail("a node picked after CONTINUE did not start a round (state %s)" % main.state)
	main.abandon_run()  # quitting to the title keeps the checkpoint
	main.refresh_saved_run()
	if main.saved_run.is_empty():
		_fail("quitting to the title lost the saved run")


# lost, won and failed runs leave nothing to continue
func _check_end_paths() -> void:
	for how in ["game_over", "win_run", "end_round"]:
		main.start_game(false, SEED_B)
		main.refresh_saved_run()
		if main.saved_run.is_empty():
			_fail("%s: no saved run to end" % how)
			continue
		# keep this check from paying a score or a leaderboard entry into the real save files
		main.meta.awarded = true
		main.daily_mode = true
		if how == "game_over":
			main.game_over("riders")
		elif how == "win_run":
			main.win_run()
		else:
			main.hits.clear()
			for i in range(main.PER_ROUND):
				main.hits.append(null)
			main.end_round()
		if main.state != "over":
			_fail("%s: state is %s, expected over" % [how, main.state])
		if not main.saved_run.is_empty():
			_fail("%s: saved_run is still set after the run ended" % how)
		main.refresh_saved_run()
		if not main.saved_run.is_empty():
			_fail("%s: the file still holds the run after it ended" % how)
		if not RunSave.load_file().is_empty():
			_fail("%s: load_file still gives a run" % how)
		if not FileAccess.file_exists(TEST_PATH):
			_fail("%s: the file was deleted, it should only be emptied" % how)
	main.daily_mode = false


func _check_replace_backup() -> void:
	var bak = TEST_PATH + ".replaced.bak"
	main.start_game(false, SEED_A)
	main.refresh_saved_run()
	main.start_game(false, SEED_B)  # replaces run A
	if not FileAccess.file_exists(bak):
		_fail("a new run replaced the saved one without a .replaced.bak copy")
	else:
		var old = JSON.parse_string(FileAccess.get_file_as_string(bak))
		if not (old is Dictionary) or int(old.get("run", {}).get("run_seed", -1)) != SEED_A:
			_fail("the .replaced.bak does not hold the replaced run")
	main.refresh_saved_run()
	if main.saved_run.is_empty() or main.saved_run["run_seed"] != SEED_B:
		_fail("the new run is not the saved one")
	# an emptied file is not worth a backup and must not overwrite the one that is
	main.clear_saved_run()
	RunSave.backup_before_replace()
	var kept = JSON.parse_string(FileAccess.get_file_as_string(bak))
	if not (kept is Dictionary) or int(kept.get("run", {}).get("run_seed", -1)) != SEED_A:
		_fail("an empty 'no run' file replaced the .replaced.bak")
	main.start_game(false, SEED_A)  # leaves a checkpoint of run A for the next checks


func _write_text(text: String) -> void:
	var f = FileAccess.open(TEST_PATH, FileAccess.WRITE)
	f.store_string(text)
	f.close()


# a run on the map screen of seed SEED_A, as a dictionary to damage and write back
func _good_run() -> Dictionary:
	main.start_game(false, SEED_A)
	return JSON.parse_string(FileAccess.get_file_as_string(TEST_PATH))["run"]


func _check_bad_files() -> void:
	_remove_bak_files()
	_write_text("this is not json {")
	if not RunSave.load_file().is_empty():
		_fail("a file that is not JSON gave a run")
	if not FileAccess.file_exists(TEST_PATH + ".bad.bak"):
		_fail("an unreadable file was not copied to .bad.bak")
	var run = _good_run()
	_write_text(JSON.stringify({"version": 2, "run": run}))
	if not RunSave.load_file().is_empty():
		_fail("a run written by a newer version was loaded")
	if not FileAccess.file_exists(TEST_PATH + ".v2.bak"):
		_fail("a run from a newer version was not copied to .v2.bak")
	# a version 1 file with nonsense in it is cleaned, never trusted
	var wild = run.duplicate(true)
	wild["hearts"] = -5
	wild["max_hearts"] = "many"
	wild["cash"] = 1e30
	wild["score"] = "lots"
	wild["hype"] = 5000
	wild["perks"] = ["ok", 5, null, ""]
	wild["up"] = {"wide": "x", "luck": 2}
	wild["pending"] = {"rapid": "x", "shield": 7, "free": 3}
	wild["round_times"] = "none"
	wild["best_rank"] = 99
	_write_text(JSON.stringify({"version": 1, "run": wild}))
	var cleaned = RunSave.load_file()
	if cleaned.is_empty():
		_fail("a run with bad values was refused instead of cleaned")
	else:
		if cleaned["hearts"] < 1 or cleaned["hearts"] > cleaned["max_hearts"]:
			_fail("hearts %d of %d after cleaning" % [cleaned["hearts"], cleaned["max_hearts"]])
		if cleaned["cash"] > 1000000000 or cleaned["score"] != 0:
			_fail(
				(
					"cash %s and score %s after cleaning"
					% [str(cleaned["cash"]), str(cleaned["score"])]
				)
			)
		if cleaned["hype"] > 100.0 or cleaned["best_rank"] > 4:
			_fail(
				(
					"hype %s and best_rank %s are not clamped"
					% [str(cleaned["hype"]), str(cleaned["best_rank"])]
				)
			)
		if cleaned["perks"] != ["ok"]:
			_fail("perks after cleaning: %s" % str(cleaned["perks"]))
		if cleaned["pending"].has("shield") and typeof(cleaned["pending"]["shield"]) != TYPE_BOOL:
			_fail("pending shield is not a bool after cleaning")
		if not (cleaned["round_times"] is Array):
			_fail("round_times is not a list after cleaning")
	# applying a cleaned run must work whatever was in the file
	main.refresh_saved_run()
	if main.saved_run.is_empty():
		_fail("a cleaned run is not playable")
	else:
		main.continue_run()
		if main.state != "map":
			_fail("a cleaned run did not reach the map screen")
	# a map position that the seed's map does not have is not playable
	for damage in ["no_seed", "floor_too_high", "lane_too_high", "path_short", "path_lane"]:
		var bad = run.duplicate(true)
		if damage == "no_seed":
			bad.erase("run_seed")
		elif damage == "floor_too_high":
			bad["map_floor"] = 99
		elif damage == "lane_too_high":
			bad["map_floor"] = 0
			bad["map_lane"] = 50
			bad["map_path"] = [50]
		elif damage == "path_short":
			bad["map_floor"] = 2
			bad["map_path"] = [0]
		else:
			bad["map_floor"] = 0
			bad["map_lane"] = 0
			bad["map_path"] = [50]
		_write_text(JSON.stringify({"version": 1, "run": bad}))
		main.refresh_saved_run()
		if not main.saved_run.is_empty():
			_fail("a saved run with %s was offered by CONTINUE" % damage)
	# a missing file is just no run
	_remove_test_files()
	main.refresh_saved_run()
	if not main.saved_run.is_empty():
		_fail("a run was found with no file")
	main.continue_run()  # nothing saved: does nothing
	if main.state == "map" and main.saved_run.is_empty() and main.run_seed == 0:
		_fail("CONTINUE with no saved run started something")


func _check_title_menu() -> void:
	var hud = main.hud
	if hud.TITLE_CONTINUE != hud.TITLE_ITEMS.size():
		_fail(
			(
				"TITLE_CONTINUE is %d, one past the last entry would be %d"
				% [hud.TITLE_CONTINUE, hud.TITLE_ITEMS.size()]
			)
		)
	_remove_test_files()
	main.start_game(false, SEED_A)
	main.go_to_title()
	if main.saved_run.is_empty():
		_fail("the title screen does not know the saved run")
		return
	if main.title_sel != hud.TITLE_CONTINUE:
		_fail("the title menu did not select CONTINUE (selected %d)" % main.title_sel)
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0), Vector2(1000.0, 800.0)]:
		hud.size = s
		var k = s.y / 720.0
		var cr = hud.title_continue_rect()
		if cr.position.y < s.y * 0.25 + 4.0 * k:
			_fail("at %s the CONTINUE button touches the logo" % str(s))
		if cr.end.y > hud.title_rect(0).position.y - 3.0 * k:
			_fail("at %s the CONTINUE button touches PLAY" % str(s))
		if cr.position.x < 0.0 or cr.end.x > s.x:
			_fail("at %s the CONTINUE button leaves the screen" % str(s))
		if hud.title_at(cr.get_center()) != hud.TITLE_CONTINUE:
			_fail("at %s a point on CONTINUE does not give CONTINUE" % str(s))
		if hud.title_at(hud.title_rect(0).get_center()) != 0:
			_fail("at %s PLAY is not where it was" % str(s))
		for f in range(2):
			hud.queue_redraw()
			await process_frame
	var detail = hud.title_continue_detail()
	if not detail.contains("ROUND 1 /"):
		_fail("the CONTINUE button says '%s' for a run before floor 1" % detail)
	# keyboard order: CONTINUE, then PLAY ... QUIT, wrapping
	main.title_sel = hud.TITLE_CONTINUE
	main.input_sys.title_move(1)
	if main.title_sel != 0:
		_fail("Down from CONTINUE went to %d, not PLAY" % main.title_sel)
	main.input_sys.title_move(-1)
	if main.title_sel != hud.TITLE_CONTINUE:
		_fail("Up from PLAY did not go to CONTINUE")
	main.input_sys.title_move(-1)
	if main.title_sel != hud.TITLE_ITEMS.size() - 1:
		_fail("Up from CONTINUE did not wrap to the last entry")
	main.input_sys.title_move(1)
	if main.title_sel != hud.TITLE_CONTINUE:
		_fail("Down from the last entry did not wrap to CONTINUE")
	# Enter on CONTINUE plays the run on
	main.go_to_title()
	main.input_sys.title_activate(main.title_sel)
	if main.state != "map" or main.run_seed != SEED_A:
		_fail("activating CONTINUE did not resume the run (state %s)" % main.state)
	# no saved run: no button, the menu is as it was
	main.clear_saved_run()
	main.go_to_title()
	hud.size = Vector2(1280.0, 720.0)
	if hud.title_has_continue():
		_fail("the title menu offers CONTINUE with no saved run")
	if hud.title_at(hud.title_continue_rect().get_center()) != -1:
		_fail("the empty CONTINUE place reacts to the mouse")
	if main.title_sel != 0:
		_fail("with no saved run the title menu selects %d, not PLAY" % main.title_sel)
	main.input_sys.title_move(-1)
	if main.title_sel != hud.TITLE_ITEMS.size() - 1:
		_fail("Up from PLAY with no saved run went to %d" % main.title_sel)
	main.input_sys.title_activate(hud.TITLE_CONTINUE)  # a stale index does nothing
	if main.state != "title":
		_fail("activating CONTINUE with no saved run left the title screen")
	for f in range(2):
		hud.queue_redraw()
		await process_frame


func _same(label: String, got, want) -> void:
	var ok = false
	if typeof(want) == TYPE_FLOAT:
		ok = (
			(typeof(got) == TYPE_FLOAT or typeof(got) == TYPE_INT)
			and absf(float(got) - want) < 0.0001
		)
	else:
		ok = got == want
	if not ok:
		_fail("%s is %s after CONTINUE, expected %s" % [label, str(got), str(want)])


func _remove_bak_files() -> void:
	for tag in ["bad", "v2", "replaced"]:
		var p = TEST_PATH + "." + tag + ".bak"
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _remove_test_files() -> void:
	_remove_bak_files()
	if FileAccess.file_exists(TEST_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_PATH))


func _finish() -> void:
	if problems.is_empty():
		print("run_save_check: the saved run, CONTINUE and the title button work")
		quit(0)
	else:
		for line in problems.slice(0, 15):
			printerr("run_save_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
