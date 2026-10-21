extends RefCounted
# Bosses: spawning, telegraphed attacks, weak points, phases and defeat.
# Shared game state stays on main.gd (g); this file holds the logic.

const Models = preload("res://scripts/models.gd")
const Util = preload("res://scripts/util.gd")

var g = null


func _init(game) -> void:
	g = game


# ================================================================== bosses
func make_strip() -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = Util.box_mesh(Vector3(1.0, 0.02, 1.0))
	mi.material_override = g.strip_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	g.add_child(mi)
	return mi


# the red circle on the ground that shows how far a slam reaches
func make_disc() -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var cm = CylinderMesh.new()
	cm.top_radius = 1.0
	cm.bottom_radius = 1.0
	cm.height = 0.02
	cm.radial_segments = 40
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = g.disc_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	g.add_child(mi)
	return mi


# bosses get tougher every round: 32% more health per round after the second
func boss_hp(base: int) -> int:
	return int(round(float(base) * (1.0 + 0.32 * float(maxi(0, g.round_n - 2)))))


func make_boss_dict(
	kind: String, nm: String, variant: int, hp: int, m: Dictionary, wp: Vector3, mode: String
) -> Dictionary:
	var t = g.arena.to_track(wp)
	return {
		"kind": kind,
		"name": nm,
		"variant": variant,
		"hp": hp,
		"max_hp": hp,
		"p": 0.7,
		"wp": wp,
		"x": t.x,
		"z": t.y,
		"wyaw": 0.0,
		"mode": mode,
		"flash": 0.0,
		"t": 0.0,
		"ph": 0.0,
		"snd": null,
		"step_t": 0.0,
		"intro": 0.0,
		"die_t": 0.0,
		"model": m,
		"gone": false,
		"phase": 1,
		"stagger": 0.0,
		"stagger_t": 0.0,
		"crashed": false,
		"tele_t": 0.0,
		"tele_total": 1.0,
		"lock": wp,
		"ldir": Vector3(0, 0, 1),
		"llen": 0.0,
		"lgo": 0.0,
		"lcrash": false,
		"lhit": false,
		"chase_t": 0.0,
		"throw_t": 2.0,
		"pat": "lunge",
		"combo": 0,
		"slam_r": 4.5,
		"disc": make_disc(),
		"strip": make_strip()
	}


# extra health of the final boss on top of the normal per-round growth
const FINAL_HP_MUL = 1.3


func spawn_boss() -> void:
	var final = g.is_final_round()
	var kind = g.BOSS_KINDS[
		(g.round_n + g.boss_count + g.seed_shift(g.BOSS_KINDS.size())) % g.BOSS_KINDS.size()
	]
	var variant = (g.round_n + g.boss_count) % 2
	if final:
		kind = "minister"  # the golden president is the final boss
		variant = 1
	var info = g.BOSS_INFO[kind]
	var nm = info["name"]
	if kind == "minister" and variant == 1:
		nm = "PREDSEDNIK POZLATA"
	var hp = boss_hp(int(info["hp"]))
	if final:
		hp = int(round(float(hp) * FINAL_HP_MUL))
	var m = Models.build_boss(kind, variant, Models.kit_of(0))
	g.add_child(m["root"])
	var sx = clampf(g.ptx() + randf_range(-14.0, 14.0), -g.arena.lim(), g.arena.lim())
	var b = make_boss_dict(kind, nm, variant, hp, m, g.arena.tw(sx, -11.6), "charge")
	b["intro"] = 2.2
	b["final"] = final
	if final:
		b["intro"] = 3.2
	b["wyaw"] = atan2(g.player.position.x - b["wp"].x, g.player.position.z - b["wp"].z)
	g.bosses.append(b)
	g.boss_count += 1
	g.wave_miss = false
	start_boss_sound(b)
	g.sfx.play("boss_intro")
	g.sfx.say(info["voice"])
	pose_boss(b, 0.0)


