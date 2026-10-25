extends SceneTree
# Checks the player-visible game name (README Milestone E, Release Readiness: rename to FB3D):
#   - the name the game shows is FB3D, in `Main.GAME_TITLE` and in the window title,
#   - the title screen draws with it,
#   - the project name in project.godot is still "Fstreli Biciklina 3D", because `user://` (settings, scores and
#     meta currency) follows that name and the old saves must keep loading (see docs/SAVE_FILES.md).
# Run from the project folder:
#   godot --headless --path . --script res://tools/game_title_check.gd
# or with tools\run_game_title_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	if main.GAME_TITLE != "FB3D":
		_fail("GAME_TITLE is '%s', expected FB3D" % main.GAME_TITLE)
	if main.get_window().title != main.GAME_TITLE:
		_fail(
			"the window title is '%s', expected '%s'" % [main.get_window().title, main.GAME_TITLE]
		)
	var project_name = str(ProjectSettings.get_setting("application/config/name"))
	if project_name != "Fstreli Biciklina 3D":
		_fail(
			(
				"the project name in project.godot is '%s'; it must stay 'Fstreli Biciklina 3D' so the saves in user:// keep loading"
				% project_name
			)
		)
	# draw the title screen at two window shapes (a script error in the drawing code shows up here)
	main.go_to_title()
	for s in [Vector2(1280.0, 720.0), Vector2(1920.0, 1080.0)]:
		main.hud.size = s
		for f in range(2):
			main.hud.queue_redraw()
			await process_frame
	_finish()


func _finish() -> void:
	if problems.is_empty():
		print(
			"game_title_check: the game shows FB3D and the project name for the saves is unchanged"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("game_title_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
