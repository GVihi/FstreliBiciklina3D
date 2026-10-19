extends Node3D
# Fstreli Biciklina 3D - full v4 port in first person.
#
# Rules (rounds, riders, phones, bosses, hype, pickups, melee, upgrades) are ported from the
# web game. World lives in world.gd, models in models.gd, overlay in hud.gd, sound in sfx.gd.

const Util = preload("res://scripts/util.gd")
const WorldBuilder = preload("res://scripts/world.gd")
const Models = preload("res://scripts/models.gd")
const HudScript = preload("res://scripts/hud.gd")
const Toon = preload("res://scripts/toon.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const Ring = preload("res://scripts/ring.gd")
const Content = preload("res://scripts/content.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const PedestriansScript = preload("res://scripts/pedestrians.gd")
const PickupsScript = preload("res://scripts/pickups.gd")
const PhonesScript = preload("res://scripts/phones.gd")

# ------------------------------------------------------------------ tuning
# The arena is a roundabout (ring.gd). All rules still work in "street" coordinates: x along the road,
# z across it. ARENA_HX is half a lap: x runs -HX..HX and the tunnel sits at the seam.
const ARENA_HX = Ring.HX
const LANE_Z = [-5.5, -2.5, 0.5] # far, middle, near lane
const LANE_MULT = [1.5, 1.2, 1.0]
const SIDEWALK_Z = -11.2
const JOG_Z = -8.8
const CHEER_Z = -12.4
const FAR_WALL_Z = -13.1
const PLAYER_R_MIN = 2.3         # the fountain
const PLAYER_R_MAX = 22.3        # the buildings

const RIDER_SCALE = 0.05         # original pixel speeds -> metres per second
const CIV_SCALE = 0.035
const RIDER_TIME_BONUS = 1.0     # extra seconds on screen: you have to turn your head now
const GRAVITY = 18.0
const PX_TO_M = 0.05

const FOV_HIP = 78.0
const FOV_ADS = 40.0
const SENS = 0.0022
const WALK = 3.2
const RUN = 5.8
const CROUCH_SPEED = 1.6
const EYE_STAND = 1.7
const EYE_CROUCH = 1.1

const DASH_TIME = 0.22
const DASH_SPEED = 15.0
const SLIDE_TIME = 0.75
const SLIDE_SPEED = 9.0

const GOLD = Color(0.95, 0.71, 0.19)
const WHITE = Color(1, 1, 1)
const RED = Color(0.9, 0.33, 0.24)
const PINK = Color(1.0, 0.7, 0.9)
const ACCENT = Color(1.0, 0.42, 0.17)

# values the HUD reads (vars so they are reachable from another script)
var PER_ROUND = 10
var NEED = 6
var MAXSHELLS = 6
var MAXHEARTS = 3
# game content tables live in content.gd; same names, so the HUD still reads g.NAME
var OVER_MSG = Content.OVER_MSG
var TYPES = Content.TYPES
var THEMES = Content.THEMES
var BOSS_KINDS = Content.BOSS_KINDS
var BOSS_INFO = Content.BOSS_INFO
var CHEER_PX = Content.CHEER_PX
var DROPS = Content.DROPS
var DROP_INFO = Content.DROP_INFO
var SHOP_POOL = Content.SHOP_POOL
var DUOS = Content.DUOS
var UPGRADES = Content.UPGRADES

# ------------------------------------------------------------------ state
var state = "title"          # title / play / clear / upgrade / over
var paused = false
var round_n = 1
var score = 0
var hi = 0
var hearts = 3
var combo = 0
var best_combo = 0
var shots_fired = 0
var shots_hit = 0
var civs_hit = 0
var over_reason = ""
var hits = []
var next_idx = 0
var riders = []
var civs = []
var bosses = []
var phones = []
var pickups = []
var particles = []
var darts = []
var popups = []
var notes = []
var offers = []
var wait = 0.0
var wait_msg = ""
var wave_miss = false
var boss_count = 0
var pending_boss = false
var throw_cool = 0.0
var flash = 0.0
var red_flash = 0.0
var hit_marker = 0.0
var shake = 0.0
var time = 0.0
var state_t = 0.0
var theme_idx = 0
var civ_t = 1.0
var amb_t = 6.0
var bird_t = 3.0
var invuln = 0.0

# v4: hype, buffs, melee, upgrades
var melee = false
var swing_t = 0.0
var swing_cd = 0.0
var swing_dir = 1.0
var hype = 0.0
var hype_t = 0.0
var hype_gain = 1.0
var cheer = 0.0
var shout_t = 0.0
var buffs = {"rapid": 0.0, "big": 0.0, "slow": 0.0, "shield": 0.0}
var up = {"wide": 0, "rubber": 0, "luck": 0.0, "reload": 0, "dashcd": 0, "magnet": 0}
var wind_used = false     # SECOND WIND perk: once per round
var shop_lvl = {}         # how many times each tiered upgrade was bought in the shop (each level costs more)
var shop_buys = 0         # purchases this run: every one makes the next ones dearer
var shop_rerolls = 0      # rerolls in the current shop
var pending = {"rapid": 0.0, "big": 0.0, "shield": false, "hype": false, "free": 0}   # packs, used up at the start of the next round
var pump_base = 0.2
var pump_dur = 0.2

# shotgun
var shells = 6
var pump_t = 0.0
var pump_fired = true
var loading = false
var load_t = 0.0
var recoil = 0.0
var bloom = 0.0
var spread_deg = 2.0

# player
var player: Node3D
var cam: Camera3D
var gun = {}
var rubber = {}
var hud
var sfx
var world = {}
var yaw = 0.0
var pitch = 0.0
var pvel = Vector3.ZERO
var crouch_t = 0.0
var ads_t = 0.0
var bob_t = 0.0
var sprinting = false

# v6: movement
var dash_cd = 0.0
var dash_t = 0.0          # > 0 while dashing
var dash_inv = 0.0        # > 0 while the dash makes you untouchable
var dash_dir = Vector3.ZERO
var slide_t = 0.0
var slide_cd = 0.0
var slide_dir = Vector3.ZERO
var was_sprint = false
var crouch_prev = false
var free_shots = 0        # darts that cost no ammo (SLIDE SHOT perk)
var dodge_cd = 0.0
var perfect_dodges = 0
var hitstop = 0.0         # brief freeze-frame on big hits

# v6: economy + style
var cash = 0
var style = 0.0
var style_idle = 0.0
var regen_t = 0.0
var perks = {}
var shop_items = []
var menu_sel = 0

# v6: settings (saved to user://settings.cfg)
var fov_hip = FOV_HIP
var sens_mul = 1.0
var toggle_ads = false
var ads_on = false
var aim_assist = 0.6
var volume = 1.0
var outlines = true
var drag_id = ""
var settings_open = false

var cheerleaders = []
var melee_ring: MeshInstance3D
var flash_mat: Material
var outline_quad: MeshInstance3D
var strip_mat: StandardMaterial3D
var disc_mat: StandardMaterial3D
const STRIP_COL_WARN = Color(1.0, 0.75, 0.15, 0.35)
const STRIP_COL_LOCK = Color(1.0, 0.15, 0.1, 0.6)
var mat_cache = {}
var mat_spark: Material
var mat_dust: Material
var mat_dart: Material
var mat_tip: Material
var confetti_mats = []

# ================================================================== setup
func _ready() -> void:
	randomize()
	hi = settings.load_hi()
	settings.load_settings()
	hearts = MAXHEARTS
	shells = MAXSHELLS

	world = WorldBuilder.build(self, ARENA_HX)

	sfx = SfxScript.new()
	add_child(sfx)
	sfx.set_master(volume)

	mat_spark = Util.unshaded(Color.html("#ff9a3a"))
	mat_dust = Util.unshaded(Color(0.72, 0.67, 0.58))
	mat_dart = Util.mat(Color.html("#ff7a1a"), 0.6)
	mat_tip = Util.mat(Color.html("#1c63c8"), 0.6)
	for c in ["#ff6a2b", "#f2b630", "#4a90d6", "#58b36a", "#e8e8e0", "#ee3c8a"]:
		confetti_mats.append(Util.unshaded(Color.html(c)))
	var fm = StandardMaterial3D.new()
	fm.albedo_color = Color(1, 1, 1, 0.55)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_mat = fm
	strip_mat = StandardMaterial3D.new()
	strip_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	strip_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	strip_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	strip_mat.albedo_color = STRIP_COL_WARN
	disc_mat = StandardMaterial3D.new()
	disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	disc_mat.albedo_color = STRIP_COL_WARN

	player = Node3D.new()
	player.position = Ring.tw(0.0, 6.0)
	add_child(player)
	cam = Camera3D.new()
	cam.fov = fov_hip
	cam.near = 0.03
	cam.far = 250.0
	cam.position = Vector3(0, EYE_STAND, 0)
	player.add_child(cam)
	cam.make_current()
	outline_quad = Toon.make_outline_quad()
	cam.add_child(outline_quad)
	gun = Models.build_gun()
	cam.add_child(gun["root"])
	rubber = Models.build_rubber()
	cam.add_child(rubber["root"])
	rubber["root"].visible = false

	# floor ring that shows where the rubber can reach
	melee_ring = MeshInstance3D.new()
	melee_ring.mesh = Util.torus_mesh(0.96, 1.0, 32, 4)
	var rm = Util.unshaded(Color(1.0, 0.48, 0.72))
	melee_ring.material_override = rm
	melee_ring.visible = false
	add_child(melee_ring)

	# cheerleaders on the far sidewalk, three on each side
	for i in range(CHEER_PX.size()):
		var m = Models.build_cheer(i)
		add_child(m["root"])
		var cx = (CHEER_PX[i] - 400.0) * PX_TO_M
		m["root"].position = Ring.tw(cx, CHEER_Z, 0.0)
		var cr: Node3D = m["root"]
		cr.rotation = Vector3(0.0, -PI * 0.5 + Ring.yaw(cx), 0.0)
		m["x"] = cx
		cheerleaders.append(m)

	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(HudScript)
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.g = self

	apply_theme(0)
	settings.apply_quality()
	for i in range(PER_ROUND):
		hits.append(null)
	civ_sys.spawn_civ(-7.0)
	civ_sys.spawn_civ(8.0)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_warm_up()

# Godot compiles a shader the first time something new is drawn, and uploads a mesh the first time it is seen.
# Done mid-game that is a hitch. So we show one of everything for a few frames behind a black cover at start-up.
func _warm_up() -> void:
	var cover_layer = CanvasLayer.new()
	cover_layer.layer = 100
	add_child(cover_layer)
	var cover = ColorRect.new()
	cover.color = Color.BLACK
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cover_layer.add_child(cover)
	cover.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var holder = Node3D.new()
	add_child(holder)
	var shift = Vector3(0.0, 0.0, player.position.z - 10.0)    # the old street warm-up spot was 4 m in front of the player
	holder.position = shift
	var x = -7.5
	var first = true
	for k in range(6):                                   # every rider kit (kit 0 is the courier with the box)
		var m = Models.build_rider("courier" if k == 0 else "pro", Models.kit_of(k))
		holder.add_child(m["root"])
		m["root"].position = Vector3(x, 0.0, 0.0)
		Models.pose_rider(m, 0.0, 0.0)
		if first:
			set_flash(m["root"], true)                    # compiles the hit-flash overlay
			first = false
		x += 2.0
	x = -7.5
	var pal = {"shirt": Color.html("#d65a4a"), "pants": Color.html("#2d3a52"), "hair": Color.html("#2b1d12"),
		"skin": Color.html("#f0c8a0"), "bag": Color.html("#c49a5a")}
	for kind in ["walker", "granny", "jogger", "tourist"]:
		var c = Models.build_civ(kind, pal)
		holder.add_child(c["root"])
		c["root"].position = Vector3(x, 0.0, 1.5)
		Models.pose_civ(c, 0.5, kind == "tourist", kind == "jogger")
		x += 1.6
	for i in range(2):
		var cl = Models.build_cheer(i)
		holder.add_child(cl["root"])
		cl["root"].position = Vector3(x, 0.0, 1.5)
		x += 1.6
	x = -6.0
	for spec in [["mower", 0], ["wifi", 0], ["minister", 0], ["minister", 1], ["runner", 0]]:
		var b = Models.build_boss(spec[0], spec[1], Models.kit_of(5))
		holder.add_child(b["root"])
		b["root"].position = Vector3(x, 0.0, -1.5)
		x += 3.0
	x = -5.0
	for t in DROP_INFO.keys():
		var pk = Models.build_pickup(DROP_INFO[t]["col"], DROP_INFO[t]["ch"])
		holder.add_child(pk["root"])
		pk["root"].position = Vector3(x, 1.0, 2.5)
		x += 2.0
	var ph = Models.build_phone()
	holder.add_child(ph)
	ph.position = Vector3(-1.0, 1.0, 3.5)
	var ring = MeshInstance3D.new()                       # the see-through warning ring under a thrown phone
	ring.mesh = Util.torus_mesh(1.0, 1.12, 24, 4)
	var rmat = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.24, 0.16, 0.3)
	ring.material_override = rmat
	holder.add_child(ring)
	ring.position = Vector3(1.5, 0.04, 3.5)
	var warm_strip = make_strip()
	warm_strip.visible = true
	warm_strip.position = Vector3(-3.0, 0.03, 3.5) + shift
	warm_strip.scale = Vector3(2.0, 1.0, 1.0)
	melee_ring.visible = true
	melee_ring.position = Vector3(3.0, 0.04, 3.5) + shift
	rubber["root"].visible = true
	for i in range(8):                                    # fills the dart / particle pools too
		spawn_dart(Vector3(i * 0.3 - 1.0, 1.0, 4.0) + shift, Vector3(i * 0.3 - 1.0, 1.0, 3.0) + shift, false)
	burst(Vector3(0.0, 1.0, 4.0) + shift, 60, ["#2b2f36", "#ff9a3a", "#3fa0ff", "#c9ced4"], 0.5, 0.25, 0.35, 0.07)
	spawn_particle(Vector3(0.5, 1.0, 4.0) + shift, Vector3.ZERO, 0.3, mat_dust, Vector3(0.1, 0.1, 0.1), 0.0)
	spawn_particle(Vector3(0.7, 1.0, 4.0) + shift, Vector3.ZERO, 0.3, confetti_mats[0], Vector3(0.14, 0.01, 0.09), 0.0, 3.0)

	for i in range(4):
		await get_tree().process_frame
	holder.queue_free()
	warm_strip.queue_free()
	melee_ring.visible = false
	rubber["root"].visible = false
	cover_layer.queue_free()

# ------------------------------------------------------------------ graphics quality (F9)
var quality = 0     # 0 = shadows + 2x MSAA, 1 = no MSAA, 2 = no MSAA and no sun shadows
var settings = SettingsScript.new(self)   # settings.gd: saved settings, graphics quality, high score file
var phone_sys = PhonesScript.new(self)   # phones.gd: Phones: riders throwing phones at the player and the phones in flight.
var pickup_sys = PickupsScript.new(self)   # pickups.gd: Pickups: drops from kills, floating collectibles, magnet and collection.
var civ_sys = PedestriansScript.new(self)   # pedestrians.gd: Pedestrians (civilians): spawning, walking, getting hit.

# the HUD calls these two on main, so they stay as thin wrappers
func get_setting(id: String):
	return settings.get_setting(id)

func set_setting(id: String, v) -> void:
	settings.set_setting(id, v)

func hi_check() -> void:
	if score > hi:
		hi = score
		settings.save_hi(hi)

func apply_theme(i: int) -> void:
	var th = THEMES[i]
	var sm = world["sky_mat"]
	sm.sky_top_color = th["top"]
	sm.sky_horizon_color = th["hor"]
	sm.ground_horizon_color = th["hor"]
	sm.ground_bottom_color = th["top"].darkened(0.5)
	var sun = world["sun"]
	sun.light_color = th["sun"]
	sun.light_energy = th["sun_e"]
	sun.rotation_degrees = Vector3(th["sun_x"], th["sun_y"], 0.0)
	var env = world["env"]
	env.ambient_light_color = th["amb"]
	env.ambient_light_energy = th["amb_e"]
	for l in world["lamps"]:
		l.visible = th["lamps"]
	world["lamp_mat"].emission_energy_multiplier = 3.0 if th["lamps"] else 0.0
	world["win_mat"].emission_energy_multiplier = th["lit"]

func col_mat(hex: String) -> Material:
	if not mat_cache.has(hex):
		mat_cache[hex] = Util.unshaded(Color.html(hex))
	return mat_cache[hex]

func set_flash(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		node.material_overlay = flash_mat if on else null
	for ch in node.get_children():
		set_flash(ch, on)

func pick_one(arr: Array):
	return arr[randi() % arr.size()]

# ================================================================== input
func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			var k = SENS * sens_mul * (cam.fov / fov_hip)
			yaw -= event.relative.x * k
			pitch = clampf(pitch - event.relative.y * k, -1.45, 1.45)
		elif drag_id != "":
			hud.apply_slider(drag_id, get_viewport().get_mouse_position())
	elif event is InputEventMouseButton:
		if not event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				drag_id = ""
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			on_click()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if toggle_ads and state == "play" and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not melee:
				ads_on = not ads_on
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if state == "play":
				toggle_weapon()
	elif event is InputEventJoypadButton and event.pressed:
		on_pad_button(event.button_index)
	elif event is InputEventKey and event.pressed and not event.echo:
		var kc = event.keycode
		if kc == KEY_R:
			if state == "shop":
				reroll()
			else:
				start_load()
		elif kc == KEY_Q:
			if state == "play":
				toggle_weapon()
		elif kc == KEY_SPACE:
			if state == "play":
				try_dash()
			elif state == "shop":
				leave_shop()
		elif kc == KEY_TAB:
			if state == "title":
				settings_open = not settings_open
			elif state == "play":
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif kc == KEY_ENTER or kc == KEY_KP_ENTER:
			menu_confirm()
		elif kc == KEY_LEFT:
			menu_move(-1)
		elif kc == KEY_RIGHT:
			menu_move(1)
		elif kc == KEY_1 or kc == KEY_KP_1:
			if state == "upgrade":
				if state_t > 0.35:
					pick_upgrade(0)
			elif state == "shop":
				buy(0)
			elif state == "play":
				toggle_weapon(false)
		elif kc == KEY_2 or kc == KEY_KP_2:
			if state == "upgrade":
				if state_t > 0.35:
					pick_upgrade(1)
			elif state == "shop":
				buy(1)
			elif state == "play":
				toggle_weapon(true)
		elif kc == KEY_3 or kc == KEY_KP_3:
			if state == "upgrade" and state_t > 0.35:
				pick_upgrade(2)
			elif state == "shop":
				buy(2)
		elif kc == KEY_4 or kc == KEY_KP_4:
			if state == "shop":
				buy(3)
		elif kc == KEY_M:
			sfx.toggle_mute()
		elif kc == KEY_V:
			sfx.toggle_voices()
		elif kc == KEY_F7:
			add_note("VOICE EFFECTS " + ("ON" if sfx.toggle_voice_fx() else "OFF"), GOLD)
		elif kc == KEY_F9:
			settings.cycle_quality()
		elif kc == KEY_F10:
			settings.set_setting("outline", not outlines)
			add_note("OUTLINES " + ("ON" if outlines else "OFF"), GOLD)
		elif kc == KEY_F8:
			hi = 0
			settings.save_hi(0)
		elif kc == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		elif kc == KEY_F11:
			if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			else:
				DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)

# gamepad buttons (sticks and triggers are polled in update_player)
func on_pad_button(btn: int) -> void:
	if btn == JOY_BUTTON_START:
		if state == "play":
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			else:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	if state == "play":
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			return
		if btn == JOY_BUTTON_A:
			try_dash()
		elif btn == JOY_BUTTON_X:
			start_load()
		elif btn == JOY_BUTTON_Y or btn == JOY_BUTTON_RIGHT_SHOULDER or btn == JOY_BUTTON_LEFT_SHOULDER:
			toggle_weapon()
		return
	if btn == JOY_BUTTON_DPAD_LEFT:
		menu_move(-1)
	elif btn == JOY_BUTTON_DPAD_RIGHT:
		menu_move(1)
	elif btn == JOY_BUTTON_A:
		if state == "title":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			start_game()
		elif state == "clear" and state_t > 0.8:
			enter_upgrade()
		elif state == "over" and state_t > 0.8:
			state = "title"
			state_t = 0.0
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		else:
			menu_confirm()
	elif btn == JOY_BUTTON_B and state == "shop":
		leave_shop()
	elif btn == JOY_BUTTON_X and state == "shop":
		reroll()

func menu_move(d: int) -> void:
	if state == "upgrade":
		menu_sel = posmod(menu_sel + d, maxi(1, offers.size()))
	elif state == "shop":
		menu_sel = posmod(menu_sel + d, maxi(1, shop_items.size()))

func menu_confirm() -> void:
	if state == "upgrade" and state_t > 0.35:
		pick_upgrade(menu_sel)
	elif state == "shop":
		buy(menu_sel)
	elif state == "clear" and state_t > 0.8:
		enter_upgrade()

func on_click() -> void:
	var captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if state == "title":
		if settings_open and settings.click_setting(hud.setting_at(get_viewport().get_mouse_position())):
			return
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		start_game()
	elif state == "clear" and state_t > 0.8:
		enter_upgrade()
	elif state == "upgrade" and state_t > 0.35:
		var i = hud.card_at(get_viewport().get_mouse_position())
		if i >= 0:
			pick_upgrade(i)
	elif state == "shop":
		var mp = get_viewport().get_mouse_position()
		var si = hud.card_at(mp)
		if si >= 0:
			buy(si)
		elif hud.continue_rect().has_point(mp):
			leave_shop()
		elif hud.reroll_rect().has_point(mp):
			reroll()
	elif state == "over" and state_t > 0.8:
		state = "title"
		state_t = 0.0
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif state == "play":
		if not captured:
			if not settings.click_setting(hud.setting_at(get_viewport().get_mouse_position())):
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		else:
			fire()

func toggle_weapon(to = null) -> void:
	if to == null:
		melee = not melee
	else:
		melee = to
	sfx.play("click")

# ================================================================== game flow
func reset_run() -> void:
	MAXSHELLS = 6
	pump_base = 0.2
	pump_dur = 0.2
	MAXHEARTS = 3
	melee = false
	swing_t = 0.0
	swing_cd = 0.0
	cash = 0
	style = 0.0
	perks = {}
	free_shots = 0
	dash_cd = 0.0
	dash_t = 0.0
	dash_inv = 0.0
	slide_t = 0.0
	perfect_dodges = 0
	hype = 0.0
	hype_t = 0.0
	hype_gain = 1.0
	cheer = 0.0
	clear_pickups()
	buffs = {"rapid": 0.0, "big": 0.0, "slow": 0.0, "shield": 0.0}
	up = {"wide": 0, "rubber": 0, "luck": 0.0, "reload": 0, "dashcd": 0, "magnet": 0}
	wind_used = false
	shop_lvl = {}
	shop_buys = 0
	shop_rerolls = 0
	pending = {"rapid": 0.0, "big": 0.0, "shield": false, "hype": false, "free": 0}

func start_game() -> void:
	reset_run()
	round_n = 1
	score = 0
	hearts = MAXHEARTS
	combo = 0
	best_combo = 0
	shots_fired = 0
	shots_hit = 0
	civs_hit = 0
	yaw = 0.0
	pitch = 0.0
	player.position = Ring.tw(0.0, 6.0)
	pvel = Vector3.ZERO
	start_round()

func clear_riders() -> void:
	for r in riders:
		free_rider(r)
	riders.clear()

func free_rider(r: Dictionary) -> void:
	r["gone"] = true
	sfx.stop_loop(r["snd"])
	r["snd"] = null
	r["model"]["root"].queue_free()
	for p in r["parts"]:
		p["node"].queue_free()

func clear_bosses() -> void:
	for b in bosses:
		free_boss(b)
	bosses.clear()

func free_boss(b: Dictionary) -> void:
	b["gone"] = true
	sfx.stop_loop(b["snd"])
	b["snd"] = null
	b["model"]["root"].queue_free()
	var strip: Node = b["strip"]
	strip.queue_free()
	var disc: Node = b["disc"]
	disc.queue_free()

func clear_phones() -> void:
	for ph in phones:
		free_phone(ph)
	phones.clear()

func free_phone(ph: Dictionary) -> void:
	ph["node"].queue_free()
	ph["ring"].queue_free()

func clear_pickups() -> void:
	for pk in pickups:
		pk["node"].queue_free()
	pickups.clear()

func start_round() -> void:
	clear_riders()
	clear_bosses()
	clear_phones()
	clear_pickups()
	theme_idx = (round_n - 1) % THEMES.size()
	apply_theme(theme_idx)
	hits.clear()
	for i in range(PER_ROUND):
		hits.append(null)
	next_idx = 0
	popups.clear()
	notes.clear()
	boss_count = 0
	pending_boss = false
	wind_used = false
	invuln = 0.0
	throw_cool = 0.6
	shells = MAXSHELLS
	loading = false
	pump_t = 0.0
	pump_fired = true
	if pending["rapid"] > 0.0:
		buffs["rapid"] = maxf(buffs["rapid"], pending["rapid"])
	if pending["big"] > 0.0:
		buffs["big"] = maxf(buffs["big"], pending["big"])
	if pending["shield"]:
		buffs["shield"] = 1.0
	if pending["free"] > 0:
		free_shots += pending["free"]
	if pending["hype"]:
		hype = 100.0
	pending = {"rapid": 0.0, "big": 0.0, "shield": false, "hype": false, "free": 0}
	wait = 1.7
	wait_msg = "ROUND %d" % round_n
	wave_miss = false
	state = "play"
	state_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sfx.say("round_start")

func count_hits() -> int:
	var n = 0
	for h in hits:
		if h == true:
			n += 1
	return n

func need_boss() -> bool:
	if round_n < 2 or bosses.size() > 0 or pending_boss:
		return false
	if boss_count == 0 and next_idx >= 4:
		return true
	if boss_count == 1 and round_n >= 3 and next_idx >= PER_ROUND:
		return true
	return false

func after_wave() -> void:
	if state != "play" or riders.size() > 0 or bosses.size() > 0:
		return
	if need_boss():
		pending_boss = true
		wait = 1.4
		wait_msg = "BOSS FIGHT"
		return
	if next_idx >= PER_ROUND:
		end_round()
	else:
		wait = 0.75
		wait_msg = "GOT AWAY" if wave_miss else ""

func end_round() -> void:
	var n = count_hits()
	var perfect = (n == PER_ROUND)
	clear_phones()
	if perfect:
		score += 5000
		add_note("PERFECT  +5000", GOLD)
		confetti()
	hi_check()
	state_t = 0.0
	if n >= NEED:
		state = "clear"
		hearts = mini(MAXHEARTS, hearts + 1)
		sfx.play("clear")
		sfx.v_cheer()
		sfx.say("round_perfect" if perfect else "round_clear")
	else:
		state = "over"
		over_reason = "riders"
		sfx.play("over")
		sfx.v_groan()
		sfx.say("game_over")

func game_over(reason: String) -> void:
	clear_riders()
	clear_bosses()
	clear_phones()
	state = "over"
	state_t = 0.0
	over_reason = reason
	hi_check()
	sfx.play("over")
	if reason == "civ":
		sfx.play("siren")
		sfx.say("police")
	else:
		sfx.v_groan()
		sfx.say("game_over")

func damage_player(label: String, reason: String) -> void:
	if state != "play":
		return
	if dash_inv > 0.0:
		perfect_dodge()
		return
	if invuln > 0.0:
		return
	if buffs["shield"] > 0.0:
		buffs["shield"] = 0.0
		invuln = 1.0
		add_note("SHIELD BLOCKED IT", Color(0.79, 0.66, 0.93))
		sfx.play("clank2")
		return
	if hearts <= 1 and perks.has("secondwind") and not wind_used:
		wind_used = true
		invuln = 1.6
		shake = 1.0
		red_flash = 0.35
		add_note("SECOND WIND - HANG ON!", GOLD)
		sfx.play("clank2")
		if has_duo("LIFE INSURANCE"):
			add_cash(80)
		return
	hearts -= 1
	combo = 0
	invuln = 1.3
	shake = 1.0
	red_flash = 0.35
	add_note(label + "  -1 LIFE", RED)
	sfx.play("crash")
	if hearts <= 0:
		game_over(reason)

func add_popup(pos: Vector3, txt: String, col: Color, sm: bool = false) -> void:
	popups.append({"pos": pos, "txt": txt, "col": col, "sm": sm, "t": 0.0})

func add_note(txt: String, col: Color) -> void:
	notes.append({"txt": txt, "col": col, "t": 0.0})

# ------------------------------------------------------------------ upgrades
func upgrade_ok(id: String) -> bool:
	if id == "clip":
		return MAXSHELLS < 12
	if id == "pump":
		return pump_base > 0.11
	if id == "wide":
		return up["wide"] < 4
	if id == "heart":
		return MAXHEARTS < 4
	if id == "rubber":
		return up["rubber"] < 4
	if id == "hype":
		return hype_gain < 2.6
	if id == "luck":
		return up["luck"] < 0.4
	if id == "speedload":
		return up["reload"] < 3
	if id == "dashcd":
		return up["dashcd"] < 4
	if id == "magnet":
		return up["magnet"] < 2
	return false

func apply_upgrade(id: String) -> void:
	if id == "clip":
		MAXSHELLS = mini(12, MAXSHELLS + 2)
	elif id == "pump":
		pump_base = maxf(0.1, pump_base - 0.035)
	elif id == "wide":
		up["wide"] += 1
	elif id == "heart":
		MAXHEARTS += 1
		hearts = mini(MAXHEARTS, hearts + 1)
	elif id == "rubber":
		up["rubber"] += 1
	elif id == "hype":
		hype_gain += 0.5
	elif id == "luck":
		up["luck"] += 0.1
	elif id == "speedload":
		up["reload"] += 1
	elif id == "dashcd":
		up["dashcd"] += 1
	elif id == "magnet":
		up["magnet"] += 1

func upgrade_stat(id: String) -> String:
	if id == "clip":
		return "DARTS %d > %d" % [MAXSHELLS, mini(12, MAXSHELLS + 2)]
	if id == "pump":
		return "PUMP %.2fs > %.2fs" % [pump_base, maxf(0.1, pump_base - 0.035)]
	if id == "wide":
		return "LEVEL %d > %d" % [up["wide"], up["wide"] + 1]
	if id == "heart":
		return "MAX LIVES %d > %d" % [MAXHEARTS, MAXHEARTS + 1]
	if id == "rubber":
		return "LEVEL %d > %d" % [up["rubber"], up["rubber"] + 1]
	if id == "hype":
		return "GAIN x%.1f > x%.1f" % [hype_gain, hype_gain + 0.5]
	if id == "speedload":
		return "LEVEL %d > %d" % [up["reload"], up["reload"] + 1]
	if id == "dashcd":
		return "COOLDOWN %.2fs > %.2fs" % [dash_cooldown(), maxf(0.45, dash_cooldown() - 0.15)]
	if id == "magnet":
		return "LEVEL %d > %d" % [up["magnet"], up["magnet"] + 1]
	return "DROPS +%d%% > +%d%%" % [int(round(up["luck"] * 100.0)), int(round(up["luck"] * 100.0 + 10.0))]

func enter_upgrade() -> void:
	var pool = []
	for u in UPGRADES:
		if upgrade_ok(u["id"]):
			pool.append(u)
	pool.shuffle()
	offers = pool.slice(0, 3)
	state = "upgrade"
	state_t = 0.0
	clear_pickups()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if offers.size() == 0:
		enter_shop()

func pick_upgrade(i: int) -> void:
	if i < 0 or i >= offers.size():
		return
	apply_upgrade(offers[i]["id"])
	sfx.play("pickup")
	sfx.v_cheer()
	sfx.say("upgrade")
	enter_shop()

# ================================================================== frame loop
func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	if hitstop > 0.0:
		hitstop -= delta
		dt *= 0.1
	var captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	paused = (state == "play" and not captured)
	time += dt
	update_player(dt, captured)
	if not paused:
		update_game(dt)
	update_gun(dt)
	update_cheerleaders(dt)
	sfx.set_ambient((state == "play" or state == "title") and not paused)

func pad_on() -> bool:
	return Input.get_connected_joypads().size() > 0

func stick(ax_x: int, ax_y: int) -> Vector2:
	var v = Vector2(Input.get_joy_axis(0, ax_x), Input.get_joy_axis(0, ax_y))
	if v.length() < 0.2:
		return Vector2.ZERO
	return v

# keyboard + left stick, x = right, y = forward
func read_move() -> Vector2:
	var mv = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		mv.y += 1.0
	if Input.is_physical_key_pressed(KEY_S):
		mv.y -= 1.0
	if Input.is_physical_key_pressed(KEY_A):
		mv.x -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		mv.x += 1.0
	if pad_on():
		var ls = stick(JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y)
		mv += Vector2(ls.x, -ls.y)
	return mv

# ------------------------------------------------------------------ roundabout helpers (see ring.gd)
func tw3(x: float, y: float, z: float) -> Vector3:
	return Ring.tw(x, z, y)

func ptx() -> float:
	return Ring.to_track(player.position).x

func ptz() -> float:
	return Ring.to_track(player.position).y

func rider_world(r: Dictionary, y: float) -> Vector3:
	return Ring.tw(r["x"], LANE_Z[r["ln"]], y)

func boss_world(b: Dictionary, y: float) -> Vector3:
	return Ring.tw(b["x"], b["z"], y)

# put a street-aligned node on the ring and turn it along the road
func place(node: Node3D, x: float, y: float, z: float) -> void:
	node.position = Ring.tw(x, z, y)
	node.rotation.y = Ring.yaw(x)

func street_vel(x: float, vx: float, vy: float, vz: float) -> Vector3:
	return Ring.tangent(x) * vx + Vector3(0.0, vy, 0.0) + Ring.inward(x) * vz

# things that can hurt you or that you can shoot: the edge arrows and the radar read this
func threat_list() -> Array:
	var out = []
	for r in riders:
		if (r["mode"] == "fly" or r["mode"] == "away") and not Ring.hidden(r["x"]):
			out.append({"pos": rider_world(r, 1.0), "kind": "rider", "urg": 0.45 if r["can_throw"] else 0.3})
	for b in bosses:
		if boss_hittable(b):
			var urg = 0.6
			if b["mode"] == "tele" or b["mode"] == "lunge":
				urg = 1.0
			elif b["mode"] == "stagger":
				urg = 0.35
			out.append({"pos": boss_world(b, 1.0), "kind": "boss", "urg": urg})
	for ph in phones:
		if not ph["ret"]:
			out.append({"pos": ph["pos"], "kind": "phone", "urg": 0.55 + 0.45 * clampf(ph["p"], 0.0, 1.0)})
	return out

# keep a point on the walkable ground: outside the fountain, inside the buildings, and out of the
# tunnel / planter wedge at the back. Sliding along the edge, not stopping dead.
func clamp_walk(p: Vector3, rmin: float, rmax: float) -> Vector3:
	var r = Vector2(p.x, p.z).length()
	if r < 0.001:
		return Vector3(0.0, p.y, -rmin)
	var rc = clampf(r, rmin, rmax)
	if absf(rc - r) > 0.0001:
		p = Vector3(p.x * rc / r, p.y, p.z * rc / r)
	var tr = Ring.to_track(p)
	var lim = Ring.player_lim()
	if absf(tr.x) > lim:
		tr.x = clampf(tr.x, -lim, lim)
		p = Ring.tw(tr.x, tr.y, p.y)
	return p

# solid for darts: the fountain, the planter and the tunnel block
func ray_blocked(p: Vector3) -> bool:
	var r = Vector2(p.x, p.z).length()
	if r < 1.45 and p.y < 1.1:
		return true
	if r < 0.3 and p.y < 2.4:
		return true
	var a = absf(wrapf(atan2(p.x, -p.z) - PI, -PI, PI))
	if r >= 1.0 and r < Ring.GATE_RHO_IN and a < PI - (Ring.player_lim() / Ring.RHO_REF + 0.06) and p.y < 1.18:
		return true
	if r >= Ring.GATE_RHO_IN and a < Ring.GATE_HALF / Ring.RHO_REF and p.y < 7.5:
		return true
	return false

func move_world(mv: Vector2) -> Vector3:
	var b = player.global_transform.basis
	var fwd = -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right = b.x
	right.y = 0.0
	right = right.normalized()
	return fwd * mv.y + right * mv.x

func update_player(dt: float, captured: bool) -> void:
	var active = (state == "play" and captured)
	var pad = pad_on()
	if not active or melee:
		ads_on = false
	var want_ads = false
	if active and not melee:
		want_ads = ads_on if toggle_ads else Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var want_crouch = active and (Input.is_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_C))
	var pad_sprint = false
	var trig = false
	var mv = Vector2.ZERO
	if active:
		mv = read_move()
		if pad:
			if Input.get_joy_axis(0, JOY_AXIS_TRIGGER_LEFT) > 0.5 and not melee:
				want_ads = true
			if Input.is_joy_button_pressed(0, JOY_BUTTON_B):
				want_crouch = true
			pad_sprint = Input.is_joy_button_pressed(0, JOY_BUTTON_LEFT_STICK)
			trig = Input.get_joy_axis(0, JOY_AXIS_TRIGGER_RIGHT) > 0.5
			var rs = stick(JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y)
			if rs.length() > 0.0:
				var lk = 2.4 * sens_mul * (cam.fov / fov_hip)
				var look = rs.normalized() * rs.length() * rs.length()
				yaw -= look.x * lk * dt
				pitch = clampf(pitch - look.y * lk * dt, -1.45, 1.45)
				apply_aim_assist(dt)

	# timers
	if dash_cd > 0.0:
		dash_cd -= dt
	if dash_inv > 0.0:
		dash_inv -= dt
	if dash_t > 0.0:
		dash_t -= dt
	if slide_cd > 0.0:
		slide_cd -= dt
	if dodge_cd > 0.0:
		dodge_cd -= dt

	# slide: press crouch while sprinting
	var crouch_edge = want_crouch and not crouch_prev
	crouch_prev = want_crouch
	if active and crouch_edge and was_sprint and slide_cd <= 0.0 and slide_t <= 0.0 and dash_t <= 0.0:
		slide_t = SLIDE_TIME
		slide_cd = 1.2
		if pvel.length() > 0.5:
			slide_dir = pvel.normalized()
		else:
			slide_dir = move_world(Vector2(0.0, 1.0))
		slide_dir.y = 0.0
		grant_free_shots()
		sfx.play("whoosh", -8.0)
	if slide_t > 0.0:
		slide_t -= dt
		want_crouch = true
		want_ads = false
	crouch_t = move_toward(crouch_t, 1.0 if want_crouch else 0.0, dt * 6.0)
	ads_t = move_toward(ads_t, 1.0 if want_ads else 0.0, dt * 9.0)
	sprinting = active and (Input.is_key_pressed(KEY_SHIFT) or pad_sprint) and mv.y > 0.0 and not want_crouch and not want_ads
	was_sprint = sprinting

	var speed = RUN * (1.12 if perks.has("sprinter") else 1.0) if sprinting else WALK
	speed = lerpf(speed, CROUCH_SPEED, crouch_t)
	speed *= lerpf(1.0, 0.55, ads_t)

	var target = Vector3.ZERO
	if mv.length() > 0.0:
		mv = mv.limit_length(1.0)
		target = move_world(mv) * speed
	if dash_t > 0.0:
		pvel = dash_dir * lerpf(5.0, DASH_SPEED, clampf(dash_t / DASH_TIME, 0.0, 1.0))
	elif slide_t > 0.0:
		pvel = slide_dir * lerpf(2.0, SLIDE_SPEED, clampf(slide_t / SLIDE_TIME, 0.0, 1.0))
	else:
		pvel = pvel.lerp(target, minf(1.0, dt * 10.0))

	player.position = clamp_walk(player.position + pvel * dt, PLAYER_R_MIN, PLAYER_R_MAX)
	player.rotation.y = yaw

	var spd = pvel.length()
	bob_t += spd * dt * 2.2
	var bob = sin(bob_t) * 0.022 * minf(1.0, spd / RUN) * (1.0 - ads_t)
	if slide_t > 0.0 or dash_t > 0.0:
		bob = 0.0
	cam.position.y = lerpf(EYE_STAND, EYE_CROUCH, crouch_t) + bob
	cam.rotation.x = pitch
	cam.rotation.z = 0.0
	if slide_t > 0.0:
		cam.rotation.z = 0.04
	if shake > 0.0:
		cam.rotation.z += randf_range(-1.0, 1.0) * shake * 0.03
	var kick = 9.0 * clampf(dash_t / DASH_TIME, 0.0, 1.0)
	cam.fov = lerpf(fov_hip, fov_hip * FOV_ADS / FOV_HIP, ads_t) + kick
	spread_deg = current_spread()
	if trig and active:
		fire()

