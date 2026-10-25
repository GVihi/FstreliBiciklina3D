extends SceneTree
# Checks that the title screen shows the arena style the run really gets (README Milestone K, "Show the style on the
# run map or the title screen"): the DAILY ARENA line under the daily seed and the ARENA line on the custom seed page.
# Run from the project folder:
#   godot --headless --path . --script res://tools/arena_style_title_check.gd
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.go_to_title()
	_check_labels_match_the_run()
	_check_daily_line()
	await _check_seed_page_draws()
	_finish()


# the text for a seed is the label of the style the generated arena of that seed carries
func _check_labels_match_the_run() -> void:
	var names = {}
	for run_seed in [0, 1, 0x7F3A91C2, 0xFFFFFFFF, 12345, 987654, 0xDEADBEEF, 42, 99, 1000]:
		var layout = main.ArenaGenScript.generate(run_seed)
		if layout.is_empty():
			_fail("no arena for seed %08X" % run_seed)
			continue
		var text = main.arena_style_text(run_seed)
		if text == "":
			_fail("seed %08X has no style text" % run_seed)
		elif text != str(layout.get("style_label", "")):
			_fail(
				(
					"seed %08X: title says '%s' but the arena is '%s'"
					% [run_seed, text, layout.get("style_label", "")]
				)
			)
		names[text] = true
	if names.size() < 2:
		_fail("ten seeds gave only one style text, so the label does not follow the seed")


func _check_daily_line() -> void:
	main.refresh_daily_seed()
	if main.daily_arena != main.arena_style_text(main.daily_seed) or main.daily_arena == "":
		_fail("daily_arena is '%s', not the style of the daily seed" % main.daily_arena)


# the title menu and the seed page draw with and without a typed seed, at two window sizes
func _check_seed_page_draws() -> void:
	for window in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = window
		main.title_page = ""
		main.hud.queue_redraw()
		await process_frame
		main.title_page = "seed"
		for typed in ["", "7F3A91C2", "7F"]:
			main.seed_buf = typed
			main.hud.queue_redraw()
			await process_frame
	main.title_page = ""
	main.seed_buf = ""


func _finish() -> void:
	if problems.is_empty():
		print("arena_style_title_check: the title screen names the arena style the seed gets")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("arena_style_title_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
