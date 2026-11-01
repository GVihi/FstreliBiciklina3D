extends RefCounted
# Pedestrians (civilians): spawning, walking, getting hit.
# Shared game state stays on main.gd (g); this file holds the logic.

const Models = preload("res://scripts/models.gd")
const Rim = preload("res://scripts/rim.gd")

# Steering, the same way riders do it (riders.gd): a pedestrian owns its world position and the way it faces
# ("yaw") and steers at a point on its lane a little way ahead, turning no faster than TURN_RATE. On the
# roundabout that point is on the lane circle, so it walks the same path as before; open ground will steer
# at a goal instead, round whatever the arena says is in the way.
const TURN_RATE = 6.0  # radians per second: far more than the ring ever asks for (well under 1)
const LOOKAHEAD_MIN = 0.5  # metres
const LOOKAHEAD_TIME = 0.03  # seconds of walking: the point to steer at is this far ahead (at least the minimum)

# Open ground (an arena where arena.rider_pursuit() is true, the generated arenas): there is no street to walk
# along. A pedestrian comes out of one of the arena's gates facing in, steers across the arena at the exit point
# of a different gate ("goal") round whatever is in the way, and is gone when it is back inside any gate's tunnel
# (or at the goal's exit point). "left" then holds the metres still to walk to that exit point, less GOAL_REACH,
# or -1 once it is in a tunnel, so the code that removes a pedestrian at "left" < 0 is the same on both kinds of
# arena.
const GOAL_REACH = 0.5  # metres short of the gate's exit point at which a pedestrian counts as gone
# A pedestrian never walks into a building: the steering (riders.gd avoid_obstacles) looks ahead and turns away,
# but when it is boxed in it only picks a heading 120 degrees round, and until the turn is made the old code walked
# on into the wall (pedestrian_check, "deep inside a building": about 2 in 100 arena and random stream pairs). So a
# step that would end in a building is not taken (it stands and turns), and one that is in a building anyway (a
# spawn, a flee turn, a frame that was too long) is put on the nearest free ground, as move_rider does for riders.

var g = null


func _init(game) -> void:
	g = game


func spawn_civ(init_x: float = 9999.0) -> void:
	if g.training_room:
		return  # the training room has no pedestrians: it is a place to aim, and nobody walks through it
	var open = g.arena.rider_pursuit()
	if open and g.arena.gates().is_empty():
		return  # nowhere to come out of
	var kind = g.pick_one(["walker", "granny", "jogger", "tourist"])
	var dir = 1 if randf() < 0.5 else -1
	var spd = 0.0
	if kind == "jogger":
		spd = randf_range(105.0, 150.0)
	elif kind == "granny":
		spd = randf_range(20.0, 32.0)
	elif kind == "tourist":
		spd = randf_range(28.0, 42.0)
	else:
		spd = randf_range(34.0, 55.0)
	spd *= g.CIV_SCALE
	var pants_list = [
		Color.html("#2d3a52"), Color.html("#4a4036"), Color.html("#2a2a2e"), Color.html("#6b7a8f")
	]
	var shirts = ["#d65a4a", "#4a90d6", "#e0b83a", "#58b36a", "#9a62c8", "#e8e8e0", "#2f3b4f"]
	var hairs = ["#2b1d12", "#6b4a2b", "#c9a266", "#1a1a1a", "#8a8a8a"]
	var skins = ["#f0c8a0", "#d9a273", "#a8734a", "#7a4e30"]
	var bags = ["#c49a5a", "#5a7fa8", "#b86a6a"]
	var pal = {
		"shirt": Color.html(g.pick_one(shirts)),
		"pants": g.pick_one(pants_list),
		"hair": Color.html("#8a8a8a" if kind == "granny" else g.pick_one(hairs)),
		"skin": Color.html(g.pick_one(skins)),
		"bag": Color.html(g.pick_one(bags))
	}
	var m = Models.build_civ(kind, pal)
	g.add_child(m["root"])
	g.rim_apply(m["root"], Rim.FRIEND)
	# init_x is where along the street it starts (a spawn point, not a position it keeps): by default
	# inside the tunnel block a little before the seam
	var x0 = init_x
	if init_x > 9000.0:
		x0 = -(g.ARENA_HX + 1.8) if dir > 0 else (g.ARENA_HX + 1.8)
	var z = g.JOG_Z if kind == "jogger" else g.SIDEWALK_Z + randf_range(-0.5, 0.5)
	var c = {
		"type": kind,
		"lane_z": z,  # the lane it walks along (street z): it steers at a point on it a little ahead
		"pos": g.arena.tw(x0, z, 0.0),  # where it stands on the ground, in world space
		"yaw": g.arena.yaw(x0) + (0.0 if dir > 0 else PI),  # the way it faces and walks (also its hit box)
		"hidden": g.arena.hidden(x0),  # inside the tunnel block: not visible, not hittable
		"avoid_side": 1.0,  # which way it last swung round an obstacle
		"open": open,  # which kind of arena it was made for: one made for the other kind is dropped (update_civs)
		"goal": {},  # open ground: the gate it walks to and leaves through
		"entered": false,  # open ground: true once it has come out of the gate it started in
		"left": street_left(x0, dir),  # street metres still to walk before it is out of the arena
		"dir": dir,
		"spd": spd,
		"ph": randf_range(0.0, 6.0),
		"t": 0.0,
		"state": "walk",
		"hop": 0.0,
		"flinch": 0.0,
		"photo": 0.0,
		"photo_t": randf_range(1.0, 3.0),
		"scale": m["scale"] * randf_range(0.97, 1.04),
		"model": m
	}
	if open:
		enter_at_gate(c)
	g.civs.append(c)
	apply_civ(c)


