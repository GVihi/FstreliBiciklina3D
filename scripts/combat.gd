extends RefCounted
# Combat: shotgun and reload, melee swing, deflecting phones and the dart projectiles.
# Shared game state stays on main.gd (g); this file holds the logic.

const Util = preload("res://scripts/util.gd")

var g = null
var dart_pool = []
var dart_scene = null  # the dart model, loaded the first time a dart is made

const DART_MODEL_GLB = true  # Milestone F2: darts use assets/models/dart.glb; false = the old box and ball
const DART_MODEL_PATH = "res://assets/models/dart.glb"


func _init(game) -> void:
	g = game


# ================================================================== shotgun + melee
func reload_step() -> float:
	var w = g.WEAPONS["dart_gun"]
	return (
		float(w["reload_step"]) * (1.0 - float(w["reload_cut_per_level"]) * float(g.up["reload"]))
	)


func start_load() -> void:
	if g.state != "play" or g.loading or g.shells >= g.MAXSHELLS:
		return
	g.loading = true
	g.load_t = reload_step() + float(g.WEAPONS["dart_gun"]["reload_extra"])


func ray_dir_with_spread() -> Vector3:
	var sp = deg_to_rad(g.spread_deg)
	var a = randf() * TAU
	var rr = sqrt(randf()) * sp
	var local = Vector3(sin(rr) * cos(a), sin(rr) * sin(a), -cos(rr))
	return (g.cam.global_transform.basis * local).normalized()


