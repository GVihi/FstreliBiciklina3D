extends RefCounted
# Riders: spawning waves, movement and sound, collisions, hits and losing parts.
# Shared game state stays on main.gd (g); this file holds the logic.

const Models = preload("res://scripts/models.gd")

# Steering. A rider owns its world position and the way it faces ("yaw") and steers at a point on its lane
# a little way ahead, turning no faster than TURN_RATE. On the roundabout that point is on the lane circle,
# so the rider rides the same ring as before; open ground will steer at the player instead.
const TURN_RATE = 9.0  # radians per second: more than the ring ever asks for (about 3 at full speed)
const LOOKAHEAD_MIN = 0.5  # metres
const LOOKAHEAD_TIME = 0.03  # seconds of riding: the point to steer at is this far ahead (at least the minimum)

# Pursuit (open ground, where arena.rider_pursuit() is true). A rider rides at the player on any surface. The
# turn is limited by sideways acceleration instead of a fixed rate, so a fast rider swings wide and a slow one
# turns tight: the rate is PURSUIT_ACCEL / speed, at most PURSUIT_MAX_TURN. When it has gone past the player (the
# player is behind it and closer than PASS_RANGE) it rides straight on for OVERSHOOT metres, then turns round in
# that arc and comes back. Riders come out of a gate and, when they give up, ride out of the nearest one.
const PURSUIT_ACCEL = 20.0  # metres per second squared, sideways
const PURSUIT_MAX_TURN = 6.0  # radians per second
const PASS_RANGE = 7.0  # metres: the player this close and behind means the rider has passed
const OVERSHOOT = 9.0  # metres ridden straight on after a pass before turning back
# A gate's "pos" is the middle of its tunnel block, which is 4 m deep on a generated arena: the outer edge of the grid
# is 2 m beyond it. A rider that starts exactly on that edge is outside the grid, where nothing can be ridden on
# (rider_speed_at is 0), so it never moved: it started this far from pos instead, well inside the tunnel.
const GATE_SPAWN = 1.0  # metres from a gate's pos towards the outside where a rider starts
const GATE_DEPTH = 2.0  # metres: with the mouth, how far a rider that gave up rides out (see gate_exit_point)
const OBSTACLE_BRAKE = 2.3  # per second: a rider with free ground ahead of L metres rides no faster than this times L
const BRAKE_MIN_SPEED = 3.0  # metres per second: the slowest it brakes to for something close ahead
const BOXED_FREE = 1.0  # metres: with less than this free ahead a rider is boxed in and may brake below BRAKE_MIN_SPEED
const CRAWL_SPEED = 0.5  # metres per second: the slowest a boxed-in rider goes while it turns on the spot to a clear heading
const AWAY_REACH = 2.0  # metres from the exit point at which a rider that gave up counts as out
const NEVER_GIVES_UP = 1.0e9  # seconds: the time limit of a rider that cannot get away (g.riders_can_escape())
const AGE_SPEED_CAP = 6.0  # seconds: the longest a rider speeds up for, where it has no time limit
const AWAY_MIN_SPEED = 8.0  # metres per second: the slowest a rider that gave up goes to make its turn

var g = null


func _init(game) -> void:
	g = game