func spawn_runner(r: Dictionary) -> void:
	var hp = (3 if r["max_hp"] > 2 else 2) + int(floor(float(maxi(0, g.round_n - 2)) / 2.0))
	var m = Models.build_boss("runner", 0, r["kit"])
	g.add_child(m["root"])
	var b = make_boss_dict("runner", "ANGRY CYCLIST", 0, hp, m, g.rider_world(r, 0.0), "charge")
	b["wyaw"] = atan2(g.player.position.x - b["wp"].x, g.player.position.z - b["wp"].z)
	g.bosses.append(b)
	g.wave_miss = false
	g.sfx.say("boss_revenge")
	pose_boss(b, 0.0)


func start_boss_sound(b: Dictionary) -> void:
	var root: Node3D = b["model"]["root"]
	if b["kind"] == "mower":
		b["snd"] = g.sfx.make_loop("loop_mower", root, Vector3(0, 0.5, 0))
	elif b["kind"] == "wifi":
		b["snd"] = g.sfx.make_loop("loop_wifi", root, Vector3(0, 1.0, 0))


func update_boss_sound(b: Dictionary) -> void:
	if b["snd"] == null:
		return
	var k = minf(1.2, b["p"])
	if b["kind"] == "mower":
		g.sfx.set_loop(b["snd"], (0.03 + 0.11 * k) * 1.6, (80.0 + 180.0 * k) / 80.0)
	else:
		g.sfx.set_loop(b["snd"], (0.012 + 0.05 * k) * 1.6, (700.0 + 500.0 * k) / 880.0)


func stop_boss_sound(b: Dictionary) -> void:
	g.sfx.stop_loop(b["snd"])
	b["snd"] = null


func boss_hover(b: Dictionary) -> float:
	if b["kind"] == "wifi":
		return 0.3 + sin(b["ph"] * 0.6) * 0.12
	return 0.0


func weak_point_y(b: Dictionary) -> float:
	return float(g.BOSS_INFO[b["kind"]]["wk"]) + boss_hover(b)


# the weak spot only does double damage while the boss is winding up an attack or dizzy; otherwise it is armour
func weak_open(b: Dictionary) -> bool:
	if b["kind"] == "runner":
		return true
	return b["mode"] == "stagger" or b["mode"] == "tele"


func boss_hittable(b: Dictionary) -> bool:
	return not b["gone"] and b["mode"] != "dying"


func pose_boss(b: Dictionary, dt: float) -> void:
	var m = b["model"]
	var root: Node3D = m["root"]
	var kind = b["kind"]
	var mode = b["mode"]
	var hover = boss_hover(b)
	var off = Vector3.ZERO
	if mode == "tele":
		off = Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.07
	var bwp: Vector3 = b["wp"]
	if mode == "stagger":
		b["wyaw"] = atan2(g.player.position.x - bwp.x, g.player.position.z - bwp.z)
	var fy = b["wyaw"]
	root.position = Vector3(bwp.x, hover, bwp.z) + off
	root.rotation = Vector3(0.0, fy, 0.0)
	if mode == "stagger":
		root.rotation = Vector3(-0.3 + sin(b["t"] * 16.0) * 0.06, fy, 0.0)
	var sc = 1.0
	if mode == "dying":
		sc = maxf(0.02, 1.0 - b["die_t"] / 0.9)
		root.rotation = Vector3(0.0, fy, sin(b["die_t"] * 20.0) * 0.1)
	root.scale = Vector3(sc, sc, sc)
	if m["fighter"]:
		Models.pose_fighter(m, b["ph"] * (1.2 if kind == "runner" else 1.0))
	elif kind == "mower":
		var blade: Node3D = m["spin"]
		blade.rotation.y += dt * 25.0
		var em: StandardMaterial3D = m["eyes"]
		em.emission_energy_multiplier = 1.5 + 1.5 * sin(b["ph"] * 2.0)
	else:
		var em2: StandardMaterial3D = m["eyes"]
		em2.emission_energy_multiplier = 1.5 + 1.5 * sin(b["ph"] * 2.0)