func fire() -> void:
	if g.state != "play" or g.paused:
		return
	if g.melee:
		swing()
		return
	if g.pump_t > 0.0:
		return
	if g.shells <= 0 and g.buffs["rapid"] <= 0.0 and g.free_shots <= 0:
		g.sfx.play("click")
		start_load()
		return
	g.loading = false
	if g.buffs["rapid"] <= 0.0:
		if g.free_shots > 0:
			g.free_shots -= 1
		else:
			g.shells -= 1
	var dart_dmg = int(g.WEAPONS["dart_gun"]["damage"])
	var lastshot = g.perks.has("lastshell") and g.shells == 0 and g.buffs["rapid"] <= 0.0
	g.pump_dur = g.player_sys.cur_pump()
	g.pump_t = g.pump_dur
	g.pump_fired = false
	g.recoil = 1.0
	g.flash = 0.07
	g.shake = 0.15
	g.shots_fired += 1
	g.sfx.play("shot")
	g.pitch = clampf(g.pitch + deg_to_rad(0.7 * (1.0 - 0.5 * g.ads_t)), -1.45, 1.45)

	var dir = ray_dir_with_spread()
	var org = g.cam.global_position
	g.bloom = minf(
		g.bloom + float(g.WEAPONS["dart_gun"]["bloom_per_shot"]),
		float(g.WEAPONS["dart_gun"]["bloom_max"])
	)
	var ex = g.player_sys.ex_bonus()

	# how far can the dart travel before hitting the world?
	var t_world = float(g.WEAPONS["dart_gun"]["range"])
	var world_kind = ""
	if dir.y < -0.0001:
		var tf = -org.y / dir.y
		if tf > 0.0 and tf < t_world:
			t_world = tf
			world_kind = "floor"
	var ts = 0.5  # fountain, planter and tunnel block
	while ts < t_world:
		if g.ray_blocked(org + dir * ts):
			t_world = ts
			world_kind = "wall"
			break
		ts += 0.5
	var tfac = g.arena.ray_exit_circle(org, dir, g.arena.FACADE_RHO)  # buildings all around
	if tfac > 0.0 and tfac < t_world:
		t_world = tfac
		world_kind = "wall"

	# nearest target of every kind
	var best_t = 1000.0
	var best_kind = ""
	var best_obj = null
	for pk in g.pickups:
		var tp = Util.ray_ellipsoid(org, dir, pk["pos"], Vector3(0.6 + ex, 0.6 + ex, 0.6 + ex))
		if tp > 0.0 and tp < best_t:
			best_t = tp
			best_kind = "pickup"
			best_obj = pk
	for ph in g.phones:
		if ph["ret"]:
			continue
		var tph = Util.ray_ellipsoid(org, dir, ph["pos"], Vector3(0.5 + ex, 0.4 + ex, 0.5 + ex))
		if tph > 0.0 and tph < best_t:
			best_t = tph
			best_kind = "phone"
			best_obj = ph
	for b in g.bosses:
		if not g.boss_sys.boss_hittable(b):
			continue
		var inf = g.BOSS_INFO[b["kind"]]
		var br: Vector3 = inf["r"]
		var tb2 = Util.ray_ellipsoid_yaw(
			org,
			dir,
			g.tw3(b["x"], inf["cy"], b["z"]),
			br + Vector3(ex, ex, ex),
			g.arena.yaw(b["x"])
		)
		if tb2 > 0.0 and tb2 < best_t:
			best_t = tb2
			best_kind = "boss"
			best_obj = b
	for r in g.riders:
		if (r["mode"] != "fly" and r["mode"] != "away") or g.arena.hidden(r["x"]):
			continue
		var c = g.tw3(r["x"], 0.95, g.LANE_Z[r["ln"]])
		var t = Util.ray_ellipsoid_yaw(
			org, dir, c, Vector3(1.3 + ex, 1.0 + ex, 0.55 + ex), g.arena.yaw(r["x"])
		)
		if t > 0.0 and t < best_t:
			best_t = t
			best_kind = "rider"
			best_obj = r
	for c2 in g.civs:
		if c2["state"] != "walk" or g.arena.hidden(c2["x"]):
			continue
		var s = c2["scale"]
		var ctr = g.tw3(c2["x"], 0.95 * s, c2["z"])
		var t2 = Util.ray_ellipsoid(org, dir, ctr, Vector3(0.55 * s, 1.0 * s, 0.55 * s))
		if t2 > 0.0 and t2 < best_t:
			best_t = t2
			best_kind = "civ"
			best_obj = c2

	var end_pt: Vector3
	var stick = false
	var target_hit = best_kind != "" and best_t < t_world
	if target_hit:
		end_pt = org + dir * best_t
	else:
		end_pt = org + dir * t_world
		stick = (world_kind == "floor")

	var muzzle_pt: Vector3 = g.gun["muzzle"].global_position
	if g.viewmodel != null:
		muzzle_pt = g.viewmodel.muzzle_point(g.gun["muzzle"])
	spawn_dart(muzzle_pt, end_pt, stick)

	# near-miss reaction for pedestrians (not the one we hit)
	for c3 in g.civs:
		if c3["state"] != "walk" or c3 == best_obj or c3["flinch"] > 0.0 or g.arena.hidden(c3["x"]):
			continue
		var to = g.tw3(c3["x"], 0.9, c3["z"]) - org
		var proj = to.dot(dir)
		if proj > 0.0 and proj < 45.0:
			var perp = (to - dir * proj).length()
			if perp < 1.5:
				c3["flinch"] = 0.6
				var cp = g.tw3(c3["x"], 1.2, c3["z"])
				g.sfx.v_gasp(cp)
				g.add_popup(g.tw3(c3["x"], 2.0, c3["z"]), "JOJ!", g.WHITE, true)

	if target_hit:
		if best_kind == "rider":
			g.rider_sys.hit_rider(best_obj, dart_dmg * (2 if lastshot else 1))
		elif best_kind == "civ":
			g.civ_sys.hit_civ(best_obj)
		elif best_kind == "boss":
			var hit_y = (org + dir * best_t).y
			var bo = best_obj
			var is_weak = (
				hit_y >= float(g.BOSS_INFO[bo["kind"]]["weak_y"]) + g.boss_sys.boss_hover(bo)
			)
			g.boss_sys.hit_boss(
				bo, dart_dmg * (2 if lastshot else 1), is_weak, 30.0 if is_weak else 14.0
			)
		elif best_kind == "phone":
			g.phone_sys.shoot_phone(best_obj)
		elif best_kind == "pickup":
			g.pickup_sys.collect_pickup(best_obj)
	else:
		if world_kind == "floor":
			for i in range(3):
				g.fx_sys.spawn_particle(
					end_pt,
					Vector3(randf_range(-0.8, 0.8), randf_range(0.6, 1.6), randf_range(-0.8, 0.8)),
					0.4,
					g.mat_dust,
					Vector3(0.05, 0.05, 0.05),
					4.0
				)
		elif world_kind == "wall":
			for i in range(5):
				g.fx_sys.spawn_particle(
					end_pt,
					Vector3(randf_range(-2.0, 2.0), randf_range(0.5, 2.5), randf_range(-2.0, 2.0)),
					0.3,
					g.mat_spark,
					Vector3(0.04, 0.04, 0.04),
					8.0
				)


# --- melee: a giant gummy worm swung at whatever is close to the player
func swing_zone() -> Dictionary:
	var f = -g.player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var m = g.WEAPONS["melee"]
	var fwd = float(m["zone_forward"])
	var c = Vector3(g.player.position.x + f.x * fwd, 1.0, g.player.position.z + f.z * fwd)
	return {"c": c, "r": float(m["zone_radius"]) + g.up["rubber"] * float(m["reach_per_level"])}


func flat_dist(a: Vector3, bx: float, bz: float) -> float:
	return Vector2(a.x - bx, a.z - bz).length()