# ================================================================== riders
func spawn_rider(lane_idx: int, dir: int) -> Dictionary:
	var roll = g.layout_f()
	var type = "pro"
	if g.round_n >= 2 and roll < 0.2:
		type = "sprinter"
	elif g.round_n >= 2 and roll < 0.4:
		type = "courier"
	if g.round_n >= 2 and g.layout_f() < minf(0.36, 0.12 + g.round_n * 0.04):
		type = "tough"
	var kit_i = g.layout_i(4)
	if type == "sprinter":
		kit_i = 4
	elif type == "courier":
		kit_i = 0
	elif type == "tough":
		kit_i = 5
	var kit = Models.kit_of(kit_i)
	var diff = 1.0 + (g.round_n - 1) * 0.13 + g.next_idx * 0.03
	var base = 165.0 * g.RIDER_SCALE * diff * g.TYPES[type]["sp"]
	var hp = 1
	if type == "tough":
		hp = 3 if g.round_n >= 5 else 2
	var m = Models.build_rider(type, kit)
	g.add_child(m["root"])
	# riders start inside the tunnel block, a little before the seam, on their own lane
	var x0 = -(g.ARENA_HX + 2.0) if dir > 0 else (g.ARENA_HX + 2.0)
	var lane_z = g.LANE_Z[lane_idx]
	var start_pos = g.arena.tw(x0, lane_z, 0.0)
	var start_yaw = g.arena.yaw(x0) + (0.0 if dir > 0 else PI)
	if g.arena.rider_pursuit():
		# open ground: in a gate's tunnel, facing out of it; "dir" stays 1 so parts fly the way it rides
		var gate = pick_gate()
		start_pos = gate_spawn_point(gate)
		start_yaw = yaw_of(-gate["outward"])
		dir = 1
	var r = {
		"pos": start_pos,  # where the rider is on the ground, in world space
		"yaw": start_yaw,  # the way it faces and rides (also its hit box)
		"hidden": true,  # inside the tunnel block: not visible, not hittable
		"avoid_side": 1.0,  # which way it last swung round an obstacle
		"ride_speed": 0.0,  # metres per second it rode at on the last step (braked for something close ahead)
		"turn_rate": 0.0,  # radians per second it was allowed to turn at on the last step
		"pursuit": "chase",  # open ground: "chase" rides at the player, "overshoot" rides straight on after a pass
		"run_left": 0.0,  # open ground: metres still to ride straight on before turning back
		"away_gate": {},  # open ground: the gate a rider that gave up rides out of
		"away_left": 0.0,  # metres still to ride before an escaping rider is out of the arena
		"dir": dir,
		"ln": lane_idx,
		"base": base,
		"spd": base,
		"tgt": base,
		"chg": randf_range(0.5, 1.2),
		"wph": 0.0,
		"cph": 0.0,
		"mode": "fly",
		"t": 0.0,
		"age": 0.0,
		"entered": false,
		"type": type,
		"idx": g.next_idx,
		"model": m,
		"parts": [],
		"kit": kit,
		"limit": maxf(3.0, 6.1 - g.round_n * 0.35) + g.RIDER_TIME_BONUS,
		"hp": hp,
		"max_hp": hp,
		"flash": 0.0,
		"snd": null,
		"gone": false,
		"can_throw": g.layout_f() < clampf(0.55 + 0.06 * g.round_n, 0.6, 0.9),
		"throw_t": randf_range(0.5, 1.4),
		"wind_t": 0.0
	}
	if not g.riders_can_escape():
		r["limit"] = NEVER_GIVES_UP
	g.next_idx += 1
	g.riders.append(r)
	r["hidden"] = is_hidden(r["pos"])
	place_rider(r, 0.0)
	r["snd"] = g.sfx.make_loop("loop_rider", m["root"], Vector3(0, 1.0, 0))
	Models.pose_rider(m, 0.0, 0.0)
	return r


func spawn_wave() -> void:
	var remaining = g.PER_ROUND - g.next_idx
	var n = 1
	if g.round_n >= 2 and remaining >= 2 and g.layout_f() < minf(0.55, 0.12 + g.round_n * 0.08):
		n = 2
	var order = [0, 1, 2]
	g.layout_shuffle(order)
	var dir = 1 if g.layout_f() < 0.5 else -1
	for k in range(n):
		var d = dir
		if k > 0 and g.layout_f() < 0.5:
			d = -dir
		var r = spawn_rider(order[k], d)
		if n == 2:
			r["limit"] += 1.0
	g.wave_miss = false


# The rest of the game reads where a rider is from "pos", "yaw" and "hidden", which are world-space values.
# Only the functions below change them (move_rider and the spawn and away switches in this file).
func is_hidden(pos: Vector3) -> bool:
	return g.arena.hidden_at(pos)


# put the rider's model on the ground at its world position, facing the way it rides
func place_rider(r: Dictionary, y: float) -> void:
	var root: Node3D = r["model"]["root"]
	root.position = r["pos"] + Vector3(0.0, y, 0.0)
	root.rotation.y = r["yaw"]


# the unit vector a rider facing yaw rides along (the models are built facing +X)
func heading_vec(yaw: float) -> Vector3:
	return Vector3(cos(yaw), 0.0, -sin(yaw))


# the yaw that faces along the world vector v
func yaw_of(v: Vector3) -> float:
	return atan2(-v.z, v.x)


