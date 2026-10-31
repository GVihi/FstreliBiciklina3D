extends SceneTree
# Checks the FPS and frametime counter above the radar (scripts/hud.gd, `_record_frame`, `fps_color`, `frame_color`):
#   - the FPS colour: 0 to 30 red, 30 to 60 yellow, 60 and above green (the edges 29.9, 30, 59.9 and 60 included),
#   - the frametime colour uses the same limits (33.3 ms and 16.7 ms),
#   - frames of a steady 16.7 ms show 60 FPS and 16.7 ms after a refresh, and 40 ms frames show 25 FPS,
#   - the numbers only change when a refresh is due, not on every frame.
# Not checked: how the counter looks (an in-game look by a person).
# Run from the project folder:
#   godot --headless --path . --script res://tools/fps_counter_check.gd
# or with: python tools/run_checks.py fps_counter
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var hud = main.hud
	var red = hud.RED
	var yellow = hud.GOLD
	var green = hud.FPS_GREEN
	for row in [
		[0.0, red], [29.9, red], [30.0, yellow], [59.9, yellow], [60.0, green], [144.0, green]
	]:
		if hud.fps_color(row[0]) != row[1]:
			_fail("%s FPS has the wrong colour" % row[0])
	for row in [
		[10.0, green], [16.6, green], [16.8, yellow], [33.2, yellow], [33.4, red], [100.0, red]
	]:
		if hud.frame_color(row[0]) != row[1]:
			_fail("a %s ms frame has the wrong colour" % row[0])
	hud._fps_shown = 0
	hud._fps_t = 0.0
	hud._fps_n = 0
	for i in range(30):
		hud._record_frame(1.0 / 60.0)
	if hud._fps_shown != 60 or absf(hud._ms_shown - 1000.0 / 60.0) > 0.1:
		_fail("steady 60 FPS frames show %d FPS, %.2f ms" % [hud._fps_shown, hud._ms_shown])
	var shown = hud._fps_shown
	hud._record_frame(0.001)
	if hud._fps_shown != shown:
		_fail("the numbers changed before a refresh was due")
	for i in range(20):
		hud._record_frame(0.04)
	if hud._fps_shown != 25 or absf(hud._ms_shown - 40.0) > 0.5:
		_fail("40 ms frames show %d FPS, %.2f ms" % [hud._fps_shown, hud._ms_shown])
	if problems.is_empty():
		print("fps_counter_check: the FPS counter colours and numbers are right")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("fps_counter_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