func remove_boss(b: Dictionary) -> void:
	var i = g.bosses.find(b)
	if i >= 0:
		g.bosses.remove_at(i)
	g.free_boss(b)


func boss_phase(b: Dictionary) -> int:
	var f = float(b["hp"]) / float(b["max_hp"])
	if f <= 0.34:
		return 3
	if f <= 0.67:
		return 2
	return 1


# how long a boss chases before it commits to a lunge
func tele_wait(b: Dictionary) -> float:
	var w = [2.6, 2.1, 1.7][b["phase"] - 1]
	if b["kind"] == "runner":
		w *= 0.6
	if b.get("final", false):
		w *= 0.85
	return w * clampf(1.0 - 0.04 * float(g.round_n - 2), 0.65, 1.0)


func boss_speed(b: Dictionary) -> float:
	var v = (
		float(g.BOSS_INFO[b["kind"]]["speed"])
		* (1.0 + 0.10 * float(b["phase"] - 1))
		* (1.0 + 0.03 * float(g.round_n - 1))
	)
	if b["intro"] > 0.0:
		v *= 0.5
	return minf(v, 6.2 if b["kind"] == "runner" else 5.5)  # never faster than your sprint (5.8): running away always works


func lunge_speed(b: Dictionary) -> float:
	return (
		(13.0 if b["kind"] == "runner" else 15.0)
		* (1.0 + 0.12 * float(b["phase"] - 1))
		* (1.0 + 0.03 * float(maxi(0, g.round_n - 2)))
	)


func set_boss_pos(b: Dictionary, wp: Vector3) -> void:
	wp = g.clamp_walk(Vector3(wp.x, 0.0, wp.z), "boss")
	b["wp"] = wp
	var t = g.arena.to_track(wp)  # the rest of the game reads the street coordinates
	b["x"] = t.x
	b["z"] = t.y


# things a lunging boss crashes into: the fountain, the buildings, the tunnel / planter wedge
func obstacle_at(p: Vector3) -> bool:
	return g.arena.obstacle_at(p)


# how far a lunge from wp along d actually goes (x), and whether it ends in a crash (y = 1)
func lunge_probe(wp: Vector3, d: Vector3, want: float) -> Vector2:
	var l = 0.0
	while l < want:
		l = minf(l + 0.4, want)
		if obstacle_at(wp + d * l):
			return Vector2(l, 1.0)
	return Vector2(want, 0.0)


func lunge_dir(b: Dictionary) -> Vector3:
	var wp: Vector3 = b["wp"]
	var lk: Vector3 = b["lock"]
	var d = Vector3(lk.x - wp.x, 0.0, lk.z - wp.z)
	if d.length() < 0.2:
		d = Vector3(g.player.position.x - wp.x, 0.0, g.player.position.z - wp.z)
	if d.length() < 0.01:
		return Vector3(0, 0, 1)
	return d.normalized()


func hide_strip(b: Dictionary) -> void:
	var strip: MeshInstance3D = b["strip"]
	strip.visible = false
	var disc: MeshInstance3D = b["disc"]
	disc.visible = false


# the red lane on the ground that shows where the lunge will go
func update_strip(b: Dictionary, locked: bool) -> void:
	var strip: MeshInstance3D = b["strip"]
	var wp: Vector3 = b["wp"]
	var d: Vector3
	var length: float
	if b["mode"] == "lunge":
		d = b["ldir"]
		length = b["llen"] - b["lgo"]
	else:
		d = lunge_dir(b)
		var lk: Vector3 = b["lock"]
		var want = Vector2(lk.x - wp.x, lk.z - wp.z).length() + 6.0
		length = lunge_probe(wp, d, want).x
	if length < 0.3:
		strip.visible = false
		return
	var wa = Vector3(wp.x, 0.035, wp.z)
	var we = wa + d * length
	var wv = we - wa
	var ln = Vector2(wv.x, wv.z).length()
	strip.visible = true
	strip.position = (wa + we) * 0.5
	strip.rotation = Vector3(0.0, atan2(-wv.z, wv.x), 0.0)
	var wd = 1.3 if b["kind"] == "runner" else 2.0
	strip.scale = Vector3(ln, 1.0, wd)
	var c = g.STRIP_COL_LOCK if locked else g.STRIP_COL_WARN
	c.a = c.a * (0.7 + 0.3 * sin(g.time * 24.0)) if locked else c.a
	g.strip_mat.albedo_color = c