# stick aim help: drifts the crosshair onto whatever is close to it
func apply_aim_assist(dt: float) -> void:
	if aim_assist <= 0.0:
		return
	var org = cam.global_position
	var fwd = -cam.global_transform.basis.z
	var best = null
	var best_ang = deg_to_rad(8.0)
	var cands = []
	for r in riders:
		if (r["mode"] == "fly" or r["mode"] == "away") and not Ring.hidden(r["x"]):
			cands.append(tw3(r["x"], 1.2, LANE_Z[r["ln"]]))
	for b in bosses:
		if boss_hittable(b):
			cands.append(tw3(b["x"], weak_point_y(b), b["z"]))
	for ph in phones:
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
	var kk = clampf(dt * 2.5 * aim_assist, 0.0, 1.0)
	yaw = lerp_angle(yaw, atan2(-to.x, -to.z), kk)
	pitch = lerpf(pitch, asin(clampf(to.y, -1.0, 1.0)), kk)

func grant_free_shots() -> void:
	if not perks.has("slideshot"):
		return
	free_shots = 5 if has_duo("QUICK DRAW") else 3
	add_note("SLIDE SHOT: %d FREE DARTS" % free_shots, GOLD)

func dash_cooldown() -> float:
	var c = 1.3 - 0.15 * float(up["dashcd"])
	if perks.has("adrenaline"):
		c *= 0.6
	if has_duo("SPEEDSTER"):
		c *= 0.8
	return maxf(0.3, c)