# where a phone thrown by this rider leaves its hand: a little ahead of it
func phone_origin(r: Dictionary) -> Vector3:
	return r["pos"] + heading_vec(r["yaw"]) * 0.6 + Vector3(0.0, 1.4, 0.0)


# one of the arena's gates, chosen with the layout's random numbers so a seed gives the same riders
# On a generated arena only the gates the node leaves open (its content "gates", indexes into the arena's gates).
func pick_gate() -> Dictionary:
	var gates = g.arena.gates()
	var usable = []
	for i in g.node_setup().get("gates", []):
		if int(i) >= 0 and int(i) < gates.size():
			usable.append(gates[int(i)])
	if usable.is_empty():
		usable = gates
	return usable[g.layout_i(usable.size())]


# the gate nearest to world point pos
func nearest_gate(pos: Vector3) -> Dictionary:
	var best = {}
	var best_d = INF
	for gate in g.arena.gates():
		var d = Vector2(gate["pos"].x - pos.x, gate["pos"].z - pos.z).length()
		if d < best_d:
			best_d = d
			best = gate
	return best


# where a rider starts at a gate: inside the tunnel, a little beyond its middle (see GATE_SPAWN)
func gate_spawn_point(gate: Dictionary) -> Vector3:
	return gate["pos"] + gate["outward"] * GATE_SPAWN


# the point a rider that gave up rides at: the far end of its gate's tunnel
func gate_exit_point(gate: Dictionary) -> Vector3:
	return gate["pos"] + gate["outward"] * (GATE_DEPTH + 1.0)


# metres a rider that gave up still has to ride to its gate's exit point (never negative)
func away_distance(r: Dictionary) -> float:
	var to = gate_exit_point(r["away_gate"]) - r["pos"]
	return maxf(0.0, Vector2(to.x, to.z).length() - AWAY_REACH)


# The fastest a rider that gave up may go and still reach its gate: its turning circle (twice the radius,
# speed squared over the sideways acceleration) must fit in the distance left, or it would circle the gate
# for ever. Never below AWAY_MIN_SPEED.
func away_speed_cap(r: Dictionary) -> float:
	var to = gate_exit_point(r["away_gate"]) - r["pos"]
	var dist = Vector2(to.x, to.z).length()
	return maxf(AWAY_MIN_SPEED, sqrt(PURSUIT_ACCEL * dist * 0.5))


# the point an open-ground rider steers at. Still inside the tunnel it rides straight out. A rider that gave up
# rides at its gate. Otherwise it rides at the player; once it has passed the player (the player behind it and
# within PASS_RANGE) it rides straight on for OVERSHOOT metres, and then it turns back at the player.
func pursuit_target(r: Dictionary) -> Vector3:
	var fwd = heading_vec(r["yaw"])
	if r["mode"] == "away":
		return gate_exit_point(r["away_gate"])
	if r["hidden"] and not r["entered"]:
		return r["pos"] + fwd * 10.0
	var pp: Vector3 = g.player.position
	var to = Vector3(pp.x - r["pos"].x, 0.0, pp.z - r["pos"].z)
	if r["pursuit"] == "chase" and to.length() < PASS_RANGE and fwd.dot(to) < 0.0:
		r["pursuit"] = "overshoot"
		r["run_left"] = OVERSHOOT
	if r["pursuit"] == "overshoot":
		return r["pos"] + fwd * 10.0
	return Vector3(pp.x, 0.0, pp.z)


# the most an open-ground rider may turn in a second at this speed (sideways acceleration over speed)
func pursuit_turn_rate(speed: float) -> float:
	return minf(PURSUIT_MAX_TURN, PURSUIT_ACCEL / maxf(speed, 1.0))