func boss_flat_dist(b: Dictionary) -> float:
	var wp: Vector3 = b["wp"]
	return Vector2(g.player.position.x - wp.x, g.player.position.z - wp.z).length()


func slam_radius(b: Dictionary) -> float:
	return clampf(4.2 + 0.2 * float(g.round_n), 4.4, 5.6) + (0.4 if b["phase"] >= 3 else 0.0)


# what the boss does next. Later phases and later rounds unlock more:
#   lunge  - the straight dash you already know
#   combo  - two or three dashes in a row, each one re-aimed at you
#   slam   - stops and slams the ground: everything inside the red circle gets hit (dash through it, or run)
#   volley - throws a fan of phones (not the mower)
func boss_pick_pattern(b: Dictionary) -> String:
	var k = b["kind"]
	var ph = b["phase"]
	var w = {}
	if k == "runner":
		w["lunge"] = 10.0
		if g.round_n >= 4:
			w["combo"] = 4.0
	else:
		w["lunge"] = maxf(2.0, [10.0, 5.0, 3.0][ph - 1] - 0.4 * float(g.round_n - 2))
		if (ph >= 2 or g.round_n >= 4) and boss_flat_dist(b) < slam_radius(b) + 4.0:
			w["slam"] = 3.0 + 1.5 * float(ph)
		if ph >= 2:
			w["combo"] = 2.0 + 2.0 * float(ph - 1)
			if k != "mower" and g.phones.size() <= 1:
				w["volley"] = 1.5 + 1.5 * float(ph - 1)
	var total = 0.0
	for key in w.keys():
		total += w[key]
	var roll = randf() * total
	for key in w.keys():
		roll -= w[key]
		if roll <= 0.0:
			return key
	return "lunge"


func start_tele(b: Dictionary, quick: bool = false) -> void:
	var runner = b["kind"] == "runner"
	b["mode"] = "tele"
	var pat = "lunge"
	if not quick:
		pat = boss_pick_pattern(b)
		if pat == "combo":
			pat = "lunge"
			b["combo"] = (
				1 + (1 if (b["phase"] >= 3 or g.round_n >= 5 or (runner and g.round_n >= 6)) else 0)
			)
			g.add_popup(g.tw3(b["x"], 2.2, b["z"]), "COMBO!", g.RED)
		else:
			b["combo"] = 0
	b["pat"] = pat
	var t = 0.7 if runner else [0.9, 0.75, 0.6][b["phase"] - 1]
	if quick:
		t = 0.34 if runner else 0.42
	elif pat == "slam":
		t = clampf(1.05 - 0.05 * float(g.round_n), 0.7, 1.05)
		b["slam_r"] = slam_radius(b)
	elif pat == "volley":
		t = 0.8
	b["tele_t"] = t
	b["tele_total"] = t
	b["lock"] = g.player.position
	g.sfx.play3d("ring", g.tw3(b["x"], 1.0, b["z"]), -3.0)


func start_stagger(b: Dictionary, t: float, crashed: bool) -> void:
	hide_strip(b)
	if b["kind"] != "runner":
		t *= clampf(1.0 - 0.06 * float(g.round_n - 2), 0.6, 1.0)  # the dizzy window shrinks every round
	b["combo"] = 0
	b["pat"] = "lunge"
	b["mode"] = "stagger"
	b["stagger_t"] = t
	b["stagger"] = 0.0
	b["crashed"] = crashed
	g.sfx.set_loop(b["snd"], 0.0, 1.0)