# Open ground: put a new pedestrian in the tunnel of a gate, facing in, and pick a different gate for it to leave
# by (the same one only when the arena has no other). The gate is a random one: pedestrians use the global random
# numbers like everything else about them, so the seed does not decide them.
func enter_at_gate(c: Dictionary) -> void:
	var rs = g.rider_sys
	var gates = g.arena.gates()
	var from: Dictionary = gates[randi() % gates.size()]
	var others = gates.filter(func(gate): return gate["pos"] != from["pos"])
	c["goal"] = from if others.is_empty() else others[randi() % others.size()]
	c["pos"] = rs.gate_spawn_point(from)
	c["yaw"] = rs.yaw_of(-from["outward"])
	c["hidden"] = rs.is_hidden(c["pos"])
	c["entered"] = false
	c["left"] = goal_left(c)


# open ground: metres still to walk before the pedestrian is at its goal gate's exit point (and so gone)
func goal_left(c: Dictionary) -> float:
	var to: Vector3 = g.rider_sys.gate_exit_point(c["goal"]) - c["pos"]
	return Vector2(to.x, to.z).length() - GOAL_REACH


# The rest of the game reads where a pedestrian is from "pos", "yaw" and "hidden", which are world-space values.
# Only move_civ (and the spawn and flee switches in this file) change them.


# street metres a pedestrian at street x walking in direction dir (+1 or -1) still has to go before it is
# out of the arena: 2.4 m past the seam at the end it walks towards. This and `turn_to_flee` below are the
# only places that still think in street coordinates; the placement item (README Milestone K, Gameplay on
# open ground) replaces them with gates.
func street_left(x: float, dir: int) -> float:
	return g.ARENA_HX + 2.4 - x * float(dir)


# walk for dt seconds at speed_street street metres per second: steer at the lane point ahead (no faster than
# TURN_RATE), then move along the heading. Returns nothing: "pos", "yaw", "hidden" and "left" are updated.
func move_civ(c: Dictionary, speed_street: float, dt: float) -> void:
	var rs = g.rider_sys
	var speed = speed_street * g.arena.scale_at(c["lane_z"])  # metres per second over the ground
	var open = g.arena.rider_pursuit()
	if open and not c["hidden"]:
		c["entered"] = true
		if g.arena.rider_blocked(c["pos"]):
			c["pos"] = g.arena.clamp_walk(c["pos"], "boss")
	var in_tunnel = open and c["hidden"] and not c["entered"]  # still in the tunnel it started in
	var target: Vector3
	if open:
		target = rs.gate_exit_point(c["goal"])
		if in_tunnel:
			target = c["pos"] + rs.heading_vec(c["yaw"]) * 10.0  # walk straight out of the tunnel first
	else:
		var ahead = maxf(LOOKAHEAD_MIN, speed * LOOKAHEAD_TIME)
		target = g.arena.lane_point(c["pos"], c["dir"], c["lane_z"], ahead)
	var want = rs.yaw_of(target - c["pos"])
	if g.arena.rider_avoidance() and not in_tunnel:
		var steered = rs.avoid_obstacles(c["pos"], want, speed, c["yaw"], c["avoid_side"])
		var swing = wrapf(steered - c["yaw"], -PI, PI)
		if absf(swing) > 0.0001:
			c["avoid_side"] = signf(swing)
		want = steered
	var turn = wrapf(want - c["yaw"], -PI, PI)
	var max_turn = TURN_RATE * dt
	c["yaw"] = wrapf(c["yaw"] + clampf(turn, -max_turn, max_turn), -PI, PI)
	var step: Vector3 = rs.heading_vec(c["yaw"]) * speed * dt
	if not (open and g.arena.rider_blocked(c["pos"] + step)):
		c["pos"] += step
	c["hidden"] = rs.is_hidden(c["pos"])
	if open:
		# back inside a gate's tunnel after coming out of one: it has left the arena, by its own gate or another
		c["left"] = -1.0 if c["entered"] and c["hidden"] else goal_left(c)
	else:
		c["left"] -= speed_street * dt