func try_dash() -> void:
	if state != "play" or paused or dash_cd > 0.0 or dash_t > 0.0:
		return
	var mv = read_move()
	var dir = Vector3.ZERO
	if mv.length() > 0.1:
		dir = move_world(mv.normalized())
	else:
		dir = Ring.tangent(ptx()) * (-1.0 if ptx() > 0.0 else 1.0)      # nothing held: dash along the island towards the front
	dir.y = 0.0
	dash_dir = dir.normalized()
	dash_t = DASH_TIME
	dash_inv = DASH_TIME + 0.18 + (0.15 if has_duo("GHOST") else 0.0)
	dash_cd = dash_cooldown()
	slide_t = 0.0
	grant_free_shots()
	sfx.play("whoosh", -4.0)

# something would have hit you while the dash made you untouchable
func perfect_dodge() -> void:
	if dodge_cd > 0.0:
		return
	dodge_cd = 0.5
	perfect_dodges += 1
	var v = int(250 * (2 if hype_t > 0.0 else 1) * style_mul())
	score += v
	hi_check()
	add_hype(15.0)
	add_style(15.0)
	add_cash(2)
	add_note("PERFECT DODGE  +%d" % v, GOLD)
	hitstop = 0.12
	sfx.play("clank2", -6.0)
	if has_duo("MATADOR"):
		shells = mini(MAXSHELLS, shells + 3)
	if perks.has("closeshave") and perfect_dodges % 2 == 0 and hearts < MAXHEARTS:
		hearts += 1
		add_note("CLOSE SHAVE  +1 LIFE", RED)