func boss_steps(b: Dictionary, dt: float) -> void:
	if b["kind"] != "minister" and b["kind"] != "runner":
		return
	b["step_t"] -= dt
	if b["step_t"] <= 0.0:
		b["step_t"] = 0.3 / (1.0 + b["p"])
		var sv = 0.1 + 0.25 * minf(1.0, b["p"])
		g.sfx.play3d("step", g.tw3(b["x"], 0.0, b["z"]), linear_to_db(sv / 0.3))


# later phases: the wifi node and the minister throw phones, which you can deflect straight back at them
func boss_throws(b: Dictionary, dt: float) -> void:
	if b["phase"] < 2 or b["kind"] == "mower" or b["kind"] == "runner":
		return
	b["throw_t"] -= dt
	if b["throw_t"] <= 0.0 and g.phones.size() < 3 and g.state == "play":
		b["throw_t"] = 3.4 if b["phase"] == 2 else 2.4
		g.phone_sys.throw_phone(g.tw3(b["x"], float(g.BOSS_INFO[b["kind"]]["cy"]) + 0.7, b["z"]), b)


func update_bosses(dt: float) -> void:
	for i in range(g.bosses.size() - 1, -1, -1):
		if i >= g.bosses.size():
			continue
		var b = g.bosses[i]
		b["t"] += dt
		b["ph"] += dt * (9.0 if b["kind"] == "minister" else 14.0)
		if b["flash"] > 0.0:
			b["flash"] -= dt
			if b["flash"] <= 0.0:
				g.set_flash(b["model"]["root"], false)
		if b["intro"] > 0.0:
			b["intro"] -= dt
		if b["stagger"] > 0.0 and b["mode"] != "stagger":
			b["stagger"] = maxf(0.0, b["stagger"] - 6.0 * dt)
		var removed = update_boss(b, dt)
		if g.state != "play":
			return
		if removed:
			continue
		pose_boss(b, dt)


# returns true when the boss was removed this frame
# Bosses never leave: they chase you across the whole roundabout, commit to a lunge, overshoot (or crash into the
# fountain / a wall), recover, and come again until one of you is down.
func update_boss(b: Dictionary, dt: float) -> bool:
	var runner = b["kind"] == "runner"
	var mode = b["mode"]
	var wp: Vector3 = b["wp"]
	var pp = g.player.position
	var to = Vector3(pp.x - wp.x, 0.0, pp.z - wp.z)
	var dist = to.length()
	var dir = to / dist if dist > 0.001 else Vector3(0, 0, 1)
	if mode == "charge":
		b["chase_t"] += dt
		var aim = Vector3(pp.x, 0.0, pp.z)
		if b["kind"] == "wifi":  # the wifi node weaves about while it comes
			aim += Vector3(-dir.z, 0.0, dir.x) * sin(b["t"] * 1.7) * 3.5
		var dv = aim - wp
		dv.y = 0.0
		var step = minf(boss_speed(b) * dt, dv.length())
		if dv.length() > 0.05:
			set_boss_pos(b, wp + dv.normalized() * step)
		b["wyaw"] = atan2(dir.x, dir.z)
		b["p"] = 0.7 + 0.15 * float(b["phase"] - 1)
		update_boss_sound(b)
		boss_steps(b, dt)
		boss_throws(b, dt)
		if dist < (1.3 if runner else 1.6) and b["intro"] <= 0.0:
			boss_tackle(b)
		elif b["chase_t"] >= tele_wait(b) and dist < 15.0 and b["intro"] <= 0.0:
			start_tele(b)
	elif mode == "tele" and b["pat"] == "slam":
		b["tele_t"] -= dt
		b["wyaw"] = atan2(dir.x, dir.z)
		update_disc(b)
		if b["tele_t"] <= 0.0:
			do_slam(b)
	elif mode == "tele" and b["pat"] == "volley":
		b["tele_t"] -= dt
		b["wyaw"] = atan2(dir.x, dir.z)
		if b["tele_t"] <= 0.0:
			do_volley(b)
	elif mode == "tele":
		b["tele_t"] -= dt
		var lk: Vector3 = b["lock"]
		if b["tele_t"] > 0.22:  # the red lane still follows you, then locks
			b["lock"] = lk.lerp(pp, minf(1.0, dt * 7.0))
		var ld = lunge_dir(b)
		b["wyaw"] = atan2(ld.x, ld.z)
		update_strip(b, b["tele_t"] <= 0.22)
		if b["tele_t"] <= 0.0:
			var d = lunge_dir(b)
			b["ldir"] = d
			var lk2: Vector3 = b["lock"]
			var want = Vector2(lk2.x - wp.x, lk2.z - wp.z).length() + 6.0  # a miss carries on past you
			var pr = lunge_probe(wp, d, want)
			b["llen"] = pr.x
			b["lcrash"] = pr.y > 0.5
			b["lgo"] = 0.0
			b["lhit"] = false
			b["mode"] = "lunge"
			g.sfx.play3d("whoosh", g.tw3(b["x"], 1.0, b["z"]))
	elif mode == "lunge":
		var d2: Vector3 = b["ldir"]
		var stp = minf(lunge_speed(b) * dt, b["llen"] - b["lgo"])
		b["lgo"] += stp
		set_boss_pos(b, wp + d2 * stp)
		b["wyaw"] = atan2(d2.x, d2.z)
		b["p"] = 1.1
		boss_steps(b, dt)
		if not b["lhit"] and dist < (1.5 if runner else 1.9):
			b["lhit"] = true
			var evaded = g.dash_inv > 0.0
			g.damage_player("CYCLIST TACKLED YOU" if runner else "BOSS REACHED YOU", "boss")
			if g.state != "play":
				return false
			if not evaded:
				start_stagger(b, 1.0, false)
				return false
		if b["lgo"] >= b["llen"] - 0.001:
			resolve_lunge(b)
		else:
			update_strip(b, true)
	elif mode == "stagger":
		b["stagger_t"] -= dt
		if b["stagger_t"] <= 0.0:
			b["mode"] = "charge"
			b["chase_t"] = 0.0
			b["crashed"] = false
	elif mode == "dying":
		b["die_t"] += dt
		if b["die_t"] > 0.9:
			remove_boss(b)
			g.after_wave()
			return true
	return false


