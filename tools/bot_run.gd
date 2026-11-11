extends SceneTree
# Bot playthrough balance harness (README Tooling & QA, "Bot playthrough balance harness").
# A simple bot plays whole runs on many seeds and logs, for every round, the time, lives lost,
# damage taken, kills, caches taken and whether it reached the extraction point.
# A per-seed and cross-seed summary gives real numbers for balance and difficulty-curve passes.
#
# Since 2026-11-07 it plays the same seeds under several Heat settings in one go and ends with one
# comparison table, for the Heat playtest items (README H1.12, H2.6, H3.5): run length, lives lost,
# clear rate and what a run pays, per setting.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/bot_run.gd
# Optional args after "--":
#   --seeds N        how many seeds to play (default 8)
#   --full           use 20 seeds (the "slow" mode; same as --seeds 20)
#   --seed HEX       play this single seed only (overrides --seeds), for example --seed 00017CFB
#   --heat LIST      Heat levels to play, comma separated, played by level like the PLAY page does
#                    (default 0; a level above the top level of data/heat.json is cut to it)
#                    example for H1.12: --heat 0,3,5
#   --mods SETS      sets of modifier ranks, "id=rank,id=rank", several sets separated by ";"
#                    (ids are in data/heat.json: swift, crowd, lives, tough, stingy); a set with a
#                    clash is played the way Heat.clean_set makes it legal, and the harness says so
#                    example: --mods "swift=2,crowd=1;lives=2"
#   --each-mod       every rank of every modifier alone (H2.6: "every modifier alone")
#   --maxed          the all-ranks-maxed set, made legal (H2.6: "the maxed set")
#   --out PATH       write the summary to this file instead of bot_run_summary.txt
#
# The settings are played in this order: the --heat levels, then the --mods sets, then --each-mod, then
# --maxed, and every setting plays the same seeds. A set worth more than the top level cannot be chosen
# on the PLAY page yet (docs/HEAT.md, H2.4), so the harness plays a set by handing it to
# `heat_sys.play_set` before the run starts, which is what the Heat checks do.
#
# Every run starts from a new player's progress (no coins, nothing owned, 0 XP; Meta.reset_all in
# memory) with every Heat level open, and nothing is written to user:// (SaveUtil.read_only), so the
# real saves are never touched and the runs of one setting do not change the next one's pay.
#
# Exit code 0 = all runs completed without a scripted error, 1 = a run timed out or got stuck,
# 2 = the arguments could not be used.
# A round-by-round log, a cross-seed summary per setting and the comparison table are printed to stdout
# and to the output file.
#
# Bot behaviour (matches the README spec):
#   - aims at the nearest rider and fires every fire-interval frames
#   - dashes away from an incoming phone that is about to hit
#   - walks toward the nearest supply cache when no rider is nearby
#   - walks to the extraction point once it opens
#   On the map screen it always picks the first available node.
#   After a cleared round it takes the first upgrade offered, in the shop it leaves at once (nothing
#   is bought), and on a rest node it refills the hearts (or takes the extra upgrade at full hearts).

const HeatScript = preload("res://scripts/heat.gd")
const SaveUtil = preload("res://scripts/save_util.gd")

const MAIN_SCENE = "res://main.tscn"
const DT = 1.0 / 60.0  # simulation step (60 fps)
const DEFAULT_SEEDS = 8
const FULL_SEEDS = 20
const MAX_ROUNDS = 10  # a full run is 10 floors
const ROUND_TIMEOUT = 180.0  # seconds: abort a round if the bot is stuck this long
const RUN_TIMEOUT = 1200.0  # seconds: abort a whole run if something is very wrong
const STUCK_ITERATIONS = 600  # the same screen this many loop steps in a row = the bot is stuck on it
# firing rate: fire every N frames when aimed at a target
const FIRE_INTERVAL = 18
# distance within which the bot moves toward a cache instead of wandering
const CACHE_ATTRACT_DIST = 50.0
# a phone is "incoming" if its target on the ground is within this radius of the player
const PHONE_DANGER_RADIUS = 2.5
# the first seconds of a cleared round the game ignores the key (input.gd), so the bot waits like a player
const CLEAR_WAIT = 0.8

var problems: Array = []
var heat_table = null  # a Heat object (heat.gd) read only for the table: levels, modifiers and the set rules

# ------------------------------------------------------------------ main


