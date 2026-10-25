extends SceneTree
# Baseline capture and frame-time log (README Milestone F1: "before" baseline and the
# Compatibility vs Forward+ test). How to run it on a real machine: tools/BASELINE.md
#
#   godot --path . --rendering-method forward_plus --script res://tools/baseline.gd -- --label=oldpc-forward
#
# What it does, in this order, without any input from you:
#   1. screenshots of every screen (main menu and its pages, play in all four lighting themes, play at
#      each graphics preset, pause menu, round clear, upgrade, shop, run over)
#   2. a frame-time log: every graphics preset (HIGH, MEDIUM, LOW) in every lighting theme, while the
#      script turns the view round, fires the gun and keeps the player alive, with vsync off
#   3. a report: report.md (read this first), results.json and frametime.csv in one output folder
#
# Scripted play keeps the score at 0 and the hearts full, so no run ever ends with a score and none of the
# score, meta, settings or high score files is written. It checks that at the end and says so in the report.
# Options after "--": --label=NAME  --out=DIR  --seconds=N (per measurement, default 8)
#                     --no-screens  --no-frametime  --raw (also write every single frame)

const QUALITY_NAMES = ["HIGH", "MEDIUM", "LOW"]
const SAVE_FILES = ["settings.cfg", "scores.json", "meta.json"]
const TITLE_PAGES = ["loadout", "unlocks", "scores", "settings"]
const WARMUP_SECONDS = 2.0
const BUDGET_MS = 16.67  # 60 fps

var main
var out_dir = ""
var label = ""
var requested = ""
var seconds = 8.0
var do_screens = true
var do_frametime = true
var do_raw = false
var results = []
var raw_lines = []
var shots = []
var notes = []
var info = {}
var saves_before = {}


func _init() -> void:
	_read_args()
	_make_folders()
	saves_before = _save_times()
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	await _frames(10)
	info = _system_info()  # after the window exists, so the size is the real one
	if do_screens:
		await _capture_screens()
	if do_frametime:
		await _measure_frame_times()
	_write_report()
	quit()


func _read_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--label="):
			label = a.substr(8)
		elif a.begins_with("--out="):
			out_dir = a.substr(6)
		elif a.begins_with("--seconds="):
			seconds = maxf(2.0, float(a.substr(10)))
		elif a.begins_with("--requested="):
			requested = a.substr(12)
		elif a == "--no-screens":
			do_screens = false
		elif a == "--no-frametime":
			do_frametime = false
		elif a == "--raw":
			do_raw = true


func _make_folders() -> void:
	var stamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	if label == "":
		label = RenderingServer.get_current_rendering_method()
	if out_dir == "":
		out_dir = ProjectSettings.globalize_path("res://") + "baseline_out/%s_%s" % [label, stamp]
	DirAccess.make_dir_recursive_absolute(out_dir + "/screens")


func _set_theme(t: int) -> void:
	# start_round sets theme_idx and then calls apply_theme; the HUD round label reads theme_idx.
	# Do both, or the screenshots show the lighting of one theme under the name of another.
	main.theme_idx = t
	main.apply_theme(t)


func _frames(n: int) -> void:
	for i in range(n):
		await process_frame


func _system_info() -> Dictionary:
	var d = {}
	d["label"] = label
	d["date"] = Time.get_datetime_string_from_system()
	d["godot"] = Engine.get_version_info()["string"]
	d["os"] = "%s %s" % [OS.get_name(), OS.get_version()]
	d["cpu"] = OS.get_processor_name()
	d["cpu_threads"] = OS.get_processor_count()
	d["gpu"] = RenderingServer.get_video_adapter_name()
	d["gpu_vendor"] = RenderingServer.get_video_adapter_vendor()
	d["gpu_api"] = RenderingServer.get_video_adapter_api_version()
	d["renderer_requested"] = requested
	d["renderer_actual"] = RenderingServer.get_current_rendering_method()
	d["driver"] = RenderingServer.get_current_rendering_driver_name()
	d["window_size"] = "%dx%d" % [root.size.x, root.size.y]
	d["screen_size"] = (
		"%dx%d" % [DisplayServer.screen_get_size().x, DisplayServer.screen_get_size().y]
	)
	d["has_rendering_device"] = RenderingServer.get_rendering_device() != null
	return d


func _save_times() -> Dictionary:
	var t = {}
	for f in SAVE_FILES:
		var p = "user://" + f
		t[f] = FileAccess.get_modified_time(p) if FileAccess.file_exists(p) else -1
	return t


# ---------------------------------------------------------------- screenshots
func _shot(shot_name: String, wait_frames: int = 8) -> void:
	await _frames(wait_frames)
	var img = root.get_viewport().get_texture().get_image()
	img.save_png("%s/screens/%s.png" % [out_dir, shot_name])
	shots.append(shot_name)


