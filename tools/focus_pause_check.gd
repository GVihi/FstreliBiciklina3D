extends SceneTree
# Checks that the game pauses by itself when the window loses focus (README Milestone A, menu follow-ups).
# Run from the project folder:
#   godot --headless --path . --script res://tools/focus_pause_check.gd
# or with tools\run_focus_pause_check.bat on Windows.
# Exits with status 1 and prints the problems when a check fails.

const SEED = 0x1234ABCD

var problems = []
var main


func _initialize() -> void:
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	await _check_title_is_left_alone()
	await _check_round_pauses()
	await _check_engine_notifications()
	await _check_paused_game_stays_paused()
	_finish()


# on the title screen there is nothing to pause
func _check_title_is_left_alone() -> void:
	main.go_to_title()
	await process_frame
	if main.pause_on_focus_loss():
		_fail("losing focus on the title screen reported a pause")
	if main.state != "title":
		_fail("losing focus on the title screen changed the state to %s" % main.state)


# a round in progress pauses, and the pause menu opens on its main page
func _check_round_pauses() -> void:
	_start_round()
	await process_frame
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		return
	if main.paused:
		_fail("a round that is being played is already paused")
	if not main.pause_on_focus_loss():
		_fail("losing focus during a round did not pause it")
	await process_frame
	await process_frame
	if not main.paused:
		_fail("the game is not paused after the window lost focus")
	if main.pause_page != "":
		_fail("the pause menu did not open on its main page (page '%s')" % main.pause_page)


# the same thing through the engine's own notifications, both kinds
func _check_engine_notifications() -> void:
	for what in [Node.NOTIFICATION_APPLICATION_FOCUS_OUT, Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		_start_round()
		await process_frame
		await process_frame
		main.notification(what)
		await process_frame
		await process_frame
		if not main.paused:
			_fail("engine notification %d did not pause the round" % what)
	# getting the focus back must not resume the game by itself: the player does that
	main.notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await process_frame
	await process_frame
	if not main.paused:
		_fail("getting the focus back resumed the game by itself")


# a game that is already paused, and the pause menu pages, are left as they are
func _check_paused_game_stays_paused() -> void:
	_start_round()
	await process_frame
	await process_frame
	main.pause_on_focus_loss()
	await process_frame
	await process_frame
	main.pause_page = "settings"
	if main.pause_on_focus_loss():
		_fail("losing focus again reported a second pause")
	if main.pause_page != "settings":
		_fail("losing focus closed the settings page (page '%s')" % main.pause_page)


func _start_round() -> void:
	main.start_game(false, SEED)
	if main.state == "map":
		main.pick_node(0)
	# headless Godot cannot capture the mouse, so the test hook plays the round
	main.force_captured = true


func _finish() -> void:
	if problems.is_empty():
		print("focus_pause_check: the game pauses when the window loses focus, and only then")
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("focus_pause_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