func _initialize() -> void:
	SaveUtil.read_only = true  # a bot run must never write the player's settings, scores, coins or run
	heat_table = HeatScript.new()

	var args = OS.get_cmdline_user_args()
	var num_seeds = DEFAULT_SEEDS
	var level_text = "0"
	var set_texts: Array = []
	var each_mod = false
	var maxed = false
	var out_path = "bot_run_summary.txt"
	var fixed_seed = -1

	var i = 0
	while i < args.size():
		var a = args[i]
		if a == "--full":
			num_seeds = FULL_SEEDS
		elif a == "--each-mod":
			each_mod = true
		elif a == "--maxed":
			maxed = true
		elif a == "--seeds" and i + 1 < args.size():
			i += 1
			num_seeds = int(args[i])
		elif a == "--heat" and i + 1 < args.size():
			i += 1
			level_text = args[i]
		elif a == "--mods" and i + 1 < args.size():
			i += 1
			for part in args[i].split(";", false):
				set_texts.append(part)
		elif a == "--out" and i + 1 < args.size():
			i += 1
			out_path = args[i]
		elif a == "--seed" and i + 1 < args.size():
			i += 1
			fixed_seed = args[i].hex_to_int()  # the summaries print seeds in hex; "0x" in front is fine
			num_seeds = 1
		else:
			problems.append('unknown or unfinished argument "%s"' % a)
		i += 1

	var seeds: Array = []
	if fixed_seed >= 0:
		seeds.append(fixed_seed)
	else:
		for k in range(num_seeds):
			seeds.append((k * 2654435761 + 97531) & 0xFFFFFFFF)

	var configs = _make_configs(level_text, set_texts, each_mod, maxed)
	if not problems.is_empty():
		print("bot_run: the arguments could not be used:")
		for p in problems:
			print("  " + p)
		quit(2)
		return

	var header = (
		"bot_run: %d seed(s), %d Heat setting(s), %s"
		% [seeds.size(), configs.size(), Time.get_datetime_string_from_system()]
	)
	print(header)

	var out_lines: PackedStringArray = PackedStringArray()
	out_lines.append(header)
	var results: Array = []  # one {"config", "runs"} per setting
	for cfg in configs:
		var runs: Array = []
		for s in seeds:
			var result = await _play_run(s, cfg)
			runs.append(result)
			_print_run_summary(result)
		results.append({"config": cfg, "runs": runs})
		var cross = _cross_seed_summary(runs, cfg)
		print("")
		print(cross)
		out_lines.append("")
		for r in runs:
			out_lines.append(_run_lines(r))
		out_lines.append("")
		out_lines.append(cross)

	if results.size() > 1:
		var table = _compare_table(results)
		print("")
		print(table)
		out_lines.append("")
		out_lines.append(table)

	var f = FileAccess.open(out_path, FileAccess.WRITE)
	if f:
		f.store_string("\n".join(out_lines))
		f.close()
		print("bot_run: summary written to %s" % out_path)
	else:
		print("bot_run: could not write to %s" % out_path)

	if problems.is_empty():
		quit(0)
	else:
		print("bot_run: %d problem(s):" % problems.size())
		for p in problems.slice(0, 10):
			print("  " + p)
		quit(1)


# ------------------------------------------------------------------ the Heat settings to play


# One setting is {"label", "level", "ranks", "points", "by_set"}. A level setting is played by level
# (`Main.heat`), the way the PLAY page starts a run; a set setting is played with `play_set`.
func _make_configs(level_text: String, set_texts: Array, each_mod: bool, maxed: bool) -> Array:
	var configs: Array = []
	for part in level_text.split(",", false):
		if not part.strip_edges().is_valid_int():
			problems.append('bad --heat entry "%s" (want whole numbers like 0,3,5)' % part)
			continue
		var level = heat_table.clamp_level(int(part.strip_edges()))
		(
			configs
			. append(
				{
					"label": "H%d" % level,
					"level": level,
					"ranks": {},
					"points": heat_table.preset_points(level),
					"by_set": false,
				}
			)
		)
	for text in set_texts:
		var ranks = _parse_set(text)
		if not ranks.is_empty():
			configs.append(_set_config(ranks, ""))
	if each_mod:
		for id in heat_table.modifier_ids():
			for rank in range(1, heat_table.max_rank(id) + 1):
				configs.append(_set_config({id: rank}, ""))
	if maxed:
		var top = {}
		for id in heat_table.modifier_ids():
			top[id] = heat_table.max_rank(id)
		configs.append(_set_config(top, "maxed "))
	return configs


