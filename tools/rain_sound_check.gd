extends SceneTree
# Check for the sound of the rain modifier (README Milestone D, MD6.3). Run from the project folder:
#   godot --headless --path . --script res://tools/rain_sound_check.gd
# Exits with status 1 and prints the first problems.
#
# A round whose node holds "rain" plays a seamless rain loop (audio/loop_rain.wav, baked by tools/bake_audio.py) and no
# bird chirps; the loop starts with the round and is stopped on every way out of it. Checked here:
#   - the loop points: every loop of Sfx.LOOPS loops forward over the whole of its baked file (sfx.gd once took the size of
#     the compressed import for the frame count, which cut every loop to a fifth of its length);
#   - the file: loop_rain is baked, listed in Sfx.LOOPS, 16-bit mono, not clipped, not silent, with no click at the loop
#     point and no body under 500 Hz (so it keeps out of the way of engines and voices);
#   - the level: the loop at RAIN_LEVEL stays at least MARGIN_DB under the rider warning bell at its QUIET setting
#     (README Accessibility: the rain must never mask the warnings);
#   - a real rain round on a generated arena: the loop plays, at the level it was asked for; a dry round and a NIGHT round
#     play none; it is silent while the game is paused or muted and keeps playing at SHAKE AND FLASH 0;
#   - every way out of a rain round, driven through the game's own functions: round clear (`end_round`), death
#     (`game_over`), quit to the title screen (`abandon_run`), restart (`restart_run`), every other state of the game, and
#     the training room: the loop is stopped (not only quiet), and no looping sound is left playing anywhere in the scene;
#   - birds: none chirp in a rain round; they do in a dry DAY round and on the title screen after rain, and still do not at
#     DUSK or on the run summary.
# What it cannot check is how it sounds: the loudness against the bells is a number here and is still to be judged by ear
# (README MD6.3, docs/ROADMAP_HISTORY.md).

const Sfx = preload("res://scripts/sfx.gd")
const Warn = preload("res://scripts/rider_warning.gd")

const SEED = 0x9E378A43
const DT = 1.0 / 60.0
const MARGIN_DB = 15.0  # the rain loop's RMS stays this far under the bell's peak at the QUIET setting
const OUT_STATES = ["title", "map", "shop", "rest", "upgrade", "clear", "dying", "over", "loading"]

var bad: Array = []
var main = null


func _init() -> void:
	await _boot()
	_check_loop_points()
	_check_file()
	_check_level()
	_check_rain_round()
	_check_birds()
	await _check_exits()
	await _check_training_room()
	main.queue_free()
	await process_frame
	if bad.is_empty():
		print(
			"rain_sound_check: the rain loop is baked and seamless, plays in a rain round only, stays well under the warning bell, and is stopped on every way out of a round"
		)
		quit(0)
	else:
		print("rain_sound_check: %d problem(s)" % bad.size())
		for p in bad.slice(0, 12):
			print("  " + p)
		quit(1)


func _boot() -> void:
	main = load("res://main.tscn").instantiate()
	main.generated_arena = true
	root.add_child(main)
	for i in range(3):
		await process_frame
	seed(5)


# one frame of the game with no time passing in it, then the sound's fade run to its end: what the sound is doing
# afterwards is what it will be doing once the fade is over
func _frame() -> void:
	main._process(DT)
	main.sfx._process(2.0)


# a rain round (or a round with the given modifiers) on the first node of a fresh run, on the DAY theme
func _start_round(mods: Array) -> void:
	main.force_captured = true  # headless Godot cannot capture the mouse, and a game without it counts as paused
	main.heat = 0
	main.start_game(false, SEED)
	main.hits.resize(400)
	main.hits.fill(false)
	var first: Dictionary = main.run_map["floors"][0][0]["content"]
	first["theme"] = 0
	first["modifiers"] = mods
	main.map_floor = 0
	main.map_lane = 0
	main.round_n = 1
	main.start_round()


# A baked wav read from the file as tools/bake_audio.py wrote it: {"channels", "rate", "bits", "data"} with the sample
# bytes in "data", or {} when it is not a wav. The imported stream cannot be measured: the .import files compress it (QOA).
func _read_wav(path: String) -> Dictionary:
	var b = FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return {}
	var out = {}
	var pos = 12
	while pos + 8 <= b.size():
		var id = b.slice(pos, pos + 4).get_string_from_ascii()
		var size = b.decode_u32(pos + 4)
		if id == "fmt ":
			out["channels"] = b.decode_u16(pos + 10)
			out["rate"] = b.decode_u32(pos + 12)
			out["bits"] = b.decode_u16(pos + 22)
		elif id == "data":
			out["data"] = b.slice(pos + 8, pos + 8 + size)
			return out
		pos += 8 + size + (size % 2)
	return {}


