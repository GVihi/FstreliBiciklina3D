extends SceneTree
# Checks jumping (README Milestone L, "Jump on Space", "Jump on the gamepad" and "Decide how jumping mixes with sprint,
# crouch, slide and dash"):
#   - a hop has a fixed height and length, and the whole player node (hit box, camera and gun with it) rises and falls,
#   - a press just before landing still jumps (jump buffer), a press long before landing does not,
#   - the speed at take-off is kept in the air (sprint jump, slide jump), and a standing jump steers at walk pace,
#   - you can jump out of a slide (the slide ends, its cooldown keeps running, the speed is kept),
#   - a dash starts in the air, stays flat, and shares the one dash bar with the ground dash,
#   - crouch in the air does not start a slide, crouch held on landing from a fast jump does (once per cooldown),
#   - you can shoot and swing the melee weapon in the air, the dart leaves from the raised camera,
#   - A or D held and Space is a side dash that uses the dash bar (an ordinary jump when the bar is empty or W is held),
#   - the arena bounds (`clamp_walk`) still hold while hopping into every direction,
#   - Space (and a paused game, and a new run) behave: the key asks for a jump only in a round, a new run lands.
# Run from the project folder:
#   godot --headless --path . --script res://tools/jump_check.gd
# or: python tools/run_checks.py jump
# Exits with status 1 and prints the problems when a check fails.

const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArena = preload("res://scripts/arena_generated.gd")

const SEED = 0x1234ABCD
const DT = 1.0 / 60.0

var problems = []
var main
var notes = []


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
	_check_hop()
	_check_buffer()
	_check_momentum()
	_check_slide_jump()
	_check_air_dash()
	_check_crouch_in_air_and_landing_slide()
	_check_shoot_and_swing()
	_check_bounds()
	_check_bounds_generated()
	_check_chain_and_carry()
	_check_side_dash()
	_check_hit_box_moves()
	_check_feedback()
	_check_hurdle()
	_check_aim_in_air()
	_check_inputs_and_resets()
	_finish()


# one flat hop from standing: height, length, the player node and the camera
func _check_hop() -> void:
	_ground()
	var eye = main.cam.global_position.y
	var player_top = 0.0
	main.player_sys.request_jump()
	var top = 0.0
	var frames = 0
	var cam_top = eye
	while frames < 120:
		main._process(DT)
		frames += 1
		top = maxf(top, main.jump_h)
		cam_top = maxf(cam_top, main.cam.global_position.y)
		if absf(main.player.position.y - main.jump_h) > 0.0001:
			_fail(
				(
					"the player node is at y %.3f but the jump height is %.3f"
					% [main.player.position.y, main.jump_h]
				)
			)
			break
		player_top = maxf(player_top, main.player.position.y)
		if not main.player_sys.is_airborne() and frames > 2:
			break
	var seconds = float(frames) * DT
	if top < 0.7 or top > 1.0:
		_fail("a standing hop reached %.2f m, expected about 0.84 m" % top)
	if seconds < 0.45 or seconds > 0.75:
		_fail("a standing hop lasted %.2f s, expected about 0.58 s" % seconds)
	if main.player_sys.is_airborne() or main.jump_h != 0.0:
		_fail("the hop did not end on the ground")
	if cam_top < eye + top - 0.05:
		_fail("the camera did not follow the jump (%.2f of %.2f m)" % [cam_top - eye, top])
	if player_top < top - 0.01:
		_fail(
			(
				"the player node did not rise with the jump (%.2f of %.2f m): the hit box has to move"
				% [player_top, top]
			)
		)
	if absf(main.player.position.y) > 0.0001:
		_fail("the player node is at y %.3f after landing" % main.player.position.y)
	main._process(DT)
	if absf(main.cam.position.y - main.EYE_STAND) > 0.05:
		_fail("after landing the camera is at %.2f, not at eye height" % main.cam.position.y)


