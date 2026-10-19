extends RefCounted
# Player: movement, dash and slide, perfect dodges, aim assist, spread and gun handling.
# Shared game state stays on main.gd (g); this file holds the logic.

const Ring = preload("res://scripts/ring.gd")

var g = null

func _init(game) -> void:
	g = game

func update_player(dt: float, captured: bool) -> void:
	var active = (g.state == "play" and captured)
	var pad = g.pad_on()
	if not active or g.melee:
		g.ads_on = false
	var want_ads = false
	if active and not g.melee:
		want_ads = g.ads_on if g.toggle_ads else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var want_crouch = active and (Input.is_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C))
	var pad_sprint = false
	var trig = false
	var mv = Vector2.ZERO
	if active:
		mv = g.read_move()
		if pad:
			if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5 and not g.melee:
				want_ads = true
			if Input.is_joy_button_pressed(0, JOY_BUTTON_B):
				want_crouch = true
			pad_sprint = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
			trig = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5
			var rs = g.stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
			if rs.length() > 0.0:
				var lk = 2.4 * g.sens_mul * (g.cam.fov / g.fov_hip)
				var look = rs.normalized() * rs.length() * rs.length()
				g.yaw -= look.x * lk * dt
				g.pitch = clampf(g.pitch - look.y * lk * dt, -1.45, 1.45)
				apply_aim_assist(dt)

	# timers
	if g.dash_cd > 0.0:
		g.dash_cd -= dt
	if g.dash_inv > 0.0:
		g.dash_inv -= dt
	if g.dash_t > 0.0:
		g.dash_t -= dt
	if g.slide_cd > 0.0:
		g.slide_cd -= dt
	if g.dodge_cd > 0.0:
		g.dodge_cd -= dt

	# slide: press crouch while sprinting
	var crouch_edge = want_crouch and not g.crouch_prev
	g.crouch_prev = want_crouch
	if active and crouch_edge and g.was_sprint and g.slide_cd <= 0.0 and g.slide_t <= 0.0 and g.dash_t <= 0.0:
		g.slide_t = g.SLIDE_TIME
		g.slide_cd = 1.2
		if g.pvel.length() > 0.5:
			g.slide_dir = g.pvel.normalized()
		else:
			g.slide_dir = g.move_world(Vector2(0.0, 1.0))
		g.slide_dir.y = 0.0
		grant_free_shots()
		g.sfx.play("whoosh", -8.0)
	if g.slide_t > 0.0:
		g.slide_t -= dt
		want_crouch = true
		want_ads = false
	g.crouch_t = move_toward(g.crouch_t, 1.0 if want_crouch else 0.0, dt * 6.0)
	g.ads_t = move_toward(g.ads_t, 1.0 if want_ads else 0.0, dt * 9.0)
	g.sprinting = active and (Input.is_key_pressed(KEY_SHIFT) or pad_sprint) and mv.y > 0.0 and not want_crouch and not want_ads
	g.was_sprint = g.sprinting

	var speed = g.RUN * (1.12 if g.perks.has("sprinter") else 1.0) if g.sprinting else g.WALK
	speed = lerpf(speed, g.CROUCH_SPEED, g.crouch_t)
	speed *= lerpf(1.0, 0.55, g.ads_t)

	var target = Vector3.ZERO
	if mv.length() > 0.0:
		mv = mv.limit_length(1.0)
		target = g.move_world(mv) * speed
	if g.dash_t > 0.0:
		g.pvel = g.dash_dir * lerpf(5.0, g.DASH_SPEED, clampf(g.dash_t / g.DASH_TIME, 0.0, 1.0))
	elif g.slide_t > 0.0:
		g.pvel = g.slide_dir * lerpf(2.0, g.SLIDE_SPEED, clampf(g.slide_t / g.SLIDE_TIME, 0.0, 1.0))
	else:
		g.pvel = g.pvel.lerp(target, minf(1.0, dt * 10.0))

	g.player.position = g.clamp_walk(g.player.position + g.pvel * dt, g.PLAYER_R_MIN, g.PLAYER_R_MAX)
	g.player.rotation.y = g.yaw

	var spd = g.pvel.length()
	g.bob_t += spd * dt * 2.2
	var bob = sin(g.bob_t) * 0.022 * minf(1.0, spd / g.RUN) * (1.0 - g.ads_t)
	if g.slide_t > 0.0 or g.dash_t > 0.0:
		bob = 0.0
	g.cam.position.y = lerpf(g.EYE_STAND, g.EYE_CROUCH, g.crouch_t) + bob
	g.cam.rotation.x = g.pitch
	g.cam.rotation.z = 0.0
	if g.slide_t > 0.0:
		g.cam.rotation.z = 0.04
	if g.shake > 0.0:
		g.cam.rotation.z += randf_range(-1.0, 1.0) * g.shake * 0.03
	var kick = 9.0 * clampf(g.dash_t / g.DASH_TIME, 0.0, 1.0)
	g.cam.fov = lerpf(g.fov_hip, g.fov_hip * g.FOV_ADS / g.FOV_HIP, g.ads_t) + kick
	g.spread_deg = current_spread()
	if trig and active:
		g.combat_sys.fire()

