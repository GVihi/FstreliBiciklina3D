extends RefCounted
# Player: movement, dash and slide, perfect dodges, aim assist, spread and gun handling.
# Shared game state stays on main.gd (g); this file holds the logic.

var g = null

# gun motion (update_gun): how far the gun lags behind turning, and the look angles of the last frame
var sway_yaw = 0.0
var sway_pitch = 0.0
var look_prev = Vector2.ZERO
var look_seen = false

# recoil spring: the gun kicks back (metres), the muzzle rises (radians) and it rolls a little, then settles with a small overshoot
var kick_back = 0.0
var kick_back_v = 0.0
var kick_rise = 0.0
var kick_rise_v = 0.0
var kick_roll = 0.0
var kick_roll_v = 0.0
var shots_seen = 0
var gun_base = Vector3.ZERO  # the smoothed hip / aim position, before the recoil is added
var kick_dip = 0.0  # the gun dips a little each time a shell goes in (metres, negative = down)
var kick_dip_v = 0.0
var shells_prev = -1
var ammo_text = ""  # what the ammo label on the gun shows now, so the text is only set when it changes
var flash_roll = 0.0  # the muzzle flash is turned a random amount for every shot
var shell_out = false  # true once the shell of the current pump has been thrown out
var pump_slide = 0.0  # 0 = slide forward, 1 = pulled all the way back
var load_blend = 0.0  # 0 = normal hold, 1 = tilted for loading shells

# jelly club wobble (Milestone F3): the tip of the club trails behind the swing on a spring, so it bends against the swing,
# overshoots when the swing stops and rings down. Fed to the club's vertex shader in update_gun.
var jelly_tip = 0.0  # where the tip is on the swing scale (-1 to 1); it chases the swing
var jelly_tip_v = 0.0
var jelly_phase = 0.0  # moves the ripple that runs down the club
var jelly_flash = 0.0  # 1 right after a hit or deflect, fades out: the club flashes bright and squashes

# Jelly club wobble tuning (Milestone F3). Metres unless noted.
const JELLY_STIFFNESS = 230.0  # spring strength: higher = the tip keeps up better and rings faster (lower = slow, floppy swings)
const JELLY_DAMPING = 3.2  # spring damping: lower = more wobble after the swing (about 8 bounces, over a second)
const JELLY_BEND = 0.45  # sideways bend of the tip per unit of lag (full swing lag gives about 45 cm)
const JELLY_DROOP = 0.22  # the tip also sags this much (per unit of lag) while the club whips
const JELLY_RIPPLE_IDLE = 0.012  # a tiny ripple that is always there
const JELLY_RIPPLE_GAIN = 0.007  # ripple strength per unit of tip speed
const JELLY_RIPPLE_MAX = 0.09
const JELLY_RIPPLE_SPEED = 18.0  # how fast the ripple runs (rad/s)
const JELLY_SQUASH = 0.14  # stretch along the club per unit of lag, thinning it a little
const JELLY_SQUASH_MAX = 0.16
const JELLY_FLASH_FADE = 5.0  # how fast the hit flash fades (per second)
const JELLY_HIT_SQUASH = 0.12  # extra stretch at the moment of a hit, fading with the flash

