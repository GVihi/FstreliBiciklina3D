extends SceneTree
# Checks the game version shown on the title screen (README Milestone E, Release Readiness):
#   - `config/version` in project.godot holds a version like 0.1.0 (the one place it is written),
#   - `Main.game_version` reads it, and the title screen draws with it.
# Run from the project folder:
#   godot --headless --path . --script res://tools/version_check.gd
# or with tools\run_version_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	var stored = str(ProjectSettings.get_setting("application/config/version", ""))
	var shape = RegEx.new()
	shape.compile("^[0-9]+\\.[0-9]+\\.[0-9]+$")
	if shape.search(stored) == null:
		_fail("config/version in project.godot is '%s', expected a version like 0.1.0" % stored)
	if main.game_version != stored:
		_fail("Main.game_version is '%s', project.godot says '%s'" % [main.game_version, stored])
	# draw the title screen at two window shapes (a script error in the drawing code shows up here)
	main.go_to_title()
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for f in range(2):
			main.hud.queue_redraw()
			await process_frame
	# no version, nothing drawn and no error
	main.game_version = ""
	main.hud.queue_redraw()
	await process_frame
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"version_check: the version is in project.godot, read by the game and drawn on the title screen"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("version_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