# the numbers of 16-bit mono sample bytes: peak and RMS (0 to 1), the step across the loop point and the biggest step
# inside it
func _stats(data: PackedByteArray) -> Dictionary:
	var n = int(data.size() / 2)
	var peak = 0.0
	var sum = 0.0
	var max_step = 0.0
	var prev = 0.0
	var first = 0.0
	for i in range(n):
		var v = float(data.decode_s16(i * 2)) / 32768.0
		if i == 0:
			first = v
		else:
			max_step = maxf(max_step, absf(v - prev))
		peak = maxf(peak, absf(v))
		sum += v * v
		prev = v
	return {
		"peak": peak,
		"rms": sqrt(sum / maxf(n, 1)),
		"seam": absf(first - prev),
		"max_step": max_step
	}


# every loop of the game loops over the whole of its file: the frame count sfx.gd gives a loop is checked against the
# frames of the baked file (it once took the size of the compressed import for it, which cut every loop short)
func _check_loop_points() -> void:
	for n in Sfx.LOOPS:
		var s = main.sfx.streams.get(n, null)
		var wav = _read_wav("res://audio/%s.wav" % n)
		if s == null or not (s is AudioStreamWAV) or wav.is_empty():
			bad.append("%s is not loaded or not a wav file" % n)
			continue
		var frames = int(wav["data"].size() / 2)
		if s.loop_mode != AudioStreamWAV.LOOP_FORWARD or s.loop_begin != 0:
			bad.append("%s does not loop forwards from the start" % n)
		elif s.loop_end != frames:
			bad.append(
				"%s loops at frame %d of %d: it would cut the sound short" % [n, s.loop_end, frames]
			)


func _check_file() -> void:
	if not Sfx.LOOPS.has("loop_rain"):
		bad.append("loop_rain is not in Sfx.LOOPS")
	var wav = _read_wav("res://audio/loop_rain.wav")
	if wav.is_empty():
		bad.append("audio/loop_rain.wav is missing: run python tools/bake_audio.py")
		return
	if wav["channels"] != 1 or wav["bits"] != 16:
		bad.append("loop_rain is not 16-bit mono")
		return
	var frames = int(wav["data"].size() / 2)
	var seconds = float(frames) / float(wav["rate"])
	if seconds < 3.0 or seconds > 8.0:
		bad.append("loop_rain is %.1f s long, expected 3 to 8 s" % seconds)
	var st = _stats(wav["data"])
	if st["peak"] > 0.95:
		bad.append("loop_rain is clipping (peak %.2f)" % st["peak"])
	if st["rms"] < 0.02:
		bad.append("loop_rain is almost silent (rms %.3f)" % st["rms"])
	# a click at the loop point is a step bigger than any step in the sound itself
	if st["seam"] > st["max_step"]:
		bad.append(
			(
				"loop_rain clicks at the loop point (step %.3f, biggest inside %.3f)"
				% [st["seam"], st["max_step"]]
			)
		)
	# almost no energy under 500 Hz is a lot to ask of one filter, so this only tells a bed with body (like the ambient
	# loop, a low-pass noise) from a hiss: the signal left after two one-pole low-passes at 500 Hz, against the signal
	var low1 = 0.0
	var low2 = 0.0
	var energy = 0.0
	var k = 1.0 - exp(-2.0 * PI * 500.0 / float(wav["rate"]))
	for i in range(frames):
		var v = float(wav["data"].decode_s16(i * 2)) / 32768.0
		low1 += k * (v - low1)
		low2 += k * (low1 - low2)
		energy += low2 * low2
	var low_rms = sqrt(energy / maxf(frames, 1))
	if low_rms > st["rms"] * 0.15:
		bad.append("loop_rain has body under 500 Hz (%.2f of its rms)" % (low_rms / st["rms"]))


func _check_level() -> void:
	var rain = _read_wav("res://audio/loop_rain.wav")
	var bell = _read_wav("res://audio/bell.wav")
	if rain.is_empty() or bell.is_empty():
		bad.append("the rain loop or the bell is not baked, the margin cannot be measured")
		return
	var rain_db = linear_to_db(_stats(rain["data"])["rms"] * Sfx.RAIN_LEVEL)
	# the bell at full loudness at the QUIET setting (level 1): the quietest a warning is while it is still on
	var bell_db = linear_to_db(_stats(bell["data"])["peak"]) + Warn.LEVEL_DB[1] + Warn.BASE_DB
	var margin = bell_db - rain_db
	var line = "rain %.1f dBFS rms, bell at QUIET %.1f dBFS peak, margin %.1f dB (needs %.0f)"
	print("rain_sound_check: " + line % [rain_db, bell_db, margin, MARGIN_DB])
	if margin < MARGIN_DB:
		var msg = "the rain loop is only %.1f dB under the bell at QUIET, %.0f dB are needed: lower RAIN_LEVEL in sfx.gd"
		bad.append(msg % [margin, MARGIN_DB])


# every looping player in the scene that is playing, as paths; the ambient bed plays all the time (at no volume when it is
# not wanted) and is not counted, and a node that is about to be freed is already gone
func _loops_running() -> Array:
	var out = []
	var stack = [main]
	while not stack.is_empty():
		var n = stack.pop_back()
		if n.is_queued_for_deletion():
			continue
		stack.append_array(n.get_children())
		if n == main.sfx.amb:
			continue
		if (n is AudioStreamPlayer or n is AudioStreamPlayer3D) and n.playing:
			var s = n.stream
			if s is AudioStreamWAV and s.loop_mode != AudioStreamWAV.LOOP_DISABLED:
				out.append(str(n.get_path()))
	return out


