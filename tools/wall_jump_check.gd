extends SceneTree
# Checks wall-jumps (README Milestone L, "Wall-jumps"):
#   - the generated arena finds the wall next to the player (`Arena.wall_near`): its normal, the spot on its face and the
#     distance, nothing beyond the reach asked for, nothing on open ground or inside a wall, and the base arena (the
#     roundabout) has no jumpable walls,
#   - in the air against a wall, Space pushes the player away from it and up, keeps the speed along the wall and stays
#     under the air speed cap, and cancels a dash that is running,
#   - a press a moment after the wall was left still works (WALL_WINDOW), a later one does not, and on open ground in the
#     air a press does nothing,
#   - at most WALL_JUMP_MAX wall-jumps per airtime, the next needs the cooldown and a new touch, and landing gives them
#     back,
#   - A or D held and Space is a wall-jump (not a side dash) against a wall, and a side dash again once they are used up,
#   - the glow on the wall shows only in the air, sits on the wall face at chest height, turns red when the wall-jumps are
#     used up, and a wall-jump runs a ring over the wall that ends,
#   - the wall-jump sound is baked and loaded,
#   - wall-jumping into every direction in every arena style never ends inside a building or above the lowest roof, so a
#     run of them cannot take the player over the arena edge (the `Arena` bounds queries still hold).
# Not checked: how the push feels (the numbers are first guesses, see the playtest item), how the glow and the sound look
# and sound.
# Run from the project folder:
#   godot --headless --path . --script res://tools/wall_jump_check.gd
# or: python tools/run_checks.py wall_jump
# Exits with status 1 and prints the problems when a check fails.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")

const SEED = 0x1234ABCD
const DT = 1.0 / 60.0
const AWAY = 0.6  # metres from the wall face where the tests put the player (inside WALL_REACH, outside the body margin)

var problems = []
var main
var notes = []
var arena = null  # a generated arena with a wall to the east of the test spot
var spot = Vector3.ZERO  # AWAY metres west of that wall
var face_x = 0.0  # x of the wall face


func _initialize() -> void:
	Input.use_accumulated_input = false  # a pressed key counts at once, not at the next real frame
	main = load("res://main.tscn").instantiate()
	root.add_child(main)
	for i in range(3):
		await process_frame
	_start_round()
	await process_frame
	if main.state != "play":
		_fail("could not start a round (state %s)" % main.state)
		_finish()
		return
	if not _find_arena():
		_fail("no generated arena with a free wall face was found")
		_finish()
		return
	var roundabout = main.arena
	_check_roundabout(roundabout)
	main.arena = arena
	_check_wall_query()
	_check_push()
	_check_momentum()
	_check_dash_cancel()
	_check_window()
	_check_limit_and_landing()
	_check_side_dash_priority()
	_check_marks()
	_check_sound()
	_check_bounds()
	main.arena = roundabout
	_finish()


# a generated arena and a free spot AWAY metres west of a wall, with open ground north, south and west of it
func _find_arena() -> bool:
	var rules = ArenaGenScript.load_rules()
	for sd in range(5000, 5100):
		var layout = ArenaGenScript.generate(sd, rules)
		if layout.is_empty():
			continue
		var a = GeneratedArena.new(layout, rules)
		var n = int(layout["cells"])
		var cell = float(layout["cell"])
		for cz in range(2, n - 2):
			for cx in range(2, n - 3):
				var c = _centre(cx, cz, n, cell)
				if (
					_open(a, c)
					and not _open(a, _centre(cx + 1, cz, n, cell))
					and _open(a, _centre(cx - 1, cz, n, cell))
					and _open(a, _centre(cx, cz - 1, n, cell))
					and _open(a, _centre(cx, cz + 1, n, cell))
				):
					face_x = (float(cx + 1) - float(n) / 2.0) * cell
					spot = Vector3(face_x - AWAY, 0.0, c.z)
					arena = a
					return true
	return false


func _centre(cx: int, cz: int, n: int, cell: float) -> Vector3:
	return Vector3(
		(float(cx) + 0.5 - float(n) / 2.0) * cell, 0.0, (float(cz) + 0.5 - float(n) / 2.0) * cell
	)


func _open(a, p: Vector3) -> bool:
	var s = a.surface_at(p)
	return s != "building" and s != "tunnel"


# the roundabout keeps its barrier between the player and the facades: no jumpable wall
func _check_roundabout(round_arena) -> void:
	for p in [Vector3(21.0, 0.0, 0.0), Vector3(0.0, 0.0, 21.5), Vector3(5.0, 0.0, 5.0)]:
		if not round_arena.wall_near(p, 3.0).is_empty():
			_fail("the roundabout reports a wall near %s" % str(p))