func current_spread() -> float:
	var s = lerpf(2.2, 0.25, ads_t)
	s *= 1.0 + clampf(pvel.length() / RUN, 0.0, 1.0) * 0.9
	s *= lerpf(1.0, 0.7, crouch_t)
	if perks.has("steady"):
		s *= 0.7
	return s + bloom

func cur_pump() -> float:
	if buffs["rapid"] > 0.0:
		return 0.08
	if hype_t > 0.0:
		return pump_base * 0.65
	return pump_base

func ex_bonus() -> float:
	# extra hit radius in metres from fat-dart upgrades and the fat-dart pickup
	return (up["wide"] * 5.0 + (18.0 if buffs["big"] > 0.0 else 0.0)) * 0.025

func update_gun(dt: float) -> void:
	var g: Node3D = gun["root"]
	var rb: Node3D = rubber["root"]
	var menu = state == "upgrade" or state == "shop"
	g.visible = not melee and not menu
	rb.visible = melee and not menu
	var pump: Node3D = gun["pump"]
	var hip = Vector3(0.24, -0.22, -0.52)
	var ads = Vector3(0.0, -0.062, -0.42)
	var p = hip.lerp(ads, ads_t)
	p.z += recoil * 0.07
	p.y -= (0.05 if sprinting else 0.0) + (0.04 if loading else 0.0)
	g.position = g.position.lerp(p, minf(1.0, dt * 18.0))
	g.rotation = Vector3(recoil * 0.14 + (0.18 if sprinting else 0.0), (1.0 - ads_t) * 0.06, 0.0)
	var phase = 0.0
	if pump_t > 0.0:
		phase = sin(PI * (1.0 - pump_t / maxf(pump_dur, 0.01)))
	if loading:
		phase = maxf(phase, 0.5 * (0.5 + 0.5 * sin(time * 24.0)))
	pump.position = Vector3(0.0, pump.position.y, -0.30 + 0.12 * phase)
	gun["light"].light_energy = 3.0 * (flash / 0.07) if flash > 0.0 else 0.0

	# rubber swing
	var sw = 0.0
	if swing_t > 0.0:
		var k = 1.0 - swing_t / 0.26
		sw = (-1.0 + 2.0 * k) * swing_dir
	rb.position = Vector3(0.3, -0.34, -0.5 + (0.0 if swing_t <= 0.0 else -0.12))
	rb.rotation = Vector3(0.0, sw * 0.9, -0.15 + sw * 0.25)

	# melee reach ring on the floor
	var show_ring = melee and state == "play" and not paused
	melee_ring.visible = show_ring
	if show_ring:
		var z = swing_zone()
		var rr = z["r"] * 0.8
		melee_ring.position = Vector3(z["c"].x, 0.04, z["c"].z)
		melee_ring.scale = Vector3(rr, 1.0, rr)

func update_cheerleaders(_dt: float) -> void:
	var chv = maxf(cheer, 1.0) if hype_t > 0.0 else cheer
	for i in range(cheerleaders.size()):
		var m = cheerleaders[i]
		var ph = time * (4.0 + chv * 4.0) + i * 1.1
		var jump = absf(sin(ph)) * (0.08 + chv * 0.32)
		var cr: Node3D = m["root"]
		cr.position = Ring.tw(m["x"], CHEER_Z, jump)
		Models.pose_cheer(m, ph, chv)

func cheer_say() -> void:
	var txt = pick_one(["BRAVO!", "DAJMO!", "FSTRELI!", "YEAH!"])
	var i = randi() % cheerleaders.size()
	var cx = float(cheerleaders[i]["x"])
	add_popup(tw3(cx, 2.5, CHEER_Z), txt, Color(1.0, 0.82, 0.93), true)

# ------------------------------------------------------------------ style meter + cash + perks
func add_style(n: float) -> void:
	if state != "play":
		return
	style = minf(100.0, style + n)
	style_idle = 1.6

func style_rank() -> int:
	return clampi(int(style / 20.0), 0, 4)

func style_letter() -> String:
	return ["D", "C", "B", "A", "S"][style_rank()]

# higher style, bigger score: x1.0 at D up to x2.0 at S
func style_mul() -> float:
	return 1.0 + 0.25 * float(style_rank())

func add_cash(n: int) -> void:
	var v = float(n) * (1.0 + 0.08 * float(round_n - 1))      # pay grows a little every round, like the shop prices
	if perks.has("bounty"):
		v *= 1.35
	cash += int(round(v))

func has_duo(nm: String) -> bool:
	for d in DUOS:
		if d["name"] == nm:
			return perks.has(d["a"]) and perks.has(d["b"])
	return false

func perk_name(id: String) -> String:
	for it in SHOP_POOL:
		if it["id"] == id:
			return it["name"]
	return id

func shop_item(id: String) -> Dictionary:
	for it in SHOP_POOL:
		if it["id"] == id:
			return it
	return {}

func shop_ok(id: String) -> bool:
	var it = shop_item(id)
	if it.size() == 0 or int(it["min"]) > round_n:
		return false
	var kind = it["kind"]
	if kind == "heal":
		return hearts < MAXHEARTS
	if kind == "tier":
		return upgrade_ok(id)
	if kind == "pack":
		return true
	return not perks.has(id)

func shop_tag(id: String) -> String:
	for d in DUOS:
		if d["a"] == id or d["b"] == id:
			var other = d["b"] if d["a"] == id else d["a"]
			if perks.has(other):
				return "DUO: " + d["name"] + " - " + d["desc"]
	for d2 in DUOS:
		if d2["a"] == id or d2["b"] == id:
			var other2 = d2["b"] if d2["a"] == id else d2["a"]
			return "PAIRS WITH " + perk_name(other2)
	return ""

func shop_price(it: Dictionary) -> int:
	var v = float(it["cost"]) * (1.0 + 0.12 * float(round_n - 1)) * (1.0 + 0.06 * float(shop_buys))
	if it["kind"] == "tier":
		v *= 1.0 + 0.45 * float(shop_lvl.get(it["id"], 0))
	if perks.has("haggler"):
		v *= 0.85
	return maxi(5, int(round(v / 5.0)) * 5)

func reroll_cost() -> int:
	var v = 20 + 15 * shop_rerolls
	if perks.has("haggler"):
		v = int(v * 0.5)
	return v

func build_shop() -> void:
	var pool = []
	for it in SHOP_POOL:
		if shop_ok(it["id"]):
			var c = it.duplicate()
			c["cost"] = shop_price(it)
			c["sold"] = false
			c["perk"] = it["kind"] == "perk"
			c["tag"] = ""
			if c["perk"]:
				c["tag"] = shop_tag(it["id"])
			elif it["kind"] == "tier":
				c["tag"] = upgrade_stat(it["id"])
			c["label"] = {"perk": "PERK", "pack": "NEXT ROUND", "tier": "UPGRADE", "heal": ""}[it["kind"]]
			pool.append(c)
	pool.shuffle()
	shop_items = []
	# 1. something affordable: a heal if you are hurt, otherwise a pack or one of the plain upgrades
	var cheap = null
	for c in pool:
		if c["kind"] == "heal":
			cheap = c
			break
	if cheap == null:
		for c in pool:
			if c["kind"] != "perk":
				cheap = c
				break
	if cheap != null:
		shop_items.append(cheap)
	# 2. a perk that completes a duo with something you already own
	for c in pool:
		if shop_items.size() < 2 and c["tag"].begins_with("DUO") and not shop_items.has(c):
			shop_items.append(c)
	# 3. at least one perk on every shelf (once you can afford to think about them)
	if round_n >= 2:
		var have_perk = false
		for c in shop_items:
			if c["kind"] == "perk":
				have_perk = true
		if not have_perk:
			for c in pool:
				if c["kind"] == "perk" and not shop_items.has(c):
					shop_items.append(c)
					break
	# 4. fill the rest at random, but never two copies of the same kind of pack
	for c in pool:
		if shop_items.size() < 4 and not shop_items.has(c):
			shop_items.append(c)
	shop_items.shuffle()

func reroll() -> void:
	if state != "shop":
		return
	var cost = reroll_cost()
	if cash < cost:
		add_note("NOT ENOUGH CASH", RED)
		sfx.play("click")
		return
	cash -= cost
	shop_rerolls += 1
	build_shop()
	menu_sel = 0
	sfx.play("pickup")

