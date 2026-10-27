extends SceneTree
# Checks XP and levels (README Milestone I): the numbers in data/xp.json load and bad ones fall back, the level
# curve adds up, a finished run pays its XP once (score, kills, cleared rounds, a won run, challenges, bosses),
# the total is saved in user://meta.json and comes back, an old or hand-edited meta.json still loads, and the
# title screen level bar and the run summary XP row draw.
# The "xp: ..." errors printed while it runs come from the bad tables it feeds in on purpose.
# It keeps the real meta.json first and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/xp_check.gd
# or with tools\run_xp_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const XpScript = preload("res://scripts/xp.gd")

var problems = []
var main
var kept = {}


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_keep_user_files()
	_check_table()
	_check_levels()
	_check_run_xp()
	_check_bad_table()
	_check_award()
	_check_meta_file()
	await _check_screens()
	_restore_user_files()
	_finish()


func _check_table() -> void:
	var t = XpScript.table
	for key in XpScript.DEFAULTS:
		if typeof(t.get(key)) != TYPE_INT or int(t[key]) < 0:
			_fail("data/xp.json: %s is %s" % [key, str(t.get(key))])
	for key in XpScript.BOSS_DEFAULTS:
		if typeof(t["boss"].get(key)) != TYPE_INT or int(t["boss"][key]) < 0:
			_fail("data/xp.json: boss.%s is %s" % [key, str(t["boss"].get(key))])
	for key in XpScript.MIN_ONE:
		if int(t[key]) < 1:
			_fail("data/xp.json: %s is %d, it must be at least 1" % [key, int(t[key])])


# the curve: level 1 at 0 XP, each level needs more than the one before, the top level stops
func _check_levels() -> void:
	var base = int(XpScript.table["level_base"])
	var step = int(XpScript.table["level_step"])
	var top = int(XpScript.table["max_level"])
	var i0 = XpScript.info(0)
	if i0["level"] != 1 or i0["into"] != 0 or i0["need"] != base or i0["max"]:
		_fail("0 XP gives %s, expected level 1 with %d needed" % [str(i0), base])
	var i1 = XpScript.info(base - 1)
	if i1["level"] != 1 or i1["into"] != base - 1:
		_fail("%d XP gives %s, expected level 1 with %d gathered" % [base - 1, str(i1), base - 1])
	var i2 = XpScript.info(base)
	if i2["level"] != 2 or i2["into"] != 0 or i2["need"] != base + step:
		_fail("%d XP gives %s, expected level 2 with 0 gathered" % [base, str(i2)])
	var i3 = XpScript.info(base + base + step + 7)
	if i3["level"] != 3 or i3["into"] != 7:
		_fail("level 3 plus 7 XP gives %s" % str(i3))
	if XpScript.info(-50)["level"] != 1:
		_fail("negative XP did not give level 1")
	# the total for a level and the level for that total agree, level by level
	for level in range(1, top + 1):
		var total = XpScript.total_for_level(level)
		var got = XpScript.info(total)
		if got["level"] != level:
			_fail(
				"total_for_level(%d) = %d, but that XP is level %d" % [level, total, got["level"]]
			)
		if level < top and XpScript.info(total + XpScript.need_for(level) - 1)["level"] != level:
			_fail("one XP before level %d already counted as level %d" % [level + 1, level + 1])
		if level > 1 and XpScript.need_for(level) <= XpScript.need_for(level - 1) and step > 0:
			_fail("level %d does not need more XP than level %d" % [level, level - 1])
	var at_top = XpScript.info(XpScript.total_for_level(top) + 999999)
	if at_top["level"] != top or not at_top["max"] or at_top["need"] != 0:
		_fail("far above the top level gives %s" % str(at_top))


func _check_run_xp() -> void:
	var t = XpScript.table
	if XpScript.run_xp(0, 0, 0, false, 0, 0) != 0:
		_fail("an empty run is worth XP")
	var per_score = int(t["score_per_xp"])
	if XpScript.run_xp(per_score * 3 + per_score - 1, 0, 0, false, 0, 0) != 3:
		_fail("score is not rounded down to whole XP")
	if XpScript.run_xp(0, 5, 0, false, 0, 0) != 5 * int(t["per_kill"]):
		_fail("5 kills are not worth 5 x per_kill")
	if XpScript.run_xp(0, 0, 4, false, 0, 0) != 4 * int(t["per_round"]):
		_fail("4 rounds are not worth 4 x per_round")
	if XpScript.run_xp(0, 0, 0, true, 0, 0) != int(t["run_won"]):
		_fail("a won run is not worth run_won")
	if XpScript.run_xp(0, 0, 0, false, 2, 0) != 2 * int(t["per_challenge"]):
		_fail("2 challenges are not worth 2 x per_challenge")
	if XpScript.run_xp(0, 0, 0, false, 0, 40) != 40:
		_fail("boss XP is not added as it is")
	if XpScript.run_xp(-100, -3, -2, false, -1, -9) != 0:
		_fail("negative inputs paid XP")
	if XpScript.boss_xp("lawnmower", false) != int(t["boss"]["boss"]):
		_fail("a normal boss pays %d" % XpScript.boss_xp("lawnmower", false))
	if XpScript.boss_xp("runner", false) != int(t["boss"]["runner"]):
		_fail("the cyclist pays %d" % XpScript.boss_xp("runner", false))
	if XpScript.boss_xp("any", true) != int(t["boss"]["final"]):
		_fail("the final boss pays %d" % XpScript.boss_xp("any", true))


