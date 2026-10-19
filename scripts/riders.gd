extends RefCounted
# Riders: spawning waves, movement and sound, collisions, hits and losing parts.
# Shared game state stays on main.gd (g); this file holds the logic.

const Models = preload("res://scripts/models.gd")
const Ring = preload("res://scripts/ring.gd")

var g = null

func _init(game) -> void:
	g = game

# ================================================================== riders
func spawn_rider(lane_idx: int, dir: int) -> Dictionary:
	var roll = randf()
	var type = "pro"
	if g.round_n >= 2 and roll < 0.2:
		type = "sprinter"
	elif g.round_n >= 2 and roll < 0.4:
		type = "courier"
	if g.round_n >= 2 and randf() < minf(0.36, 0.12 + g.round_n * 0.04):
		type = "tough"
	var kit_i = randi() % 4
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
	var x0 = -(g.ARENA_HX + 2.0) if dir > 0 else (g.ARENA_HX + 2.0)
	g.place(m["root"], x0, 0.0, g.LANE_Z[lane_idx])
	face_rider(m, dir)
	var r = {
		"x": x0, "dir": dir, "ln": lane_idx, "base": base, "spd": base, "tgt": base,
		"chg": randf_range(0.5, 1.2), "wph": 0.0, "cph": 0.0, "mode": "fly", "t": 0.0, "age": 0.0,
		"entered": false, "type": type, "idx": g.next_idx, "model": m, "parts": [], "kit": kit,
		"limit": maxf(3.0, 6.1 - g.round_n * 0.35) + g.RIDER_TIME_BONUS,
		"hp": hp, "max_hp": hp, "flash": 0.0, "snd": null, "gone": false,
		"can_throw": randf() < clampf(0.55 + 0.06 * g.round_n, 0.6, 0.9), "throw_t": randf_range(0.5, 1.4), "wind_t": 0.0
	}
	g.next_idx += 1
	g.riders.append(r)
	r["snd"] = g.sfx.make_loop("loop_rider", m["root"], Vector3(0, 1.0, 0))
	Models.pose_rider(m, 0.0, 0.0)
	return r

func spawn_wave() -> void:
	var remaining = g.PER_ROUND - g.next_idx
	var n = 1
	if g.round_n >= 2 and remaining >= 2 and randf() < minf(0.55, 0.12 + g.round_n * 0.08):
		n = 2
	var order = [0, 1, 2]
	order.shuffle()
	var dir = 1 if randf() < 0.5 else -1
	for k in range(n):
		var d = dir
		if k > 0 and randf() < 0.5:
			d = -dir
		var r = spawn_rider(order[k], d)
		if n == 2:
			r["limit"] += 1.0
	g.wave_miss = false

func face_rider(m: Dictionary, dir: int) -> void:
	var pv: Node3D = m["pivot"]
	pv.rotation = Vector3(0.0, 0.0 if dir > 0 else PI, 0.0)

func update_rider_sound(r: Dictionary) -> void:
	var spd_px = r["spd"] / g.PX_TO_M
	var vol = 0.05 * clampf(spd_px / 250.0, 0.4, 1.8)
	g.sfx.set_loop(r["snd"], vol * 2.2, (500.0 + spd_px * 1.6) / 700.0)