# the jump buffer: a press shortly before landing jumps again, a press at the top of the hop does not
func _check_buffer() -> void:
	_ground()
	main.player_sys.request_jump()
	main._process(DT)
	# press close to the ground on the way down
	var guard = 0
	while not (main.jump_v < 0.0 and main.jump_h < 0.35) and guard < 200:
		main._process(DT)
		guard += 1
	main.player_sys.request_jump()
	var landed = false
	var jumped_again = false
	for i in range(30):
		main._process(DT)
		if main.jump_v > 0.0 and landed:
			jumped_again = true
			break
		if not main.player_sys.is_airborne():
			landed = true
	if not jumped_again:
		_fail("a jump pressed just before landing was lost (jump buffer)")
	_ground()
	# press at the top: the buffer is gone long before the landing
	main.player_sys.request_jump()
	main._process(DT)  # the take-off happens in the frame
	guard = 0
	while main.jump_v > 0.3 and guard < 200:
		main._process(DT)
		guard += 1
	main.player_sys.request_jump()
	guard = 0
	while main.player_sys.is_airborne() and guard < 200:
		main._process(DT)
		guard += 1
	main._process(DT)
	if main.player_sys.is_airborne():
		_fail(
			"a jump pressed at the top of a hop was remembered until landing (the buffer is too long)"
		)


# speed is kept in the air; a standing jump steers at walk pace
func _check_momentum() -> void:
	_ground()
	var run = main.RUN
	main.pvel = Vector3(0.0, 0.0, -run)
	main.player_sys.request_jump()
	for i in range(18):
		main._process(DT)
	if main.pvel.length() < run * 0.97:
		_fail(
			(
				"a sprint jump lost speed in the air (%.2f of %.2f m/s after 0.3 s)"
				% [main.pvel.length(), run]
			)
		)
	_ground()
	main.pvel = Vector3.ZERO
	main.player_sys.request_jump()
	main._process(DT)
	if absf(main.air_speed - main.WALK) > 0.01:
		_fail(
			(
				"a standing jump has air speed %.2f, expected the walk speed %.2f"
				% [main.air_speed, main.WALK]
			)
		)
	if _press(KEY_W):
		for i in range(30):
			main._process(DT)
		var s = main.pvel.length()
		_release(KEY_W)
		if s < main.WALK * 0.5 or s > main.WALK + 0.05:
			_fail("steering a standing jump gave %.2f m/s, expected up to the walk speed" % s)
	else:
		notes.append("W could not be pressed in this run: air steering not checked")
	_ground()


# jump out of a slide
func _check_slide_jump() -> void:
	_ground()
	main.slide_t = main.SLIDE_TIME * 0.8
	main.slide_cd = 1.0
	main.slide_dir = Vector3(0.0, 0.0, -1.0)
	main.pvel = main.slide_dir * 8.0
	main.player_sys.request_jump()
	main._process(DT)
	if main.slide_t > 0.0:
		_fail("a jump did not end the slide")
	if not main.player_sys.is_airborne():
		_fail("the jump out of a slide did not take off")
	if main.slide_cd < 0.9:
		_fail("jumping out of a slide reset the slide cooldown (%.2f)" % main.slide_cd)
	for i in range(18):
		main._process(DT)
	if main.pvel.length() < 7.0:
		_fail("a jump out of a slide lost its speed (%.2f m/s after 0.3 s)" % main.pvel.length())
	if main.pvel.length() > main.player_sys.AIR_SPEED_MAX + 0.05:
		_fail("a slide jump is faster than the air speed cap (%.2f m/s)" % main.pvel.length())
	_ground()


# dash in the air
func _check_air_dash() -> void:
	_ground()
	main.dash_cd = 0.0
	main.player_sys.request_jump()
	for i in range(8):
		main._process(DT)
	var v0 = main.jump_v
	main.player_sys.try_dash()
	if main.dash_t <= 0.0:
		_fail("a dash could not start in the air")
	if main.dash_cd <= 0.0:
		_fail("an air dash did not use the dash bar")
	var h_before = main.jump_h
	for i in range(6):
		main._process(DT)
	var drop = v0 - main.jump_v
	var free_fall = main.player_sys.JUMP_GRAVITY * DT * 6.0
	if drop > free_fall * 0.6:
		_fail(
			(
				"an air dash fell as fast as free fall (speed dropped %.2f, free fall %.2f)"
				% [drop, free_fall]
			)
		)
	if main.pvel.length() < 8.0:
		_fail("an air dash is slow (%.2f m/s)" % main.pvel.length())
	if main.jump_h < h_before - 0.5:
		_fail("an air dash dropped the player (%.2f m)" % (h_before - main.jump_h))
	var before = main.dash_t
	main.player_sys.try_dash()
	if main.dash_t > before:
		_fail("a second dash started in the air while the bar was still empty")
	var guard = 0
	while main.player_sys.is_airborne() and guard < 300:
		main._process(DT)
		guard += 1
	if main.player_sys.is_airborne():
		_fail("the player never came down after an air dash")
	main.dash_t = 0.0
	main.dash_cd = 0.0
	_ground()


