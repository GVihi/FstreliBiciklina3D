extends SceneTree
# Checks the meta challenges (README Milestone B, "Earn from challenges"): the table in data/challenges.json loads,
# bad entries are refused, each condition is judged the way data/README.md says, a run pays the coins once and
# counts the challenges in user://meta.json, an old or hand-edited meta.json still loads, and the CHALLENGES
# title page and the run summary lines draw.
# The "challenges: ..." errors printed while it runs come from the bad entries it feeds in on purpose.
# It keeps the real meta.json first and puts it back at the end.
# Run from the project folder:
#   godot --headless --path . --script res://tools/challenges_check.gd
# or with tools\run_challenges_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const ChallengesScript = preload("res://scripts/challenges.gd")
const IDS = ["no_gun_round", "all_caches", "dodge_streak", "no_life_lost", "fast_run"]

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
	_check_bad_entries()
	_check_round_conditions()
	_check_streak()
	_check_run_time()
	_check_award()
	_check_meta_file()
	await _check_screens()
	_restore_user_files()
	_finish()


# a fresh run with no challenge ever done
func _new_run() -> void:
	main.meta.challenge_counts = {}
	main.meta.begin_run()
	main.challenges.begin_run()
	main.round_lives_lost = 0
	main.score = 0


func _done_ids() -> Array:
	var ids = main.challenges.done.keys()
	ids.sort()
	return ids


func _check_table() -> void:
	var table = main.challenges.table
	if table.size() != IDS.size():
		_fail("the table has %d challenges, expected %d" % [table.size(), IDS.size()])
	var seen = {}
	for c in table:
		if not IDS.has(c["id"]):
			_fail("unexpected challenge id %s" % c["id"])
		if seen.has(c["counter"]):
			_fail("counter %s is used twice" % c["counter"])
		seen[c["counter"]] = true
		if c["target"] <= 0 or c["reward"] <= 0:
			_fail("%s has target %d and reward %d" % [c["id"], c["target"], c["reward"]])


func _good_entry() -> Dictionary:
	return {
		"id": "x",
		"name": "X",
		"desc": "d",
		"condition": "round_no_gun",
		"scope": "round",
		"target": 1,
		"reward": 2,
		"counter": "x_count"
	}


func _check_bad_entries() -> void:
	if ChallengesScript._clean(_good_entry(), {}, {}).is_empty():
		_fail("a good entry was refused")
	var bad = {}
	bad["unknown condition"] = _with("condition", "fly_to_the_moon")
	bad["unknown scope"] = _with("scope", "week")
	bad["missing name"] = _without("name")
	bad["empty id"] = _with("id", "")
	bad["target zero"] = _with("target", 0)
	bad["reward as text"] = _with("reward", "five")
	bad["negative reward"] = _with("reward", -1)
	for what in bad:
		if not ChallengesScript._clean(bad[what], {}, {}).is_empty():
			_fail("an entry with %s was accepted" % what)
	if not ChallengesScript._clean(_good_entry(), {"x": true}, {}).is_empty():
		_fail("a duplicate id was accepted")
	if not ChallengesScript._clean(_good_entry(), {}, {"x_count": true}).is_empty():
		_fail("a duplicate counter was accepted")
	if not ChallengesScript._clean("not an object", {}, {}).is_empty():
		_fail("an entry that is not an object was accepted")


func _with(key: String, value) -> Dictionary:
	var e = _good_entry()
	e[key] = value
	return e


func _without(key: String) -> Dictionary:
	var e = _good_entry()
	e.erase(key)
	return e


