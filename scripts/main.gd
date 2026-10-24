extends Node3D
# Fstreli Biciklina 3D - full v4 port in first person.
#
# Rules (rounds, riders, phones, bosses, hype, pickups, melee, upgrades) are ported from the
# web game. World lives in world.gd, models in models.gd, overlay in hud.gd, sound in sfx.gd.

const Lighting = preload("res://scripts/lighting.gd")
const Util = preload("res://scripts/util.gd")
const WorldBuilder = preload("res://scripts/world.gd")
const Models = preload("res://scripts/models.gd")
const HudScript = preload("res://scripts/hud.gd")
const Toon = preload("res://scripts/toon.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const Content = preload("res://scripts/content.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const PedestriansScript = preload("res://scripts/pedestrians.gd")
const PickupsScript = preload("res://scripts/pickups.gd")
const PhonesScript = preload("res://scripts/phones.gd")
const BossesScript = preload("res://scripts/bosses.gd")
const RidersScript = preload("res://scripts/riders.gd")
const ShopScript = preload("res://scripts/shop.gd")
const CombatScript = preload("res://scripts/combat.gd")
const EffectsScript = preload("res://scripts/effects.gd")
const InputScript = preload("res://scripts/input.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ScoresScript = preload("res://scripts/scores.gd")
const MetaScript = preload("res://scripts/meta.gd")
const ViewmodelScript = preload("res://scripts/viewmodel.gd")
const DailyScript = preload("res://scripts/daily.gd")
const ArenaRoundaboutScript = preload("res://scripts/arena_roundabout.gd")
const MapGenScript = preload("res://scripts/map_gen.gd")
const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArenaScript = preload("res://scripts/arena_generated.gd")
const WorldGeneratedScript = preload("res://scripts/world_generated.gd")

# ------------------------------------------------------------------ tuning
# The arena is a roundabout (ring.gd). All rules still work in "street" coordinates: x along the road,
# z across it. ARENA_HX is half a lap: x runs -HX..HX and the tunnel sits at the seam.
const ARENA_HX = ArenaRoundaboutScript.HX
const LANE_Z = [-5.5, -2.5, 0.5]  # far, middle, near lane
const LANE_MULT = [1.5, 1.2, 1.0]
const SIDEWALK_Z = -11.2
const JOG_Z = -8.8
const CHEER_Z = -12.4
const FAR_WALL_Z = -13.1

const RIDER_SCALE = 0.05  # original pixel speeds -> metres per second
const CIV_SCALE = 0.035
const RIDER_TIME_BONUS = 1.0  # extra seconds on screen: you have to turn your head now
const GRAVITY = 18.0
const PX_TO_M = 0.05

# the gun and worm get their own camera, FOV and depth buffer (viewmodel.gd); false = old single-camera look
const VIEWMODEL_PASS = true
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

# riders in a round without a node that says otherwise (the roundabout, a run without a map)
const DEFAULT_PER_ROUND = 10

# values the HUD reads (vars so they are reachable from another script)
var PER_ROUND = 10  # riders in this round: DEFAULT_PER_ROUND, or what the node says (plan_riders)
var MAX_ROUNDS = 10  # a run is this many rounds; clearing the last one wins the run
var NEED = 6  # hits that clear a round where riders can get away (the roundabout); see hits_needed()
var MAXSHELLS = int(Content.WEAPONS["dart_gun"]["start_clip"])
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
var WEAPONS = Content.WEAPONS

# ------------------------------------------------------------------ state
var state = "title"  # title / play / clear / upgrade / over
var paused = false
var force_captured = false  # test hook: headless Godot cannot capture the mouse, so a check sets this to play a round
var round_n = 1
var score = 0
var hi = 0
var daily_date = ""  # UTC date the daily seed belongs to, "YYYY-MM-DD"
var daily_seed = 0  # same for every player on that date (daily.gd); a Daily Run uses it as its run seed
var daily_label = ""  # title-screen text for the above
var daily_mode = false  # true while a Daily Run is in progress (own scoreboard later, no normal high score)
var custom_seed_run = false  # true while a run with a seed typed in on the title screen is in progress (kept off the normal high score and Top 10, like a Daily Run; a restart replays the same seed)
var run_seed = 0  # the seed this run started with: today's daily seed in a Daily Run, a random one in a normal run
var run_map = {}  # the run map generated from run_seed (map_gen.gd); the run walks it one node per round (see "run map walk" below)
var map_floor = -1  # floor index (0-based) of the node being played, -1 before the first pick
var map_lane = 0  # lane of the node being played
var map_path = []  # the lane taken on every floor so far, in order (map_path[f] is the lane on floor f)
var map_choices = []  # on the map screen: the lanes of the next floor the player may pick
var map_sel = 0  # highlighted entry of map_choices (keyboard / gamepad / mouse hover)
var rider_rng = RandomNumberGenerator.new()  # which riders spawn, reseeded from the run seed at the start of every round
var hearts = 3
var combo = 0
var best_combo = 0
# run timer, to tune the run length (README target: 20-30 minutes). Paused and menu time is not counted.
var play_time = 0.0  # seconds spent fighting this run
var shop_time = 0.0  # seconds on the clear / upgrade / shop screens this run
var round_t = 0.0  # fighting seconds in the current round
var round_times = []  # fighting seconds of each finished round (also printed to the console)
var final_boss_dead = false  # the last round's final boss was defeated (needed to win the run)
var run_won = false  # the run ended by clearing the last round
var kills = 0  # riders and bosses taken down this run
var best_rank = 0  # highest style rank reached this run (0 = D .. 4 = S)
var last_rank = -1  # leaderboard place of the run that just ended (0 = first), -1 = not on the list
var player_name = "PLAYER"  # last name typed on the leaderboard (saved), offered again next time
var name_entry = false  # true on the run summary while the player is typing a name for a new leaderboard entry
var name_buf = ""
var new_unlocks = []  # names of items unlocked by this run (filled once the unlock system exists)
var meta_earned = 0  # meta coins this run paid out (shown on the run summary); run cash is the separate `cash`
var shots_fired = 0
var shots_hit = 0
var civs_hit = 0
var over_reason = ""
var hits = []
var next_idx = 0
var riders = []
var round_modifiers: Array = []  # the node's round modifiers ("rain", "double_riders"), see plan_riders
var rider_plan: Array = []  # the kind of each rider of this round when the node plans them (plan_riders)
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
var round_lives_lost = 0  # lives lost in this round: a round with none lost is perfect where no rider can get away
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
var wind_used = false  # SECOND WIND perk: once per round
var shop_lvl = {}  # how many times each tiered upgrade was bought in the shop (each level costs more)
var shop_buys = 0  # purchases this run: every one makes the next ones dearer
var shop_rerolls = 0  # rerolls in the current shop
var pending = {"rapid": 0.0, "big": 0.0, "shield": false, "hype": false, "free": 0}  # packs, used up at the start of the next round
var pump_base = float(Content.WEAPONS["dart_gun"]["pump_start"])
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
var dash_t = 0.0  # > 0 while dashing
var dash_inv = 0.0  # > 0 while the dash makes you untouchable
var dash_dir = Vector3.ZERO
var slide_t = 0.0
var slide_cd = 0.0
var slide_dir = Vector3.ZERO
var was_sprint = false
var crouch_prev = false
var free_shots = 0  # darts that cost no ammo (SLIDE SHOT perk)
var dodge_cd = 0.0
var perfect_dodges = 0
var hitstop = 0.0  # brief freeze-frame on big hits

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
var title_page = ""  # "" = main menu, otherwise settings / loadout / unlocks / scores
var pause_page = ""  # "" = pause menu, "settings" = settings panel, "confirm" = restart / quit confirmation
var pause_sel = 0  # highlighted pause-menu entry (keyboard / gamepad)
var confirm_id = ""  # what the confirmation asks about: "restart" or "title"
var confirm_sel = 0  # highlighted confirmation button: 0 = NO (the safe default), 1 = YES
var confirm_t0 = 0.0  # g.time when the confirmation opened; YES is ignored for a moment after (double clicks)
var seed_buf = ""  # the hex digits typed on the custom seed page of the title screen (up to 8)
var title_sel = 0  # highlighted title-menu entry (keyboard / gamepad)

var cheerleaders = []
var melee_ring: MeshInstance3D
var flash_mat: Material
var outline_quad: MeshInstance3D  # null while Toon.ENABLED is false
var viewmodel = null  # viewmodel.gd, null when VIEWMODEL_PASS is off
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
	refresh_daily_seed()
	hi = settings.load_hi()
	settings.load_settings()
	hearts = MAXHEARTS
	shells = MAXSHELLS

	if OS.get_cmdline_user_args().has(GENERATED_ARENA_ARG):
		generated_arena = true
	if not (generated_arena and use_generated_arena(daily_seed)):
		world = WorldBuilder.build(self, arena)

	sfx = SfxScript.new()
	add_child(sfx)
	sfx.set_master(volume)
	settings.apply_loaded()

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
	player.position = arena.start_position()
	add_child(player)
	cam = Camera3D.new()
	cam.fov = fov_hip
	cam.near = 0.03
	cam.far = 250.0
	cam.position = Vector3(0, EYE_STAND, 0)
	player.add_child(cam)
	cam.make_current()
	if Toon.ENABLED:
		outline_quad = Toon.make_outline_quad()
		cam.add_child(outline_quad)
	gun = Models.build_gun()
	cam.add_child(gun["root"])
	rubber = Models.build_rubber()
	cam.add_child(rubber["root"])
	rubber["root"].visible = false
	if VIEWMODEL_PASS:
		viewmodel = ViewmodelScript.new(self)
		viewmodel.setup(cam, [gun["root"], rubber["root"]], world["env"])

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
		# a cheerleader never moves, so its world position and facing are worked out once, here
		m["pos"] = arena.tw(cx, CHEER_Z, 0.0)
		var cr: Node3D = m["root"]
		cr.position = m["pos"]
		cr.rotation = Vector3(0.0, -PI * 0.5 + arena.yaw(cx), 0.0)
		m["home_pos"] = m["pos"]  # the roundabout's place for it, which update_arena_dressing goes back to
		m["home_yaw"] = cr.rotation.y
		cheerleaders.append(m)

	var layer = CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_script(HudScript)
	layer.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.g = self

	update_arena_dressing()
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
	var shift = Vector3(0.0, 0.0, player.position.z - 10.0)  # the old street warm-up spot was 4 m in front of the player
	holder.position = shift
	var x = -7.5
	var first = true
	for k in range(6):  # every rider kit (kit 0 is the courier with the box)
		var m = Models.build_rider("courier" if k == 0 else "pro", Models.kit_of(k))
		holder.add_child(m["root"])
		m["root"].position = Vector3(x, 0.0, 0.0)
		Models.pose_rider(m, 0.0, 0.0)
		if first:
			set_flash(m["root"], true)  # compiles the hit-flash overlay
			first = false
		x += 2.0
	x = -7.5
	var pal = {
		"shirt": Color.html("#d65a4a"),
		"pants": Color.html("#2d3a52"),
		"hair": Color.html("#2b1d12"),
		"skin": Color.html("#f0c8a0"),
		"bag": Color.html("#c49a5a")
	}
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
	var ring = MeshInstance3D.new()  # the see-through warning ring under a thrown phone
	ring.mesh = Util.torus_mesh(1.0, 1.12, 24, 4)
	var rmat = StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(1.0, 0.24, 0.16, 0.3)
	ring.material_override = rmat
	holder.add_child(ring)
	ring.position = Vector3(1.5, 0.04, 3.5)
	var warm_strip = boss_sys.make_strip()
	warm_strip.visible = true
	warm_strip.position = Vector3(-3.0, 0.03, 3.5) + shift
	warm_strip.scale = Vector3(2.0, 1.0, 1.0)
	melee_ring.visible = true
	melee_ring.position = Vector3(3.0, 0.04, 3.5) + shift
	rubber["root"].visible = true
	for i in range(8):  # fills the dart / particle pools too
		combat_sys.spawn_dart(
			Vector3(i * 0.3 - 1.0, 1.0, 4.0) + shift,
			Vector3(i * 0.3 - 1.0, 1.0, 3.0) + shift,
			false
		)
	fx_sys.burst(
		Vector3(0.0, 1.0, 4.0) + shift,
		60,
		["#2b2f36", "#ff9a3a", "#3fa0ff", "#c9ced4"],
		0.5,
		0.25,
		0.35,
		0.07
	)
	fx_sys.spawn_particle(
		Vector3(0.5, 1.0, 4.0) + shift, Vector3.ZERO, 0.3, mat_dust, Vector3(0.1, 0.1, 0.1), 0.0
	)
	fx_sys.spawn_particle(
		Vector3(0.7, 1.0, 4.0) + shift,
		Vector3.ZERO,
		0.3,
		confetti_mats[0],
		Vector3(0.14, 0.01, 0.09),
		0.0,
		3.0
	)

	for i in range(4):
		await get_tree().process_frame
	holder.queue_free()
	warm_strip.queue_free()
	melee_ring.visible = false
	rubber["root"].visible = false
	cover_layer.queue_free()


# ------------------------------------------------------------------ graphics quality (F9)
var quality = 0  # 0 = 2x MSAA + shadows (2048 map), 1 = FXAA + shadows (1024 map), 2 = no anti-aliasing, no shadows, no glow (see settings.gd)
var arena = ArenaRoundaboutScript.new()  # arena.gd: the space the run is played in (the roundabout, arena_roundabout.gd, unless the generated arena flag is on)
# The generated arena flag (README Milestone K): off by default, so the game is the roundabout as always. Turn it
# on by starting the game with the user argument --generated-arena (godot --path . -- --generated-arena). Then the
# title screen shows the arena made from today's daily seed and every run plays on the arena made from its run
# seed (arena_generated.gd, world_generated.gd). Work in progress: bosses come out of a gate; pedestrians come out
# of a gate and walk to another one; the cheerleaders stand on the start plaza.
const GENERATED_ARENA_ARG = "--generated-arena"
var generated_arena = false
var world_root: Node3D = null  # the generated arena's world (the roundabout's is built straight into this node)
var settings = SettingsScript.new(self)  # settings.gd: saved settings, graphics quality, high score file
var phone_sys = PhonesScript.new(self)  # phones.gd: Phones: riders throwing phones at the player and the phones in flight.
var pickup_sys = PickupsScript.new(self)  # pickups.gd: Pickups: drops from kills, floating collectibles, magnet and collection.
var civ_sys = PedestriansScript.new(self)  # pedestrians.gd: Pedestrians (civilians): spawning, walking, getting hit.
var boss_sys = BossesScript.new(self)  # bosses.gd: Bosses: spawning, telegraphed attacks, weak points, phases and defeat.
var rider_sys = RidersScript.new(self)  # riders.gd: Riders: spawning waves, movement and sound, collisions, hits and losing parts.
var shop_sys = ShopScript.new(self)  # shop.gd: Shop: between-round upgrades, the shop and its prices, perks and duos, plus style meter and cash.
var combat_sys = CombatScript.new(self)  # combat.gd: Combat: shotgun and reload, melee swing, deflecting phones and the dart projectiles.
var fx_sys = EffectsScript.new(self)  # effects.gd: Effects: pooled particles, bursts, plastic debris and confetti.
var scores = ScoresScript.new(self)  # scores.gd: Scores: the local Top 10 leaderboard saved to user://scores.json.
var meta = MetaScript.new(self)  # meta.gd: Meta currency: earned from finished runs, saved to user://meta.json, separate from run cash.
var input_sys = InputScript.new(self)  # input.gd: Input: mouse, keyboard and gamepad handling, menu clicks and weapon switching.
var player_sys = PlayerScript.new(self)  # player.gd: Player: movement, dash and slide, perfect dodges, aim assist, spread and gun handling.


# Recomputes today's daily seed (UTC date). Called at start-up and whenever the title screen opens,
# so a game left running past midnight UTC picks up the new day's seed.
func refresh_daily_seed() -> void:
	daily_date = DailyScript.date_string()
	daily_seed = DailyScript.seed_for(daily_date)
	daily_label = "DAILY SEED %s   %s UTC" % [DailyScript.seed_text(daily_seed), daily_date]


# the HUD calls these two on main, so they stay as thin wrappers
func get_setting(id: String):
	return settings.get_setting(id)


func set_setting(id: String, v) -> void:
	settings.set_setting(id, v)


# true when this run counts for the normal high score and Top 10: not a Daily Run and not a typed-in seed
# (a seed everybody can replay would let one easy seed be farmed)
func ranked_run() -> bool:
	return not daily_mode and not custom_seed_run


func hi_check() -> void:
	if not ranked_run():  # daily and custom-seed runs stay off the normal high score
		return
	if score > hi:
		hi = score
		settings.save_hi(hi)


# Makes the arena generated from seed_value the arena of the game and builds its world (the old generated world is
# freed). Returns false and changes nothing when the seed gives no usable layout, so the game goes on with the
# arena it had. The caller puts the player on arena.start_position() and applies the theme and quality again.
func use_generated_arena(seed_value: int) -> bool:
	var layout = ArenaGenScript.generate(seed_value)
	if layout.is_empty():
		push_warning(
			(
				"main: seed %s gave no generated arena, keeping the one in use"
				% DailyScript.seed_text(seed_value)
			)
		)
		return false
	if world_root != null:
		remove_child(world_root)
		world_root.free()
	arena = GeneratedArenaScript.new(layout)
	civ_sys.clear_civs()  # a pedestrian walks between the gates of the arena it was made for
	world_root = Node3D.new()
	world_root.name = "GeneratedWorld"
	add_child(world_root)
	world = WorldGeneratedScript.build(world_root, arena)
	print(
		(
			"generated arena for seed %s: %d gates, %d triangles, %d draw calls"
			% [
				DailyScript.seed_text(seed_value),
				arena.gates().size(),
				world["tris"],
				world["draw_calls"]
			]
		)
	)
	return true


# what stands on the ground that depends on the arena: the cheerleaders. The roundabout has them on its far sidewalk
# (where they were built). A generated arena says where they stand (arena.cheer_spots, on its start plaza) and they
# face the start; one it has no spot for is hidden.
func update_arena_dressing() -> void:
	var spots = arena.cheer_spots(cheerleaders.size())
	for i in range(cheerleaders.size()):
		var m = cheerleaders[i]
		var cr: Node3D = m["root"]
		if arena.rider_pursuit():
			cr.visible = i < spots.size()
			if cr.visible:
				m["pos"] = spots[i]
				cr.rotation = Vector3(0.0, rider_sys.yaw_of(arena.start_position() - spots[i]), 0.0)
		else:
			cr.visible = true
			m["pos"] = m["home_pos"]
			cr.rotation = Vector3(0.0, m["home_yaw"], 0.0)
		cr.position = m["pos"]


func apply_theme(i: int) -> void:
	Lighting.apply_theme(THEMES[i], world)
	if viewmodel != null:
		viewmodel.sync_env(world["env"])


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


# ---- run layout randomness. Every run (normal or daily) draws the parts that shape it (rider mix, shop and
# upgrade offers, starting boss and lighting theme) from generators seeded by the run seed, so a run can be
# replayed from its seed. A Daily Run uses the daily seed, a normal run a random one (shown on the run summary).
# Moment-to-moment randomness (effects, aim spread, drops) stays unseeded.
func layout_f() -> float:
	return rider_rng.randf()


func layout_i(n: int) -> int:
	return rider_rng.randi() % n


func layout_shuffle(arr: Array) -> void:
	DailyScript.shuffle_with(arr, rider_rng)


# shuffles an offer list; the order depends only on the run seed, the round and `part`
func offer_shuffle(arr: Array, part: String) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = DailyScript.stream_seed(run_seed, round_n, part)
	DailyScript.shuffle_with(arr, rng)


# the seed rotates which boss comes first and which lighting theme starts, so each seed feels different
func seed_shift(n: int) -> int:
	return run_seed % n


# engine callback: the logic lives in input.gd
func _input(event: InputEvent) -> void:
	input_sys.handle_input(event)


# engine callback: the game window lost focus (Alt+Tab, a click on another window)
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		pause_on_focus_loss()


# The game is paused by letting go of the mouse (see `_process`), so pausing on focus loss means
# releasing it. Only a round in progress is paused; the title screen, menus and the pause menu
# itself are left alone. Returns true when it paused the game.
func pause_on_focus_loss() -> bool:
	if state != "play":
		return false
	var captured = force_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if not captured:
		return false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	force_captured = false  # the test hook as well, so a check sees the game pause
	return true


# ================================================================== game flow
func reset_run() -> void:
	MAXSHELLS = int(WEAPONS["dart_gun"]["start_clip"])
	pump_base = float(WEAPONS["dart_gun"]["pump_start"])
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


func go_to_title() -> void:
	state = "title"
	state_t = 0.0
	title_page = ""
	last_rank = -1
	name_entry = false
	refresh_daily_seed()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# leave a run in progress (pause menu: quit to title); the run is simply dropped
func abandon_run() -> void:
	clear_riders()
	clear_bosses()
	clear_phones()
	clear_pickups()
	go_to_title()


# `daily`: a Daily Run (today's seed). `custom_seed`: 0 to 4294967295 to play that seed (typed in on the title
# screen); -1 draws a random one.
func start_game(daily: bool = false, custom_seed: int = -1) -> void:
	reset_run()
	meta.begin_run()
	daily_mode = daily
	custom_seed_run = not daily and custom_seed >= 0
	if daily:
		refresh_daily_seed()
		run_seed = daily_seed
	elif custom_seed_run:
		run_seed = custom_seed & 0xFFFFFFFF
	else:
		run_seed = DailyScript.random_seed()
	if generated_arena and use_generated_arena(run_seed):  # one arena per run, made from the run seed
		update_arena_dressing()
		settings.apply_quality()
	run_map = MapGenScript.generate(run_seed)
	print(MapGenScript.to_text(run_map))
	print(MapGenScript.content_text(run_map))
	round_n = 1
	map_floor = -1
	map_lane = 0
	map_path = []
	map_choices = []
	map_sel = 0
	if not run_map.is_empty():
		MAX_ROUNDS = run_map["floors"].size()  # a run is one node on every floor of the map
	score = 0
	hearts = MAXHEARTS
	combo = 0
	best_combo = 0
	run_won = false
	final_boss_dead = false
	play_time = 0.0
	shop_time = 0.0
	round_times = []
	kills = 0
	best_rank = 0
	last_rank = -1
	name_entry = false
	new_unlocks = []
	shots_fired = 0
	shots_hit = 0
	civs_hit = 0
	yaw = 0.0
	pitch = 0.0
	player.position = arena.start_position()
	pvel = Vector3.ZERO
	if run_map.is_empty():
		start_round()  # no map (it could not be generated): play the rounds in a line, as before
	else:
		enter_map()


# ---- run map walk. The run walks the map from floor 1 to the final boss, one node per round, and picks the
# next node on the map screen (state "map"). The floor number is the round number, so everything that grows with
# the round (rider speed, prices, boss strength) is unchanged. What each node TYPE does (elite, shop, event, rest,
# boss) is still the old round: those are the next roadmap items, so for now the type is only shown.
const NODE_NAMES = {
	"normal": "NORMAL FIGHT",
	"elite": "ELITE FIGHT",
	"shop": "SHOP",
	"event": "EVENT",
	"rest": "REST STOP",
	"boss": "BOSS"
}


# the node being played, or {} before the first pick or when there is no map
func current_node() -> Dictionary:
	if run_map.is_empty() or map_floor < 0 or map_floor >= run_map["floors"].size():
		return {}
	return run_map["floors"][map_floor][map_lane]


# What the node being played says about the round (its "content", docs/MAP_GENERATION.md), or {} when there is none.
# Only on an arena with rider pursuit (the generated arena): the content is made for it (its gate numbers are the
# layout's), so the roundabout plays every node as it always did.
func node_setup() -> Dictionary:
	if not arena.rider_pursuit():
		return {}
	return current_node().get("content", {})


# the theme of the round: the node's, where it has one, otherwise the old rule (round number and run seed)
func round_theme() -> int:
	var setup = node_setup()
	if setup.has("theme"):
		return int(setup["theme"]) % THEMES.size()
	return (round_n - 1 + seed_shift(THEMES.size())) % THEMES.size()


# The riders of this round from the node's content: how many (PER_ROUND) and of which kinds, in a shuffled order
# (rider_plan, one kind per rider, read by rider_sys.spawn_rider). Without a node's content a round has
# DEFAULT_PER_ROUND riders and no plan, so riders are drawn as they always were.
func plan_riders() -> void:
	rider_plan = []
	round_modifiers = []
	PER_ROUND = DEFAULT_PER_ROUND
	var setup = node_setup()
	if not setup.has("riders"):
		return
	round_modifiers = setup.get("modifiers", [])
	var mix: Dictionary = setup["riders"]["mix"]
	for kind in mix:
		for k in range(int(mix[kind])):
			rider_plan.append(str(kind))
	if rider_plan.is_empty():
		return
	layout_shuffle(rider_plan)
	PER_ROUND = rider_plan.size()


# true if the node being played has this round modifier
func has_modifier(name: String) -> bool:
	return round_modifiers.has(name)


# the kind the node plans for rider number i of this round, or "" when it plans none (draw it as usual)
func planned_rider_type(i: int) -> String:
	if i >= 0 and i < rider_plan.size():
		return rider_plan[i]
	return ""


# the lanes of the next floor the player may pick: every node of floor 1 at the start, otherwise the nodes the
# current one connects to
func next_lanes() -> Array:
	var out = []
	if run_map.is_empty() or map_floor + 1 >= run_map["floors"].size():
		return out
	if map_floor < 0:
		for i in range(run_map["floors"][0].size()):
			out.append(i)
	else:
		for j in current_node()["next"]:
			out.append(int(j))
	return out


# opens the map screen with the choices for the next round
func enter_map() -> void:
	map_choices = next_lanes()
	map_sel = 0
	state = "map"
	state_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# plays the i-th choice of the map screen as the next round
func pick_node(i: int) -> void:
	if state != "map" or i < 0 or i >= map_choices.size():
		return
	map_lane = int(map_choices[i])
	map_floor += 1
	map_path.append(map_lane)
	round_n = map_floor + 1
	sfx.play("click")
	start_round()


# between rounds, after the shop: on to the map screen (or the next round of a linear run)
func next_round() -> void:
	if run_map.is_empty():
		round_n += 1
		start_round()
	else:
		enter_map()


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
	theme_idx = round_theme()
	apply_theme(theme_idx)
	rider_rng.seed = DailyScript.stream_seed(run_seed, round_n, "riders")
	plan_riders()
	round_t = 0.0
	hits.clear()
	for i in range(PER_ROUND):
		hits.append(null)
	next_idx = 0
	round_lives_lost = 0
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
	if has_modifier("double_riders"):
		add_note("DOUBLE RIDERS", GOLD)


func count_hits() -> int:
	var n = 0
	for h in hits:
		if h == true:
			n += 1
	return n


# Can a rider get away? On the roundabout a rider that is not hit gives up after its time limit and rides out of
# the tunnel ("GOT AWAY"). On an arena with rider pursuit (the generated arena) it never gives up: it keeps coming
# back until it is shot, so every rider ends up hit and the round ends when the last one is down.
func riders_can_escape() -> bool:
	return not arena.rider_pursuit()


# riders that have to be hit to clear the round: NEED where they can get away, all of them where they cannot
func hits_needed() -> int:
	if riders_can_escape():
		return NEED
	return PER_ROUND


# a perfect round: every rider hit where they can get away; where they cannot (so every rider is hit anyway), no
# life lost during the round
func is_perfect_round(n: int) -> bool:
	if riders_can_escape():
		return n == PER_ROUND
	return n >= PER_ROUND and round_lives_lost == 0


func fmt_time(sec: float) -> String:
	var s = int(sec)
	return "%d:%02d" % [int(sec / 60.0), s % 60]


func is_final_round() -> bool:
	return round_n >= MAX_ROUNDS


func need_boss() -> bool:
	if round_n < 2 or bosses.size() > 0 or pending_boss:
		return false
	# a fight node on a generated arena decides for itself: a boss node has its boss after the riders (and only
	# once, when they are all down), any other fight node has none. Nodes without riders (shop, rest, event) and
	# the roundabout keep the old rule below.
	var setup = node_setup()
	if setup.has("riders"):
		return (
			setup.has("boss")
			and boss_count == 0
			and next_idx >= PER_ROUND
			and count_hits() >= hits_needed()
		)
	if is_final_round():
		# the last round has no ordinary bosses: after the riders comes the final boss, if you got far enough to face it
		return boss_count == 0 and next_idx >= PER_ROUND and count_hits() >= hits_needed()
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
		wait_msg = "FINAL BOSS" if is_final_round() else "BOSS FIGHT"
		return
	if next_idx >= PER_ROUND:
		end_round()
	else:
		wait = 0.75
		wait_msg = "GOT AWAY" if wave_miss else ""


func end_round() -> void:
	var n = count_hits()
	round_times.append(round_t)
	print(
		(
			"[run timer] round %d: %s fighting, run so far %s (+%s in shops)"
			% [round_n, fmt_time(round_t), fmt_time(play_time), fmt_time(shop_time)]
		)
	)
	var perfect = is_perfect_round(n)
	clear_phones()
	if perfect:
		score += 5000
		add_note("PERFECT  +5000", GOLD)
		fx_sys.confetti()
	hi_check()
	state_t = 0.0
	if n >= hits_needed() and is_final_round() and final_boss_dead:
		win_run()
	elif n >= hits_needed():
		state = "clear"
		hearts = mini(MAXHEARTS, hearts + 1)
		sfx.play("clear")
		sfx.v_cheer()
		sfx.say("round_perfect" if perfect else "round_clear")
	else:
		state = "over"
		over_reason = "riders"
		meta.award_run()
		scores.submit_run()
		sfx.play("over")
		sfx.v_groan()
		sfx.say("game_over")


# the last round was cleared: the run is won. It ends on the same summary screen as a loss.
func win_run() -> void:
	run_won = true
	state = "over"
	over_reason = "victory"
	meta.award_run()
	scores.submit_run()
	fx_sys.confetti()
	sfx.play("clear")
	sfx.v_cheer()
	sfx.say("round_clear")


func game_over(reason: String) -> void:
	clear_riders()
	clear_bosses()
	clear_phones()
	state = "over"
	state_t = 0.0
	over_reason = reason
	hi_check()
	meta.award_run()
	scores.submit_run()
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
		player_sys.perfect_dodge()
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
		if shop_sys.has_duo("LIFE INSURANCE"):
			shop_sys.add_cash(80)
		return
	hearts -= 1
	round_lives_lost += 1
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


# ================================================================== frame loop
func _process(delta: float) -> void:
	var dt = minf(delta, 0.05)
	if hitstop > 0.0:
		hitstop -= delta
		dt *= 0.1
	var captured = force_captured or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	paused = (state == "play" and not captured)
	if not paused:
		pause_page = ""
		pause_sel = 0
		confirm_sel = 0
	time += dt
	player_sys.update_player(dt, captured)
	if not paused:
		update_game(dt)
	player_sys.update_gun(dt)
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
	return arena.tw(x, z, y)


func ptx() -> float:
	return arena.to_track(player.position).x


func ptz() -> float:
	return arena.to_track(player.position).y


func rider_world(r: Dictionary, y: float) -> Vector3:
	return r["pos"] + Vector3(0.0, y, 0.0)


func boss_world(b: Dictionary, y: float) -> Vector3:
	return b["wp"] + Vector3(0.0, y, 0.0)


# put a street-aligned node on the ring and turn it along the road
func place(node: Node3D, x: float, y: float, z: float) -> void:
	node.position = arena.tw(x, z, y)
	node.rotation.y = arena.yaw(x)


# street-space velocity to world (riders no longer use it; tools/arena_check.gd still compares it)
func street_vel(x: float, vx: float, vy: float, vz: float) -> Vector3:
	return arena.tangent(x) * vx + Vector3(0.0, vy, 0.0) + arena.inward(x) * vz


# things that can hurt you or that you can shoot: the edge arrows and the radar read this. Each entry has the world
# position "pos", the "kind" ("rider", "boss" or "phone"), "urg" (how pressing it is, 0 to 1), "dist" (metres to the
# player over the ground) and "closing" (metres per second it moves towards the player over the ground: negative
# when it moves away; only riders have a velocity, the rest are 0)
func threat_list() -> Array:
	var out = []
	for r in riders:
		if (r["mode"] == "fly" or r["mode"] == "away") and not r["hidden"]:
			var vel = rider_sys.heading_vec(r["yaw"]) * r["ride_speed"]
			out.append(
				threat_entry(rider_world(r, 1.0), "rider", 0.45 if r["can_throw"] else 0.3, vel)
			)
	for b in bosses:
		if boss_sys.boss_hittable(b):
			var urg = 0.6
			if b["mode"] == "tele" or b["mode"] == "lunge":
				urg = 1.0
			elif b["mode"] == "stagger":
				urg = 0.35
			out.append(threat_entry(boss_world(b, 1.0), "boss", urg))
	for ph in phones:
		if not ph["ret"]:
			out.append(threat_entry(ph["pos"], "phone", 0.55 + 0.45 * clampf(ph["p"], 0.0, 1.0)))
	return out


# one threat: see threat_list. vel is its velocity (zero when it has none).
func threat_entry(
	pos: Vector3, kind: String, urg: float, vel: Vector3 = Vector3.ZERO
) -> Dictionary:
	var to = Vector3(player.position.x - pos.x, 0.0, player.position.z - pos.z)
	var dist = to.length()
	var closing = 0.0
	if dist > 0.01:
		closing = (to / dist).dot(Vector3(vel.x, 0.0, vel.z))
	return {"pos": pos, "kind": kind, "urg": urg, "dist": dist, "closing": closing}


# keep a point on the walkable ground (sliding along an edge, not stopping dead): the arena decides where
func clamp_walk(p: Vector3, who: String = "player") -> Vector3:
	return arena.clamp_walk(p, who)


# solid for darts
func ray_blocked(p: Vector3) -> bool:
	return arena.ray_blocked(p)


func move_world(mv: Vector2) -> Vector3:
	var b = player.global_transform.basis
	var fwd = -b.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var right = b.x
	right.y = 0.0
	right = right.normalized()
	return fwd * mv.y + right * mv.x


func update_cheerleaders(_dt: float) -> void:
	var chv = maxf(cheer, 1.0) if hype_t > 0.0 else cheer
	for i in range(cheerleaders.size()):
		var m = cheerleaders[i]
		var ph = time * (4.0 + chv * 4.0) + i * 1.1
		var jump = absf(sin(ph)) * (0.08 + chv * 0.32)
		var cr: Node3D = m["root"]
		cr.position = m["pos"] + Vector3(0.0, jump, 0.0)
		Models.pose_cheer(m, ph, chv)


func cheer_say() -> void:
	var txt = pick_one(["BRAVO!", "DAJMO!", "FSTRELI!", "YEAH!"])
	var i = randi() % cheerleaders.size()
	add_popup(cheerleaders[i]["pos"] + Vector3(0.0, 2.5, 0.0), txt, Color(1.0, 0.82, 0.93), true)


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
	if state == "play":
		play_time += dt
		round_t += dt
	elif state == "clear" or state == "upgrade" or state == "shop" or state == "map":
		shop_time += dt
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
			combat_sys.deflect_scan()
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
		if shop_sys.style_rank() >= 4 and shells < MAXSHELLS and not loading:
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

	fx_sys.update_particles(dt)
	combat_sys.update_darts(dt)
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
			combat_sys.start_load()
		if (
			riders.size() == 0
			and bosses.size() == 0
			and wait > 0.0
			and shells < MAXSHELLS
			and not loading
		):
			combat_sys.start_load()
	if loading and pump_t <= 0.0:
		load_t -= dt
		if load_t <= 0.0:
			shells += 1
			sfx.play("shell_tick")
			load_t = combat_sys.reload_step()
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
	boss_sys.update_bosses(gdt)
	if riders.size() == 0 and bosses.size() == 0 and wait > 0.0:
		wait -= dt
		if wait <= 0.0:
			if pending_boss:
				pending_boss = false
				boss_sys.spawn_boss()
			elif next_idx < PER_ROUND:
				rider_sys.spawn_wave()
		return
	for i in range(riders.size() - 1, -1, -1):
		if i < riders.size():
			rider_sys.update_rider(riders[i], gdt)