# crouch in the air is not a slide, crouch held on landing after a fast jump is (once per cooldown)
func _check_crouch_in_air_and_landing_slide() -> void:
	if not _press(KEY_C):
		notes.append("C could not be pressed in this run: crouch in the air not checked")
		_ground()
		return
	_release(KEY_C)
	_ground()
	main.slide_cd = 0.0
	main.was_sprint = true
	main.pvel = Vector3(0.0, 0.0, -main.RUN)
	main.player_sys.request_jump()
	for i in range(5):
		main._process(DT)
	main.was_sprint = true
	_press(KEY_C)
	main._process(DT)
	if main.slide_t > 0.0:
		_fail("pressing crouch in the air started a slide")
	var guard = 0
	while main.player_sys.is_airborne() and guard < 200:
		main._process(DT)
		guard += 1
	if main.slide_t <= 0.0:
		_fail("landing from a sprint jump with crouch held did not roll into a slide")
	_release(KEY_C)
	_ground()
	# the cooldown still applies: no slide on landing while it runs
	main.slide_cd = 5.0
	main.pvel = Vector3(0.0, 0.0, -main.RUN)
	main.player_sys.request_jump()
	main._process(DT)
	_press(KEY_C)
	guard = 0
	while main.player_sys.is_airborne() and guard < 200:
		main._process(DT)
		guard += 1
	if main.slide_t > 0.0:
		_fail("a landing slide started while the slide cooldown was still running")
	_release(KEY_C)
	_ground()


# shooting and swinging in the air: nothing blocks them, and the dart leaves from the raised camera
func _check_shoot_and_swing() -> void:
	_ground()
	main.melee = false
	main.shells = maxi(main.MAXSHELLS, 2)
	main.loading = false
	main.pump_t = 0.0
	main.player_sys.request_jump()
	for i in range(12):
		main._process(DT)
	if main.jump_h < 0.3:
		_fail("the check could not get into the air before shooting")
	var shells = main.shells
	main.combat_sys.fire()
	if main.shells != shells - 1 and main.free_shots <= 0:
		_fail("the gun did not fire in the air (%d darts left of %d)" % [main.shells, shells])
	if main.pump_t <= 0.0:
		_fail("the gun did not start its pump after a shot in the air")
	if main.cam.global_position.y < main.EYE_STAND + 0.3:
		_fail("the camera is not raised in the air, so darts would still leave from eye height")
	main.equip_melee("melee")  # a new player's melee slot is empty (the gummy worm is bought)
	main.melee = true
	main.swing_cd = 0.0
	main.swing_t = 0.0
	main.combat_sys.fire()
	if main.swing_t <= 0.0:
		_fail("the melee weapon did not swing in the air")
	main.melee = false
	_ground()


# hopping into every direction for a while never takes the player out of the walkable area
func _check_bounds() -> void:
	_ground()
	var bad = 0
	for a in range(0, 360, 30):
		var dir = Vector3(sin(deg_to_rad(float(a))), 0.0, cos(deg_to_rad(float(a))))
		for k in range(240):
			main.pvel = dir * main.RUN
			if k % 20 == 0:
				main.player_sys.request_jump()
			main._process(DT)
			var p = main.player.position
			if absf(p.y - main.jump_h) > 0.0001 or main.clamp_walk(p).distance_to(p) > 0.01:
				bad += 1
	if bad > 0:
		_fail("%d frames of hopping left the walkable area or the ground level" % bad)
	_ground()


