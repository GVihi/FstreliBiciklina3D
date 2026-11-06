extends SceneTree
# Bot playthrough balance harness (README Tooling & QA, "Bot playthrough balance harness").
# A simple bot plays whole runs on many seeds and logs, for every round, the time, lives lost,
# damage taken, kills, caches taken and whether it reached the extraction point.
# A per-seed and cross-seed summary gives real numbers for balance and difficulty-curve passes.
#
# Run from the project folder:
#   godot --headless --path . --script res://tools/bot_run.gd
# Optional args after "--":
#   --seeds N     how many seeds to play (default 8)
#   --heat N      Heat level (0-5, default 0)
#   --full        use 20 seeds (the "slow" mode; same as --seeds 20)
#   --out PATH    write summary to this file instead of bot_run_summary.txt
#   --seed HEX    play this single seed only (overrides --seeds)
#
# Exit code 0 = all runs completed without a scripted error.
# A round-by-round log and a cross-seed summary are printed to stdout and to the output file.
#
# Bot behaviour (matches the README spec):
#   - aims at the nearest rider and fires every fire-interval frames
#   - dashes away from an incoming phone that is about to hit
#   - walks toward the nearest supply cache when no rider is nearby
#   - walks to the extraction point once it opens
#   On the map screen it always picks the first available node.
#   In the shop / upgrade / rest screens it leaves immediately (no upgrades bought;
#   upgrades would change the economy across runs and make seeds incomparable).

const MAIN_SCENE = "res://main.tscn"
const DT = 1.0 / 60.0  # simulation step (60 fps)
const DEFAULT_SEEDS = 8
const FULL_SEEDS = 20
const MAX_ROUNDS = 10  # a full run is 10 floors
const ROUND_TIMEOUT = 180.0  # seconds: abort a round if the bot is stuck this long
const RUN_TIMEOUT = 1200.0  # seconds: abort a whole run if something is very wrong
# firing rate: fire every N frames when aimed at a target
const FIRE_INTERVAL = 18
# distance within which the bot moves toward a cache instead of wandering
const CACHE_ATTRACT_DIST = 50.0
# a phone is "incoming" if its target on the ground is within this radius of the player
const PHONE_DANGER_RADIUS = 2.5

var problems: Array = []

# ------------------------------------------------------------------ main

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	var num_seeds = DEFAULT_SEEDS
	var heat_level = 0
	var out_path = "bot_run_summary.txt"
	var fixed_seed = -1

	var i = 0
	while i < args.size():
		var a = args[i]
		if a == "--full":
			num_seeds = FULL_SEEDS
		elif a == "--seeds" and i + 1 < args.size():
			i += 1
			num_seeds = int(args[i])
		elif a == "--heat" and i + 1 < args.size():
			i += 1
			heat_level = clampi(int(args[i]), 0, 5)
		elif a == "--out" and i + 1 < args.size():
			i += 1
			out_path = args[i]
		elif a == "--seed" and i + 1 < args.size():
			i += 1
			fixed_seed = int("0x" + args[i]) if args[i].begins_with("0x") else int(args[i])
			num_seeds = 1
		i += 1

	var seeds: Array = []
	if fixed_seed >= 0:
		seeds.append(fixed_seed)
	else:
		for k in range(num_seeds):
			seeds.append((k * 2654435761 + 97531) & 0xFFFFFFFF)

	var header = (
		"bot_run: %d seed(s), Heat %d, %s"
		% [seeds.size(), heat_level, Time.get_datetime_string_from_system()]
	)
	print(header)

	var all_runs: Array = []
	for s in seeds:
		var result = await _play_run(s, heat_level)
		all_runs.append(result)
		_print_run_summary(result)

	var cross = _cross_seed_summary(all_runs, heat_level)
	print("")
	print(cross)

	var out_lines: PackedStringArray = PackedStringArray()
	out_lines.append(header)
	out_lines.append("")
	for r in all_runs:
		out_lines.append(_run_lines(r))
	out_lines.append("")
	out_lines.append(cross)
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


# ------------------------------------------------------------------ one full run

func _play_run(seed_value: int, heat_level: int) -> Dictionary:
	var tag = "seed %08X heat %d" % [seed_value, heat_level]
	var main = load(MAIN_SCENE).instantiate()
	main.generated_arena = true
	root.add_child(main)

	# wait a few frames for the scene to settle
	for _f in range(4):
		await process_frame

	main.start_game(false, seed_value)
	main.heat = heat_level
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
		"heat": heat_level,
		"won": false,
		"rounds": [],
		"total_time": 0.0,
		"total_lives_lost": 0,
		"total_kills": 0,
		"total_caches": 0,
		"abort": "",
	}

	var run_t = 0.0
	var frame = 0
	while run_t < RUN_TIMEOUT:
		var s = main.state
		if s == "over" or s == "dying":
			run["won"] = main.run_won
			break
		elif s == "map":
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
		elif s == "play":
			var round_result = await _play_round(main, run_t, frame)
			run["rounds"].append(round_result)
			run["total_lives_lost"] += round_result["lives_lost"]
			run["total_kills"] += round_result["kills"]
			run["total_caches"] += round_result["caches"]
			run_t += round_result["time"]
			frame += int(round_result["time"] / DT)
			if round_result["aborted"]:
				run["abort"] = "round %d timed out" % round_result["round_n"]
				break
			continue
		else:
			# clear / upgrade / other transitions: step and wait
			main._process(DT)
			run_t += DT
			frame += 1
			await process_frame
			continue

		# after every non-play step, run a few simulation frames
		for _f in range(6):
			main._process(DT)
			run_t += DT
			frame += 1
		await process_frame

	run["total_time"] = run_t
	main.queue_free()
	await process_frame
	return run