# "swift=2,crowd=1" -> {"swift": 2, "crowd": 1}; {} (and a problem logged) when an entry cannot be read
func _parse_set(text: String) -> Dictionary:
	var ranks = {}
	for part in text.split(",", false):
		var kv = part.strip_edges().split("=")
		if kv.size() != 2 or heat_table.max_rank(kv[0]) == 0 or not kv[1].is_valid_int():
			problems.append(
				(
					'bad --mods entry "%s" (want id=rank, ids: %s)'
					% [part, ", ".join(heat_table.modifier_ids())]
				)
			)
			return {}
		ranks[kv[0]] = int(kv[1])
	return ranks


# the setting of a set of ranks, made legal first (a set with a clash is played the way the game would play it)
func _set_config(ranks: Dictionary, prefix: String) -> Dictionary:
	var legal = heat_table.clean_set(ranks)
	if not heat_table.is_legal(ranks):
		print(
			(
				"bot_run: set %s has a clash or a rank out of range, played as %s"
				% [_set_text(ranks), _set_text(legal)]
			)
		)
	return {
		"label": "%sset %s" % [prefix, _set_text(legal)],
		"level": 0,
		"ranks": legal,
		"points": heat_table.total_points(legal),
		"by_set": true,
	}


# "swift=2 crowd=1" in the order of the table, "none" for an empty set
func _set_text(ranks: Dictionary) -> String:
	var parts: PackedStringArray = PackedStringArray()
	for id in heat_table.modifier_ids():
		if int(ranks.get(id, 0)) > 0:
			parts.append("%s=%d" % [id, int(ranks[id])])
	return " ".join(parts) if not parts.is_empty() else "none"


# ------------------------------------------------------------------ one full run


func _play_run(seed_value: int, cfg: Dictionary) -> Dictionary:
	var tag = "seed %08X  %s" % [seed_value, cfg["label"]]
	var main = load(MAIN_SCENE).instantiate()
	main.generated_arena = true
	root.add_child(main)

	# wait a few frames for the scene to settle
	for _f in range(4):
		await process_frame

	# Heat is read by start_game itself (the starting hearts, the heat level kept open), so it is set up first.
	# A new player's progress with every level open: the runs of one setting must not change what the next one
	# pays (challenge coins are paid once, XP and coins pile up), and a level that is not open plays as Heat 0.
	main.meta.reset_all()
	main.meta.heat_open = heat_table.top_level()
	main.heat_ranks = {}  # a set the owner chose on the modifiers page must not leak in from settings.cfg
	main.heat_sys.clear_set()
	if cfg["by_set"]:
		main.heat_sys.play_set(cfg["ranks"])
		main.heat = clampi(int(cfg["points"]), 0, heat_table.top_level())
	else:
		main.heat = int(cfg["level"])

	main.start_game(false, seed_value)
	main.force_captured = true  # headless: treat as mouse-captured so the game is not paused

	# wait for the map screen
	var wait_frames = 0
	while main.state == "loading" and wait_frames < 300:
		main._process(DT)
		wait_frames += 1
		await process_frame
	if main.state == "loading":
		main.finish_loading()

	var run: Dictionary = {
		"tag": tag,
		"seed": seed_value,
		"label": cfg["label"],
		"points": cfg["points"],
		"won": false,
		"rounds": [],
		"total_time": 0.0,
		"total_lives_lost": 0,
		"total_kills": 0,
		"total_caches": 0,
		"start_hearts": main.MAXHEARTS,
		"coins": 0,
		"heat_coins": 0,
		"xp": 0,
		"heat_xp": 0,
		"abort": "",
	}

	var run_t = 0.0
	var last_state = ""
	var same_state = 0
	while run_t < RUN_TIMEOUT:
		var s = main.state
		if s == "over" or s == "dying":
			run["won"] = main.run_won
			break

		# a screen that never changes is a bot that cannot get on: stop instead of waiting for RUN_TIMEOUT
		if s != "play" and s == last_state:
			same_state += 1
			if same_state > STUCK_ITERATIONS:
				run["abort"] = "stuck on the %s screen" % s
				problems.append("%s: %s (round %d)" % [tag, run["abort"], main.round_n])
				break
		else:
			same_state = 0
		last_state = s

		if s == "map":
			main.pick_node(0)
		elif s == "shop":
			main.shop_sys.leave_shop()
		elif s == "rest":
			# refill hearts if below max, otherwise take upgrade (or just leave)
			if main.shop_sys.rest_refill_ok():
				main.shop_sys.rest_choose(0)
			else:
				main.shop_sys.rest_choose(1)
		elif s == "upgrade":
			# pick the first offered upgrade so the bot has at least some progression
			main.shop_sys.pick_upgrade(0)
		elif s == "clear" and main.state_t > CLEAR_WAIT:
			# a cleared round waits for a key (input.gd): the key opens the upgrade screen
			main.shop_sys.enter_upgrade()
		elif s == "play":
			var round_result = await _play_round(main)
			run["rounds"].append(round_result)
			run["total_lives_lost"] += round_result["lives_lost"]
			run["total_kills"] += round_result["kills"]
			run["total_caches"] += round_result["caches"]
			run_t += round_result["time"]
			if round_result["aborted"]:
				run["abort"] = "round %d timed out" % round_result["round_n"]
				break
			continue
		else:
			# clear (before its key works) / other transitions: step and wait
			main._process(DT)
			run_t += DT
			await process_frame
			continue

		# after every non-play step, run a few simulation frames
		for _f in range(6):
			main._process(DT)
			run_t += DT
		await process_frame

	run["total_time"] = run_t
	# what the run paid (award_run ran when it ended; a run that was cut off by a timeout paid nothing)
	if main.meta.awarded:
		run["coins"] = int(main.meta_earned)
		run["heat_coins"] = int(main.meta.heat_coins)
		run["xp"] = int(main.meta.xp_earned)
		run["heat_xp"] = int(main.meta.heat_xp)
	main.queue_free()
	await process_frame
	return run