func _check_round_conditions() -> void:
	# a clean round: no dart fired, no life lost
	_new_run()
	main.challenges.on_round_cleared()
	if _done_ids() != ["no_gun_round", "no_life_lost"]:
		_fail("a clean round completed %s" % str(_done_ids()))
	# a dart fired
	_new_run()
	main.challenges.on_dart_fired()
	main.challenges.on_round_cleared()
	if _done_ids() != ["no_life_lost"]:
		_fail("a round with a dart fired completed %s" % str(_done_ids()))
	# a life lost
	_new_run()
	main.round_lives_lost = 1
	main.challenges.on_round_cleared()
	if _done_ids() != ["no_gun_round"]:
		_fail("a round with a life lost completed %s" % str(_done_ids()))
	# a new round forgets the dart of the one before
	_new_run()
	main.challenges.on_dart_fired()
	main.challenges.begin_round()
	main.challenges.on_round_cleared()
	if not main.challenges.done.has("no_gun_round"):
		_fail("a dart fired in the round before still counted in the next one")
	# every cache taken while riders were up, and after they were down
	_new_run()
	main.challenges.on_all_caches(true)
	main.challenges.on_round_cleared()
	if not main.challenges.done.has("all_caches"):
		_fail("every cache before the last rider fell did not count")
	_new_run()
	main.challenges.on_all_caches(false)
	main.challenges.on_round_cleared()
	if main.challenges.done.has("all_caches"):
		_fail("every cache after the last rider fell counted")
	# a round challenge done in round 1 is still done after a bad round 2
	_new_run()
	main.challenges.on_round_cleared()
	main.challenges.begin_round()
	main.challenges.on_dart_fired()
	main.round_lives_lost = 2
	main.challenges.on_round_cleared()
	if _done_ids() != ["no_gun_round", "no_life_lost"]:
		_fail("a bad round 2 changed the challenges of round 1: %s" % str(_done_ids()))


func _check_streak() -> void:
	_new_run()
	for i in range(4):
		main.challenges.on_perfect_dodge()
	if main.challenges.done.has("dodge_streak"):
		_fail("four perfect dodges in a row completed the streak")
	main.challenges.on_perfect_dodge()
	if not main.challenges.done.has("dodge_streak"):
		_fail("five perfect dodges in a row did not complete the streak")
	# a lost life ends the streak
	_new_run()
	for i in range(3):
		main.challenges.on_perfect_dodge()
	main.challenges.on_life_lost()
	for i in range(2):
		main.challenges.on_perfect_dodge()
	if main.challenges.done.has("dodge_streak"):
		_fail("3 dodges, a lost life and 2 more dodges completed the streak")
	var streak_entry = {}
	for c in main.challenges.table:
		if c["id"] == "dodge_streak":
			streak_entry = c
	if main.challenges.progress_text(streak_entry) != "3 / 5":
		_fail(
			(
				"the streak progress is '%s', expected '3 / 5'"
				% main.challenges.progress_text(streak_entry)
			)
		)
	_new_run()
	if main.challenges.progress_text(streak_entry) != "":
		_fail(
			"a run with no dodges shows progress '%s'" % main.challenges.progress_text(streak_entry)
		)


func _check_run_time() -> void:
	_new_run()
	main.challenges.on_run_won(1199.0)
	if not main.challenges.done.has("fast_run"):
		_fail("a run won in 1199 s did not count as under 20 minutes")
	_new_run()
	main.challenges.on_run_won(1200.0)
	if main.challenges.done.has("fast_run"):
		_fail("a run won in exactly 1200 s counted as under 20 minutes")


# coins, counters, NEW and paying once
func _check_award() -> void:
	_new_run()
	main.challenges.on_round_cleared()  # no_gun_round (5) and no_life_lost (3)
	var coins = main.challenges.award()
	if coins != 8:
		_fail("two challenges paid %d coins, expected 8" % coins)
	if main.challenges.award() != 8 or int(main.meta.challenge_counts.get("no_gun_rounds", 0)) != 1:
		_fail("paying the same run twice counted twice")
	var new_ids = main.challenges.new_ids.duplicate()
	new_ids.sort()
	if new_ids != ["no_gun_round", "no_life_lost"]:
		_fail("first-time challenges were %s" % str(new_ids))
	# the same two again in a second run: paid again, no longer new, counted twice
	main.meta.begin_run()
	main.challenges.begin_run()
	main.challenges.on_round_cleared()
	if main.challenges.award() != 8:
		_fail("the second run paid %d coins, expected 8" % main.challenges.coins)
	if not main.challenges.new_ids.is_empty():
		_fail("challenges done before were marked NEW again: %s" % str(main.challenges.new_ids))
	if int(main.meta.challenge_counts.get("no_gun_rounds", 0)) != 2:
		_fail(
			(
				"no_gun_rounds is %s after two runs"
				% str(main.meta.challenge_counts.get("no_gun_rounds"))
			)
		)
	# a run with nothing done pays nothing
	_new_run()
	if main.challenges.award() != 0:
		_fail("a run with no challenge done paid coins")