func _check_wall_query() -> void:
	var w = arena.wall_near(spot, 2.4)
	if w.is_empty():
		_fail("no wall found %.1f m from a wall face" % AWAY)
		return
	if w["normal"].distance_to(Vector3(-1.0, 0.0, 0.0)) > 0.001:
		_fail("the wall normal is %s, expected (-1, 0, 0)" % str(w["normal"]))
	if absf(float(w["dist"]) - AWAY) > 0.05:
		_fail("the wall is %.3f m away, expected %.2f m" % [float(w["dist"]), AWAY])
	if absf(w["point"].x - face_x) > 0.05 or absf(w["point"].z - spot.z) > 0.001:
		_fail("the spot on the wall is %s, expected x %.2f" % [str(w["point"]), face_x])
	if not arena.wall_near(spot, AWAY - 0.1).is_empty():
		_fail("a wall was found beyond the reach asked for")
	if not arena.wall_near(arena.start_position(), 1.0).is_empty():
		_fail("a wall was found within 1 m of the start, which is open ground")
	if not arena.wall_near(Vector3(face_x + 0.5, 0.0, spot.z), 2.4).is_empty():
		_fail("a wall was found for a point inside a wall")


# in the air against the wall: away and up
func _check_push() -> void:
	_hang(spot, Vector3(3.0, 0.0, 0.0))
	main._process(DT)
	if main.wall_t <= 0.0:
		_fail("touching a wall in the air did not open the wall-jump window")
	main.player_sys.request_jump()
	main._process(DT)
	if main.wall_jumps != 1:
		_fail("Space against a wall in the air was not a wall-jump (count %d)" % main.wall_jumps)
	if main.jump_v < main.player_sys.WALL_JUMP_SPEED - 0.5:
		_fail(
			(
				"a wall-jump goes up at %.2f m/s, expected %.1f"
				% [main.jump_v, main.player_sys.WALL_JUMP_SPEED]
			)
		)
	if main.pvel.x > -main.player_sys.WALL_PUSH + 0.5:
		_fail(
			(
				"a wall-jump pushes away at %.2f m/s, expected %.1f"
				% [-main.pvel.x, main.player_sys.WALL_PUSH]
			)
		)
	if main.wall_cd <= 0.0:
		_fail("a wall-jump started no cooldown")
	# the press was used up: no second wall-jump from the same press
	main._process(DT)
	if main.wall_jumps != 1:
		_fail("one press made %d wall-jumps" % main.wall_jumps)


# the speed along the wall is kept, the total stays under the air speed cap
func _check_momentum() -> void:
	_hang(spot, Vector3(2.0, 0.0, 5.0))
	main._process(DT)
	main.player_sys.request_jump()
	main._process(DT)
	if main.wall_jumps != 1:
		_fail("no wall-jump while running along the wall")
		return
	if main.pvel.z < 4.5:
		_fail("a wall-jump lost the speed along the wall (%.2f of 5 m/s)" % main.pvel.z)
	if main.pvel.length() > main.player_sys.AIR_SPEED_MAX + 0.01:
		_fail("a wall-jump went over the air speed cap (%.2f m/s)" % main.pvel.length())


func _check_dash_cancel() -> void:
	_hang(spot, Vector3(3.0, 0.0, 0.0))
	main.dash_dir = Vector3(1.0, 0.0, 0.0)
	main.dash_t = 0.12
	main._process(DT)
	main.player_sys.request_jump()
	main._process(DT)
	if main.wall_jumps != 1:
		_fail("no wall-jump out of a dash")
	if main.dash_t > 0.0:
		_fail("the wall-jump did not end the dash")
	if main.pvel.x > -main.player_sys.WALL_PUSH + 0.5:
		_fail("the dash kept pushing into the wall after a wall-jump (%.2f m/s)" % main.pvel.x)


# the window after leaving the wall, and nothing on open ground
func _check_window() -> void:
	var far = spot + Vector3(-4.0, 0.0, 0.0)
	# a press 6 frames after touching the wall still works
	_hang(spot, Vector3.ZERO)
	main._process(DT)
	main.player.position = Vector3(far.x, main.player.position.y, far.z)
	for i in range(5):
		main._process(DT)
	main.player_sys.request_jump()
	main._process(DT)
	if main.wall_jumps != 1:
		_fail("a press 0.1 s after the wall was left did not wall-jump")
	# a press 0.15 s after does not
	_hang(spot, Vector3.ZERO)
	main._process(DT)
	main.player.position = Vector3(far.x, main.player.position.y, far.z)
	for i in range(9):
		main._process(DT)
	main.player_sys.request_jump()
	main._process(DT)
	if main.wall_jumps != 0:
		_fail("a press 0.15 s after the wall was left still wall-jumped")
	# open ground the whole time
	_hang(far, Vector3.ZERO)
	for i in range(3):
		main._process(DT)
	main.player_sys.request_jump()
	main._process(DT)
	if main.wall_jumps != 0 or main.jump_v > 0.0:
		_fail("a press in the air far from any wall did something")