# ------------------------------------------------------------------ one round


func _play_round(main) -> Dictionary:
	var round_n = main.round_n
	var result: Dictionary = {
		"round_n": round_n,
		"time": 0.0,
		"lives_lost": 0,
		"kills": main.kills,  # snapshot; delta computed after
		"caches": 0,
		"reached_extraction": false,
		"cleared": false,
		"aborted": false,
	}
	var kills_before = main.kills
	var caches_before = main.objective_sys.taken
	var frame = 0
	var fire_cooldown = 0

	while result["time"] < ROUND_TIMEOUT:
		if main.state != "play":
			break
		result["time"] += DT
		frame += 1

		# --- aim and fire ---
		var target = _nearest_rider(main)
		if not target.is_empty():
			var to: Vector3 = target["pos"] + Vector3(0.0, 1.0, 0.0) - main.cam.global_position
			main.yaw = atan2(-to.x, -to.z)
			main.pitch = atan2(to.y, Vector2(to.x, to.z).length())
			fire_cooldown -= 1
			if fire_cooldown <= 0:
				fire_cooldown = FIRE_INTERVAL
				main.combat_sys.fire()

		# --- move: dash away from incoming phones, then toward cache or wander ---
		if main.dash_cd <= 0.0:
			var phone_dir = _incoming_phone_dir(main)
			if phone_dir != Vector3.ZERO:
				# dash perpendicular to the phone
				var perp = Vector3(-phone_dir.z, 0.0, phone_dir.x).normalized()
				main.pvel = perp * 8.0
				main.player_sys.try_dash()

		var move_target = _pick_move_target(main, target)
		if move_target != Vector3.ZERO:
			var to_tgt = move_target - main.player.position
			to_tgt.y = 0.0
			if to_tgt.length() > 0.5:
				var step = to_tgt.normalized() * 4.0 * DT
				var new_pos = main.player.position + step
				main.player.position = main.clamp_walk(new_pos)

		main._process(DT)
		await process_frame

	# fill in deltas
	result["kills"] = main.kills - kills_before
	result["caches"] = main.objective_sys.taken - caches_before
	result["reached_extraction"] = (
		main.objective_sys.taken >= 0
		and (
			main.state != "play" and main.round_n > round_n
			or (main.state == "over" and main.run_won and main.round_n >= main.MAX_ROUNDS)
		)
	)
	var cleared_hits = main.count_hits() >= main.hits_needed()
	result["cleared"] = cleared_hits
	result["lives_lost"] = main.round_lives_lost
	if result["time"] >= ROUND_TIMEOUT:
		result["aborted"] = true
		problems.append(
			(
				"%s round %d: bot timed out after %.0f s (state %s)"
				% [main.run_seed, round_n, result["time"], main.state]
			)
		)
	return result


# ------------------------------------------------------------------ bot helpers


func _nearest_rider(main) -> Dictionary:
	var best = {}
	var best_d = INF
	var pp: Vector3 = main.player.position
	for r in main.riders:
		if r.get("hidden", false) or r.get("gone", false):
			continue
		var d = Vector2(r["pos"].x - pp.x, r["pos"].z - pp.z).length()
		if d < best_d:
			best_d = d
			best = r
	return best


