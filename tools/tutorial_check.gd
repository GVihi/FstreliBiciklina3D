extends SceneTree
# Checks the short tutorial in the training room (scripts/tutorial.gd; main.gd start_training and the tutorial_sys
# calls in _process; hud.gd pause_items and _draw_tutorial_prompt; input.gd tutorial_skip and tutorial_start;
# settings.gd tutorial_done). Run from the project folder:
#   python tools/run_checks.py tutorial
# or: godot --headless --path . --script res://tools/tutorial_check.gd
# It checks that
#   - the steps are in the order look, walk, shoot, reload, rider, dash, jump, melee, each with a short text
#   - the first TRAINING ROOM visit starts it, with the door shut: no rider comes out while the early steps run
#   - every step moves on only when the player has done its thing (a little turning and a teleport do not count) and the rider step lets a rider out and waits for it to go down
#   - the last step shows DONE_TEXT for a few seconds, saves tutorial_done, and the riders keep coming
#   - the pause menu has SKIP TUTORIAL while it runs and TUTORIAL after, TUTORIAL starts it again from the first
#     step with the door shut, SKIP counts as seen and opens the door; TRY IT practice has neither entry
#   - the next visit to the room starts without it, leaving the room stops it without marking it done, and
#     tutorial_done is loaded back from settings.cfg
# Exits with status 1 and lists the first problems when a check fails.

const MAIN_SCENE = "res://main.tscn"
const Tutorial = preload("res://scripts/tutorial.gd")
const DT = 1.0 / 60.0

var problems = []
var main = null


func _initialize() -> void:
	_check_steps()
	await _check_run()
	await _check_pause_menu()
	await _check_other_ways_out()
	if problems.is_empty():
		print("tutorial_check: the tutorial runs in the training room as the roadmap describes")
		quit(0)
	else:
		print("tutorial_check: %d problem(s)" % problems.size())
		for p in problems.slice(0, 15):
			print("  " + p)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)


func _make_main() -> void:
	main = load(MAIN_SCENE).instantiate()
	main.generated_arena = true
	main.training_room = false
	root.add_child(main)
	for i in range(3):
		await process_frame
	main.tutorial_done = false


func _free_main() -> void:
	if main != null:
		main.free()
		main = null
	await process_frame


# the room from the title menu's TRAINING ROOM entry
func _enter_room() -> bool:
	var entry = -1
	for i in range(main.hud.TITLE_ITEMS.size()):
		if main.hud.TITLE_ITEMS[i]["id"] == "training":
			entry = i
	main.go_to_title()
	main.input_sys.title_activate(entry)
	return main.practice and main.state == "play"


# one frame of play (headless Godot cannot capture the mouse, so the test hook keeps the game from pausing)
func _tick() -> void:
	main.force_captured = true
	main._process(DT)


func _frames(n: int) -> void:
	for f in range(n):
		_tick()


func _step() -> String:
	return main.tutorial_sys.step_id()


func _pause_ids() -> Array:
	var ids = []
	for it in main.hud.pause_items():
		ids.append(it["id"])
	return ids


# presses a pause menu entry by id, the way the pause menu does
func _press(id: String) -> void:
	var ids = _pause_ids()
	main.paused = true
	main.pause_page = ""
	main.input_sys.pause_activate(ids.find(id))
	main.paused = false


func _check_steps() -> void:
	var want = ["look", "walk", "shoot", "reload", "rider", "dash", "jump", "melee"]
	var got = []
	for s in Tutorial.STEPS:
		got.append(s["id"])
		var t = str(s["text"])
		if t == "" or t.length() > Tutorial.TEXT_MAX_CHARS or t != t.to_upper():
			_fail(
				"step %s has a text that is empty, too long or not in capitals: '%s'" % [s["id"], t]
			)
	if got != want:
		_fail("the steps are %s, not %s" % [got, want])