func _check_limit_and_landing() -> void:
	var max_jumps = main.player_sys.WALL_JUMP_MAX
	_hang(spot, Vector3(3.0, 0.0, 0.0))
	for i in range(max_jumps + 1):
		# back at the wall, high up: touch it, press
		main.player.position = Vector3(spot.x, main.player.position.y, spot.z)
		main.jump_h = 3.0
		main.jump_v = 0.0
		main.pvel = Vector3(3.0, 0.0, 0.0)
		main._process(DT)
		main.player_sys.request_jump()
		main._process(DT)
		var want = mini(i + 1, max_jumps)
		if main.wall_jumps != want:
			_fail(
				(
					"wall-jump %d of an airtime: the count is %d, expected %d"
					% [i + 1, main.wall_jumps, want]
				)
			)
		if i >= max_jumps and main.jump_v > 0.0:
			_fail("a wall-jump beyond the limit of %d went up" % max_jumps)
		# wait for the cooldown away from the wall
		main.player.position = Vector3(spot.x - 4.0, main.player.position.y, spot.z)
		for k in range(14):
			main._process(DT)
	# landing gives them back
	main.jump_h = 0.05
	main.jump_v = -5.0
	main._process(DT)
	if main.player_sys.is_airborne():
		_fail("the test player did not land")
	if main.wall_jumps != 0:
		_fail("landing left %d wall-jumps counted" % main.wall_jumps)


# A or D and Space against a wall: the wall-jump, not the side dash; the side dash when they are used up
func _check_side_dash_priority() -> void:
	_hang(spot, Vector3(2.0, 0.0, 0.0))
	if not _press(KEY_D):
		notes.append("D could not be pressed in this run: the side dash priority was not checked")
		return
	main._process(DT)
	main.player_sys.request_jump()
	if main.side_t > 0.0 or main.dash_cd > 0.0:
		_fail("D held and Space against a wall started a side dash instead of a wall-jump")
	main._process(DT)
	if main.wall_jumps != 1:
		_fail("D held and Space against a wall was not a wall-jump")
	_hang(spot, Vector3(2.0, 0.0, 0.0))
	_press(KEY_D)
	main._process(DT)
	main.wall_jumps = main.player_sys.WALL_JUMP_MAX
	main.player_sys.request_jump()
	if main.side_t <= 0.0:
		_fail("with the wall-jumps used up, D held and Space was not a side dash")
	_release(KEY_D)
	main.side_t = 0.0
	main.dash_cd = 0.0


# the glow on the wall and the ring of a wall-jump
func _check_marks() -> void:
	var marks = main.wall_marks
	_hang(spot, Vector3.ZERO)
	for i in range(8):
		main._process(DT)
	if marks.pad == null or not marks.pad.visible or marks.vis < 0.5:
		_fail("no glow on a wall the player could jump off")
		return
	if absf(marks.pad.position.x - (face_x - 0.05)) > 0.02:
		_fail(
			(
				"the glow is at x %.3f, not on the wall face (%.3f)"
				% [marks.pad.position.x, face_x - 0.05]
			)
		)
	if absf(marks.pad.position.y - (main.player.position.y + 1.0)) > 0.15:
		_fail(
			(
				"the glow is at y %.2f, not at chest height (%.2f)"
				% [marks.pad.position.y, main.player.position.y + 1.0]
			)
		)
	var mat: ShaderMaterial = marks.pad.material_override
	if (
		float(mat.get_shader_parameter("u_ready")) < 0.5
		or float(mat.get_shader_parameter("u_spent")) > 0.5
	):
		_fail("the glow of a wall in reach is not the ready one")
	# a wall further off glows, but is not the ready one
	_hang(spot + Vector3(-1.5, 0.0, 0.0), Vector3.ZERO)
	main._process(DT)
	if marks.pad.material_override.get_shader_parameter("u_ready") > 0.5:
		_fail("a wall out of reach is marked as ready")
	if main.wall_t > 0.0:
		_fail("a wall out of reach opened the wall-jump window")
	# used up: red
	_hang(spot, Vector3.ZERO)
	main.wall_jumps = main.player_sys.WALL_JUMP_MAX
	main._process(DT)
	if float(marks.pad.material_override.get_shader_parameter("u_spent")) < 0.5:
		_fail("the glow does not turn red when the wall-jumps are used up")
	# the ring of a wall-jump
	_hang(spot, Vector3(3.0, 0.0, 0.0))
	main._process(DT)
	main.player_sys.request_jump()
	main._process(DT)
	if marks.ripple_t < 0.0 or marks.ripple == null or not marks.ripple.visible:
		_fail("a wall-jump ran no ring over the wall")
	for i in range(40):
		main.jump_h = 3.0
		main._process(DT)
	if marks.ripple_t >= 0.0 or marks.ripple.visible:
		_fail("the ring of a wall-jump did not end")
	# on the ground nothing is drawn
	_ground()
	for i in range(20):
		main._process(DT)
	if marks.pad.visible or marks.vis > 0.01:
		_fail("the glow is drawn on the ground")