func swing() -> void:
	if g.swing_cd > 0.0:
		return
	g.swing_cd = float(g.WEAPONS["melee"]["cooldown"])
	g.swing_t = float(g.WEAPONS["melee"]["swing_time"])
	g.swing_dir = -g.swing_dir
	g.shots_fired += 1
	g.sfx.play("swing")
	var z = swing_zone()
	var zc: Vector3 = z["c"]
	var zr: float = z["r"]
	var hit_any = deflect_scan()
	for i in range(g.pickups.size() - 1, -1, -1):
		if zc.distance_to(g.pickups[i]["pos"]) < zr * 0.8 + 0.6:
			g.pickup_sys.collect_pickup(g.pickups[i])
	for i in range(g.bosses.size() - 1, -1, -1):
		var b = g.bosses[i]
		if not g.boss_sys.boss_hittable(b):
			continue
		var inf = g.BOSS_INFO[b["kind"]]
		var br: Vector3 = inf["r"]
		if flat_dist_v(zc, g.boss_world(b, 0.0)) < zr * 0.8 + br.x:
			g.boss_sys.hit_boss(b, int(g.WEAPONS["melee"]["damage"]), false, 45.0)
			hit_any = true
	for i in range(g.riders.size() - 1, -1, -1):
		var r = g.riders[i]
		if r["mode"] != "fly" and r["mode"] != "away":
			continue
		if not g.arena.hidden(r["x"]) and flat_dist_v(zc, g.rider_world(r, 0.0)) < zr * 0.8 + 0.9:
			g.rider_sys.hit_rider(r, int(g.WEAPONS["melee"]["damage"]))
			hit_any = true
	if hit_any:
		g.sfx.play3d("rubber", zc)
		g.shake = 0.35
		g.hitstop = maxf(g.hitstop, 0.06)
		g.fx_sys.jelly_burst(zc + Vector3(0, 0.3, 0))
		g.player_sys.jelly_kick(16.0, 0.6)  # the club shudders on impact


# --- deflect: a thrown phone that is close when the rubber swings goes straight back at whoever threw it
func deflect_range() -> float:
	return (
		float(g.WEAPONS["melee"]["deflect_range"])
		+ g.up["rubber"] * float(g.WEAPONS["melee"]["reach_per_level"])
	)


func deflect_scan() -> bool:
	var any = false
	for ph in g.phones:
		if ph["ret"]:
			continue
		var pp: Vector3 = ph["pos"]
		var d = Vector2(pp.x - g.player.position.x, pp.z - g.player.position.z).length()
		if d <= deflect_range() and pp.y < 2.6:
			deflect_phone(ph)
			any = true
	return any


func deflect_phone(ph: Dictionary) -> void:
	ph["ret"] = true
	ph["chain"] = 2 if g.perks.has("boomerang") else 0
	if g.shop_sys.has_duo("RICOCHET"):
		ph["chain"] = 4
	if g.perks.has("counter"):
		g.shells = mini(g.MAXSHELLS, g.shells + 1)
	ph["rspd"] = 14.0
	var ring_node: Node3D = ph["ring"]
	ring_node.visible = false
	g.hitstop = maxf(g.hitstop, 0.08)
	g.shake = 0.3
	g.sfx.play3d("rubber", ph["pos"])
	g.add_popup(ph["pos"] + Vector3(0, 0.6, 0), "DEFLECTED!", g.PINK, true)
	g.fx_sys.deflect_burst(ph["pos"])
	g.player_sys.jelly_kick(26.0, 1.0)  # a deflect is a harder hit: bigger shudder and a white flash
	g.shop_sys.add_style(12.0)


func target_valid(t) -> bool:
	if t == null:
		return false
	if t.get("gone", false):
		return false
	if t.has("ln"):
		return t["mode"] == "fly" or t["mode"] == "away"
	return g.boss_sys.boss_hittable(t)


func target_pos(t) -> Vector3:
	if t.has("ln"):
		return g.tw3(t["x"], 1.1, g.LANE_Z[t["ln"]])
	return g.tw3(t["x"], float(g.BOSS_INFO[t["kind"]]["cy"]) + 0.4, t["z"])


func nearest_target(from: Vector3, skip):
	var best = null
	var bd = 1.0e9
	for r in g.riders:
		if target_valid(r) and not is_same(r, skip):
			var d = target_pos(r).distance_to(from)
			if d < bd:
				bd = d
				best = r
	for b in g.bosses:
		if target_valid(b) and not is_same(b, skip):
			var d2 = target_pos(b).distance_to(from)
			if d2 < bd:
				bd = d2
				best = b
	return best