# ride for dt seconds: steer at the lane point ahead (no faster than TURN_RATE), then move along the heading.
# Where the arena has rider pursuit, steer at the player instead (pursuit_target) with the sideways limit.
func move_rider(r: Dictionary, dt: float) -> void:
	var pursuit = g.arena.rider_pursuit()
	if pursuit and not r["hidden"] and g.arena.rider_blocked(r["pos"]):
		# inside a wall (a rider cannot ride out of one: it has no speed there, and a dart cannot reach it): put
		# it on the nearest free ground
		r["pos"] = g.arena.clamp_walk(r["pos"], "boss")
	var lane_z = g.LANE_Z[r["ln"]]
	# metres per second over the ground: on open ground the surface under the rider sets its share of the speed
	var speed = (
		r["spd"] * (g.arena.rider_speed_at(r["pos"]) if pursuit else g.arena.scale_at(lane_z))
	)
	var in_tunnel = pursuit and r["hidden"] and not r["entered"]
	if pursuit and not in_tunnel:
		# something close ahead: ride slower, so the arc the rider can swing is tight enough to clear it
		var look = speed / OBSTACLE_BRAKE + 1.0
		var free = clear_distance(r["pos"], r["yaw"], look)
		if free < look:
			speed = minf(
				speed,
				maxf(BRAKE_MIN_SPEED if free >= BOXED_FREE else CRAWL_SPEED, OBSTACLE_BRAKE * free)
			)
	var target: Vector3
	var turn_rate = TURN_RATE
	if pursuit:
		target = pursuit_target(r)
		turn_rate = pursuit_turn_rate(speed)
	else:
		var ahead = maxf(LOOKAHEAD_MIN, speed * LOOKAHEAD_TIME)
		target = g.arena.lane_point(r["pos"], r["dir"], lane_z, ahead)
	var want = yaw_of(target - r["pos"])
	if (g.arena.rider_avoidance() or pursuit) and not in_tunnel:
		# on open ground the look reaches over the arc the rider needs to swing clear: its turning radius (speed
		# squared over the sideways acceleration) plus a margin, so it starts to turn away in time
		var min_reach = 0.0
		if pursuit:
			min_reach = 1.2 * speed * speed / PURSUIT_ACCEL + 3.0
		var steered = avoid_obstacles(r["pos"], want, speed, r["yaw"], r["avoid_side"], min_reach)
		var swing = wrapf(steered - r["yaw"], -PI, PI)
		if absf(swing) > 0.0001:
			r["avoid_side"] = signf(swing)
		want = steered
	var turn = wrapf(want - r["yaw"], -PI, PI)
	var max_turn = turn_rate * dt
	r["ride_speed"] = speed
	r["turn_rate"] = turn_rate
	r["yaw"] = wrapf(r["yaw"] + clampf(turn, -max_turn, max_turn), -PI, PI)
	r["pos"] += heading_vec(r["yaw"]) * speed * dt
	r["hidden"] = is_hidden(r["pos"])
	if pursuit and r["pursuit"] == "overshoot":
		r["run_left"] -= speed * dt
		if r["run_left"] <= 0.0:
			r["pursuit"] = "chase"


# If the way ahead (a little further the faster the rider goes) is blocked, keep riding on the clear heading
# that needs the smallest turn from the one the rider has now: straight on if that is clear, else the nearest
# one on either side, up to 120 degrees off, trying the `side` it swung to last time (+1 or -1) first so a
# rider does not dither between the two sides of an obstacle; boxed in, it turns hard away. When the way
# to `want` is clear it just returns `want`. Used only where the arena asks for it.
func avoid_obstacles(
	pos: Vector3, want: float, speed: float, yaw: float, side: float = 1.0, min_reach: float = 0.0
) -> float:
	var reach = maxf(maxf(2.0, speed * 0.4), min_reach)
	# a long look is sampled every metre so a post cannot slip between two samples; the short look keeps 3
	var samples = 3 if min_reach <= 0.0 else int(ceil(reach))
	if way_clear(pos, want, reach, samples):
		return want
	for k in range(0, 7):
		var off = deg_to_rad(20.0) * float(k)
		for sgn in [side, -side]:
			var cand = yaw + off * sgn
			if way_clear(pos, cand, reach, samples):
				return cand
	return yaw + deg_to_rad(120.0) * side


# metres a rider at pos can ride along yaw before it reaches something it cannot ride through (with the same
# 0.7 m to spare on both sides as way_clear), looking at most `reach` metres ahead: `reach` when nothing is there
func clear_distance(pos: Vector3, yaw: float, reach: float) -> float:
	var fwd = heading_vec(yaw)
	var across = Vector3(-fwd.z, 0.0, fwd.x) * 0.7
	var d = 1.0
	while d < reach + 1.0:
		var at = minf(d, reach)
		var p = pos + fwd * at
		if (
			g.arena.rider_blocked(p)
			or g.arena.rider_blocked(p + across)
			or g.arena.rider_blocked(p - across)
		):
			return maxf(0.0, at - 1.0)
		d += 1.0
	return reach