# a startled pedestrian runs away: turn round at once and head for the nearer end of the street (it can only
# be startled while visible, so its street x is not wrapped round the seam); on open ground it heads for the
# nearest gate and the steering turns it round at the usual rate
func turn_to_flee(c: Dictionary) -> void:
	c["state"] = "flee"
	c["hop"] = 0.0
	if c["open"]:
		# open ground: run for the gate nearest to where it stands, steering round whatever is in the way
		c["goal"] = g.rider_sys.nearest_gate(c["pos"])
		c["left"] = goal_left(c)
		return
	var street_x = g.arena.to_track(c["pos"]).x
	c["dir"] = -1 if street_x < 0.0 else 1
	c["yaw"] = g.arena.yaw(street_x) + (0.0 if c["dir"] > 0 else PI)
	c["left"] = street_left(street_x, c["dir"])
	c["hop"] = 0.0


func apply_civ(c: Dictionary) -> void:
	var m = c["model"]
	var s = c["scale"]
	var cr: Node3D = m["root"]
	cr.position = c["pos"] + Vector3(0.0, c["hop"], 0.0)
	cr.rotation = Vector3(0.0, c["yaw"], 0.0)
	cr.scale = Vector3(s, s, s)
	Models.pose_civ(m, c["ph"], c["photo"] > 0.0, c["type"] == "jogger" or c["state"] == "flee")


func update_civs(dt: float) -> void:
	g.civ_t -= dt
	var max_c = mini(4, 2 + int(g.round_n / 2))
	if g.civ_t <= 0.0:
		g.civ_t = maxf(0.8, randf_range(1.4, 3.4) - g.round_n * 0.1)
		if g.civs.size() < max_c:
			spawn_civ()
	for i in range(g.civs.size() - 1, -1, -1):
		var c = g.civs[i]
		if c["open"] != g.arena.rider_pursuit():
			c["model"]["root"].queue_free()  # made for the other kind of arena (the arena was swapped under it)
			g.civs.remove_at(i)
			continue
		c["t"] += dt
		if c["flinch"] > 0.0:
			c["flinch"] -= dt
		var st = c["state"]
		if st == "walk":
			var moving = true
			if c["type"] == "tourist":
				c["photo_t"] -= dt
				if c["photo_t"] <= 0.0:
					if c["photo"] > 0.0:
						c["photo"] = 0.0
						c["photo_t"] = randf_range(2.0, 4.0)
					else:
						c["photo"] = randf_range(0.9, 1.4)
						c["photo_t"] = c["photo"]
				if c["photo"] > 0.0:
					moving = false
			if moving:
				move_civ(c, c["spd"], dt)
				c["ph"] += dt * (4.0 + c["spd"] * 2.0)
		elif st == "startled":
			c["hop"] = absf(sin(c["t"] * PI / 0.35)) * 0.3 if c["t"] < 0.7 else 0.0
			if c["t"] > 0.8:
				turn_to_flee(c)
		elif st == "flee":
			move_civ(c, 6.6, dt)
			c["ph"] += dt * 16.0
		if c["left"] < 0.0:
			c["model"]["root"].queue_free()
			g.civs.remove_at(i)
		else:
			apply_civ(c)


# remove every pedestrian (their models too): used when the arena changes, since a pedestrian's position and its
# goal gate belong to the arena it was made for
func clear_civs() -> void:
	for c in g.civs:
		c["model"]["root"].queue_free()
	g.civs.clear()


func hit_civ(c: Dictionary) -> void:
	c["state"] = "startled"
	c["t"] = 0.0
	c["hop"] = 0.0
	if g.practice:  # the training room: the pedestrian is startled and nothing else happens
		g.show_hit_marker("hit")
		g.add_popup(c["pos"] + Vector3(0.0, 2.2, 0.0), "ALO!", g.WHITE, true)
		g.sfx.play3d("thud", c["pos"] + Vector3(0.0, 1.2, 0.0))
		return
	g.hearts -= 1
	g.round_lives_lost += 1
	g.challenges.on_life_lost()
	g.combo = 0
	g.civs_hit += 1
	g.show_hit_marker("bad")
	g.score = maxi(0, g.score - 1500)
	var cp = c["pos"] + Vector3(0.0, 1.2, 0.0)
	g.add_popup(c["pos"] + Vector3(0.0, 2.2, 0.0), "ALO!", g.WHITE, true)
	g.add_note("PEDESTRIAN HIT  -1 LIFE  -1500", g.RED)
	g.red_flash = 0.25
	g.sfx.play3d("thud", cp)
	g.sfx.v_hey(cp)
	g.sfx.say("civ_hit")
	if g.hearts <= 0:
		g.game_over("civ")