# stick aim help: drifts the crosshair onto whatever is close to it
func apply_aim_assist(dt: float) -> void:
	if g.aim_assist <= 0.0:
		return
	var org = g.cam.global_position
	var fwd = -g.cam.global_transform.basis.z
	var best = null
	var best_ang = deg_to_rad(8.0)
	var cands = []
	for r in g.riders:
		if (r["mode"] == "fly" or r["mode"] == "away") and not Ring.hidden(r["x"]):
			cands.append(g.tw3(r["x"], 1.2, g.LANE_Z[r["ln"]]))
	for b in g.bosses:
		if g.boss_sys.boss_hittable(b):
			cands.append(g.tw3(b["x"], g.boss_sys.weak_point_y(b), b["z"]))
	for ph in g.phones:
		if not ph["ret"]:
			cands.append(ph["pos"])
	for c in cands:
		var ang = fwd.angle_to((c - org).normalized())
		if ang < best_ang:
			best_ang = ang
			best = c
	if best == null:
		return
	var to = (best - org).normalized()
	var kk = clampf(dt * 2.5 * g.aim_assist, 0.0, 1.0)
	g.yaw = lerp_angle(g.yaw, atan2(-to.x, -to.z), kk)
	g.pitch = lerpf(g.pitch, asin(clampf(to.y, -1.0, 1.0)), kk)

func grant_free_shots() -> void:
	if not g.perks.has("slideshot"):
		return
	g.free_shots = 5 if g.shop_sys.has_duo("QUICK DRAW") else 3
	g.add_note("SLIDE SHOT: %d FREE DARTS" % g.free_shots, g.GOLD)

func dash_cooldown() -> float:
	var c = 1.3 - 0.15 * float(g.up["dashcd"])
	if g.perks.has("adrenaline"):
		c *= 0.6
	if g.shop_sys.has_duo("SPEEDSTER"):
		c *= 0.8
	return maxf(0.3, c)

func try_dash() -> void:
	if g.state != "play" or g.paused or g.dash_cd > 0.0 or g.dash_t > 0.0:
		return
	var mv = g.read_move()
	var dir = Vector3.ZERO
	if mv.length() > 0.1:
		dir = g.move_world(mv.normalized())
	else:
		dir = Ring.tangent(g.ptx()) * (-1.0 if g.ptx() > 0.0 else 1.0)      # nothing held: dash along the island towards the front
	dir.y = 0.0
	g.dash_dir = dir.normalized()
	g.dash_t = g.DASH_TIME
	g.dash_inv = g.DASH_TIME + 0.18 + (0.15 if g.shop_sys.has_duo("GHOST") else 0.0)
	g.dash_cd = dash_cooldown()
	g.slide_t = 0.0
	grant_free_shots()
	g.sfx.play("whoosh", -4.0)