# true if nothing is in the way over `reach` metres from pos along yaw, with 0.7 m to spare on both sides
# (looked at in `samples` steps, three by default)
func way_clear(pos: Vector3, yaw: float, reach: float, samples: int = 3) -> bool:
	var fwd = heading_vec(yaw)
	var across = Vector3(-fwd.z, 0.0, fwd.x) * 0.7
	for k in range(1, samples + 1):
		var p = pos + fwd * (reach * float(k) / float(samples))
		if (
			g.arena.rider_blocked(p)
			or g.arena.rider_blocked(p + across)
			or g.arena.rider_blocked(p - across)
		):
			return false
	return true


func update_rider_sound(r: Dictionary) -> void:
	var spd_px = r["spd"] / g.PX_TO_M
	var vol = 0.05 * clampf(spd_px / 250.0, 0.4, 1.8)
	g.sfx.set_loop(r["snd"], vol * 2.2, (500.0 + spd_px * 1.6) / 700.0)


# standing on the road is dangerous: a rider that reaches you knocks you down (a dash through it is a perfect dodge)
func rider_collide(r: Dictionary) -> void:
	if g.state != "play" or r["hidden"]:
		return
	var rp = r["pos"]
	if Vector2(rp.x - g.player.position.x, rp.z - g.player.position.z).length() < 0.95:
		g.damage_player("RUN OVER BY A CYCLIST", "run")