# Gun motion tuning (Milestone F2). Everything is in metres / radians and fades out while aiming down sights.
const IDLE_SWAY = 0.0035  # breathing: how far the gun drifts up/down while standing still
const BOB_SIDE = 0.010  # walk bob: side-to-side travel
const BOB_UP = 0.010  # walk bob: up/down travel
const BOB_SPRINT_MUL = 1.8  # a sprint bobs this much harder than a walk
const BOB_LAG = 0.6  # the gun trails the camera bob by this many radians, so it feels heavy
const LOOK_SWAY = 0.5  # how much of a turn the gun lags behind (1.0 = no follow at all)
const LOOK_SWAY_MAX = 0.07  # largest lag in radians
const LOOK_SWAY_RETURN = 9.0  # how fast the gun catches up again (per second)
const ADS_CALM = 0.85  # how much of the motion aiming down sights removes
const KICK_BACK_SPEED = 1.4  # recoil: how hard a shot shoves the gun back (m/s, about 5 cm of travel)
const KICK_RISE_SPEED = 3.6  # recoil: how hard it flips the muzzle up (rad/s, about 7 degrees)
const KICK_ROLL_SPEED = 0.7  # recoil: random roll, to either side (rad/s)
const KICK_STIFFNESS = 320.0  # spring strength: higher = snappier return
const KICK_DAMPING = 24.0  # spring damping: lower = more wobble after the kick
const PUMP_TRAVEL = 0.12  # pump: how far the slide travels (metres)
const PUMP_PULL = 0.4  # pump: the slide spends this share of the pump time going back (a fast pull, a slower push)
const PUMP_JOLT_PITCH = 0.05  # pump: the muzzle dips this much (rad) when the slide is back
const PUMP_JOLT_BACK = 0.012  # pump: and the gun is pulled this far towards you (metres)
const LOAD_OPEN = 0.25  # reload: how far back the slide rests while shells go in (0 to 1)
const LOAD_SHIFT = Vector3(-0.035, -0.04, 0.02)  # reload: where the gun moves to
const LOAD_TILT = Vector2(0.22, 0.5)  # reload: pitch up and roll (rad), so the loading port faces you
const SHELL_DIP_SPEED = 0.45  # reload: how hard each shell nudges the gun down (m/s, about 1 cm)
const SHELL_PORT = Vector3(0.0405, 0.03, 0.0)  # the ejection port on the gun's right side
const SHELL_EJECT_AT = 0.7  # a shell flies out when the pumped slide is this far back (0 to 1)
const KICK_BACK_MAX = 0.09  # limits, so rapid fire stacks up but never runs away
const KICK_RISE_MAX = 0.26
const KICK_ADS_MUL = 0.5  # recoil is this much smaller while aiming down sights (the view carries it instead)


func _init(game) -> void:
	g = game


func update_player(dt: float, captured: bool) -> void:
	var active = g.state == "play" and captured
	var pad = g.pad_on()
	if not active or g.melee:
		g.ads_on = false
	var want_ads = false
	if active and not g.melee:
		want_ads = g.ads_on if g.toggle_ads else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var want_crouch = (
		active and (Input.is_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C))
	)
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
	if (
		active
		and crouch_edge
		and g.was_sprint
		and g.slide_cd <= 0.0
		and g.slide_t <= 0.0
		and g.dash_t <= 0.0
	):
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
	g.sprinting = (
		active
		and (Input.is_key_pressed(KEY_SHIFT) or pad_sprint)
		and mv.y > 0.0
		and not want_crouch
		and not want_ads
	)
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

	g.player.position = g.clamp_walk(
		g.player.position + g.pvel * dt, g.PLAYER_R_MIN, g.PLAYER_R_MAX
	)
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
		if (r["mode"] == "fly" or r["mode"] == "away") and not g.arena.hidden(r["x"]):
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
		dir = g.arena.tangent(g.ptx()) * (-1.0 if g.ptx() > 0.0 else 1.0)  # nothing held: dash along the island towards the front
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
	var w = g.WEAPONS["dart_gun"]
	var s = lerpf(float(w["spread_hip"]), float(w["spread_aimed"]), g.ads_t)
	s *= 1.0 + clampf(g.pvel.length() / g.RUN, 0.0, 1.0) * float(w["spread_move_extra"])
	s *= lerpf(1.0, float(w["spread_crouch_mul"]), g.crouch_t)
	if g.perks.has("steady"):
		s *= float(w["spread_steady_mul"])
	return s + g.bloom


func cur_pump() -> float:
	if g.buffs["rapid"] > 0.0:
		return float(g.WEAPONS["dart_gun"]["rapid_pump"])
	if g.hype_t > 0.0:
		return g.pump_base * float(g.WEAPONS["dart_gun"]["hype_pump_mul"])
	return g.pump_base


func ex_bonus() -> float:
	# extra hit radius in metres from fat-dart upgrades and the fat-dart pickup
	return (g.up["wide"] * 5.0 + (18.0 if g.buffs["big"] > 0.0 else 0.0)) * 0.025