# one frame later: is the rain loop in the state `on`, and at the level it was asked for
func _expect_rain(where: String, on: bool) -> void:
	_frame()
	var playing = main.sfx.rain_playing()
	if playing != on:
		bad.append(
			(
				"%s: the rain loop is %s, expected %s"
				% [where, "playing" if playing else "stopped", "playing" if on else "stopped"]
			)
		)
		return
	if on:
		if not is_equal_approx(main.sfx.rain_level, Sfx.RAIN_LEVEL):
			bad.append(
				(
					"%s: the rain level is %s, expected %s"
					% [where, main.sfx.rain_level, Sfx.RAIN_LEVEL]
				)
			)
		if main.sfx.rain.stream != main.sfx.streams.get("loop_rain", null):
			bad.append("%s: the rain player does not play loop_rain" % where)
		if not _loops_running().has(str(main.sfx.rain.get_path())):
			(
				bad
				. append(
					(
						"%s: the scene sweep does not see the rain loop, so it could not see a leftover one"
						% where
					)
				)
			)


# after a way out of a round: the rain loop is stopped and no looping sound is left playing anywhere
func _expect_no_loops(where: String) -> void:
	_frame()
	if main.sfx.rain_playing():
		bad.append("%s: the rain loop is still playing" % where)
	var left = _loops_running()
	if not left.is_empty():
		bad.append(
			"%s: %d looping sound(s) still playing, first %s" % [where, left.size(), left[0]]
		)


func _check_rain_round() -> void:
	_start_round(["rain"])
	if not main.rain_sys.round_rain:
		bad.append("a rain round is not marked as one")
	_expect_rain("rain round", true)
	main.force_captured = false  # the mouse is let go: the game is paused
	_expect_rain("rain round, paused", false)
	main.force_captured = true
	_expect_rain("rain round, resumed", true)
	main.sfx.muted = true
	_expect_rain("rain round, muted", false)
	main.sfx.muted = false
	_expect_rain("rain round, unmuted", true)
	main.fx_scale = 0.0  # SHAKE AND FLASH 0 takes the streaks away, not the sound (docs/MAP_GENERATION.md)
	_expect_rain("rain round, SHAKE AND FLASH 0", true)
	main.fx_scale = 1.0
	_start_round([])
	_expect_rain("dry round", false)
	_start_round(["night"])
	_expect_rain("night round", false)
	_start_round(["rain"])
	_expect_rain("rain round after a dry one", true)
	_start_round([])
	_expect_rain("dry round after a rain one", false)


func _check_birds() -> void:
	_start_round([])
	if not main.birds_may_sing():
		bad.append("no birds in a dry DAY round")
	_start_round(["rain"])
	if main.birds_may_sing():
		bad.append("birds sing in a rain round")
	main.state = "title"  # the round is over: the rain with it, and the birds are back
	if not main.birds_may_sing():
		bad.append("no birds on the title screen after a rain round")
	main.state = "over"
	if main.birds_may_sing():
		bad.append("birds sing on the run summary")
	main.state = "play"
	main.rain_sys.round_rain = false
	main.theme_idx = 2  # DUSK had none before rain and has none now
	if main.birds_may_sing():
		bad.append("birds sing at DUSK")


func _check_exits() -> void:
	for way in ["clear", "death", "quit", "restart"]:
		_start_round(["rain"])
		_expect_rain("%s: during the round" % way, true)
		if way == "clear":
			main.hits.fill(true)  # every rider down
			main.end_round()
			if main.state != "clear":
				bad.append("clear: end_round left the state at %s, expected clear" % main.state)
		elif way == "death":
			main.game_over("check")
			if main.state != "dying":
				bad.append("death: game_over left the state at %s, expected dying" % main.state)
		elif way == "quit":
			main.abandon_run()
			if main.state != "title":
				bad.append("quit: abandon_run left the state at %s, expected title" % main.state)
		else:
			main.restart_run()
		await process_frame  # what the way out freed is gone after a frame
		_expect_no_loops("after %s" % way)
	# every other state of the game, with the rain round still the one the game has on record
	_start_round(["rain"])
	_expect_rain("before the states", true)
	for st in OUT_STATES:
		main.state = st
		_expect_no_loops("state %s" % st)
	main.state = "play"
	_expect_rain("back in play", true)
	# the round after a rain round, without rain: nothing carries over
	main.abandon_run()
	_start_round([])
	_expect_rain("the round after a rain round", false)


func _check_training_room() -> void:
	_start_round(["rain"])
	_expect_rain("before the training room", true)
	main.abandon_run()
	await process_frame
	if not main.start_training():
		bad.append("the training room did not start, so its sound is not checked")
		return
	if main.state != "play":
		bad.append("the training room is in state %s, expected play" % main.state)
	if main.rain_sys.round_rain:
		bad.append("the training room is marked as a rain round")
	_frame()
	if main.sfx.rain_playing():
		bad.append("the rain loop is playing in the training room")