func update_rider(r: Dictionary, dt: float) -> void:
	var m = r["model"]
	var root: Node3D = m["root"]
	var mode = r["mode"]
	if r["flash"] > 0.0:
		r["flash"] -= dt
		if r["flash"] <= 0.0:
			g.set_flash(root, false)
	if mode == "fly":
		r["age"] += dt
		r["chg"] -= dt
		if r["chg"] <= 0.0:
			var roll = randf()
			if roll < 0.22:
				r["tgt"] = r["base"] * randf_range(1.8, 2.3)
				r["chg"] = randf_range(0.3, 0.5)
			elif roll < 0.42:
				r["tgt"] = r["base"] * randf_range(0.3, 0.5)
				r["chg"] = randf_range(0.4, 0.8)
			else:
				r["tgt"] = r["base"] * randf_range(0.7, 1.4)
				r["chg"] = randf_range(0.5, 1.3)
		# a rider that never gives up must not keep speeding up for ever
		var mul = (
			1.0 + minf(r["age"], AGE_SPEED_CAP if r["limit"] >= NEVER_GIVES_UP else INF) * 0.08
		)
		r["spd"] += (r["tgt"] * mul - r["spd"]) * minf(1.0, dt * 3.0)
		move_rider(r, dt)  # riders keep circling: through the tunnel and round again
		if not r["entered"] and not r["hidden"]:
			r["entered"] = true
		r["wph"] += r["spd"] * dt / 0.34
		r["cph"] += dt * (6.0 + 0.444 * r["spd"])
		place_rider(r, sin(r["age"] * 10.0) * 0.015)
		Models.pose_rider(m, r["cph"], r["wph"])
		update_rider_sound(r)
		rider_collide(r)
		if r["wind_t"] > 0.0:
			r["wind_t"] -= dt
			if r["wind_t"] <= 0.0:
				g.phone_sys.launch_phone(r)
		elif r["can_throw"] and r["entered"] and not r["hidden"] and g.phones.size() < 3:
			r["throw_t"] -= dt
			if r["throw_t"] <= 0.0:
				# on open ground only with a clear line to the player (phones.gd, throw_clear)
				if (
					g.throw_cool <= 0.0
					and g.state == "play"
					and g.phone_sys.throw_clear(phone_origin(r))
				):
					g.phone_sys.start_throw(r)
				else:
					r["throw_t"] = 0.3
		if r["age"] > r["limit"]:
			r["mode"] = "away"
			if g.arena.rider_pursuit():
				# give up: swing round in the usual arc and ride out of the nearest gate
				r["away_gate"] = nearest_gate(r["pos"])
				r["away_left"] = away_distance(r)
			else:
				# give up: turn round at once towards the nearer seam and ride out through the tunnel
				var street_x = g.arena.to_track(r["pos"]).x
				r["dir"] = -1 if street_x < 0.0 else 1
				r["yaw"] = g.arena.yaw(street_x) + (0.0 if r["dir"] > 0 else PI)
				r["away_left"] = g.arena.exit_distance(r["pos"], r["dir"])
			place_rider(r, 0.0)
			g.sfx.play3d("whoosh", root.position)
	elif mode == "away":
		r["spd"] = minf(39.0, r["spd"] + 26.0 * dt)
		if g.arena.rider_pursuit():
			r["spd"] = minf(r["spd"], away_speed_cap(r))
		move_rider(r, dt)
		if g.arena.rider_pursuit():
			r["away_left"] = away_distance(r)
		else:
			r["away_left"] -= r["spd"] * dt
		r["wph"] += r["spd"] * dt / 0.34
		r["cph"] += dt * (6.0 + 0.444 * r["spd"])
		place_rider(r, 0.0)
		Models.pose_rider(m, r["cph"], r["wph"])
		update_rider_sound(r)
		rider_collide(r)
		if r["away_left"] <= 0.0:
			resolve(r, false)
	elif mode == "hit":
		r["t"] += dt
		m["pivot"].visible = (int(r["t"] * 30.0) % 2 == 1)
		if r["t"] > 0.3:
			m["pivot"].visible = true
			spawn_parts(r)
			r["mode"] = "fall"
			r["t"] = 0.0
	elif mode == "fall":
		r["t"] += dt
		var alive = 0
		for p in r["parts"]:
			if p["done"]:
				continue
			var node: Node3D = p["node"]
			var v: Vector3 = p["vel"]
			if not p["landed"]:
				v.y -= g.GRAVITY * dt
				node.position += v * dt
				node.rotation += p["av"] * dt
				if node.position.y <= p["floor"] and v.y < 0.0:
					node.position = Vector3(node.position.x, p["floor"], node.position.z)
					if absf(v.y) > 2.5:
						var k = clampf(absf(v.y) / 10.0, 0.2, 1.0)
						g.sfx.play3d(
							"land_s" if k < 0.4 else ("land_m" if k < 0.75 else "land_l"),
							node.position
						)
						v.y = -v.y * 0.3
						v.x *= 0.65
						v.z *= 0.65
						p["av"] = p["av"] * 0.5
					else:
						v.y = 0.0
						p["landed"] = true
			else:
				v.x *= maxf(0.0, 1.0 - 3.0 * dt)
				v.z *= maxf(0.0, 1.0 - 3.0 * dt)
				node.position += Vector3(v.x, 0.0, v.z) * dt
				var kk = minf(1.0, dt * 8.0)
				var rot: Vector3 = node.rotation
				rot.x = lerp_angle(rot.x, p["rest_x"], kk)
				rot.z = lerp_angle(rot.z, 0.0, kk)
				node.rotation = rot
				p["rest"] += dt
				if p["rest"] > 1.0:
					p["done"] = true
			p["vel"] = v
			node.position = g.arena.clamp_road(node.position)
			if r["t"] > 4.0:
				p["done"] = true
			if not p["done"]:
				alive += 1
		if alive == 0:
			resolve(r, true)