func _check_run() -> void:
	await _make_main()
	if not _enter_room():
		_fail("TRAINING ROOM did not start the room")
		await _free_main()
		return
	var t = main.tutorial_sys
	if not t.active or _step() != "look" or not t.holding():
		_fail("the first visit did not start the tutorial on its first step with the door shut")
	if not _pause_ids().has("tutorial_skip") or _pause_ids().has("tutorial_start"):
		_fail("while it runs the pause menu should say SKIP TUTORIAL, got %s" % [_pause_ids()])
	# the door stays shut for the early steps
	var riders_seen = 0
	for f in range(int(5.0 / DT)):
		_tick()
		riders_seen += main.riders.size()
	if riders_seen > 0 or _step() != "look":
		_fail(
			(
				"a rider came out (%d frames) or the step moved on by itself during 5 seconds"
				% riders_seen
			)
		)
	# look: a little turning is not enough
	main.yaw += 0.3
	_frames(2)
	if _step() != "look":
		_fail("a turn of 0.3 radians finished the look step")
	main.yaw += 0.5
	_frames(2)
	main.pitch += 0.5
	_frames(2)
	if _step() != "walk":
		_fail("turning about 1.3 radians did not finish the look step (now %s)" % _step())
	# walk: a teleport does not count, six metres on foot do
	main.player.position = main.clamp_walk(Vector3(0.0, 0.0, -2.0))
	_frames(2)
	if _step() != "walk":
		_fail("a teleport finished the walk step")
	for i in range(7):
		main.player.position = main.clamp_walk(main.player.position + Vector3(0.0, 0.0, -1.0))
		_frames(1)
	if _step() != "shoot":
		_fail("walking 7 m did not finish the walk step (now %s)" % _step())
	# shoot: nothing happens until a dart is fired, and the one dart of the clip is the whole step
	_frames(30)
	if _step() != "shoot":
		_fail("the shoot step finished without a shot (now %s)" % _step())
	main.pump_t = 0.0
	main.combat_sys.fire()
	_frames(2)
	if _step() != "reload":
		_fail("a shot did not finish the shoot step (now %s)" % _step())
	# reload
	main.input_sys.manual_reload()
	_frames(2)
	if _step() != "rider":
		_fail("reloading did not finish the reload step (now %s)" % _step())
	if t.holding():
		_fail("the door is still shut on the rider step")
	# rider: one comes out of the door, and the step waits until it is down
	var waited = 0
	while main.riders.size() == 0 and waited < int(4.0 / DT):
		_tick()
		waited += 1
	if main.riders.size() == 0:
		_fail("no rider came out on the rider step")
	else:
		_frames(30)
		if _step() != "rider":
			_fail("the rider step finished before a rider was down")
		for r in main.riders.duplicate():
			main.rider_sys.hit_rider(r, 99999)
		_frames(4)
	if _step() != "dash":
		_fail("bringing a rider down did not finish the rider step (now %s)" % _step())
	# dash and jump
	main.dash_cd = 0.0
	main.player_sys.try_dash()
	_frames(2)
	if _step() != "jump":
		_fail("dashing did not finish the dash step (now %s)" % _step())
	main.player_sys.request_jump()
	_frames(20)
	var expect_melee = main.has_melee()
	if expect_melee and _step() != "melee":
		_fail("jumping did not finish the jump step (now %s)" % _step())
	if expect_melee:
		main.melee = true
		main.swing_cd = 0.0
		main.combat_sys.fire()
		_frames(2)
	if t.active or t.text() != Tutorial.DONE_TEXT or not main.tutorial_done:
		_fail(
			(
				"the last step did not end the tutorial with DONE_TEXT and tutorial_done (active %s)"
				% t.active
			)
		)
	_frames(int((Tutorial.DONE_SECONDS + 1.0) / DT))
	if t.text() != "":
		_fail("DONE_TEXT stayed on screen after %s seconds" % Tutorial.DONE_SECONDS)
	# the riders keep coming
	main.clear_riders()
	main.next_idx = main.PER_ROUND
	main.after_wave()
	var again = false
	for f in range(int(6.0 / DT)):
		_tick()
		if main.riders.size() > 0:
			again = true
			break
	if not again:
		_fail("no rider came after the tutorial was done")
	# saved and loaded back
	main.tutorial_done = false
	main.settings.load_settings()
	if not main.tutorial_done:
		_fail("tutorial_done was not saved in settings.cfg")
	await _free_main()


func _check_pause_menu() -> void:
	await _make_main()
	if not _enter_room():
		_fail("TRAINING ROOM did not start the room (pause menu part)")
		await _free_main()
		return
	main.yaw = 2.0
	main.player.position = main.clamp_walk(Vector3(2.0, 0.0, 0.0))
	_press("tutorial_skip")
	if main.tutorial_sys.active or not main.tutorial_done or main.tutorial_sys.text() != "":
		_fail("SKIP TUTORIAL did not end the tutorial, count it as seen and clear the prompt")
	if _pause_ids().has("tutorial_skip") or not _pause_ids().has("tutorial_start"):
		_fail("after a skip the pause menu should say TUTORIAL, got %s" % [_pause_ids()])
	var seen = 0
	for f in range(int(6.0 / DT)):
		_tick()
		seen += main.riders.size()
	if seen == 0:
		_fail("the door stayed shut after SKIP TUTORIAL")
	_press("tutorial_start")
	var t = main.tutorial_sys
	if not t.active or _step() != "look" or not t.holding():
		_fail("TUTORIAL did not start the tutorial again from the first step with the door shut")
	if (
		main.riders.size() > 0
		or main.yaw != 0.0
		or main.player.position != main.arena.start_position()
	):
		_fail("TUTORIAL did not clear the riders and put the player back on the start")
	# a visit with the tutorial already done starts without it
	main.end_practice()
	if t.active:
		_fail("leaving the room did not stop the tutorial")
	if not _enter_room() or main.tutorial_sys.active:
		_fail("the tutorial started again on a visit after it was skipped")
	await _free_main()


func _check_other_ways_out() -> void:
	await _make_main()
	if not _enter_room():
		_fail("TRAINING ROOM did not start the room (leaving part)")
		await _free_main()
		return
	main.end_practice()
	if main.tutorial_sys.active or main.tutorial_done:
		_fail("leaving the room in the middle of the tutorial stopped it wrongly or marked it done")
	# TRY IT practice has no tutorial and no menu entry for it
	var tried = false
	for u in main.UNLOCKS:
		if main.can_try(u):
			main.go_to_title()
			tried = main.start_practice(u)
			break
	if not tried:
		_fail("no weapon could be tried")
	elif (
		main.tutorial_sys.active
		or _pause_ids().has("tutorial_skip")
		or _pause_ids().has("tutorial_start")
	):
		_fail("TRY IT practice started the tutorial or shows a tutorial entry: %s" % [_pause_ids()])
	await _free_main()