# the run payout adds the coins, saves the counters, and a reload gets them back
func _check_meta_file() -> void:
	_new_run()
	main.meta.balance = 10
	main.meta.total_earned = 10
	main.meta.boss_coins = 0
	main.challenges.on_round_cleared()
	var n = main.meta.award_run()
	if n != 8 or main.meta_earned != 8:
		_fail("award_run paid %d (meta_earned %d), expected 8" % [n, main.meta_earned])
	if main.meta.balance != 18:
		_fail("the balance is %d after the payout, expected 18" % main.meta.balance)
	if main.meta.award_run() != 0:
		_fail("award_run paid a second time")
	main.meta.balance = 0
	main.meta.challenge_counts = {}
	main.meta.load_meta()
	if main.meta.balance != 18 or int(main.meta.challenge_counts.get("untouched_rounds", 0)) != 1:
		_fail(
			(
				"after a reload the balance is %d and untouched_rounds %s"
				% [main.meta.balance, str(main.meta.challenge_counts.get("untouched_rounds"))]
			)
		)
	# a file from before challenges has no counts
	_write_meta('{"version": 1, "balance": 5, "total_earned": 9}')
	main.meta.load_meta()
	if main.meta.balance != 5 or not main.meta.challenge_counts.is_empty():
		_fail(
			(
				"an old meta.json loaded balance %d and counts %s"
				% [main.meta.balance, str(main.meta.challenge_counts)]
			)
		)
	# hand-edited nonsense does not crash and is clamped
	_write_meta('{"version": 1, "balance": 5, "challenges": {"a": -4, "b": "x", "c": 3}}')
	main.meta.load_meta()
	if (
		int(main.meta.challenge_counts.get("a", -1)) != 0
		or int(main.meta.challenge_counts.get("c", 0)) != 3
	):
		_fail("hand-edited counts loaded as %s" % str(main.meta.challenge_counts))
	_write_meta('{"version": 1, "balance": 5, "challenges": 7}')
	main.meta.load_meta()
	if not main.meta.challenge_counts.is_empty():
		_fail("counts that are not an object loaded as %s" % str(main.meta.challenge_counts))


func _write_meta(text: String) -> void:
	var f = FileAccess.open(main.meta.PATH, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()


# the title page and the run summary draw (a script error in the drawing code shows up here)
func _check_screens() -> void:
	main.meta.load_meta()
	main.go_to_title()
	main.hud.size = Vector2(1280.0, 720.0)
	var hud = main.hud
	var item = -1
	for i in range(hud.TITLE_ITEMS.size()):
		if hud.TITLE_ITEMS[i]["id"] == "challenges":
			item = i
	if item < 0:
		_fail("the title menu has no CHALLENGES entry")
		return
	for i in range(hud.TITLE_ITEMS.size() - 1):
		if hud.title_rect(i).end.y > hud.title_rect(i + 1).position.y:
			_fail("title buttons %d and %d overlap" % [i, i + 1])
	var last = hud.title_rect(hud.TITLE_ITEMS.size() - 1)
	if last.end.y > 720.0 * 0.885 - 20.0:
		_fail("the last title button ends at %.0f, too close to the high score text" % last.end.y)
	main.input_sys.title_activate(item)
	if main.title_page != "challenges":
		_fail("choosing CHALLENGES opened '%s'" % main.title_page)
	await _draw_at_two_sizes()
	main.input_sys.title_back()
	if main.title_page != "":
		_fail("going back left the page '%s' open" % main.title_page)
	# the summary lines: two done (both NEW), then all five done, which are cut to three lines
	_new_run()
	main.challenges.on_round_cleared()
	main.challenges.award()
	var lines = hud._challenge_summary_lines()
	if lines.size() != 2 or not str(lines[0][0]).begins_with("NEW "):
		_fail("the summary lines after two new challenges are %s" % str(lines))
	_new_run()
	main.challenges.on_all_caches(true)
	main.challenges.on_round_cleared()
	for i in range(5):
		main.challenges.on_perfect_dodge()
	main.challenges.on_run_won(100.0)
	main.challenges.award()
	lines = hud._challenge_summary_lines()
	if (
		lines.size() != hud.CHALLENGE_LINES
		or not str(lines[lines.size() - 1][0]).begins_with("AND ")
	):
		_fail("the summary lines after five challenges are %s" % str(lines))
	main.state = "over"
	main.over_reason = "riders"
	main.run_won = false
	await _draw_at_two_sizes()
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
		print(
			"challenges_check: the challenge list, conditions, payout, save file and screens work"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("challenges_check: " + line)
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