# one spring per recoil axis: a shot gives them a push, then they swing back to rest with a small overshoot
func update_kick(dt: float) -> void:
	if g.shots_fired != shots_seen:
		if g.shots_fired > shots_seen:
			var mul = lerpf(1.0, KICK_ADS_MUL, g.ads_t)
			kick_back_v += KICK_BACK_SPEED * mul
			kick_rise_v += KICK_RISE_SPEED * mul
			kick_roll_v += randf_range(-KICK_ROLL_SPEED, KICK_ROLL_SPEED) * mul
			flash_roll = randf() * TAU
		shots_seen = g.shots_fired
	var steps = clampi(ceili(dt / 0.008), 0, 8)  # small steps keep the stiff spring stable on a slow frame
	if steps == 0:
		return
	var h = minf(dt, 0.064) / float(steps)
	for _i in range(steps):
		kick_back_v += (-KICK_STIFFNESS * kick_back - KICK_DAMPING * kick_back_v) * h
		kick_back += kick_back_v * h
		kick_rise_v += (-KICK_STIFFNESS * kick_rise - KICK_DAMPING * kick_rise_v) * h
		kick_rise += kick_rise_v * h
		kick_roll_v += (-KICK_STIFFNESS * kick_roll - KICK_DAMPING * kick_roll_v) * h
		kick_roll += kick_roll_v * h
		kick_dip_v += (-KICK_STIFFNESS * kick_dip - KICK_DAMPING * kick_dip_v) * h
		kick_dip += kick_dip_v * h
	kick_back = clampf(kick_back, -KICK_BACK_MAX, KICK_BACK_MAX)
	kick_rise = clampf(kick_rise, -KICK_RISE_MAX, KICK_RISE_MAX)
	kick_roll = clampf(kick_roll, -0.12, 0.12)
	kick_dip = clampf(kick_dip, -0.03, 0.03)
	# kick_back is a push towards +Z (towards the player), kick_rise tips the muzzle up


# throws one shell out of the ejection port: out to the right, up and a little back, plus some of your own speed
func eject_shell(gun_node: Node3D) -> void:
	var basis = g.cam.global_transform.basis
	var vel = (
		basis.x * randf_range(1.5, 2.2)
		+ basis.y * randf_range(1.0, 1.7)
		+ basis.z * randf_range(0.2, 0.8)
	)
	vel += g.pvel * 0.6
	g.fx_sys.spawn_shell(gun_node.to_global(SHELL_PORT), vel)


# the slide over one pump, k from 0 to 1: a fast pull back (eased out), then a slower push forward (eased in and out)
func pump_curve(k: float) -> float:
	k = clampf(k, 0.0, 1.0)
	if k < PUMP_PULL:
		var t = k / PUMP_PULL
		return 1.0 - (1.0 - t) * (1.0 - t)
	var u = (k - PUMP_PULL) / (1.0 - PUMP_PULL)
	return 1.0 - smoothstep(0.0, 1.0, u)