func enter_shop() -> void:
	shop_rerolls = 0
	build_shop()
	menu_sel = 0
	state = "shop"
	state_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	sfx.say("shop")

func leave_shop() -> void:
	if state != "shop":
		return
	round_n += 1
	start_round()

func buy(i: int) -> void:
	if state != "shop" or i < 0 or i >= shop_items.size():
		return
	var it = shop_items[i]
	if it["sold"]:
		sfx.play("click")
		return
	if cash < it["cost"]:
		add_note("NOT ENOUGH CASH", RED)
		sfx.play("click")
		return
	cash -= it["cost"]
	it["sold"] = true
	shop_buys += 1
	var id = it["id"]
	var kind = it["kind"]
	if kind == "heal":
		hearts = mini(MAXHEARTS, hearts + 1)
	elif kind == "tier":
		apply_upgrade(id)
		shop_lvl[id] = int(shop_lvl.get(id, 0)) + 1
	elif kind == "pack":
		if id == "pack_rapid":
			pending["rapid"] = 25.0
		elif id == "pack_fat":
			pending["big"] = 25.0
		elif id == "pack_shield":
			pending["shield"] = true
		elif id == "pack_hype":
			pending["hype"] = true
		elif id == "pack_free":
			pending["free"] = 12
		add_note(it["name"] + " READY", GOLD)
	else:
		perks[id] = true
		for d in DUOS:
			if (d["a"] == id or d["b"] == id) and has_duo(d["name"]):
				add_note("DUO UNLOCKED: " + d["name"], GOLD)
				sfx.v_cheer()
	sfx.play("pickup")

# ------------------------------------------------------------------ hype
func add_hype(n: float) -> void:
	if hype_t > 0.0 or state != "play":
		return
	hype = minf(100.0, hype + n * hype_gain)
	if hype >= 100.0:
		hype = 100.0
		hype_t = 8.0
		cheer = 2.0
		add_note("HYPE MODE  x2", ACCENT)
		sfx.v_cheer()
		sfx.say("hype")
		cheer_say()

func combo_shout() -> void:
	if shout_t > 0.0:
		return
	if combo == 3:
		add_note("NICE!", WHITE)
		sfx.say("praise")
		cheer_say()
		shout_t = 1.2
	elif combo == 5:
		add_note("UNSTOPPABLE!", ACCENT)
		sfx.say("unstoppable")
		sfx.v_cheer()
		cheer_say()
		cheer = maxf(cheer, 1.5)
		shout_t = 1.2

# ================================================================== update
func update_game(dt: float) -> void:
	state_t += dt
	if invuln > 0.0:
		invuln -= dt
	if red_flash > 0.0:
		red_flash -= dt
	if flash > 0.0:
		flash -= dt
	if hit_marker > 0.0:
		hit_marker -= dt
	if swing_t > 0.0:
		swing_t -= dt
		if swing_t > 0.08 and state == "play":
			deflect_scan()
	if swing_cd > 0.0:
		swing_cd -= dt
	if shout_t > 0.0:
		shout_t -= dt
	if cheer > 0.0:
		cheer = maxf(0.0, cheer - dt * 0.6)
	if throw_cool > 0.0:
		throw_cool -= dt
	if shake > 0.0:
		shake = maxf(0.0, shake - dt * 4.0)
	if recoil > 0.0:
		recoil = maxf(0.0, recoil - dt * 4.5)
	if bloom > 0.0:
		bloom = maxf(0.0, bloom - dt * 2.0)
	if state == "play":
		if style_idle > 0.0:
			style_idle -= dt
		elif style > 0.0:
			style = maxf(0.0, style - (4.0 + style * 0.06) * dt)
		if style_rank() >= 4 and shells < MAXSHELLS and not loading:
			regen_t -= dt
			if regen_t <= 0.0:
				regen_t = 3.0
				shells += 1

	for i in range(popups.size() - 1, -1, -1):
		popups[i]["t"] += dt
		var pp: Vector3 = popups[i]["pos"]
		pp.y += 0.6 * dt
		popups[i]["pos"] = pp
		if popups[i]["t"] > 1.3:
			popups.remove_at(i)
	for i in range(notes.size() - 1, -1, -1):
		notes[i]["t"] += dt
		if notes[i]["t"] > 1.6:
			notes.remove_at(i)

	update_particles(dt)
	update_darts(dt)
	civ_sys.update_civs(dt)

	# ambience: passing cars and birds
	amb_t -= dt
	if amb_t <= 0.0:
		amb_t = randf_range(7.0, 15.0)
		if state == "play":
			sfx.play("car", -12.0)
	bird_t -= dt
	if bird_t <= 0.0:
		bird_t = randf_range(2.5, 6.0)
		if theme_idx < 2 and state != "over":
			sfx.play("bird", -10.0)

	# shotgun
	if pump_t > 0.0:
		pump_t -= dt
		if not pump_fired and pump_dur - pump_t >= 0.04:
			pump_fired = true
			sfx.play("pump")
	if state == "play":
		if shells == 0 and not loading and pump_t <= 0.15:
			start_load()
		if riders.size() == 0 and bosses.size() == 0 and wait > 0.0 and shells < MAXSHELLS and not loading:
			start_load()
	if loading and pump_t <= 0.0:
		load_t -= dt
		if load_t <= 0.0:
			shells += 1
			sfx.play("shell_tick")
			load_t = reload_step()
			if shells >= MAXSHELLS:
				loading = false

	if state != "play":
		return

	var gdt = dt * 0.55 if buffs["slow"] > 0.0 else dt
	if buffs["rapid"] > 0.0:
		buffs["rapid"] -= dt
	if buffs["big"] > 0.0:
		buffs["big"] -= dt
	if buffs["slow"] > 0.0:
		buffs["slow"] -= dt
	if hype_t > 0.0:
		hype_t -= dt
		if hype_t <= 0.0:
			hype_t = 0.0
			hype = 0.0
	elif hype > 0.0:
		hype = maxf(0.0, hype - 3.0 * dt)
	pickup_sys.update_pickups(dt)
	phone_sys.update_phones(gdt)
	update_bosses(gdt)
	if riders.size() == 0 and bosses.size() == 0 and wait > 0.0:
		wait -= dt
		if wait <= 0.0:
			if pending_boss:
				pending_boss = false
				spawn_boss()
			elif next_idx < PER_ROUND:
				spawn_wave()
		return
	for i in range(riders.size() - 1, -1, -1):
		if i < riders.size():
			update_rider(riders[i], gdt)

# ================================================================== shotgun + melee
func reload_step() -> float:
	return 0.38 * (1.0 - 0.22 * float(up["reload"]))

func start_load() -> void:
	if state != "play" or loading or shells >= MAXSHELLS:
		return
	loading = true
	load_t = reload_step() + 0.12

func ray_dir_with_spread() -> Vector3:
	var sp = deg_to_rad(spread_deg)
	var a = randf() * TAU
	var rr = sqrt(randf()) * sp
	var local = Vector3(sin(rr) * cos(a), sin(rr) * sin(a), -cos(rr))
	return (cam.global_transform.basis * local).normalized()

func fire() -> void:
	if state != "play" or paused:
		return
	if melee:
		swing()
		return
	if pump_t > 0.0:
		return
	if shells <= 0 and buffs["rapid"] <= 0.0 and free_shots <= 0:
		sfx.play("click")
		start_load()
		return
	loading = false
	if buffs["rapid"] <= 0.0:
		if free_shots > 0:
			free_shots -= 1
		else:
			shells -= 1
	var lastshot = perks.has("lastshell") and shells == 0 and buffs["rapid"] <= 0.0
	pump_dur = cur_pump()
	pump_t = pump_dur
	pump_fired = false
	recoil = 1.0
	flash = 0.07
	shake = 0.15
	shots_fired += 1
	sfx.play("shot")
	pitch = clampf(pitch + deg_to_rad(0.7 * (1.0 - 0.5 * ads_t)), -1.45, 1.45)

	var dir = ray_dir_with_spread()
	var org = cam.global_position
	bloom = minf(bloom + 0.5, 1.6)
	var ex = ex_bonus()

	# how far can the dart travel before hitting the world?
	var t_world = 80.0
	var world_kind = ""
	if dir.y < -0.0001:
		var tf = -org.y / dir.y
		if tf > 0.0 and tf < t_world:
			t_world = tf
			world_kind = "floor"
	var ts = 0.5                                                      # fountain, planter and tunnel block
	while ts < t_world:
		if ray_blocked(org + dir * ts):
			t_world = ts
			world_kind = "wall"
			break
		ts += 0.5
	var tfac = Ring.ray_exit_circle(org, dir, Ring.FACADE_RHO)       # buildings all around
	if tfac > 0.0 and tfac < t_world:
		t_world = tfac
		world_kind = "wall"

	# nearest target of every kind
	var best_t = 1000.0
	var best_kind = ""
	var best_obj = null
	for pk in pickups:
		var tp = Util.ray_ellipsoid(org, dir, pk["pos"], Vector3(0.6 + ex, 0.6 + ex, 0.6 + ex))
		if tp > 0.0 and tp < best_t:
			best_t = tp
			best_kind = "pickup"
			best_obj = pk
	for ph in phones:
		if ph["ret"]:
			continue
		var tph = Util.ray_ellipsoid(org, dir, ph["pos"], Vector3(0.5 + ex, 0.4 + ex, 0.5 + ex))
		if tph > 0.0 and tph < best_t:
			best_t = tph
			best_kind = "phone"
			best_obj = ph
	for b in bosses:
		if not boss_hittable(b):
			continue
		var inf = BOSS_INFO[b["kind"]]
		var br: Vector3 = inf["r"]
		var tb2 = Util.ray_ellipsoid_yaw(org, dir, tw3(b["x"], inf["cy"], b["z"]), br + Vector3(ex, ex, ex), Ring.yaw(b["x"]))
		if tb2 > 0.0 and tb2 < best_t:
			best_t = tb2
			best_kind = "boss"
			best_obj = b
	for r in riders:
		if (r["mode"] != "fly" and r["mode"] != "away") or Ring.hidden(r["x"]):
			continue
		var c = tw3(r["x"], 0.95, LANE_Z[r["ln"]])
		var t = Util.ray_ellipsoid_yaw(org, dir, c, Vector3(1.3 + ex, 1.0 + ex, 0.55 + ex), Ring.yaw(r["x"]))
		if t > 0.0 and t < best_t:
			best_t = t
			best_kind = "rider"
			best_obj = r
	for c2 in civs:
		if c2["state"] != "walk" or Ring.hidden(c2["x"]):
			continue
		var s = c2["scale"]
		var ctr = tw3(c2["x"], 0.95 * s, c2["z"])
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

	spawn_dart(gun["muzzle"].global_position, end_pt, stick)

	# near-miss reaction for pedestrians (not the one we hit)
	for c3 in civs:
		if c3["state"] != "walk" or c3 == best_obj or c3["flinch"] > 0.0 or Ring.hidden(c3["x"]):
			continue
		var to = tw3(c3["x"], 0.9, c3["z"]) - org
		var proj = to.dot(dir)
		if proj > 0.0 and proj < 45.0:
			var perp = (to - dir * proj).length()
			if perp < 1.5:
				c3["flinch"] = 0.6
				var cp = tw3(c3["x"], 1.2, c3["z"])
				sfx.v_gasp(cp)
				add_popup(tw3(c3["x"], 2.0, c3["z"]), "JOJ!", WHITE, true)

	if target_hit:
		if best_kind == "rider":
			hit_rider(best_obj, 2 if lastshot else 1)
		elif best_kind == "civ":
			civ_sys.hit_civ(best_obj)
		elif best_kind == "boss":
			var hit_y = (org + dir * best_t).y
			var bo = best_obj
			var is_weak = hit_y >= float(BOSS_INFO[bo["kind"]]["weak_y"]) + boss_hover(bo)
			hit_boss(bo, 2 if lastshot else 1, is_weak, 30.0 if is_weak else 14.0)
		elif best_kind == "phone":
			phone_sys.shoot_phone(best_obj)
		elif best_kind == "pickup":
			pickup_sys.collect_pickup(best_obj)
	else:
		if world_kind == "floor":
			for i in range(3):
				spawn_particle(end_pt, Vector3(randf_range(-0.8, 0.8), randf_range(0.6, 1.6), randf_range(-0.8, 0.8)),
					0.4, mat_dust, Vector3(0.05, 0.05, 0.05), 4.0)
		elif world_kind == "wall":
			for i in range(5):
				spawn_particle(end_pt, Vector3(randf_range(-2.0, 2.0), randf_range(0.5, 2.5), randf_range(-2.0, 2.0)),
					0.3, mat_spark, Vector3(0.04, 0.04, 0.04), 8.0)

# --- melee: a giant gummy worm swung at whatever is close to the player
func swing_zone() -> Dictionary:
	var f = -player.global_transform.basis.z
	f.y = 0.0
	f = f.normalized()
	var c = Vector3(player.position.x + f.x * 2.3, 1.0, player.position.z + f.z * 2.3)
	return {"c": c, "r": 1.5 + up["rubber"] * 0.3}

func flat_dist(a: Vector3, bx: float, bz: float) -> float:
	return Vector2(a.x - bx, a.z - bz).length()