func update_disc(b: Dictionary) -> void:
	var disc: MeshInstance3D = b["disc"]
	var wp: Vector3 = b["wp"]
	var r = float(b["slam_r"])
	disc.visible = true
	disc.position = Vector3(wp.x, 0.04, wp.z)
	disc.scale = Vector3(r, 1.0, r)
	var k = 1.0 - clampf(b["tele_t"] / maxf(b["tele_total"], 0.01), 0.0, 1.0)
	var c = g.STRIP_COL_WARN.lerp(g.STRIP_COL_LOCK, k)
	if b["tele_t"] < 0.25:
		c.a *= 0.75 + 0.25 * sin(g.time * 30.0)
	g.disc_mat.albedo_color = c


func do_slam(b: Dictionary) -> void:
	hide_strip(b)
	var wp: Vector3 = b["wp"]
	var pos = Vector3(wp.x, 0.4, wp.z)
	g.sfx.play3d("crash", pos)
	g.shake = maxf(g.shake, 0.7)
	g.hitstop = maxf(g.hitstop, 0.05)
	g.fx_sys.burst(pos, 22, ["#c9ced4", "#f2b630", "#8a8f98"], 5.0, 0.4, 0.8, 0.1)
	if boss_flat_dist(b) < float(b["slam_r"]):
		g.damage_player("BOSS SLAMMED YOU", "boss")
		if g.state != "play":
			return
	else:
		g.shop_sys.add_style(6.0)
		g.add_popup(pos + Vector3(0, 1.6, 0), "SLAM DODGED", g.ACCENT, true)
	start_stagger(b, 1.2, false)