func _capture_screens() -> void:
	# main menu and its pages (the game starts on the title screen)
	main.go_to_title()
	await _shot("01_title_menu", 20)
	for page in TITLE_PAGES:
		main.title_page = page
		await _shot("02_title_" + page)
	main.go_to_title()

	# play: every lighting theme at the HIGH preset, after a few seconds so riders are on the street
	main.quality = 0
	main.settings.apply_quality()
	main.start_game()
	await _frames(240)
	for t in range(main.THEMES.size()):
		_set_theme(t)
		await _shot(
			"03_play_%d_%s" % [t, str(main.THEMES[t]["name"]).to_lower().replace(" ", "_")], 12
		)

	# play at each graphics preset (DAY): compare the edges of these three for the anti-aliasing check
	_set_theme(0)
	for q in range(3):
		main.quality = q
		main.settings.apply_quality()
		await _shot("04_play_day_preset_%d_%s" % [q, QUALITY_NAMES[q].to_lower()], 12)
		var vp = root.get_viewport()
		notes.append(
			(
				"preset %s: msaa_3d=%d screen_space_aa=%d"
				% [QUALITY_NAMES[q], vp.msaa_3d, vp.screen_space_aa]
			)
		)
	main.quality = 0
	main.settings.apply_quality()

	# pause menu: releasing the mouse pauses the game
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await _shot("05_pause_menu", 12)
	main.pause_page = "settings"
	await _shot("05_pause_settings")
	main.pause_page = "confirm"
	await _shot("05_pause_confirm")
	main.pause_page = ""
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await _frames(4)

	# the screens between rounds and at the end. State is set directly and nothing is saved.
	main.state = "clear"
	main.state_t = 3.0
	await _shot("06_round_clear")
	main.shop_sys.enter_upgrade()
	main.state_t = 3.0
	await _shot("07_upgrade")
	main.shop_sys.enter_shop()
	main.state_t = 3.0
	await _shot("08_shop")
	main.state = "over"
	main.over_reason = "riders"
	main.state_t = 3.0
	await _shot("09_run_over_riders")
	main.run_won = true
	main.over_reason = "victory"
	await _shot("09_run_over_victory")
	main.run_won = false
	main.go_to_title()
	await _frames(4)


# ---------------------------------------------------------------- frame times
func _measure_frame_times() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var rid = root.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(rid, true)
	main.start_game()
	await _frames(30)
	for q in range(3):
		for t in range(main.THEMES.size()):
			main.quality = q
			main.settings.apply_quality()
			_set_theme(t)
			var r = await _measure_one(q, t, rid)
			results.append(r)
			print(
				(
					"frametime %s / %s: %.1f fps average, %.1f fps 1%% low"
					% [r["preset"], r["theme"], r["fps_avg"], r["fps_1pct_low"]]
				)
			)
	main.quality = 0
	main.settings.apply_quality()


func _measure_one(q: int, t: int, rid: RID) -> Dictionary:
	var times = []
	var cpu = []
	var gpu = []
	var draws = 0.0
	var objs = 0.0
	var prims = 0.0
	var vmem = 0.0
	var samples = 0
	var fire_t = 0.0
	var start = Time.get_ticks_usec()
	var last = start
	var elapsed = 0.0
	while elapsed < WARMUP_SECONDS + seconds:
		await process_frame
		var now = Time.get_ticks_usec()
		var dt = float(now - last) / 1000000.0
		last = now
		elapsed = float(now - start) / 1000000.0
		# scripted play: turn the view round, fire, never die, never leave the round
		if main.state != "play":
			main.start_game()
		main.hearts = main.MAXHEARTS
		main.score = 0  # a game over with a score would write the high score, scores and meta files
		main.yaw += 0.7 * minf(dt, 0.05)
		fire_t -= dt
		if fire_t <= 0.0:
			main.combat_sys.fire()
			fire_t = 0.35
		if elapsed < WARMUP_SECONDS:
			continue
		times.append(dt * 1000.0)
		cpu.append(
			(
				RenderingServer.viewport_get_measured_render_time_cpu(rid)
				+ RenderingServer.get_frame_setup_time_cpu()
			)
		)
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(rid))
		draws += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		objs += Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)
		prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		vmem += Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED)
		samples += 1
		if do_raw:
			raw_lines.append("%s,%s,%.3f" % [QUALITY_NAMES[q], main.THEMES[t]["name"], dt * 1000.0])
	var sorted = times.duplicate()
	sorted.sort()
	var n = maxi(1, sorted.size())
	var over_budget = 0
	var total = 0.0
	for x in times:
		total += x
		if x > BUDGET_MS:
			over_budget += 1
	var avg = total / n
	var p99 = _percentile(sorted, 0.99)
	var r = {}
	r["preset"] = QUALITY_NAMES[q]
	r["theme"] = main.THEMES[t]["name"]
	r["frames"] = sorted.size()
	r["ms_avg"] = avg
	r["ms_median"] = _percentile(sorted, 0.5)
	r["ms_p95"] = _percentile(sorted, 0.95)
	r["ms_p99"] = p99
	r["ms_max"] = sorted.back() if sorted.size() > 0 else 0.0
	r["fps_avg"] = 1000.0 / maxf(avg, 0.001)
	r["fps_1pct_low"] = 1000.0 / maxf(p99, 0.001)
	r["pct_over_16_7ms"] = 100.0 * float(over_budget) / n
	r["render_cpu_ms_avg"] = _average(cpu)
	r["render_gpu_ms_avg"] = _average(gpu)
	r["draw_calls_avg"] = draws / maxf(samples, 1)
	r["objects_avg"] = objs / maxf(samples, 1)
	r["primitives_avg"] = prims / maxf(samples, 1)
	r["video_mem_mb_avg"] = vmem / maxf(samples, 1) / 1048576.0
	return r