# the same on every generated arena style: hopping and side dashing into every direction never ends in a building, a
# tunnel block or outside the grid, and the player node stays on the ground, so a jump cannot clear a building
func _check_bounds_generated() -> void:
	var rules = ArenaGenScript.load_rules()
	var old_arena = main.arena
	var tested = 0
	var bad = 0
	for style in ["plaza", "canyon", "market", "park", "bridge", "tunnel"]:
		var arena = null
		for sd in range(5000, 5400):
			var layout = ArenaGenScript.generate(sd, rules)
			if not layout.is_empty() and str(layout.get("style", "")) == style:
				arena = GeneratedArena.new(layout, rules)
				break
		if arena == null:
			continue
		tested += 1
		_ground()
		main.arena = arena
		main.player.position = arena.start_position()
		for a in range(0, 360, 45):
			var dir = Vector3(sin(deg_to_rad(float(a))), 0.0, cos(deg_to_rad(float(a))))
			for k in range(180):
				main.pvel = dir * main.player_sys.CHAIN_MAX_SPEED
				if k % 15 == 0:
					main.player_sys.request_jump()
				if k % 40 == 20:
					main.dash_cd = 0.0
					main.player_sys.try_side_dash(1.0 if (k / 40) % 2 == 0 else -1.0)
				main._process(DT)
				var p = main.player.position
				if (
					absf(p.y - main.jump_h) > 0.0001
					or main.arena.obstacle_at(p)
					or main.clamp_walk(p).distance_to(p) > 0.01
				):
					bad += 1
	main.arena = old_arena
	if tested == 0:
		_fail("no generated arena was found to test the bounds on")
	if bad > 0:
		_fail(
			(
				"%d frames of hopping and side dashing ended inside a building or at the wrong height"
				% bad
			)
		)
	_ground()


# chained hops at sprint speed add a little speed up to a cap, and a landing keeps its speed
func _check_chain_and_carry() -> void:
	_ground()
	if not _press(KEY_W):
		notes.append("W could not be pressed in this run: chained hops not checked")
		return
	var fwd = main.move_world(Vector2(0.0, 1.0))
	main.pvel = fwd * main.RUN
	var first = main.pvel.length()
	for hop in range(7):
		main.player_sys.request_jump()
		main._process(DT)
		var guard = 0
		while main.player_sys.is_airborne() and guard < 200:
			main._process(DT)
			guard += 1
		if hop == 3:
			var before = main.pvel.length()
			main._process(DT)
			if main.pvel.length() < before * 0.93:
				_fail("a landing lost its speed (%.2f to %.2f m/s)" % [before, main.pvel.length()])
	var s = main.pvel.length()
	var cap = main.player_sys.CHAIN_MAX_SPEED
	if s < first + 1.0:
		_fail("seven chained hops did not add speed (%.2f from %.2f m/s)" % [s, first])
	if s > cap + 0.1:
		_fail("chained hops went past the cap (%.2f of %.2f m/s)" % [s, cap])
	if main.chain < 3:
		_fail("the chain count stayed at %d after seven hops in a row" % main.chain)
	# a pause on the ground ends the chain
	for i in range(30):
		main._process(DT)
	if main.chain != 0:
		_fail("the chain did not end after a pause on the ground")
	_release(KEY_W)
	_ground()