func do_volley(b: Dictionary) -> void:
	var wp: Vector3 = b["wp"]
	var fwd = Vector3(g.player.position.x - wp.x, 0.0, g.player.position.z - wp.z)
	if fwd.length() < 0.1:
		fwd = Vector3(0, 0, 1)
	fwd = fwd.normalized()
	var side = Vector3(-fwd.z, 0.0, fwd.x)
	var n = 3 if b["phase"] < 3 else 5
	if b.get("final", false):
		n += 2
	var start = Vector3(wp.x, float(g.BOSS_INFO[b["kind"]]["cy"]) + 0.7, wp.z)
	for i in range(n):
		g.phone_sys.throw_phone(start, b, side * (float(i) - float(n - 1) * 0.5) * 2.0)
	b["mode"] = "charge"
	b["pat"] = "lunge"
	b["chase_t"] = tele_wait(b) * 0.4


# it caught you while chasing: it hurts, then the boss reels for a moment
func boss_tackle(b: Dictionary) -> void:
	g.damage_player("CYCLIST TACKLED YOU" if b["kind"] == "runner" else "BOSS REACHED YOU", "boss")
	if g.state != "play":
		return
	g.shake = maxf(g.shake, 0.5)
	start_stagger(b, 0.9, false)


# the lunge ran out: either it slammed into something solid (dizzy, and you are rewarded) or it just overshot
func resolve_lunge(b: Dictionary) -> void:
	hide_strip(b)
	var runner = b["kind"] == "runner"
	var wp: Vector3 = b["wp"]
	var pos = Vector3(wp.x, 0.8, wp.z)
	if not b["lcrash"]:
		if b["combo"] > 0 and g.state == "play":
			b["combo"] -= 1
			start_tele(b, true)
			return
		g.shop_sys.add_style(5.0)
		g.add_note("OVERSHOT - HIT IT", g.ACCENT)
		start_stagger(b, 1.0 if runner else 1.3, false)
		return
	b["combo"] = 0
	g.sfx.play3d("crash", pos)
	g.shake = 0.6
	g.fx_sys.burst(pos, 14, ["#c9ced4", "#f2b630", "#8a8f98"], 3.0, 0.4, 0.7, 0.09)
	g.hitstop = 0.1
	var sp = 300 if runner else 600
	g.score += int(sp * (2 if g.hype_t > 0.0 else 1) * g.shop_sys.style_mul())
	g.hi_check()
	g.add_hype(12.0)
	g.shop_sys.add_style(20.0)
	g.shop_sys.add_cash(5 if runner else 12)
	g.add_popup(pos + Vector3(0, 1.8, 0), "CRASHED!  +%d" % sp, g.GOLD)
	g.add_note("DIZZY: HIT IT NOW", g.ACCENT)
	start_stagger(b, 2.0 if runner else 2.4, true)


func hit_boss(b: Dictionary, dmg: int, weak: bool = false, stag: float = 14.0) -> void:
	if not boss_hittable(b):
		return
	var inf = g.BOSS_INFO[b["kind"]]
	var c = g.tw3(b["x"], inf["cy"], b["z"])
	var k = b["kind"]
	var stunned = b["mode"] == "stagger"
	var armoured = weak and not weak_open(b)
	if armoured:
		weak = false
	if k != "runner":
		stag = stag / (1.0 + 0.12 * float(maxi(0, g.round_n - 2)))  # harder to stagger later on
	var total = dmg * (2 if weak else 1)
	if stunned:
		total += 1
	if weak and g.perks.has("deadeye"):
		total += 1
	if weak and g.shop_sys.has_duo("SNIPER") and g.shells == 0:
		total += 2
	if weak and g.shop_sys.has_duo("HEADHUNTER"):
		g.shells = mini(g.MAXSHELLS, g.shells + 2)
	b["hp"] -= total
	b["flash"] = 0.12
	g.set_flash(b["model"]["root"], true)
	g.shots_hit += 1
	if k == "mower":
		g.sfx.play3d("boss_hit_mower", c)
	elif k == "wifi":
		g.sfx.play3d("boss_hit_wifi", c)
	else:
		g.sfx.play3d("boss_hit_minister", c)
	g.fx_sys.burst(c, 8, ["#ff9a3a"], 4.0, 0.3, 0.5, 0.06)
	var lbl = "HIT"
	if armoured:
		lbl = "ARMOURED"
	if weak:
		lbl = "WEAK SPOT x2"
		g.hitstop = maxf(g.hitstop, 0.05)
		g.shop_sys.add_style(8.0)
	elif stunned:
		lbl = "DIZZY  +1"
	g.shop_sys.add_style(4.0)
	g.add_popup(
		c + Vector3(0, 1.0, 0),
		lbl,
		g.ACCENT if weak else (Color(0.65, 0.68, 0.72) if armoured else g.WHITE),
		true
	)
	if b["hp"] <= 0:
		kill_boss(b)
		return
	if k != "runner":
		if not stunned:
			b["stagger"] += stag
			if b["stagger"] >= 100.0:
				g.add_popup(c + Vector3(0, 1.8, 0), "STAGGERED!", g.GOLD)
				start_stagger(b, 2.4, true)
		var ph = boss_phase(b)
		if ph > b["phase"]:
			b["phase"] = ph
			b["throw_t"] = 1.2
			g.add_note("PHASE %d" % ph, g.RED)
			g.sfx.play("boss_intro", -4.0)
			g.shake = 0.6
	if k == "minister" and randf() < 0.3:
		g.sfx.say("minister_hit")