func update_gun(dt: float) -> void:
	var gun_node: Node3D = g.gun["root"]
	var rb: Node3D = g.rubber["root"]
	var menu = g.state == "upgrade" or g.state == "shop"
	gun_node.visible = not g.melee and not menu
	rb.visible = g.melee and not menu
	var pump: Node3D = g.gun["pump"]
	var hip = Vector3(0.24, -0.22, -0.52)
	var ads = Vector3(0.0, float(g.gun.get("ads_y", -0.062)), -0.42)  # the gun's own height: its sights sit on the screen centre
	var p = hip.lerp(ads, g.ads_t)
	p.y -= (0.05 if g.sprinting else 0.0)

	# pump and reload: the slide curve, a small jolt of the whole gun, and the tilt while shells go in
	var pumping = g.pump_t > 0.0
	var slide_target = 0.0
	if pumping:
		slide_target = pump_curve(1.0 - g.pump_t / maxf(g.pump_dur, 0.01))
		pump_slide = slide_target  # follows the pump timing exactly
	else:
		if g.loading:
			slide_target = LOAD_OPEN
		pump_slide = lerpf(pump_slide, slide_target, minf(1.0, dt * 20.0))
	var reloading = g.loading and not pumping
	load_blend = move_toward(load_blend, 1.0 if reloading else 0.0, dt * 7.0)
	var lb = smoothstep(0.0, 1.0, load_blend) * (1.0 - g.ads_t * 0.6)
	p += LOAD_SHIFT * lb
	var jolt = pump_slide if pumping else 0.0
	jolt *= 1.0 - g.ads_t * 0.5
	p.z += jolt * PUMP_JOLT_BACK
	if shells_prev < 0:
		shells_prev = g.shells
	if g.shells > shells_prev and g.loading:
		kick_dip_v -= SHELL_DIP_SPEED
	shells_prev = g.shells

	# idle sway (breathing), walk / sprint bob and look sway. They ease out while aiming down sights.
	var calm = 1.0 - g.ads_t * ADS_CALM
	var spd = g.pvel.length()
	var moving = clampf(spd / g.RUN, 0.0, 1.0)
	if g.slide_t > 0.0 or g.dash_t > 0.0:
		moving = 0.0
	var bob_mul = BOB_SPRINT_MUL if g.sprinting else 1.0
	var still = 1.0 - moving
	var step_side = sin(g.bob_t * 0.5)  # one full sway left-right per two steps
	var step_up = sin(g.bob_t - BOB_LAG)  # one bounce per step, a little behind the camera
	var off = Vector3(
		sin(g.time * 0.85) * IDLE_SWAY * 0.7 * still + step_side * BOB_SIDE * bob_mul * moving,
		sin(g.time * 1.7) * IDLE_SWAY * still + step_up * BOB_UP * bob_mul * moving,
		0.0
	)
	p += off * calm

	# look sway: turning the view leaves the gun lagging a little, then it catches up
	var look = Vector2(g.yaw, g.pitch)
	if not look_seen:
		look_prev = look
		look_seen = true
	var turn = Vector2(wrapf(look.x - look_prev.x, -PI, PI), look.y - look_prev.y)
	look_prev = look
	sway_yaw = clampf(sway_yaw - turn.x * LOOK_SWAY, -LOOK_SWAY_MAX, LOOK_SWAY_MAX)
	sway_pitch = clampf(sway_pitch + turn.y * LOOK_SWAY, -LOOK_SWAY_MAX, LOOK_SWAY_MAX)
	var back = minf(1.0, dt * LOOK_SWAY_RETURN)
	sway_yaw = lerpf(sway_yaw, 0.0, back)
	sway_pitch = lerpf(sway_pitch, 0.0, back)

	var roll = (sin(g.time * 0.85) * 0.010 * still + step_side * 0.025 * bob_mul * moving) * calm
	var tilt = step_up * 0.018 * bob_mul * moving * calm
	update_kick(dt)
	gun_base = gun_base.lerp(p, minf(1.0, dt * 18.0))
	gun_node.position = gun_base + Vector3(0.0, kick_dip, kick_back)
	gun_node.rotation = Vector3(
		(
			kick_rise
			+ (0.18 if g.sprinting else 0.0)
			+ tilt
			+ sway_pitch * calm
			+ LOAD_TILT.x * lb
			- jolt * PUMP_JOLT_PITCH
		),
		(1.0 - g.ads_t) * 0.06 + sway_yaw * calm,
		roll + kick_roll + LOAD_TILT.y * lb
	)
	pump.position = Vector3(0.0, pump.position.y, -0.30 + PUMP_TRAVEL * pump_slide)
	g.gun["light"].light_energy = 3.0 * (g.flash / 0.07) if g.flash > 0.0 else 0.0

	# muzzle flash: bright for the first moments after a shot, smaller while aiming so it does not cover the sights
	var flash_node = g.gun.get("flash")
	if flash_node != null:
		var fl = clampf(g.flash / 0.07, 0.0, 1.0) if g.flash > 0.0 else 0.0
		flash_node.visible = fl > 0.0 and gun_node.visible
		flash_node.scale = Vector3.ONE * lerpf(0.5, 1.15, fl) * (1.0 - g.ads_t * 0.5)
		flash_node.rotation = Vector3(0.0, 0.0, flash_roll)

	# ammo count on the gun: cyan, amber when nearly empty, red when empty, INF with the rapid-fire pickup
	var ammo_label = g.gun.get("ammo")
	if ammo_label != null:
		var unlimited = g.buffs["rapid"] > 0.0
		var txt = "INF" if unlimited else str(g.shells)
		if txt != ammo_text:
			ammo_text = txt
			ammo_label.text = txt
		var ac = Color(0.22, 0.91, 1.0)
		if not unlimited and g.shells <= 0:
			ac = Color(1.0, 0.29, 0.23)
		elif not unlimited and g.shells <= 2:
			ac = Color(1.0, 0.69, 0.18)
		ammo_label.modulate = ac

	# shell ejection: when the pump pulls the slide back, the spent shell flies out of the right side
	if not pumping:
		shell_out = false
	elif not shell_out and pump_slide >= SHELL_EJECT_AT and gun_node.visible:
		shell_out = true
		eject_shell(gun_node)
	if g.viewmodel != null:
		g.viewmodel.update(g.ads_t)

	# rubber swing
	var sw = 0.0
	if g.swing_t > 0.0:
		var k = 1.0 - g.swing_t / 0.26
		sw = (-1.0 + 2.0 * k) * g.swing_dir
	rb.position = Vector3(0.3, -0.34, -0.5 + (0.0 if g.swing_t <= 0.0 else -0.12))
	rb.rotation = Vector3(0.0, sw * 0.9, -0.15 + sw * 0.25)
	update_jelly(dt, sw, rb.visible)

	# melee reach ring on the floor
	var show_ring = g.melee and g.state == "play" and not g.paused
	g.melee_ring.visible = show_ring
	if show_ring:
		var z = g.combat_sys.swing_zone()
		var rr = z["r"] * 0.8
		g.melee_ring.position = Vector3(z["c"].x, 0.04, z["c"].z)
		g.melee_ring.scale = Vector3(rr, 1.0, rr)