# returns a direction (from player) to dash away from if a phone is about to land close
func _incoming_phone_dir(main) -> Vector3:
	var pp: Vector3 = main.player.position
	for ph in main.phones:
		if ph.get("ret", false):
			continue
		# the phone targets a point on the ground: check if that ring is close
		var tg: Vector3 = ph.get("target", Vector3.ZERO)
		var flat_d = Vector2(tg.x - pp.x, tg.z - pp.z).length()
		if flat_d < PHONE_DANGER_RADIUS and ph.get("p", 0.0) > 0.3:
			# direction from phone toward player (dash that way, away from impact)
			var from_tg = Vector3(pp.x - tg.x, 0.0, pp.z - tg.z).normalized()
			return from_tg
	return Vector3.ZERO


# returns the position the bot should walk toward this frame
func _pick_move_target(main, nearest_rider) -> Vector3:
	var pp: Vector3 = main.player.position

	# if the extraction point is open, walk to it
	if main.objective_sys.extracting and main.objective_sys.has_goal():
		return main.objective_sys.goal.get("pos", Vector3.ZERO)

	# if a cache is close and no rider is right on top of us, walk to the nearest cache
	if (
		nearest_rider.is_empty()
		or Vector2(nearest_rider["pos"].x - pp.x, nearest_rider["pos"].z - pp.z).length() > 8.0
	):
		var best_cache_pos = Vector3.ZERO
		var best_cd = INF
		for c in main.objective_sys.caches:
			if c.get("taken", false):
				continue
			var cp: Vector3 = c.get("pos", Vector3.ZERO)
			var cd = Vector2(cp.x - pp.x, cp.z - pp.z).length()
			if cd < best_cd and cd < CACHE_ATTRACT_DIST:
				best_cd = cd
				best_cache_pos = cp
		if best_cache_pos != Vector3.ZERO:
			return best_cache_pos

	# when fighting, orbit around the arena centre at a moderate distance
	if not nearest_rider.is_empty():
		# keep roughly facing the rider while circling: strafe sideways
		var to_rider = (
			Vector3(nearest_rider["pos"].x - pp.x, 0.0, nearest_rider["pos"].z - pp.z).normalized()
		)
		var strafe = Vector3(-to_rider.z, 0.0, to_rider.x)
		return pp + strafe * 4.0

	return Vector3.ZERO


# ------------------------------------------------------------------ output


func _print_run_summary(run: Dictionary) -> void:
	print(_run_lines(run))