func kill_boss(b: Dictionary) -> void:
	g.kills += 1
	g.meta.add_boss_kill(str(b["kind"]), b.get("final", false))
	b["mode"] = "dying"
	b["die_t"] = 0.0
	stop_boss_sound(b)
	var is_run = b["kind"] == "runner"
	var pts = (600 + 100 * (g.round_n - 1)) if is_run else (2000 + 500 * (g.round_n - 1))
	if g.hype_t > 0.0:
		pts *= 2
	g.score += pts
	g.hi_check()
	g.add_hype(15.0 if is_run else 40.0)
	g.cheer = 1.0 if is_run else 2.0
	g.shout_t = 0.0
	hide_strip(b)
	g.hitstop = 0.15
	g.shop_sys.add_style(30.0)
	g.shop_sys.add_cash(18 if is_run else 55)
	var bpos = g.tw3(b["x"], 1.0, b["z"])
	if not is_run:
		if g.hearts < g.MAXHEARTS:
			g.hearts += 1
		else:
			g.score += 1000
			g.hi_check()
		g.pickup_sys.maybe_drop(bpos, 1.0)
	else:
		g.pickup_sys.maybe_drop(bpos, 0.5)
	g.add_note(("CYCLIST DOWN +" if is_run else "BOSS DOWN +") + str(pts), g.GOLD)
	if b.get("final", false):
		g.final_boss_dead = true
		g.score += 10000
		g.hi_check()
		g.add_note("FINAL BOSS DEFEATED  +10000", g.GOLD)
		g.fx_sys.confetti()
	if is_run:
		g.sfx.play3d("thud", bpos)
		g.sfx.v_yelp(bpos)
	elif b["kind"] == "minister":
		g.sfx.play("boss_down_minister")
	else:
		g.sfx.play("boss_down")
	var cols = ["#ffffff", "#f2b630", "#4a90d6"]
	if is_run:
		cols = ["#ffffff", "#f2b630", "#7a3fc0"]
	elif b["kind"] == "mower":
		cols = ["#f1f3ef", "#2fae5f", "#ffd23f", "#3a3d41"]
	elif b["kind"] == "wifi":
		cols = ["#ffffff", "#e5533d", "#cfd4da"]
	g.fx_sys.burst(bpos, 40, cols, 6.0, 0.6, 1.1, 0.09)
	if b["kind"] == "minister":
		for i in range(26):
			g.fx_sys.spawn_particle(
				(
					bpos
					+ Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 1.5), randf_range(-0.6, 0.6))
				),
				Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 4.0), randf_range(-2.5, 2.5)),
				randf_range(1.5, 2.5),
				g.pick_one(g.confetti_mats),
				Vector3(0.12, 0.01, 0.08),
				3.0,
				randf_range(-8.0, 8.0)
			)
		g.sfx.say("minister_out")