# something would have hit you while the dash made you untouchable
func perfect_dodge() -> void:
	if g.dodge_cd > 0.0:
		return
	g.dodge_cd = 0.5
	g.perfect_dodges += 1
	var v = int(250 * (2 if g.hype_t > 0.0 else 1) * g.shop_sys.style_mul())
	g.score += v
	g.hi_check()
	g.add_hype(15.0)
	g.shop_sys.add_style(15.0)
	g.shop_sys.add_cash(2)
	g.add_note("PERFECT DODGE  +%d" % v, g.GOLD)
	g.hitstop = 0.12
	g.sfx.play("clank2", -6.0)
	if g.shop_sys.has_duo("MATADOR"):
		g.shells = mini(g.MAXSHELLS, g.shells + 3)
	if g.perks.has("closeshave") and g.perfect_dodges % 2 == 0 and g.hearts < g.MAXHEARTS:
		g.hearts += 1
		g.add_note("CLOSE SHAVE  +1 LIFE", g.RED)

func current_spread() -> float:
	var s = lerpf(2.2, 0.25, g.ads_t)
	s *= 1.0 + clampf(g.pvel.length() / g.RUN, 0.0, 1.0) * 0.9
	s *= lerpf(1.0, 0.7, g.crouch_t)
	if g.perks.has("steady"):
		s *= 0.7
	return s + g.bloom

func cur_pump() -> float:
	if g.buffs["rapid"] > 0.0:
		return 0.08
	if g.hype_t > 0.0:
		return g.pump_base * 0.65
	return g.pump_base

func ex_bonus() -> float:
	# extra hit radius in metres from fat-dart upgrades and the fat-dart pickup
	return (g.up["wide"] * 5.0 + (18.0 if g.buffs["big"] > 0.0 else 0.0)) * 0.025

func update_gun(dt: float) -> void:
	var g: Node3D = g.gun["root"]
	var rb: Node3D = g.rubber["root"]
	var menu = g.state == "upgrade" or g.state == "shop"
	g.visible = not g.melee and not menu
	rb.visible = g.melee and not menu
	var pump: Node3D = g.gun["pump"]
	var hip = Vector3(0.24, -0.22, -0.52)
	var ads = Vector3(0.0, -0.062, -0.42)
	var p = hip.lerp(ads, g.ads_t)
	p.z += g.recoil * 0.07
	p.y -= (0.05 if g.sprinting else 0.0) + (0.04 if g.loading else 0.0)
	g.position = g.position.lerp(p, minf(1.0, dt * 18.0))
	g.rotation = Vector3(g.recoil * 0.14 + (0.18 if g.sprinting else 0.0), (1.0 - g.ads_t) * 0.06, 0.0)
	var phase = 0.0
	if g.pump_t > 0.0:
		phase = sin(PI * (1.0 - g.pump_t / maxf(g.pump_dur, 0.01)))
	if g.loading:
		phase = maxf(phase, 0.5 * (0.5 + 0.5 * sin(g.time * 24.0)))
	pump.position = Vector3(0.0, pump.position.y, -0.30 + 0.12 * phase)
	g.gun["light"].light_energy = 3.0 * (g.flash / 0.07) if g.flash > 0.0 else 0.0

	# rubber swing
	var sw = 0.0
	if g.swing_t > 0.0:
		var k = 1.0 - g.swing_t / 0.26
		sw = (-1.0 + 2.0 * k) * g.swing_dir
	rb.position = Vector3(0.3, -0.34, -0.5 + (0.0 if g.swing_t <= 0.0 else -0.12))
	rb.rotation = Vector3(0.0, sw * 0.9, -0.15 + sw * 0.25)

	# melee reach ring on the floor
	var show_ring = g.melee and g.state == "play" and not g.paused
	g.melee_ring.visible = show_ring
	if show_ring:
		var z = g.combat_sys.swing_zone()
		var rr = z["r"] * 0.8
		g.melee_ring.position = Vector3(z["c"].x, 0.04, z["c"].z)
		g.melee_ring.scale = Vector3(rr, 1.0, rr)