func update_returning_phone(ph: Dictionary, i: int, dt: float) -> void:
	var tgt = ph["src"]
	if not target_valid(tgt):
		tgt = nearest_target(ph["pos"], null)
		ph["src"] = tgt
	if tgt == null:
		g.phones.remove_at(i)
		g.fx_sys.plastic_burst(ph["pos"])
		g.sfx.play3d("phone_smash", ph["pos"])
		g.free_phone(ph)
		return
	var tp = target_pos(tgt)
	var pos: Vector3 = ph["pos"]
	var dv = tp - pos
	var dist = dv.length()
	ph["rspd"] = minf(34.0, ph["rspd"] + 60.0 * dt)
	var step = ph["rspd"] * dt
	if dist <= 1.0 or step >= dist:
		strike_with_phone(ph, i, tgt)
		return
	pos += dv / dist * step
	ph["pos"] = pos
	var node: Node3D = ph["node"]
	node.position = pos
	node.rotation += ph["rotv"] * dt * 2.0
	if randf() < dt * 40.0:
		g.fx_sys.return_trail(pos)  # a pink and gold trail shows the phone is on its way back


func strike_with_phone(ph: Dictionary, i: int, tgt) -> void:
	var tp = target_pos(tgt)
	g.fx_sys.plastic_burst(tp)
	g.fx_sys.deflect_burst(tp)
	g.shake = maxf(g.shake, 0.5)
	g.sfx.play3d("phone_smash", tp)
	if tgt.has("ln"):
		g.rider_sys.hit_rider(tgt, 99)
	else:
		g.boss_sys.hit_boss(tgt, 3, false, 100.0)
	g.hitstop = 0.12
	var v = int(800 * (2 if g.hype_t > 0.0 else 1) * g.shop_sys.style_mul())
	g.score += v
	g.hi_check()
	g.add_popup(tp + Vector3(0, 1.4, 0), "RETURN TO SENDER +%d" % v, g.GOLD)
	g.shop_sys.add_cash(36 if g.shop_sys.has_duo("BOUNTY HUNTER") else 12)
	g.shop_sys.add_style(25.0)
	if ph["chain"] > 0:
		var nxt = nearest_target(tp, tgt)
		if nxt != null:
			ph["chain"] -= 1
			ph["src"] = nxt
			ph["rspd"] = 20.0
			return
	g.phones.remove_at(i)
	g.free_phone(ph)


func flat_dist_v(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


# ================================================================== darts + particles
# Darts and particles are recycled instead of created and freed, so a shot or a burst costs no allocations.


func release_dart(node: Node3D) -> void:
	node.visible = false
	dart_pool.append(node)


# a fresh copy of the modelled dart, or null when the model is switched off or missing
func dart_model() -> Node3D:
	if not DART_MODEL_GLB:
		return null
	if dart_scene == null:
		if not ResourceLoader.exists(DART_MODEL_PATH):
			return null
		dart_scene = load(DART_MODEL_PATH)
	if not (dart_scene is PackedScene):
		return null
	return dart_scene.instantiate() as Node3D


func spawn_dart(a: Vector3, b: Vector3, stick: bool) -> void:
	var node: Node3D
	if dart_pool.size() > 0:
		node = dart_pool.pop_back()
		node.visible = true
		node.rotation = Vector3.ZERO
	else:
		node = Node3D.new()
		var model = dart_model()
		if model != null:
			node.add_child(model)  # the model's tip points to -Z, the way look_at aims
		else:
			Util.box(node, Vector3(0.025, 0.025, 0.16), Vector3.ZERO, g.mat_dart)
			Util.sphere(node, 0.022, Vector3(0, 0, -0.09), g.mat_tip)
		Util.trim_shadows(node, 1.0)
		g.add_child(node)
	node.position = a
	if a.distance_to(b) > 0.1:
		var dirn = (b - a).normalized()
		var upv = Vector3.UP
		if absf(dirn.y) > 0.98:
			upv = Vector3.RIGHT
		node.look_at(b, upv)
	var dur = clampf(a.distance_to(b) / 120.0, 0.03, 0.4)
	g.darts.append({"node": node, "a": a, "b": b, "t": 0.0, "max": dur, "stick": stick})
	while g.darts.size() > 80:
		release_dart(g.darts[0]["node"])
		g.darts.remove_at(0)


func update_darts(dt: float) -> void:
	for i in range(g.darts.size() - 1, -1, -1):
		var d = g.darts[i]
		d["t"] += dt
		var node: Node3D = d["node"]
		if d["t"] < d["max"]:
			node.position = d["a"].lerp(d["b"], d["t"] / d["max"])
		else:
			node.position = d["b"]
			if (not d["stick"]) or d["t"] > d["max"] + 4.0:
				release_dart(node)
				g.darts.remove_at(i)