func _check_sound() -> void:
	if not main.sfx.streams.has("wall_jump"):
		_fail("the wall-jump sound (audio/wall_jump.wav) is not loaded")


# wall-jumping into every direction in every arena style stays inside the arena and under the lowest roof
func _check_bounds() -> void:
	var rules = ArenaGenScript.load_rules()
	var tested = 0
	var bad = 0
	var total = 0
	var highest = 0.0
	for style in ["plaza", "canyon", "market", "park", "bridge", "tunnel"]:
		var a = null
		for sd in range(5000, 5400):
			var layout = ArenaGenScript.generate(sd, rules)
			if not layout.is_empty() and str(layout.get("style", "")) == style:
				a = GeneratedArena.new(layout, rules)
				break
		if a == null:
			continue
		tested += 1
		main.arena = a
		for deg in range(0, 360, 45):
			var dir = Vector3(sin(deg_to_rad(float(deg))), 0.0, cos(deg_to_rad(float(deg))))
			_ground()
			main.player.position = a.start_position()
			var seen = main.wall_jumps
			for k in range(240):
				if k % 40 == 0:
					main.pvel = dir * main.player_sys.CHAIN_MAX_SPEED
				if k % 6 == 0:
					main.player_sys.request_jump()
				main._process(DT)
				if main.wall_jumps > seen:
					total += 1
				seen = main.wall_jumps
				highest = maxf(highest, main.jump_h)
				var p = main.player.position
				if (
					absf(p.y - main.jump_h) > 0.0001
					or a.obstacle_at(p)
					or main.clamp_walk(p).distance_to(p) > 0.01
					or main.jump_h >= GeneratedArena.SOLID_HEIGHT
				):
					bad += 1
	if tested == 0:
		_fail("no generated arena was found to test the bounds on")
	if total == 0:
		_fail("no wall-jump happened in any arena style: the walls are never found in a real arena")
	if bad > 0:
		_fail(
			(
				"%d frames of wall-jumping ended inside a building, at the wrong height or above the lowest roof"
				% bad
			)
		)
	notes.append("%d wall-jumps in %d arenas, highest point %.2f m" % [total, tested, highest])
	main.arena = arena
	_ground()


# in the air at `pos` (x and z; the height is 3 m, so a test frame never lands), moving at `vel`, nothing used up yet
func _hang(pos: Vector3, vel: Vector3) -> void:
	_ground()
	main.player.position = Vector3(pos.x, 3.0, pos.z)
	main.jump_h = 3.0
	main.jump_v = 0.0
	main.coyote_t = 0.0
	main.pvel = vel
	main.dash_t = 0.0
	main.dash_cd = 0.0
	main.wall_t = 0.0
	main.wall_cd = 0.0
	main.wall_jumps = 0
	main.wall_marks.reset()


func _ground() -> void:
	main.player_sys.reset_air()
	main.pvel = Vector3.ZERO
	main.slide_t = 0.0
	main.slide_cd = 0.0
	main.dash_t = 0.0
	main.dash_cd = 0.0
	main.dash_inv = 0.0
	main.side_t = 0.0
	main.crouch_t = 0.0
	main.invuln = 1000.0
	main.state = "play"
	main.player.position = main.arena.start_position()
	for k in [KEY_W, KEY_C, KEY_SHIFT, KEY_A, KEY_D]:
		_release(k)
	main._process(DT)


func _press(key: int) -> bool:
	var e = InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = true
	Input.parse_input_event(e)
	return Input.is_physical_key_pressed(key)


func _release(key: int) -> void:
	var e = InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	e.pressed = false
	Input.parse_input_event(e)


func _start_round() -> void:
	main.start_game(false, SEED)
	main.equip_primary("dart_gun")
	if main.state == "map":
		main.pick_node(0)
	# headless Godot cannot capture the mouse, so the test hook plays the round
	main.force_captured = true


func _finish() -> void:
	for n in notes:
		print("wall_jump_check: note: " + n)
	if problems.is_empty():
		print(
			"wall_jump_check: wall query, push, momentum, window, limit, side dash priority, marks, sound and bounds are fine"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("wall_jump_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