func swing() -> void:
	if swing_cd > 0.0:
		return
	swing_cd = 0.3
	swing_t = 0.26
	swing_dir = -swing_dir
	shots_fired += 1
	sfx.play("swing")
	var z = swing_zone()
	var zc: Vector3 = z["c"]
	var zr: float = z["r"]
	var hit_any = deflect_scan()
	for i in range(pickups.size() - 1, -1, -1):
		if zc.distance_to(pickups[i]["pos"]) < zr * 0.8 + 0.6:
			pickup_sys.collect_pickup(pickups[i])
	for i in range(bosses.size() - 1, -1, -1):
		var b = bosses[i]
		if not boss_hittable(b):
			continue
		var inf = BOSS_INFO[b["kind"]]
		var br: Vector3 = inf["r"]
		if flat_dist_v(zc, boss_world(b, 0.0)) < zr * 0.8 + br.x:
			hit_boss(b, 2, false, 45.0)
			hit_any = true
	for i in range(riders.size() - 1, -1, -1):
		var r = riders[i]
		if r["mode"] != "fly" and r["mode"] != "away":
			continue
		if not Ring.hidden(r["x"]) and flat_dist_v(zc, rider_world(r, 0.0)) < zr * 0.8 + 0.9:
			hit_rider(r, 2)
			hit_any = true
	if hit_any:
		sfx.play3d("rubber", zc)
		shake = 0.35
		hitstop = maxf(hitstop, 0.06)

# --- deflect: a thrown phone that is close when the rubber swings goes straight back at whoever threw it
func deflect_range() -> float:
	return 2.7 + up["rubber"] * 0.3

func deflect_scan() -> bool:
	var any = false
	for ph in phones:
		if ph["ret"]:
			continue
		var pp: Vector3 = ph["pos"]
		var d = Vector2(pp.x - player.position.x, pp.z - player.position.z).length()
		if d <= deflect_range() and pp.y < 2.6:
			deflect_phone(ph)
			any = true
	return any

func deflect_phone(ph: Dictionary) -> void:
	ph["ret"] = true
	ph["chain"] = 2 if perks.has("boomerang") else 0
	if has_duo("RICOCHET"):
		ph["chain"] = 4
	if perks.has("counter"):
		shells = mini(MAXSHELLS, shells + 1)
	ph["rspd"] = 14.0
	var ring_node: Node3D = ph["ring"]
	ring_node.visible = false
	hitstop = maxf(hitstop, 0.08)
	shake = 0.3
	sfx.play3d("rubber", ph["pos"])
	add_popup(ph["pos"] + Vector3(0, 0.6, 0), "DEFLECTED!", PINK, true)
	add_style(12.0)

func target_valid(t) -> bool:
	if t == null:
		return false
	if t.get("gone", false):
		return false
	if t.has("ln"):
		return t["mode"] == "fly" or t["mode"] == "away"
	return boss_hittable(t)

func target_pos(t) -> Vector3:
	if t.has("ln"):
		return tw3(t["x"], 1.1, LANE_Z[t["ln"]])
	return tw3(t["x"], float(BOSS_INFO[t["kind"]]["cy"]) + 0.4, t["z"])

func nearest_target(from: Vector3, skip):
	var best = null
	var bd = 1.0e9
	for r in riders:
		if target_valid(r) and not is_same(r, skip):
			var d = target_pos(r).distance_to(from)
			if d < bd:
				bd = d
				best = r
	for b in bosses:
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
		phones.remove_at(i)
		plastic_burst(ph["pos"])
		sfx.play3d("phone_smash", ph["pos"])
		free_phone(ph)
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

func strike_with_phone(ph: Dictionary, i: int, tgt) -> void:
	var tp = target_pos(tgt)
	plastic_burst(tp)
	sfx.play3d("phone_smash", tp)
	if tgt.has("ln"):
		hit_rider(tgt, 99)
	else:
		hit_boss(tgt, 3, false, 100.0)
	hitstop = 0.12
	var v = int(800 * (2 if hype_t > 0.0 else 1) * style_mul())
	score += v
	hi_check()
	add_popup(tp + Vector3(0, 1.4, 0), "RETURN TO SENDER +%d" % v, GOLD)
	add_cash(36 if has_duo("BOUNTY HUNTER") else 12)
	add_style(25.0)
	if ph["chain"] > 0:
		var nxt = nearest_target(tp, tgt)
		if nxt != null:
			ph["chain"] -= 1
			ph["src"] = nxt
			ph["rspd"] = 20.0
			return
	phones.remove_at(i)
	free_phone(ph)

func flat_dist_v(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

# ================================================================== darts + particles
# Darts and particles are recycled instead of created and freed, so a shot or a burst costs no allocations.
var dart_pool = []
var particle_pool = []

func release_dart(node: Node3D) -> void:
	node.visible = false
	dart_pool.append(node)

func spawn_dart(a: Vector3, b: Vector3, stick: bool) -> void:
	var node: Node3D
	if dart_pool.size() > 0:
		node = dart_pool.pop_back()
		node.visible = true
		node.rotation = Vector3.ZERO
	else:
		node = Node3D.new()
		Util.box(node, Vector3(0.025, 0.025, 0.16), Vector3.ZERO, mat_dart)
		Util.sphere(node, 0.022, Vector3(0, 0, -0.09), mat_tip)
		Util.trim_shadows(node, 1.0)
		add_child(node)
	node.position = a
	if a.distance_to(b) > 0.1:
		var dirn = (b - a).normalized()
		var upv = Vector3.UP
		if absf(dirn.y) > 0.98:
			upv = Vector3.RIGHT
		node.look_at(b, upv)
	var dur = clampf(a.distance_to(b) / 120.0, 0.03, 0.4)
	darts.append({"node": node, "a": a, "b": b, "t": 0.0, "max": dur, "stick": stick})
	while darts.size() > 80:
		release_dart(darts[0]["node"])
		darts.remove_at(0)

func update_darts(dt: float) -> void:
	for i in range(darts.size() - 1, -1, -1):
		var d = darts[i]
		d["t"] += dt
		var node: Node3D = d["node"]
		if d["t"] < d["max"]:
			node.position = d["a"].lerp(d["b"], d["t"] / d["max"])
		else:
			node.position = d["b"]
			if (not d["stick"]) or d["t"] > d["max"] + 4.0:
				release_dart(node)
				darts.remove_at(i)

func spawn_particle(pos: Vector3, vel: Vector3, life: float, m: Material, sz: Vector3, grav: float, spin: float = 0.0) -> void:
	var mi: MeshInstance3D
	if particle_pool.size() > 0:
		mi = particle_pool.pop_back()
		mi.visible = true
		mi.scale = Vector3.ONE
		mi.rotation = Vector3.ZERO
	else:
		mi = MeshInstance3D.new()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	mi.mesh = Util.box_mesh(sz)
	mi.material_override = m
	mi.position = pos
	particles.append({"node": mi, "vel": vel, "life": life, "max": life, "grav": grav, "spin": spin})
	while particles.size() > 300:
		release_particle(particles[0]["node"])
		particles.remove_at(0)

func release_particle(node: Node3D) -> void:
	node.visible = false
	particle_pool.append(node)

func update_particles(dt: float) -> void:
	for i in range(particles.size() - 1, -1, -1):
		var p = particles[i]
		p["life"] -= dt
		var node: Node3D = p["node"]
		if p["life"] <= 0.0:
			release_particle(node)
			particles.remove_at(i)
			continue
		var v: Vector3 = p["vel"]
		v.y -= p["grav"] * dt
		p["vel"] = v
		node.position += v * dt
		if node.position.y < 0.02:
			node.position = Vector3(node.position.x, 0.02, node.position.z)
			p["vel"] = Vector3(v.x * 0.3, 0.0, v.z * 0.3)
		if p["spin"] != 0.0:
			node.rotation += Vector3(p["spin"], p["spin"] * 0.7, 0.0) * dt
		else:
			var f = clampf(p["life"] / p["max"], 0.05, 1.0)
			node.scale = Vector3(f, f, f)

func burst(pos: Vector3, count: int, cols: Array, speed: float, life_lo: float, life_hi: float, size: float) -> void:
	for i in range(count):
		spawn_particle(pos + Vector3(randf_range(-0.3, 0.3), randf_range(-0.3, 0.3), randf_range(-0.3, 0.3)),
			Vector3(randf_range(-speed, speed), randf_range(0.5, speed * 1.2), randf_range(-speed, speed)),
			randf_range(life_lo, life_hi), col_mat(pick_one(cols)), Vector3(size, size, size), 10.0)

func plastic_burst(pos: Vector3) -> void:
	burst(pos, 14, ["#2b2f36", "#3a3f47", "#3fa0ff", "#c9ced4"], 4.0, 0.5, 0.8, 0.07)

func confetti() -> void:
	for i in range(70):
		var pos = Vector3(randf_range(-12.0, 12.0), randf_range(5.0, 9.0), randf_range(-9.0, 2.0))
		spawn_particle(pos, Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 0.5), randf_range(-1.0, 1.0)),
			randf_range(2.5, 4.0), pick_one(confetti_mats), Vector3(0.14, 0.01, 0.09), 1.5, randf_range(-8.0, 8.0))

# ================================================================== riders
func spawn_rider(lane_idx: int, dir: int) -> Dictionary:
	var roll = randf()
	var type = "pro"
	if round_n >= 2 and roll < 0.2:
		type = "sprinter"
	elif round_n >= 2 and roll < 0.4:
		type = "courier"
	if round_n >= 2 and randf() < minf(0.36, 0.12 + round_n * 0.04):
		type = "tough"
	var kit_i = randi() % 4
	if type == "sprinter":
		kit_i = 4
	elif type == "courier":
		kit_i = 0
	elif type == "tough":
		kit_i = 5
	var kit = Models.kit_of(kit_i)
	var diff = 1.0 + (round_n - 1) * 0.13 + next_idx * 0.03
	var base = 165.0 * RIDER_SCALE * diff * TYPES[type]["sp"]
	var hp = 1
	if type == "tough":
		hp = 3 if round_n >= 5 else 2
	var m = Models.build_rider(type, kit)
	add_child(m["root"])
	var x0 = -(ARENA_HX + 2.0) if dir > 0 else (ARENA_HX + 2.0)
	place(m["root"], x0, 0.0, LANE_Z[lane_idx])
	face_rider(m, dir)
	var r = {
		"x": x0, "dir": dir, "ln": lane_idx, "base": base, "spd": base, "tgt": base,
		"chg": randf_range(0.5, 1.2), "wph": 0.0, "cph": 0.0, "mode": "fly", "t": 0.0, "age": 0.0,
		"entered": false, "type": type, "idx": next_idx, "model": m, "parts": [], "kit": kit,
		"limit": maxf(3.0, 6.1 - round_n * 0.35) + RIDER_TIME_BONUS,
		"hp": hp, "max_hp": hp, "flash": 0.0, "snd": null, "gone": false,
		"can_throw": randf() < clampf(0.55 + 0.06 * round_n, 0.6, 0.9), "throw_t": randf_range(0.5, 1.4), "wind_t": 0.0
	}
	next_idx += 1
	riders.append(r)
	r["snd"] = sfx.make_loop("loop_rider", m["root"], Vector3(0, 1.0, 0))
	Models.pose_rider(m, 0.0, 0.0)
	return r

func spawn_wave() -> void:
	var remaining = PER_ROUND - next_idx
	var n = 1
	if round_n >= 2 and remaining >= 2 and randf() < minf(0.55, 0.12 + round_n * 0.08):
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
	wave_miss = false

func face_rider(m: Dictionary, dir: int) -> void:
	var pv: Node3D = m["pivot"]
	pv.rotation = Vector3(0.0, 0.0 if dir > 0 else PI, 0.0)

func update_rider_sound(r: Dictionary) -> void:
	var spd_px = r["spd"] / PX_TO_M
	var vol = 0.05 * clampf(spd_px / 250.0, 0.4, 1.8)
	sfx.set_loop(r["snd"], vol * 2.2, (500.0 + spd_px * 1.6) / 700.0)

# standing on the road is dangerous: a rider that reaches you knocks you down (a dash through it is a perfect dodge)
func rider_collide(r: Dictionary) -> void:
	if state != "play" or Ring.hidden(r["x"]):
		return
	var rp = rider_world(r, 0.0)
	if Vector2(rp.x - player.position.x, rp.z - player.position.z).length() < 0.95:
		damage_player("RUN OVER BY A CYCLIST", "run")