# standing on the road is dangerous: a rider that reaches you knocks you down (a dash through it is a perfect dodge)
func rider_collide(r: Dictionary) -> void:
	if g.state != "play" or Ring.hidden(r["x"]):
		return
	var rp = g.rider_world(r, 0.0)
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
		var mul = 1.0 + r["age"] * 0.08
		r["spd"] += (r["tgt"] * mul - r["spd"]) * minf(1.0, dt * 3.0)
		r["x"] += r["dir"] * r["spd"] * dt
		if not r["entered"] and not Ring.hidden(r["x"]):
			r["entered"] = true
		if r["entered"]:                                  # riders keep circling: through the tunnel and round again
			if r["x"] > g.ARENA_HX:
				r["x"] -= 2.0 * g.ARENA_HX
			elif r["x"] < -g.ARENA_HX:
				r["x"] += 2.0 * g.ARENA_HX
		r["wph"] += r["spd"] * dt / 0.34
		r["cph"] += dt * (6.0 + 0.444 * r["spd"])
		face_rider(m, r["dir"])
		g.place(root, r["x"], sin(r["age"] * 10.0) * 0.015, g.LANE_Z[r["ln"]])
		Models.pose_rider(m, r["cph"], r["wph"])
		update_rider_sound(r)
		rider_collide(r)
		if r["wind_t"] > 0.0:
			r["wind_t"] -= dt
			if r["wind_t"] <= 0.0:
				g.phone_sys.launch_phone(r)
		elif r["can_throw"] and r["entered"] and not Ring.hidden(r["x"]) and g.phones.size() < 3:
			r["throw_t"] -= dt
			if r["throw_t"] <= 0.0:
				if g.throw_cool <= 0.0 and g.state == "play":
					g.phone_sys.start_throw(r)
				else:
					r["throw_t"] = 0.3
		if r["age"] > r["limit"]:
			r["mode"] = "away"
			r["dir"] = -1 if r["x"] < 0.0 else 1
			face_rider(m, r["dir"])
			g.sfx.play3d("whoosh", root.position)
	elif mode == "away":
		r["spd"] = minf(39.0, r["spd"] + 26.0 * dt)
		r["x"] += r["dir"] * r["spd"] * dt
		r["wph"] += r["spd"] * dt / 0.34
		r["cph"] += dt * (6.0 + 0.444 * r["spd"])
		g.place(root, r["x"], 0.0, g.LANE_Z[r["ln"]])
		Models.pose_rider(m, r["cph"], r["wph"])
		update_rider_sound(r)
		rider_collide(r)
		if absf(r["x"]) > g.ARENA_HX + 2.6:
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
						g.sfx.play3d("land_s" if k < 0.4 else ("land_m" if k < 0.75 else "land_l"), node.position)
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
			node.position = Ring.clamp_road(node.position)
			if r["t"] > 4.0:
				p["done"] = true
			if not p["done"]:
				alive += 1
		if alive == 0:
			resolve(r, true)

func hit_rider(r: Dictionary, dmg: int) -> void:
	r["hp"] -= dmg
	var wpos = g.tw3(r["x"], 1.0, g.LANE_Z[r["ln"]])
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
	g.combo = mini(5, g.combo + 1)
	g.best_combo = maxi(g.best_combo, g.combo)
	var pts = int(round(500.0 * g.TYPES[r["type"]]["pts"] * g.LANE_MULT[r["ln"]] * (1.0 + 0.1 * (g.round_n - 1))))
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
	r["parts"].append(detach_part(m["bike"],
		g.street_vel(r["x"], dirf * r["spd"] * 0.45 + randf_range(-1.0, 1.0), randf_range(2.5, 4.0), randf_range(-1.5, 1.5)),
		Vector3(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0), randf_range(-6.0, 6.0)), 0.09, sgn * PI * 0.5))
	if r["type"] == "tough":
		# the armoured rider jumps off the bike and runs at you
		g.boss_sys.spawn_runner(r)
		var man: Node3D = m["man"]
		man.queue_free()
	else:
		r["parts"].append(detach_part(m["man"],
			g.street_vel(r["x"], dirf * r["spd"] * 0.35 + randf_range(-1.5, 1.5), randf_range(4.0, 5.5), randf_range(-1.5, 1.5)),
			Vector3(randf_range(-5.0, 5.0), randf_range(-3.0, 3.0), randf_range(-5.0, 5.0)), 0.2, -sgn * PI * 0.5))

func detach_part(node: Node3D, vel: Vector3, av: Vector3, floor_y: float, rest_x: float) -> Dictionary:
	var gt = node.global_transform
	node.get_parent().remove_child(node)
	g.add_child(node)
	node.global_transform = gt
	return {"node": node, "vel": vel, "av": av, "floor": floor_y, "rest_x": rest_x, "landed": false, "rest": 0.0, "done": false}

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