func _run_lines(run: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var status = (
		"WON" if run["won"] else ("ABORT: " + run["abort"] if run["abort"] != "" else "LOST")
	)
	(
		lines
		. append(
			(
				"\n%s — %s  total %.0f s  kills %d  caches %d  lives lost %d of %d hearts  paid %d coins (Heat +%d)  %d XP (Heat +%d)"
				% [
					run["tag"],
					status,
					run["total_time"],
					run["total_kills"],
					run["total_caches"],
					run["total_lives_lost"],
					run["start_hearts"],
					run["coins"],
					run["heat_coins"],
					run["xp"],
					run["heat_xp"],
				]
			)
		)
	)
	lines.append("  rnd  time   kills  caches  lives_lost  cleared")
	for r in run["rounds"]:
		var cleared_str = "YES" if r["cleared"] else "no "
		lines.append(
			(
				"  %3d  %5.1f  %5d  %6d  %10d  %s"
				% [r["round_n"], r["time"], r["kills"], r["caches"], r["lives_lost"], cleared_str]
			)
		)
	return "\n".join(lines)


# the averages of the runs of one setting (all keys are per run, "won" and "aborts" are counts)
func _stats(runs: Array) -> Dictionary:
	var st = {
		"n": runs.size(),
		"won": 0,
		"aborts": 0,
		"time": 0.0,
		"kills": 0.0,
		"caches": 0.0,
		"lives": 0.0,
		"played": 0.0,
		"cleared": 0.0,
		"coins": 0.0,
		"heat_coins": 0.0,
		"xp": 0.0,
	}
	if runs.is_empty():
		return st
	for run in runs:
		if run["won"]:
			st["won"] += 1
		if run["abort"] != "":
			st["aborts"] += 1
		st["time"] += run["total_time"]
		st["kills"] += run["total_kills"]
		st["caches"] += run["total_caches"]
		st["lives"] += run["total_lives_lost"]
		st["played"] += run["rounds"].size()
		st["coins"] += run["coins"]
		st["heat_coins"] += run["heat_coins"]
		st["xp"] += run["xp"]
		for r in run["rounds"]:
			if r["cleared"]:
				st["cleared"] += 1
	for key in [
		"time", "kills", "caches", "lives", "played", "cleared", "coins", "heat_coins", "xp"
	]:
		st[key] = st[key] / float(runs.size())
	return st


func _cross_seed_summary(all_runs: Array, cfg: Dictionary) -> String:
	var n = all_runs.size()
	if n == 0:
		return "bot_run: no runs"
	var st = _stats(all_runs)

	# per-round-number aggregates (index 0 = round 1)
	var round_time: Array = []
	var round_lives: Array = []
	var round_clear: Array = []
	for _i in range(MAX_ROUNDS):
		round_time.append([])
		round_lives.append([])
		round_clear.append([])
	for run in all_runs:
		for r in run["rounds"]:
			var idx = clampi(r["round_n"] - 1, 0, MAX_ROUNDS - 1)
			round_time[idx].append(r["time"])
			round_lives[idx].append(r["lives_lost"])
			round_clear[idx].append(1 if r["cleared"] else 0)

	var lines: PackedStringArray = PackedStringArray()
	lines.append(
		(
			"=== cross-seed summary: %d run(s), %s (%d Heat points, %d hearts) ==="
			% [n, cfg["label"], cfg["points"], all_runs[0]["start_hearts"]]
		)
	)
	(
		lines
		. append(
			(
				"  won %d / %d (%.0f %%)   avg time %.0f s   avg kills %.1f   avg caches %.1f   avg lives lost %.1f"
				% [
					st["won"],
					n,
					100.0 * float(st["won"]) / float(n),
					st["time"],
					st["kills"],
					st["caches"],
					st["lives"],
				]
			)
		)
	)
	(
		lines
		. append(
			(
				"  rounds played %.1f avg   cleared %.1f avg (%.0f %%)   aborted runs %d"
				% [
					st["played"],
					st["cleared"],
					100.0 * st["cleared"] / maxf(1.0, st["played"]),
					st["aborts"],
				]
			)
		)
	)
	lines.append(
		(
			"  paid per run: %.1f coins (of which Heat %.1f)   %.0f XP"
			% [st["coins"], st["heat_coins"], st["xp"]]
		)
	)
	lines.append("")
	lines.append("  per-round (across runs that reached that round):")
	lines.append("  rnd  plays  avg_time  avg_lives  clear%")
	for idx in range(MAX_ROUNDS):
		var plays = round_time[idx].size()
		if plays == 0:
			break
		var avg_t = 0.0
		for t in round_time[idx]:
			avg_t += t
		avg_t /= float(plays)
		var avg_lv = 0.0
		for lv in round_lives[idx]:
			avg_lv += lv
		avg_lv /= float(plays)
		var clr = 0
		for c in round_clear[idx]:
			clr += c
		var clr_pct = 100.0 * float(clr) / float(plays)
		lines.append("  %3d  %5d  %8.1f  %9.2f  %5.0f" % [idx + 1, plays, avg_t, avg_lv, clr_pct])
	return "\n".join(lines)


# one line per setting, the same seeds in every line, so a change of Heat shows as a change of the numbers
func _compare_table(results: Array) -> String:
	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== Heat comparison: the same seeds under every setting ===")
	(
		lines
		. append(
			"  setting                          pts  hearts  won%  rounds  clear%  lives  time_s  coins  heat+  xp  aborts"
		)
	)
	for res in results:
		var cfg = res["config"]
		var runs = res["runs"]
		var st = _stats(runs)
		var n = maxi(1, runs.size())
		var hearts = runs[0]["start_hearts"] if not runs.is_empty() else 0
		(
			lines
			. append(
				(
					"  %-32s %3d  %6d  %4.0f  %6.1f  %6.0f  %5.1f  %6.0f  %5.1f  %5.1f  %3.0f  %6d"
					% [
						cfg["label"],
						cfg["points"],
						hearts,
						100.0 * float(st["won"]) / float(n),
						st["played"],
						100.0 * st["cleared"] / maxf(1.0, st["played"]),
						st["lives"],
						st["time"],
						st["coins"],
						st["heat_coins"],
						st["xp"],
						st["aborts"],
					]
				)
			)
		)
	return "\n".join(lines)
