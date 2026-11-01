extends RefCounted
# Phones: riders throwing phones at the player and the phones in flight.
# Shared game state stays on main.gd (g); this file holds the logic.

const Models = preload("res://scripts/models.gd")
const Util = preload("res://scripts/util.gd")
const Threats = preload("res://scripts/threats.gd")

# the height the sight line to the player ends at (a phone comes down about knee high, but below the lowest
# roof every height is blocked alike, so this only matters at a wall's edge)
const SIGHT_Y = 1.0

var g = null


func _init(game) -> void:
	g = game


func start_throw(r: Dictionary) -> void:
	r["wind_t"] = 0.5
	r["throw_t"] = randf_range(1.4, 2.6)
	g.throw_cool = 1.0
	g.sfx.say("phone_throw")


func launch_phone(r: Dictionary) -> void:
	if r["mode"] != "fly":
		return
	var origin: Vector3 = g.rider_sys.phone_origin(r)
	if not throw_clear(origin):
		# a building came between the wind-up and the throw: the rider holds it and tries again soon
		r["throw_t"] = 0.3
		return
	throw_phone(origin, r)


# On open ground a phone is only thrown when nothing solid is between the thrower and the player (the arena's
# ray_blocked along the line, Threats.sight_clear), the way a boss only starts a lunge with a clear line.
# The roundabout throws as it always did.
func throw_clear(start: Vector3) -> bool:
	if not g.arena.rider_pursuit():
		return true
	var tgt = Vector3(g.player.position.x, SIGHT_Y, g.player.position.z)
	return Threats.sight_clear(g.arena, start, tgt)


# src is whoever threw it (a rider or a boss): a deflected phone flies back to it
func throw_phone(start: Vector3, src, off: Vector3 = Vector3.ZERO) -> void:
	var target = Vector3(g.player.position.x + off.x, 0.45, g.player.position.z + off.z)
	var d = clampf(1.25 - g.round_n * 0.05, 0.75, 1.25)
	var node = Models.build_phone()
	g.add_child(node)
	node.position = start
	var ring = MeshInstance3D.new()
	ring.mesh = Util.torus_mesh(1.0, 1.12, 24, 4)
	var rmat = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.24, 0.16, 0.3)
	ring.material_override = rmat
	g.add_child(ring)
	ring.position = Vector3(target.x, 0.04, target.z)
	g.phones.append(
		{
			"node": node,
			"ring": ring,
			"rmat": rmat,
			"start": start,
			"target": target,
			"pos": start,
			"p": 0.0,
			"dur": d,
			"src": src,
			"ret": false,
			"chain": 0,
			"rspd": 0.0,
			"off": off,
			"rotv": Vector3(randf_range(-9.0, 9.0), randf_range(-9.0, 9.0), randf_range(-9.0, 9.0))
		}
	)
	g.sfx.play3d("throw", start)
	g.sfx.play3d("ring", start)


func update_phones(dt: float) -> void:
	for i in range(g.phones.size() - 1, -1, -1):
		var ph = g.phones[i]
		if ph["ret"]:
			g.combat_sys.update_returning_phone(ph, i, dt)
			continue
		ph["p"] += dt / ph["dur"]
		var p = minf(ph["p"], 1.0)
		var s: Vector3 = ph["start"]
		var tg: Vector3 = ph["target"]
		if ph["p"] < 0.6:  # it follows you (a little ahead of you) until the last moment
			var lead = Vector3(
				g.player.position.x + g.pvel.x * 0.35 + ph["off"].x,
				0.45,
				g.player.position.z + g.pvel.z * 0.35 + ph["off"].z
			)
			tg = tg.lerp(lead, minf(1.0, dt * 5.0))
			ph["target"] = tg
			var rg: MeshInstance3D = ph["ring"]
			rg.position = Vector3(tg.x, 0.04, tg.z)
		var pos = Vector3(
			lerpf(s.x, tg.x, p),
			lerpf(s.y, tg.y, pow(p, 1.35)) + sin(p * PI) * 0.9,
			lerpf(s.z, tg.z, p)
		)
		var prev: Vector3 = ph["pos"]
		if g.arena.rider_pursuit() and flight_blocked(prev, pos):
			wall_smash(ph, i, prev)
			continue
		ph["pos"] = pos
		var node: Node3D = ph["node"]
		node.position = pos
		node.rotation += ph["rotv"] * dt
		var rm: StandardMaterial3D = ph["rmat"]
		rm.albedo_color = Color(1.0, 0.24, 0.16, 0.4 + 0.45 * minf(1.0, ph["p"]))
		if ph["p"] >= 1.0:
			g.phones.remove_at(i)
			var near = (
				Vector2(tg.x - g.player.position.x, tg.z - g.player.position.z).length() < 1.5
				and not g.player_sys.is_hurdling()
			)  # jumped over it: it smashes on the ground below
			g.fx_sys.plastic_burst(Vector3(tg.x, 0.4, tg.z))
			if near:
				g.free_phone(ph)
				g.damage_player("MISSED CALL", "phone")
				if g.state != "play":
					return
			else:
				g.add_popup(Vector3(tg.x, 1.4, tg.z), "DODGED!", g.GOLD)
				g.sfx.play3d("phone_smash", tg)
				g.free_phone(ph)


# true if a phone moving from prev to pos meets a building, a tree or a lamp (open ground only: the caller checks the arena)
func flight_blocked(prev: Vector3, pos: Vector3) -> bool:
	var d = pos - prev
	var dist = d.length()
	# a trunk or a pole is thinner than the step of one frame: cut the whole step
	if dist > 0.0001 and g.arena.tree_hit(prev, d / dist, dist) >= 0.0:
		return true
	return g.arena.ray_blocked(pos) or not Threats.sight_clear(g.arena, prev, pos)


# a phone that meets a building smashes against it, at the last clear point: no hit, no "dodged" popup and no score
func wall_smash(ph: Dictionary, i: int, at: Vector3) -> void:
	g.phones.remove_at(i)
	g.fx_sys.plastic_burst(at)
	g.sfx.play3d("phone_smash", at)
	g.free_phone(ph)


func shoot_phone(ph: Dictionary) -> void:
	var i = g.phones.find(ph)
	if i >= 0:
		g.phones.remove_at(i)
	g.fx_sys.plastic_burst(ph["pos"])
	g.sfx.play3d("phone_smash", ph["pos"])
	g.score += 150
	g.hi_check()
	g.add_popup(ph["pos"] + Vector3(0, 0.6, 0), "+150", g.GOLD)
	g.free_phone(ph)