# A hit shudders the club: speed (swing units per second) is added to the tip along the swing, and the flash lights it up.
func jelly_kick(speed: float, flash: float) -> void:
	jelly_tip_v += speed * g.swing_dir
	jelly_flash = maxf(jelly_flash, flash)


# Jelly club wobble: a spring chases the swing, and the lag between the swing and the spring bends the club.
# sw is the swing position (-1 to 1, 0 at rest); the same number that turns the club in update_gun.
func update_jelly(dt: float, sw: float, shown: bool) -> void:
	var mats = g.rubber.get("wobble", [])
	if mats.is_empty():
		return
	if not shown:
		jelly_tip = 0.0  # start from rest when the club comes back
		jelly_tip_v = 0.0
		return
	var step = minf(dt, 1.0 / 30.0)  # a long frame must not blow the spring up
	jelly_tip_v += (JELLY_STIFFNESS * (sw - jelly_tip) - JELLY_DAMPING * jelly_tip_v) * step
	jelly_tip += jelly_tip_v * step
	jelly_phase += JELLY_RIPPLE_SPEED * step
	var lag = sw - jelly_tip  # > 0 while the swing runs ahead of the tip
	var side = lag * JELLY_BEND
	var droop = -absf(lag) * JELLY_DROOP
	var ripple = minf(JELLY_RIPPLE_IDLE + absf(jelly_tip_v) * JELLY_RIPPLE_GAIN, JELLY_RIPPLE_MAX)
	var squash = minf(absf(lag) * JELLY_SQUASH, JELLY_SQUASH_MAX) + jelly_flash * JELLY_HIT_SQUASH
	jelly_flash = maxf(0.0, jelly_flash - step * JELLY_FLASH_FADE)
	for m in mats:
		m.set_shader_parameter("wob", Vector2(side, droop))
		m.set_shader_parameter("jelly", ripple)
		m.set_shader_parameter("phase", jelly_phase)
		m.set_shader_parameter("squash", squash)
		m.set_shader_parameter("flash", jelly_flash)