# a missing or wrong value falls back to the built-in number, and the file is read again afterwards
func _check_bad_table() -> void:
	var good = XpScript.table.duplicate(true)
	# the loader reads the real file, so the bad cases go through _number, which it uses for every value
	if XpScript._number("x", "k", 7, 0) != 7:
		_fail("text as a number did not fall back")
	if XpScript._number(null, "k", 7, 0) != 7:
		_fail("a missing number did not fall back")
	if XpScript._number(-3, "k", 7, 0) != 7:
		_fail("a negative number did not fall back")
	if XpScript._number(0, "k", 7, 1) != 7:
		_fail("0 where 1 is the least did not fall back")
	if XpScript._number(12.9, "k", 7, 0) != 12:
		_fail("a decimal was not cut to a whole number")
	if XpScript._number(5, "k", 7, 0) != 5:
		_fail("a good number was changed")
	if XpScript.load_table().hash() != good.hash():
		_fail("loading data/xp.json twice gave different tables")


func _new_run() -> void:
	main.meta.xp = 0
	main.meta.begin_run()
	main.challenges.begin_run()
	main.score = 0
	main.kills = 0
	main.round_n = 1
	main.run_won = false
	main.round_lives_lost = 0


# a run pays its XP once, bosses count, and the level-up is reported
func _check_award() -> void:
	var t = XpScript.table
	_new_run()
	main.score = int(t["score_per_xp"]) * 10  # 10 XP
	main.kills = 6  # 6 x per_kill
	main.round_n = 4  # three rounds cleared in a lost run (it ended in round 4)
	main.meta.add_boss_kill("lawnmower", false)
	main.meta.add_boss_kill("runner", false)
	var expect = (
		10
		+ 6 * int(t["per_kill"])
		+ 3 * int(t["per_round"])
		+ int(t["boss"]["boss"])
		+ int(t["boss"]["runner"])
	)
	main.meta.award_run()
	if main.meta.xp_earned != expect:
		_fail("the run paid %d XP, expected %d" % [main.meta.xp_earned, expect])
	if main.meta.xp != expect:
		_fail("the total is %d XP, expected %d" % [main.meta.xp, expect])
	main.meta.award_run()
	if main.meta.xp != expect:
		_fail("paying the run a second time changed the total to %d" % main.meta.xp)
	# a won run: every round counts as cleared, plus the win and the final boss
	_new_run()
	main.round_n = main.MAX_ROUNDS
	main.run_won = true
	main.meta.add_boss_kill("any", true)
	main.meta.award_run()
	var won = main.MAX_ROUNDS * int(t["per_round"]) + int(t["run_won"]) + int(t["boss"]["final"])
	if main.meta.xp_earned != won:
		_fail("a won run paid %d XP, expected %d" % [main.meta.xp_earned, won])
	# a shop node is a screen, not a round (README alpha B2.4): a run lost in round 4 that went through a shop node on
	# floor 2 cleared two rounds, not three
	_new_run()
	main.run_map = {
		"floors":
		[[{"type": "normal"}], [{"type": "shop"}], [{"type": "normal"}], [{"type": "normal"}]]
	}
	main.map_path = [0, 0, 0, 0]
	main.map_floor = 3
	main.round_n = 4
	main.meta.award_run()
	if main.meta.xp_earned != 2 * int(t["per_round"]):
		_fail(
			(
				"a run with a shop node paid %d XP, expected %d"
				% [main.meta.xp_earned, 2 * int(t["per_round"])]
			)
		)
	main.run_map = {}
	main.map_path = []
	main.map_floor = -1
	# a quit run pays nothing, because award_run is never called for it
	_new_run()
	main.score = 99999
	if main.meta.xp != 0 or main.meta.xp_earned != 0:
		_fail("a run that was not paid out changed the XP")
	# going over a level boundary
	_new_run()
	main.meta.xp = XpScript.total_for_level(2) - 1
	main.kills = 1  # per_kill XP, enough to cross if per_kill >= 1
	main.meta.award_run()
	if int(t["per_kill"]) >= 1 and not main.meta.leveled_up():
		_fail("crossing into level 2 was not reported as a level-up")
	if main.meta.level_before != 1:
		_fail("level_before is %d, expected 1" % main.meta.level_before)
	_new_run()
	main.meta.xp = 0
	main.meta.award_run()
	if main.meta.leveled_up():
		_fail("a run that paid nothing reported a level-up")
	# the total cannot grow past the sanity limit
	_new_run()
	main.meta.xp = main.meta.MAX_XP
	main.kills = 1000
	main.meta.award_run()
	if main.meta.xp != main.meta.MAX_XP:
		_fail("the XP went past the limit: %d" % main.meta.xp)