# ------------------------------------------------------------------ one round

func _play_round(main, run_t_offset: float, frame_offset: int) -> Dictionary:
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
		if target != null:
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
			var to_tgt = (move_target - main.player.position)
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
	result["reached_extraction"] = main.objective_sys.taken >= 0 and (
		main.state != "play" and main.round_n > round_n
		or (main.state == "over" and main.run_won and main.round_n >= main.MAX_ROUNDS)
	)
	var cleared_hits = main.count_hits() >= main.hits_needed()
	result["cleared"] = cleared_hits
	result["lives_lost"] = main.round_lives_lost
	if result["time"] >= ROUND_TIMEOUT:
		result["aborted"] = true
		problems.append(
			"%s round %d: bot timed out after %.0f s (state %s)"
			% [main.run_seed, round_n, result["time"], main.state]
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
	if nearest_rider.is_empty() or Vector2(
		nearest_rider["pos"].x - pp.x, nearest_rider["pos"].z - pp.z
	).length() > 8.0:
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
		var to_rider = Vector3(
			nearest_rider["pos"].x - pp.x, 0.0, nearest_rider["pos"].z - pp.z
		).normalized()
		var strafe = Vector3(-to_rider.z, 0.0, to_rider.x)
		return pp + strafe * 4.0

	return Vector3.ZERO


# ------------------------------------------------------------------ output

func _print_run_summary(run: Dictionary) -> void:
	print(_run_lines(run))


func _run_lines(run: Dictionary) -> String:
	var lines: PackedStringArray = PackedStringArray()
	var status = "WON" if run["won"] else ("ABORT: " + run["abort"] if run["abort"] != "" else "LOST")
	lines.append(
		"\n%s — %s  total %.0f s  kills %d  caches %d  lives lost %d"
		% [
			run["tag"],
			status,
			run["total_time"],
			run["total_kills"],
			run["total_caches"],
			run["total_lives_lost"],
		]
	)
	lines.append("  rnd  time   kills  caches  lives_lost  cleared")
	for r in run["rounds"]:
		var cleared_str = "YES" if r["cleared"] else "no "
		lines.append(
			"  %3d  %5.1f  %5d  %6d  %10d  %s"
			% [r["round_n"], r["time"], r["kills"], r["caches"], r["lives_lost"], cleared_str]
		)
	return "\n".join(lines)


func _cross_seed_summary(all_runs: Array, heat_level: int) -> String:
	var n = all_runs.size()
	if n == 0:
		return "bot_run: no runs"

	var won = 0
	var total_time_sum = 0.0
	var total_kills_sum = 0
	var total_caches_sum = 0
	var total_lives_sum = 0
	var rounds_played_sum = 0
	var rounds_cleared_sum = 0
	# per-round-number aggregates (index 0 = round 1)
	var round_time: Array = []
	var round_lives: Array = []
	var round_clear: Array = []
	for _i in range(MAX_ROUNDS):
		round_time.append([])
		round_lives.append([])
		round_clear.append([])

	for run in all_runs:
		if run["won"]:
			won += 1
		total_time_sum += run["total_time"]
		total_kills_sum += run["total_kills"]
		total_caches_sum += run["total_caches"]
		total_lives_sum += run["total_lives_lost"]
		rounds_played_sum += run["rounds"].size()
		for r in run["rounds"]:
			var idx = clampi(r["round_n"] - 1, 0, MAX_ROUNDS - 1)
			round_time[idx].append(r["time"])
			round_lives[idx].append(r["lives_lost"])
			round_clear[idx].append(1 if r["cleared"] else 0)
			if r["cleared"]:
				rounds_cleared_sum += 1

	var lines: PackedStringArray = PackedStringArray()
	lines.append("=== cross-seed summary: %d run(s), Heat %d ===" % [n, heat_level])
	lines.append(
		"  won %d / %d (%.0f %%)   avg time %.0f s   avg kills %.1f   avg caches %.1f   avg lives lost %.1f"
		% [
			won,
			n,
			100.0 * float(won) / float(n),
			total_time_sum / float(n),
			float(total_kills_sum) / float(n),
			float(total_caches_sum) / float(n),
			float(total_lives_sum) / float(n),
		]
	)
	lines.append(
		"  rounds played %.1f avg   cleared %.1f avg (%.0f %%)"
		% [
			float(rounds_played_sum) / float(n),
			float(rounds_cleared_sum) / float(n),
			100.0 * float(rounds_cleared_sum) / float(maxi(1, rounds_played_sum)),
		]
	)
	lines.append("")
	lines.append(
		"  per-round (across runs that reached that round):"
	)
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
		lines.append(
			"  %3d  %5d  %8.1f  %9.2f  %5.0f"
			% [idx + 1, plays, avg_t, avg_lv, clr_pct]
		)
	return "\n".join(lines)