func update_rider(r: Dictionary, dt: float) -> void:
	var m = r["model"]
	var root: Node3D = m["root"]
	var mode = r["mode"]
	if r["flash"] > 0.0:
		r["flash"] -= dt
		if r["flash"] <= 0.0:
			set_flash(root, false)
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
			if r["x"] > ARENA_HX:
				r["x"] -= 2.0 * ARENA_HX
			elif r["x"] < -ARENA_HX:
				r["x"] += 2.0 * ARENA_HX
		r["wph"] += r["spd"] * dt / 0.34
		r["cph"] += dt * (6.0 + 0.444 * r["spd"])
		face_rider(m, r["dir"])
		place(root, r["x"], sin(r["age"] * 10.0) * 0.015, LANE_Z[r["ln"]])
		Models.pose_rider(m, r["cph"], r["wph"])
		update_rider_sound(r)
		rider_collide(r)
		if r["wind_t"] > 0.0:
			r["wind_t"] -= dt
			if r["wind_t"] <= 0.0:
				phone_sys.launch_phone(r)
		elif r["can_throw"] and r["entered"] and not Ring.hidden(r["x"]) and phones.size() < 3:
			r["throw_t"] -= dt
			if r["throw_t"] <= 0.0:
				if throw_cool <= 0.0 and state == "play":
					phone_sys.start_throw(r)
				else:
					r["throw_t"] = 0.3
		if r["age"] > r["limit"]:
			r["mode"] = "away"
			r["dir"] = -1 if r["x"] < 0.0 else 1
			face_rider(m, r["dir"])
			sfx.play3d("whoosh", root.position)
	elif mode == "away":
		r["spd"] = minf(39.0, r["spd"] + 26.0 * dt)
		r["x"] += r["dir"] * r["spd"] * dt
		r["wph"] += r["spd"] * dt / 0.34
		r["cph"] += dt * (6.0 + 0.444 * r["spd"])
		place(root, r["x"], 0.0, LANE_Z[r["ln"]])
		Models.pose_rider(m, r["cph"], r["wph"])
		update_rider_sound(r)
		rider_collide(r)
		if absf(r["x"]) > ARENA_HX + 2.6:
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
				v.y -= GRAVITY * dt
				node.position += v * dt
				node.rotation += p["av"] * dt
				if node.position.y <= p["floor"] and v.y < 0.0:
					node.position = Vector3(node.position.x, p["floor"], node.position.z)
					if absf(v.y) > 2.5:
						var k = clampf(absf(v.y) / 10.0, 0.2, 1.0)
						sfx.play3d("land_s" if k < 0.4 else ("land_m" if k < 0.75 else "land_l"), node.position)
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
	var wpos = tw3(r["x"], 1.0, LANE_Z[r["ln"]])
	if r["hp"] > 0:
		r["flash"] = 0.15
		set_flash(r["model"]["root"], true)
		sfx.play3d("thud", wpos)
		sfx.play3d("clank2", wpos)
		var arm = int(round(150.0 * (1.0 + 0.1 * (round_n - 1))))
		score += arm * (2 if hype_t > 0.0 else 1)
		hi_check()
		add_hype(6.0)
		add_popup(wpos + Vector3(0, 1.2, 0), "ARMOURED  %d LEFT" % r["hp"], WHITE, true)
		burst(wpos, 6, ["#f2b630"], 3.0, 0.3, 0.4, 0.06)
		return
	r["mode"] = "hit"
	r["t"] = 0.0
	r["wind_t"] = 0.0
	sfx.stop_loop(r["snd"])
	r["snd"] = null
	sfx.play3d("hit", wpos)
	shots_hit += 1
	combo = mini(5, combo + 1)
	best_combo = maxi(best_combo, combo)
	var pts = int(round(500.0 * TYPES[r["type"]]["pts"] * LANE_MULT[r["ln"]] * (1.0 + 0.1 * (round_n - 1))))
	pts *= combo
	if hype_t > 0.0:
		pts *= 2
	if melee:
		pts = int(round(pts * 1.5))
	pts = int(round(pts * style_mul()))
	score += pts
	hi_check()
	add_hype(10.0 + 3.0 * combo)
	cheer = maxf(cheer, 0.7 + 0.1 * combo)
	combo_shout()
	add_style(12.0 + (6.0 if melee else 0.0))
	add_cash(13 if r["type"] == "tough" else 5)
	hitstop = maxf(hitstop, 0.09 if melee else 0.04)
	pickup_sys.drop_kill(wpos + Vector3(0, 0.5, 0), r["type"] == "tough")
	var label = "+%d" % pts
	if combo > 1:
		label += "  x%d" % combo
	add_popup(wpos + Vector3(0, 1.0, 0), label, GOLD)
	add_popup(wpos + Vector3(0, 0.5, 0), "JOJ!", WHITE, true)
	burst(wpos, 10, ["#ff9a3a"], 4.0, 0.3, 0.5, 0.06)
	sfx.v_yelp(wpos)
	if randf() < 0.4:
		sfx.say("rider_hit")

func spawn_parts(r: Dictionary) -> void:
	var m = r["model"]
	var dirf = float(r["dir"])
	var sgn = 1.0 if randf() < 0.5 else -1.0
	r["parts"].append(detach_part(m["bike"],
		street_vel(r["x"], dirf * r["spd"] * 0.45 + randf_range(-1.0, 1.0), randf_range(2.5, 4.0), randf_range(-1.5, 1.5)),
		Vector3(randf_range(-6.0, 6.0), randf_range(-4.0, 4.0), randf_range(-6.0, 6.0)), 0.09, sgn * PI * 0.5))
	if r["type"] == "tough":
		# the armoured rider jumps off the bike and runs at you
		spawn_runner(r)
		var man: Node3D = m["man"]
		man.queue_free()
	else:
		r["parts"].append(detach_part(m["man"],
			street_vel(r["x"], dirf * r["spd"] * 0.35 + randf_range(-1.5, 1.5), randf_range(4.0, 5.5), randf_range(-1.5, 1.5)),
			Vector3(randf_range(-5.0, 5.0), randf_range(-3.0, 3.0), randf_range(-5.0, 5.0)), 0.2, -sgn * PI * 0.5))

func detach_part(node: Node3D, vel: Vector3, av: Vector3, floor_y: float, rest_x: float) -> Dictionary:
	var gt = node.global_transform
	node.get_parent().remove_child(node)
	add_child(node)
	node.global_transform = gt
	return {"node": node, "vel": vel, "av": av, "floor": floor_y, "rest_x": rest_x, "landed": false, "rest": 0.0, "done": false}

func resolve(r: Dictionary, hit: bool) -> void:
	var i = riders.find(r)
	if i >= 0:
		riders.remove_at(i)
	free_rider(r)
	hits[r["idx"]] = hit
	if not hit:
		combo = 0
		wave_miss = true
		if randf() < 0.35:
			sfx.say("taunt")
	after_wave()

# ================================================================== bosses
func make_strip() -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	mi.mesh = Util.box_mesh(Vector3(1.0, 0.02, 1.0))
	mi.material_override = strip_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
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
	mi.material_override = disc_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi

# bosses get tougher every round: 32% more health per round after the second
func boss_hp(base: int) -> int:
	return int(round(float(base) * (1.0 + 0.32 * float(maxi(0, round_n - 2)))))

func make_boss_dict(kind: String, nm: String, variant: int, hp: int, m: Dictionary, wp: Vector3, mode: String) -> Dictionary:
	var t = Ring.to_track(wp)
	return {
		"kind": kind, "name": nm, "variant": variant, "hp": hp, "max_hp": hp, "p": 0.7,
		"wp": wp, "x": t.x, "z": t.y, "wyaw": 0.0, "mode": mode, "flash": 0.0, "t": 0.0, "ph": 0.0,
		"snd": null, "step_t": 0.0, "intro": 0.0, "die_t": 0.0, "model": m,
		"gone": false, "phase": 1, "stagger": 0.0, "stagger_t": 0.0, "crashed": false,
		"tele_t": 0.0, "tele_total": 1.0, "lock": wp, "ldir": Vector3(0, 0, 1), "llen": 0.0, "lgo": 0.0,
		"lcrash": false, "lhit": false, "chase_t": 0.0, "throw_t": 2.0,
		"pat": "lunge", "combo": 0, "slam_r": 4.5, "disc": make_disc(),
		"strip": make_strip()
	}

func spawn_boss() -> void:
	var kind = BOSS_KINDS[(round_n + boss_count) % BOSS_KINDS.size()]
	var info = BOSS_INFO[kind]
	var variant = (round_n + boss_count) % 2
	var nm = info["name"]
	if kind == "minister" and variant == 1:
		nm = "PREDSEDNIK POZLATA"
	var hp = boss_hp(int(info["hp"]))
	var m = Models.build_boss(kind, variant, Models.kit_of(0))
	add_child(m["root"])
	var sx = clampf(ptx() + randf_range(-14.0, 14.0), -Ring.lim(), Ring.lim())
	var b = make_boss_dict(kind, nm, variant, hp, m, Ring.tw(sx, -11.6), "charge")
	b["intro"] = 2.2
	b["wyaw"] = atan2(player.position.x - b["wp"].x, player.position.z - b["wp"].z)
	bosses.append(b)
	boss_count += 1
	wave_miss = false
	start_boss_sound(b)
	sfx.play("boss_intro")
	sfx.say(info["voice"])
	pose_boss(b, 0.0)

func spawn_runner(r: Dictionary) -> void:
	var hp = (3 if r["max_hp"] > 2 else 2) + int(floor(float(maxi(0, round_n - 2)) / 2.0))
	var m = Models.build_boss("runner", 0, r["kit"])
	add_child(m["root"])
	var b = make_boss_dict("runner", "ANGRY CYCLIST", 0, hp, m, rider_world(r, 0.0), "charge")
	b["wyaw"] = atan2(player.position.x - b["wp"].x, player.position.z - b["wp"].z)
	bosses.append(b)
	wave_miss = false
	sfx.say("boss_revenge")
	pose_boss(b, 0.0)

func start_boss_sound(b: Dictionary) -> void:
	var root: Node3D = b["model"]["root"]
	if b["kind"] == "mower":
		b["snd"] = sfx.make_loop("loop_mower", root, Vector3(0, 0.5, 0))
	elif b["kind"] == "wifi":
		b["snd"] = sfx.make_loop("loop_wifi", root, Vector3(0, 1.0, 0))

func update_boss_sound(b: Dictionary) -> void:
	if b["snd"] == null:
		return
	var k = minf(1.2, b["p"])
	if b["kind"] == "mower":
		sfx.set_loop(b["snd"], (0.03 + 0.11 * k) * 1.6, (80.0 + 180.0 * k) / 80.0)
	else:
		sfx.set_loop(b["snd"], (0.012 + 0.05 * k) * 1.6, (700.0 + 500.0 * k) / 880.0)

func stop_boss_sound(b: Dictionary) -> void:
	sfx.stop_loop(b["snd"])
	b["snd"] = null

func boss_hover(b: Dictionary) -> float:
	if b["kind"] == "wifi":
		return 0.3 + sin(b["ph"] * 0.6) * 0.12
	return 0.0

func weak_point_y(b: Dictionary) -> float:
	return float(BOSS_INFO[b["kind"]]["wk"]) + boss_hover(b)

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
		b["wyaw"] = atan2(player.position.x - bwp.x, player.position.z - bwp.z)
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
	var i = bosses.find(b)
	if i >= 0:
		bosses.remove_at(i)
	free_boss(b)

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
	return w * clampf(1.0 - 0.04 * float(round_n - 2), 0.65, 1.0)

func boss_speed(b: Dictionary) -> float:
	var v = float(BOSS_INFO[b["kind"]]["speed"]) * (1.0 + 0.10 * float(b["phase"] - 1)) * (1.0 + 0.03 * float(round_n - 1))
	if b["intro"] > 0.0:
		v *= 0.5
	return minf(v, 6.2 if b["kind"] == "runner" else 5.5)       # never faster than your sprint (5.8): running away always works

func lunge_speed(b: Dictionary) -> float:
	return (13.0 if b["kind"] == "runner" else 15.0) * (1.0 + 0.12 * float(b["phase"] - 1)) * (1.0 + 0.03 * float(maxi(0, round_n - 2)))

func set_boss_pos(b: Dictionary, wp: Vector3) -> void:
	wp = clamp_walk(Vector3(wp.x, 0.0, wp.z), 2.1, 22.6)
	b["wp"] = wp
	var t = Ring.to_track(wp)                 # the rest of the game reads the street coordinates
	b["x"] = t.x
	b["z"] = t.y

# things a lunging boss crashes into: the fountain, the buildings, the tunnel / planter wedge
func obstacle_at(p: Vector3) -> bool:
	var r = Vector2(p.x, p.z).length()
	if r < 2.3 or r > Ring.FACADE_RHO - 1.35:
		return true
	return absf(Ring.to_track(p).x) > Ring.player_lim() - 0.05

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
		d = Vector3(player.position.x - wp.x, 0.0, player.position.z - wp.z)
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
	var c = STRIP_COL_LOCK if locked else STRIP_COL_WARN
	c.a = c.a * (0.7 + 0.3 * sin(time * 24.0)) if locked else c.a
	strip_mat.albedo_color = c

func boss_flat_dist(b: Dictionary) -> float:
	var wp: Vector3 = b["wp"]
	return Vector2(player.position.x - wp.x, player.position.z - wp.z).length()