func _check_meta_file() -> void:
	_new_run()
	main.score = int(XpScript.table["score_per_xp"]) * 50
	main.meta.award_run()
	var saved = main.meta.xp
	if saved != 50:
		_fail("expected 50 XP from the score, got %d" % saved)
	main.meta.xp = 0
	main.meta.load_meta()
	if main.meta.xp != saved:
		_fail("after a reload the XP is %d, expected %d" % [main.meta.xp, saved])
	# a file from before XP has none
	_write_meta('{"version": 1, "balance": 5, "total_earned": 9}')
	main.meta.load_meta()
	if main.meta.xp != 0:
		_fail("an old meta.json loaded %d XP" % main.meta.xp)
	# hand-edited nonsense does not crash and is clamped
	_write_meta('{"version": 1, "xp": -40}')
	main.meta.load_meta()
	if main.meta.xp != 0:
		_fail("negative XP loaded as %d" % main.meta.xp)
	_write_meta('{"version": 1, "xp": "lots"}')
	main.meta.load_meta()
	if main.meta.xp != 0:
		_fail("XP as text loaded as %d" % main.meta.xp)
	_write_meta('{"version": 1, "xp": [1, 2]}')
	main.meta.load_meta()
	if main.meta.xp != 0:
		_fail("XP as a list loaded as %d" % main.meta.xp)
	_write_meta('{"version": 1, "xp": 99999999999999}')
	main.meta.load_meta()
	if main.meta.xp != main.meta.MAX_XP:
		_fail("a huge XP loaded as %d" % main.meta.xp)
	_write_meta('{"version": 1, "xp": 450.7}')
	main.meta.load_meta()
	if main.meta.xp != 450:
		_fail("450.7 XP loaded as %d" % main.meta.xp)


func _write_meta(text: String) -> void:
	var f = FileAccess.open(main.meta.PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


# the title screen level bar and the run summary XP row draw (a script error in the drawing code shows up here)
func _check_screens() -> void:
	var hud = main.hud
	# the labels
	_new_run()
	main.meta.xp = 0
	main.meta.level_before = 1
	var label = hud._xp_row_label()
	if label != "XP (LEVEL 1: 0 / %d)" % XpScript.need_for(1):
		_fail("the XP row label at 0 XP is '%s'" % label)
	main.meta.xp = XpScript.total_for_level(3) + 5
	main.meta.level_before = 2
	if not hud._xp_row_label().begins_with("XP (LEVEL UP! NOW LEVEL 3"):
		_fail("the XP row label after a level-up is '%s'" % hud._xp_row_label())
	main.meta.level_before = 3
	if hud._xp_row_label() != "XP (LEVEL 3: 5 / %d)" % XpScript.need_for(3):
		_fail("the XP row label at level 3 is '%s'" % hud._xp_row_label())
	main.meta.xp = XpScript.total_for_level(int(XpScript.table["max_level"])) + 10
	main.meta.level_before = int(XpScript.table["max_level"])
	if not hud._xp_row_label().ends_with("TOP LEVEL)"):
		_fail("the XP row label at the top level is '%s'" % hud._xp_row_label())
	# the title screen at the start, mid level and the top level
	for xp in [0, XpScript.total_for_level(7) + 100, main.meta.xp]:
		main.meta.xp = xp
		main.go_to_title()
		await _draw_at_two_sizes()
	# the run summary after a lost and a won run, with a level-up
	_new_run()
	main.score = 5000
	main.kills = 12
	main.round_n = 5
	main.meta.award_run()
	main.state = "over"
	main.over_reason = "riders"
	main.run_won = false
	await _draw_at_two_sizes()
	_new_run()
	main.round_n = main.MAX_ROUNDS
	main.run_won = true
	main.meta.award_run()
	main.state = "over"
	main.over_reason = "victory"
	await _draw_at_two_sizes()
	main.run_won = false
	main.go_to_title()


func _draw_at_two_sizes() -> void:
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for f in range(2):
			main.hud.queue_redraw()
			await process_frame
	main.hud.size = Vector2(1280.0, 720.0)


func _finish() -> void:
	if problems.is_empty():
		print("xp_check: the XP table, level curve, payout, save file and screens work")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("xp_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


# the real meta.json is kept in memory and written back at the end
func _keep_user_files() -> void:
	var path = main.meta.PATH
	if FileAccess.file_exists(path):
		kept[path] = FileAccess.get_file_as_bytes(path)


func _restore_user_files() -> void:
	var path = main.meta.PATH
	if kept.has(path):
		var f = FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(kept[path])
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	main.meta.load_meta()