# the side dash: A or D held and Space, on the dash bar, speed kept, untouchable for a moment (PERFECT DODGE), in the air too
func _check_side_dash() -> void:
	_ground()
	if not _press(KEY_D):
		notes.append("D could not be pressed in this run: side dash not checked")
		return
	var fwd = main.move_world(Vector2(0.0, 1.0))
	main.pvel = fwd * 5.0
	var right = main.move_world(Vector2(1.0, 0.0))
	main.player_sys.request_jump()
	if main.side_t <= 0.0:
		_fail("D held and Space did not start a side dash")
	if main.player_sys.is_airborne() or main.jump_buf > 0.0:
		_fail("D held and Space also jumped: it must be the side dash only")
	if main.dash_cd <= 0.0:
		_fail("the side dash did not use up the dash bar")
	if main.dash_inv <= 0.0:
		_fail("the side dash gave no untouchable moment")
	main._process(DT)
	if main.pvel.dot(right) < 8.0:
		_fail("the side dash has little sideways speed (%.2f m/s)" % main.pvel.dot(right))
	var start = main.player.position
	var guard = 0
	while main.side_t > 0.0 and guard < 60:
		main._process(DT)
		guard += 1
	var moved = (main.player.position - start).dot(right)
	if moved < 0.8 or moved > 2.6:
		_fail("a side dash moved %.2f m sideways, expected about 1.6 m" % moved)
	if absf(main.pvel.dot(right)) > 0.6:
		_fail("sideways speed was left over after the side dash (%.2f m/s)" % main.pvel.dot(right))
	if main.pvel.dot(fwd) < 3.4:
		_fail("the side dash lost the forward speed")
	_release(KEY_D)
	_ground()
	# with the dash bar empty the same press is an ordinary jump
	_press(KEY_D)
	main.dash_cd = 1.0
	main.player_sys.request_jump()
	if main.side_t > 0.0 or main.jump_buf <= 0.0:
		_fail("with the dash bar empty, D and Space should be a plain jump")
	_release(KEY_D)
	_ground()
	# W held as well: a plain jump (forward-and-sideways jumps are not side dashes)
	_press(KEY_D)
	_press(KEY_W)
	main.player_sys.request_jump()
	if main.side_t > 0.0 or main.jump_buf <= 0.0:
		_fail("D and W and Space should be a plain jump")
	_release(KEY_D)
	_release(KEY_W)
	_ground()
	# a second side dash waits for the dash bar; left, in the air, and a near miss is a PERFECT DODGE
	_press(KEY_A)
	main.player_sys.request_jump()
	if main.side_t <= 0.0 or main.pvel.dot(right) > 0.0 and main.side_dir.dot(right) > 0.0:
		_fail("A held and Space did not side dash to the left")
	main.side_t = 0.0
	main.dash_cd = 0.0
	_release(KEY_A)
	_ground()
	main.player_sys.request_jump()
	for i in range(8):
		main._process(DT)
	_press(KEY_A)
	main.player_sys.request_jump()
	if main.side_t <= 0.0:
		_fail("a side dash did not start in the air")
	main._process(DT)
	if main.pvel.dot(right) > -8.0:
		_fail(
			(
				"a side dash to the left in the air went the wrong way (%.2f m/s)"
				% main.pvel.dot(right)
			)
		)
	if main.jump_h <= 0.0:
		_fail("the side dash in the air ended the jump")
	var dodges = main.perfect_dodges
	main.invuln = 0.0
	main.damage_player("TEST", "run")
	if main.perfect_dodges != dodges + 1:
		_fail("something that hit you during a side dash was not a PERFECT DODGE")
	main.invuln = 1000.0
	_release(KEY_A)
	_ground()


# the hit box is the player node: the melee zone rises with it, and a phone or a slam cannot reach a player in the air
func _check_hit_box_moves() -> void:
	_ground()
	var ground_y = main.combat_sys.swing_zone()["c"].y
	main.player_sys.request_jump()
	for i in range(18):
		main._process(DT)
	var air_y = main.combat_sys.swing_zone()["c"].y
	if air_y < ground_y + 0.5:
		_fail("the melee zone did not rise with the player (%.2f to %.2f m)" % [ground_y, air_y])
	if not main.player_sys.is_hurdling():
		_fail("near the top of a jump the player should be above ground hazards")
	# a phone that lands on the player's spot: it misses a player in the air and hits one on the ground
	for high in [true, false]:
		_ground()
		main.invuln = 0.0
		var hearts = main.hearts
		main.player_sys.reset_air()
		if high:
			main.jump_h = 0.8
			main.jump_v = 0.1
			main.player.position.y = 0.8
		main.phones.clear()
		main.phone_sys.throw_phone(main.player.position + Vector3(0.0, 3.0, 0.0), null)
		main.phones[0]["p"] = 0.999
		main.phone_sys.update_phones(DT)
		if high and main.hearts != hearts:
			_fail("a phone hit a player who had jumped over it")
		if not high and main.hearts == hearts:
			_fail("a phone that landed on a player on the ground did no damage")
	main.invuln = 1000.0
	_ground()


# landing dips the eye and the gun, and the dip settles
func _check_feedback() -> void:
	_ground()
	main.player_sys.request_jump()
	var low = 0.0
	var guard = 0
	var landed = false
	for i in range(160):
		main._process(DT)
		if not main.player_sys.is_airborne():
			landed = true
		if landed:
			low = minf(low, main.player_sys.land_dip)
			guard += 1
			if guard > 40:
				break
	if low > -0.03:
		_fail("a landing barely dipped the camera (%.3f m)" % low)
	if low < -0.16:
		_fail("a landing dipped the camera too far (%.3f m)" % low)
	for i in range(60):
		main._process(DT)
	if absf(main.player_sys.land_dip) > 0.005:
		_fail("the landing dip did not settle (%.3f m)" % main.player_sys.land_dip)
	_ground()