func _percentile(sorted: Array, p: float) -> float:
	if sorted.is_empty():
		return 0.0
	return sorted[int(p * float(sorted.size() - 1))]


func _average(arr: Array) -> float:
	if arr.is_empty():
		return 0.0
	var total = 0.0
	for x in arr:
		total += x
	return total / arr.size()


# ---------------------------------------------------------------- report
func _write_report() -> void:
	var saves_after = _save_times()
	var untouched = saves_after == saves_before
	var md = "# Baseline report: %s\n\n" % label
	md += "## This machine\n\n"
	for k in info.keys():
		md += "- **%s**: %s\n" % [k, str(info[k])]
	if requested != "" and requested != str(info["renderer_actual"]):
		md += (
			"\n> **Warning:** the renderer asked for was `%s` but Godot is running `%s`. "
			% [requested, info["renderer_actual"]]
		)
		md += "That usually means the graphics card or driver does not support the one asked for.\n"
	md += (
		"\nSave files (settings, scores, meta, high score) untouched by this run: **%s**\n"
		% ("yes" if untouched else "NO, check your saves")
	)
	if not results.is_empty():
		md += "\n## Frame times\n\n"
		md += (
			"%.0f seconds measured per row after %.0f seconds warm-up, vsync off, view turning and gun firing. "
			% [seconds, WARMUP_SECONDS]
		)
		md += "Budget for 60 fps is %.2f ms per frame.\n\n" % BUDGET_MS
		md += "| Preset | Theme | avg fps | 1% low fps | avg ms | p95 ms | p99 ms | max ms | frames over 16.7 ms | draw calls | gpu ms | video MB |\n"
		md += "|---|---|---|---|---|---|---|---|---|---|---|---|\n"
		for r in results:
			md += (
				"| %s | %s | %.0f | %.0f | %.2f | %.2f | %.2f | %.1f | %.1f%% | %.0f | %.2f | %.0f |\n"
				% [
					r["preset"],
					r["theme"],
					r["fps_avg"],
					r["fps_1pct_low"],
					r["ms_avg"],
					r["ms_p95"],
					r["ms_p99"],
					r["ms_max"],
					r["pct_over_16_7ms"],
					r["draw_calls_avg"],
					r["render_gpu_ms_avg"],
					r["video_mem_mb_avg"],
				]
			)
		md += "\n`gpu ms` is 0 when the renderer or driver does not report GPU time.\n"
	if not notes.is_empty():
		md += "\n## Anti-aliasing state per preset\n\n"
		for n in notes:
			md += "- %s\n" % n
	if not shots.is_empty():
		md += "\n## Screenshots (folder `screens/`)\n\n"
		for s in shots:
			md += "- %s.png\n" % s
	_write_text(out_dir + "/report.md", md)
	var data = {
		"system": info, "frame_times": results, "notes": notes, "saves_untouched": untouched
	}
	_write_text(out_dir + "/results.json", JSON.stringify(data, "\t"))
	var csv = "preset,theme,frames,fps_avg,fps_1pct_low,ms_avg,ms_median,ms_p95,ms_p99,ms_max,pct_over_16_7ms,draw_calls_avg,gpu_ms_avg,video_mem_mb\n"
	for r in results:
		csv += (
			"%s,%s,%d,%.2f,%.2f,%.3f,%.3f,%.3f,%.3f,%.2f,%.2f,%.0f,%.3f,%.1f\n"
			% [
				r["preset"],
				r["theme"],
				r["frames"],
				r["fps_avg"],
				r["fps_1pct_low"],
				r["ms_avg"],
				r["ms_median"],
				r["ms_p95"],
				r["ms_p99"],
				r["ms_max"],
				r["pct_over_16_7ms"],
				r["draw_calls_avg"],
				r["render_gpu_ms_avg"],
				r["video_mem_mb_avg"],
			]
		)
	_write_text(out_dir + "/frametime.csv", csv)
	if do_raw:
		_write_text(out_dir + "/frames_raw.csv", "preset,theme,ms\n" + "\n".join(raw_lines) + "\n")
	print("BASELINE DONE: report in ", out_dir)


func _write_text(path: String, text: String) -> void:
	var f = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("could not write " + path)
		return
	f.store_string(text)
	f.close()