func hit_rider(r: Dictionary, dmg: int) -> void:
	r["hp"] -= dmg
	var wpos = r["pos"] + Vector3(0.0, 1.0, 0.0)
	if r["hp"] > 0:
		r["flash"] = 0.15
		g.set_flash(r["model"]["root"], true)
		g.sfx.play3d("thud", wpos)
		g.sfx.play3d("clank2", wpos)
		var arm = int(round(150.0 * (1.0 + 0.1 * (g.round_n - 1))))
		g.score += arm * (2 if g.hype_t > 0.0 else 1)
		g.hi_check()
		g.add_hype(6.0)
		g.add_popup(wpos + Vector3(0, 1.2, 0), "ARMOURED  %d LEFT" % r["hp"], g.WHITE, true)
		g.fx_sys.burst(wpos, 6, ["#f2b630"], 3.0, 0.3, 0.4, 0.06)
		return
	r["mode"] = "hit"
	r["t"] = 0.0
	r["wind_t"] = 0.0
	g.sfx.stop_loop(r["snd"])
	r["snd"] = null
	g.sfx.play3d("hit", wpos)
	g.shots_hit += 1
	g.kills += 1
	g.combo = mini(5, g.combo + 1)
	g.best_combo = maxi(g.best_combo, g.combo)
	var pts = int(
		round(
			500.0 * g.TYPES[r["type"]]["pts"] * g.LANE_MULT[r["ln"]] * (1.0 + 0.1 * (g.round_n - 1))
		)
	)
	pts *= g.combo
	if g.hype_t > 0.0:
		pts *= 2
	if g.melee:
		pts = int(round(pts * 1.5))
	pts = int(round(pts * g.shop_sys.style_mul()))
	g.score += pts
	g.hi_check()
	g.add_hype(10.0 + 3.0 * g.combo)
	g.cheer = maxf(g.cheer, 0.7 + 0.1 * g.combo)
	g.combo_shout()
	g.shop_sys.add_style(12.0 + (6.0 if g.melee else 0.0))
	g.shop_sys.add_cash(13 if r["type"] == "tough" else 5)
	g.hitstop = maxf(g.hitstop, 0.09 if g.melee else 0.04)
	g.pickup_sys.drop_kill(wpos + Vector3(0, 0.5, 0), r["type"] == "tough")
	var label = "+%d" % pts
	if g.combo > 1:
		label += "  x%d" % g.combo
	g.add_popup(wpos + Vector3(0, 1.0, 0), label, g.GOLD)
	g.add_popup(wpos + Vector3(0, 0.5, 0), "JOJ!", g.WHITE, true)
	g.fx_sys.burst(wpos, 10, ["#ff9a3a"], 4.0, 0.3, 0.5, 0.06)
	g.sfx.v_yelp(wpos)
	if randf() < 0.4:
		g.sfx.say("rider_hit")


func spawn_parts(r: Dictionary) -> void:
	var m = r["model"]
	var dirf = float(r["dir"])
	var sgn = 1.0 if randf() < 0.5 else -1.0
	r["parts"].append(
		detach_part(
			m["bike"],
			part_vel(
				r,
				dirf * r["spd"] * 0.45 + randf_range(-1.0, 1.0),
				randf_range(2.5, 4.0),
				randf_range(-1.5, 1.5)
			),
			Vector3(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0), randf_range(-6.0, 6.0)),
			0.09,
			sgn * PI * 0.5
		)
	)
	if r["type"] == "tough":
		# the armoured rider jumps off the bike and runs at you
		g.boss_sys.spawn_runner(r)
		var man: Node3D = m["man"]
		man.queue_free()
	else:
		r["parts"].append(
			detach_part(
				m["man"],
				part_vel(
					r,
					dirf * r["spd"] * 0.35 + randf_range(-1.5, 1.5),
					randf_range(4.0, 5.5),
					randf_range(-1.5, 1.5)
				),
				Vector3(randf_range(-5.0, 5.0), randf_range(-3.0, 3.0), randf_range(-5.0, 5.0)),
				0.2,
				-sgn * PI * 0.5
			)
		)


# velocity for a part that flies off a rider: vx along the rider's lane direction (positive is the way it was
# going when dir is +1, as the old street coordinates had it), vy up, vz sideways
func part_vel(r: Dictionary, vx: float, vy: float, vz: float) -> Vector3:
	var fwd = heading_vec(r["yaw"])
	var dirf = float(r["dir"])
	return fwd * dirf * vx + Vector3(0.0, vy, 0.0) + Vector3(-fwd.z, 0.0, fwd.x) * dirf * vz


func detach_part(
	node: Node3D, vel: Vector3, av: Vector3, floor_y: float, rest_x: float
) -> Dictionary:
	var gt = node.global_transform
	node.get_parent().remove_child(node)
	g.add_child(node)
	node.global_transform = gt
	return {
		"node": node,
		"vel": vel,
		"av": av,
		"floor": floor_y,
		"rest_x": rest_x,
		"landed": false,
		"rest": 0.0,
		"done": false
	}


func resolve(r: Dictionary, hit: bool) -> void:
	var i = g.riders.find(r)
	if i >= 0:
		g.riders.remove_at(i)
	g.free_rider(r)
	g.hits[r["idx"]] = hit
	if not hit:
		g.combo = 0
		g.wave_miss = true
		if randf() < 0.35:
			g.sfx.say("taunt")
	g.after_wave()