func slam_radius(b: Dictionary) -> float:
	return clampf(4.2 + 0.2 * float(round_n), 4.4, 5.6) + (0.4 if b["phase"] >= 3 else 0.0)

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
		if round_n >= 4:
			w["combo"] = 4.0
	else:
		w["lunge"] = maxf(2.0, [10.0, 5.0, 3.0][ph - 1] - 0.4 * float(round_n - 2))
		if (ph >= 2 or round_n >= 4) and boss_flat_dist(b) < slam_radius(b) + 4.0:
			w["slam"] = 3.0 + 1.5 * float(ph)
		if ph >= 2:
			w["combo"] = 2.0 + 2.0 * float(ph - 1)
			if k != "mower" and phones.size() <= 1:
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
			b["combo"] = 1 + (1 if (b["phase"] >= 3 or round_n >= 5 or (runner and round_n >= 6)) else 0)
			add_popup(tw3(b["x"], 2.2, b["z"]), "COMBO!", RED)
		else:
			b["combo"] = 0
	b["pat"] = pat
	var t = 0.7 if runner else [0.9, 0.75, 0.6][b["phase"] - 1]
	if quick:
		t = 0.34 if runner else 0.42
	elif pat == "slam":
		t = clampf(1.05 - 0.05 * float(round_n), 0.7, 1.05)
		b["slam_r"] = slam_radius(b)
	elif pat == "volley":
		t = 0.8
	b["tele_t"] = t
	b["tele_total"] = t
	b["lock"] = player.position
	sfx.play3d("ring", tw3(b["x"], 1.0, b["z"]), -3.0)

func start_stagger(b: Dictionary, t: float, crashed: bool) -> void:
	hide_strip(b)
	if b["kind"] != "runner":
		t *= clampf(1.0 - 0.06 * float(round_n - 2), 0.6, 1.0)     # the dizzy window shrinks every round
	b["combo"] = 0
	b["pat"] = "lunge"
	b["mode"] = "stagger"
	b["stagger_t"] = t
	b["stagger"] = 0.0
	b["crashed"] = crashed
	sfx.set_loop(b["snd"], 0.0, 1.0)

func boss_steps(b: Dictionary, dt: float) -> void:
	if b["kind"] != "minister" and b["kind"] != "runner":
		return
	b["step_t"] -= dt
	if b["step_t"] <= 0.0:
		b["step_t"] = 0.3 / (1.0 + b["p"])
		var sv = 0.1 + 0.25 * minf(1.0, b["p"])
		sfx.play3d("step", tw3(b["x"], 0.0, b["z"]), linear_to_db(sv / 0.3))

# later phases: the wifi node and the minister throw phones, which you can deflect straight back at them
func boss_throws(b: Dictionary, dt: float) -> void:
	if b["phase"] < 2 or b["kind"] == "mower" or b["kind"] == "runner":
		return
	b["throw_t"] -= dt
	if b["throw_t"] <= 0.0 and phones.size() < 3 and state == "play":
		b["throw_t"] = 3.4 if b["phase"] == 2 else 2.4
		phone_sys.throw_phone(tw3(b["x"], float(BOSS_INFO[b["kind"]]["cy"]) + 0.7, b["z"]), b)

func update_bosses(dt: float) -> void:
	for i in range(bosses.size() - 1, -1, -1):
		if i >= bosses.size():
			continue
		var b = bosses[i]
		b["t"] += dt
		b["ph"] += dt * (9.0 if b["kind"] == "minister" else 14.0)
		if b["flash"] > 0.0:
			b["flash"] -= dt
			if b["flash"] <= 0.0:
				set_flash(b["model"]["root"], false)
		if b["intro"] > 0.0:
			b["intro"] -= dt
		if b["stagger"] > 0.0 and b["mode"] != "stagger":
			b["stagger"] = maxf(0.0, b["stagger"] - 6.0 * dt)
		var removed = update_boss(b, dt)
		if state != "play":
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
	var pp = player.position
	var to = Vector3(pp.x - wp.x, 0.0, pp.z - wp.z)
	var dist = to.length()
	var dir = to / dist if dist > 0.001 else Vector3(0, 0, 1)
	if mode == "charge":
		b["chase_t"] += dt
		var aim = Vector3(pp.x, 0.0, pp.z)
		if b["kind"] == "wifi":                                       # the wifi node weaves about while it comes
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
		if b["tele_t"] > 0.22:                                        # the red lane still follows you, then locks
			b["lock"] = lk.lerp(pp, minf(1.0, dt * 7.0))
		var ld = lunge_dir(b)
		b["wyaw"] = atan2(ld.x, ld.z)
		update_strip(b, b["tele_t"] <= 0.22)
		if b["tele_t"] <= 0.0:
			var d = lunge_dir(b)
			b["ldir"] = d
			var lk2: Vector3 = b["lock"]
			var want = Vector2(lk2.x - wp.x, lk2.z - wp.z).length() + 6.0     # a miss carries on past you
			var pr = lunge_probe(wp, d, want)
			b["llen"] = pr.x
			b["lcrash"] = pr.y > 0.5
			b["lgo"] = 0.0
			b["lhit"] = false
			b["mode"] = "lunge"
			sfx.play3d("whoosh", tw3(b["x"], 1.0, b["z"]))
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
			var evaded = dash_inv > 0.0
			damage_player("CYCLIST TACKLED YOU" if runner else "BOSS REACHED YOU", "boss")
			if state != "play":
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
			after_wave()
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
	var c = STRIP_COL_WARN.lerp(STRIP_COL_LOCK, k)
	if b["tele_t"] < 0.25:
		c.a *= 0.75 + 0.25 * sin(time * 30.0)
	disc_mat.albedo_color = c

func do_slam(b: Dictionary) -> void:
	hide_strip(b)
	var wp: Vector3 = b["wp"]
	var pos = Vector3(wp.x, 0.4, wp.z)
	sfx.play3d("crash", pos)
	shake = maxf(shake, 0.7)
	hitstop = maxf(hitstop, 0.05)
	burst(pos, 22, ["#c9ced4", "#f2b630", "#8a8f98"], 5.0, 0.4, 0.8, 0.1)
	if boss_flat_dist(b) < float(b["slam_r"]):
		damage_player("BOSS SLAMMED YOU", "boss")
		if state != "play":
			return
	else:
		add_style(6.0)
		add_popup(pos + Vector3(0, 1.6, 0), "SLAM DODGED", ACCENT, true)
	start_stagger(b, 1.2, false)

func do_volley(b: Dictionary) -> void:
	var wp: Vector3 = b["wp"]
	var fwd = Vector3(player.position.x - wp.x, 0.0, player.position.z - wp.z)
	if fwd.length() < 0.1:
		fwd = Vector3(0, 0, 1)
	fwd = fwd.normalized()
	var side = Vector3(-fwd.z, 0.0, fwd.x)
	var n = 3 if b["phase"] < 3 else 5
	var start = Vector3(wp.x, float(BOSS_INFO[b["kind"]]["cy"]) + 0.7, wp.z)
	for i in range(n):
		phone_sys.throw_phone(start, b, side * (float(i) - float(n - 1) * 0.5) * 2.0)
	b["mode"] = "charge"
	b["pat"] = "lunge"
	b["chase_t"] = tele_wait(b) * 0.4

# it caught you while chasing: it hurts, then the boss reels for a moment
func boss_tackle(b: Dictionary) -> void:
	damage_player("CYCLIST TACKLED YOU" if b["kind"] == "runner" else "BOSS REACHED YOU", "boss")
	if state != "play":
		return
	shake = maxf(shake, 0.5)
	start_stagger(b, 0.9, false)

# the lunge ran out: either it slammed into something solid (dizzy, and you are rewarded) or it just overshot
func resolve_lunge(b: Dictionary) -> void:
	hide_strip(b)
	var runner = b["kind"] == "runner"
	var wp: Vector3 = b["wp"]
	var pos = Vector3(wp.x, 0.8, wp.z)
	if not b["lcrash"]:
		if b["combo"] > 0 and state == "play":
			b["combo"] -= 1
			start_tele(b, true)
			return
		add_style(5.0)
		add_note("OVERSHOT - HIT IT", ACCENT)
		start_stagger(b, 1.0 if runner else 1.3, false)
		return
	b["combo"] = 0
	sfx.play3d("crash", pos)
	shake = 0.6
	burst(pos, 14, ["#c9ced4", "#f2b630", "#8a8f98"], 3.0, 0.4, 0.7, 0.09)
	hitstop = 0.1
	var sp = 300 if runner else 600
	score += int(sp * (2 if hype_t > 0.0 else 1) * style_mul())
	hi_check()
	add_hype(12.0)
	add_style(20.0)
	add_cash(5 if runner else 12)
	add_popup(pos + Vector3(0, 1.8, 0), "CRASHED!  +%d" % sp, GOLD)
	add_note("DIZZY: HIT IT NOW", ACCENT)
	start_stagger(b, 2.0 if runner else 2.4, true)

func hit_boss(b: Dictionary, dmg: int, weak: bool = false, stag: float = 14.0) -> void:
	if not boss_hittable(b):
		return
	var inf = BOSS_INFO[b["kind"]]
	var c = tw3(b["x"], inf["cy"], b["z"])
	var k = b["kind"]
	var stunned = b["mode"] == "stagger"
	var armoured = weak and not weak_open(b)
	if armoured:
		weak = false
	if k != "runner":
		stag = stag / (1.0 + 0.12 * float(maxi(0, round_n - 2)))     # harder to stagger later on
	var total = dmg * (2 if weak else 1)
	if stunned:
		total += 1
	if weak and perks.has("deadeye"):
		total += 1
	if weak and has_duo("SNIPER") and shells == 0:
		total += 2
	if weak and has_duo("HEADHUNTER"):
		shells = mini(MAXSHELLS, shells + 2)
	b["hp"] -= total
	b["flash"] = 0.12
	set_flash(b["model"]["root"], true)
	shots_hit += 1
	if k == "mower":
		sfx.play3d("boss_hit_mower", c)
	elif k == "wifi":
		sfx.play3d("boss_hit_wifi", c)
	else:
		sfx.play3d("boss_hit_minister", c)
	burst(c, 8, ["#ff9a3a"], 4.0, 0.3, 0.5, 0.06)
	var lbl = "HIT"
	if armoured:
		lbl = "ARMOURED"
	if weak:
		lbl = "WEAK SPOT x2"
		hitstop = maxf(hitstop, 0.05)
		add_style(8.0)
	elif stunned:
		lbl = "DIZZY  +1"
	add_style(4.0)
	add_popup(c + Vector3(0, 1.0, 0), lbl, ACCENT if weak else (Color(0.65, 0.68, 0.72) if armoured else WHITE), true)
	if b["hp"] <= 0:
		kill_boss(b)
		return
	if k != "runner":
		if not stunned:
			b["stagger"] += stag
			if b["stagger"] >= 100.0:
				add_popup(c + Vector3(0, 1.8, 0), "STAGGERED!", GOLD)
				start_stagger(b, 2.4, true)
		var ph = boss_phase(b)
		if ph > b["phase"]:
			b["phase"] = ph
			b["throw_t"] = 1.2
			add_note("PHASE %d" % ph, RED)
			sfx.play("boss_intro", -4.0)
			shake = 0.6
	if k == "minister" and randf() < 0.3:
		sfx.say("minister_hit")

func kill_boss(b: Dictionary) -> void:
	b["mode"] = "dying"
	b["die_t"] = 0.0
	stop_boss_sound(b)
	var is_run = b["kind"] == "runner"
	var pts = (600 + 100 * (round_n - 1)) if is_run else (2000 + 500 * (round_n - 1))
	if hype_t > 0.0:
		pts *= 2
	score += pts
	hi_check()
	add_hype(15.0 if is_run else 40.0)
	cheer = 1.0 if is_run else 2.0
	shout_t = 0.0
	hide_strip(b)
	hitstop = 0.15
	add_style(30.0)
	add_cash(18 if is_run else 55)
	var bpos = tw3(b["x"], 1.0, b["z"])
	if not is_run:
		if hearts < MAXHEARTS:
			hearts += 1
		else:
			score += 1000
			hi_check()
		pickup_sys.maybe_drop(bpos, 1.0)
	else:
		pickup_sys.maybe_drop(bpos, 0.5)
	add_note(("CYCLIST DOWN +" if is_run else "BOSS DOWN +") + str(pts), GOLD)
	if is_run:
		sfx.play3d("thud", bpos)
		sfx.v_yelp(bpos)
	elif b["kind"] == "minister":
		sfx.play("boss_down_minister")
	else:
		sfx.play("boss_down")
	var cols = ["#ffffff", "#f2b630", "#4a90d6"]
	if is_run:
		cols = ["#ffffff", "#f2b630", "#7a3fc0"]
	elif b["kind"] == "mower":
		cols = ["#f1f3ef", "#2fae5f", "#ffd23f", "#3a3d41"]
	elif b["kind"] == "wifi":
		cols = ["#ffffff", "#e5533d", "#cfd4da"]
	burst(bpos, 40, cols, 6.0, 0.6, 1.1, 0.09)
	if b["kind"] == "minister":
		for i in range(26):
			spawn_particle(bpos + Vector3(randf_range(-0.6, 0.6), randf_range(0.3, 1.5), randf_range(-0.6, 0.6)),
				Vector3(randf_range(-2.5, 2.5), randf_range(1.0, 4.0), randf_range(-2.5, 2.5)),
				randf_range(1.5, 2.5), pick_one(confetti_mats), Vector3(0.12, 0.01, 0.08), 3.0, randf_range(-8.0, 8.0))
		sfx.say("minister_out")