# a rider passes underneath a high jump (no collision, no PERFECT DODGE), and still runs you over on the ground
func _check_hurdle() -> void:
	_ground()
	main.invuln = 0.0
	var r = main.rider_sys.spawn_rider(0, 1)
	if not main.riders.has(r):
		main.riders.append(r)
	r["hidden"] = false
	r["pos"] = main.player.position
	var hearts = main.hearts
	var dodges = main.perfect_dodges
	main.jump_h = 0.8
	main.jump_v = 0.1
	main.player.position.y = 0.8
	main.rider_sys.rider_collide(r)
	if main.hearts != hearts:
		_fail("a rider hit a player who was high in a jump")
	if main.perfect_dodges != dodges:
		_fail("hurdling a rider counted as a PERFECT DODGE")
	main.jump_h = 0.3
	main.player.position.y = 0.3
	main.rider_sys.rider_collide(r)
	if main.hearts == hearts and main.perfect_dodges == dodges:
		_fail("a rider passed through a player who was only just off the ground")
	main.riders.erase(r)
	main.invuln = 1000.0
	_ground()


# darts fly from the raised camera and still hit what the crosshair is on
func _check_aim_in_air() -> void:
	for airborne in [false, true]:
		_ground()
		main.melee = false
		main.shells = maxi(main.MAXSHELLS, 2)
		main.pump_t = 0.0
		main.loading = false
		main.bloom = 0.0
		var r = main.rider_sys.spawn_rider(0, 1)
		if not main.riders.has(r):
			main.riders.append(r)
		r["hidden"] = false
		r["mode"] = "fly"
		if airborne:
			main.player_sys.request_jump()
			for i in range(12):
				main._process(DT)
		var fwd = main.move_world(Vector2(0.0, 1.0))
		r["pos"] = main.player.position + fwd * 8.0
		r["pos"].y = 0.0
		r["hidden"] = false  # the frames above may have hidden it (it spawned in a gate); it stands in the open now
		r["mode"] = "fly"
		var cam_y = main.cam.global_position.y
		main.yaw = atan2(-fwd.x, -fwd.z)
		main.pitch = atan2(0.95 - cam_y, 8.0)
		main.cam.rotation.x = main.pitch
		main.player.rotation.y = main.yaw
		var hits = main.shots_hit
		main.combat_sys.fire()
		if main.shots_hit <= hits:
			_fail(
				(
					"a dart aimed at a rider missed %s"
					% ("in the air" if airborne else "on the ground")
				)
			)
		main.riders.erase(r)
	_ground()


func _check_inputs_and_resets() -> void:
	_ground()
	# Space in a round asks for a jump
	var ev = InputEventKey.new()
	ev.keycode = KEY_SPACE
	ev.physical_keycode = KEY_SPACE
	ev.pressed = true
	main.jump_buf = 0.0
	main.input_sys.handle_input(ev)
	if main.jump_buf <= 0.0:
		_fail("the Space key did not ask for a jump in a round")
	# a paused game does not jump
	main.jump_buf = 0.0
	main.paused = true
	main.player_sys.request_jump()
	main.paused = false
	if main.jump_buf > 0.0:
		_fail("a paused game remembered a jump press")
	# a new run starts standing on the ground
	main.jump_h = 0.6
	main.jump_v = 2.0
	main.jump_buf = 0.1
	_start_round()
	if main.player_sys.is_airborne() or main.jump_buf > 0.0:
		_fail("a new run started in the air or with a remembered jump")
	# Space in the shop still leaves it, and does not jump
	main.state = "shop"
	main.jump_buf = 0.0
	main.input_sys.handle_input(ev)
	if main.jump_buf > 0.0:
		_fail("Space in the shop asked for a jump")
	main.state = "play"
	_ground()


# put the player back on the ground, standing still, with nothing held
func _ground() -> void:
	main.player_sys.reset_air()
	main.pvel = Vector3.ZERO
	main.slide_t = 0.0
	main.slide_cd = 0.0
	main.dash_t = 0.0
	main.dash_cd = 0.0
	main.dash_inv = 0.0
	main.crouch_t = 0.0
	main.invuln = 1000.0
	main.state = "play"
	main.player.position = main.arena.start_position()
	for k in [KEY_W, KEY_C, KEY_SHIFT]:
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
		print("jump_check: note: " + n)
	if problems.is_empty():
		print(
			"jump_check: hop, buffer, momentum, slide jump, air dash, landing slide, shooting, bounds and inputs are fine"
		)
		quit(0)
	else:
		for line in problems.slice(0, 10):
			printerr("jump_check: " + line)
		quit(1)


func _fail(text: String) -> void:
	problems.append(text)
