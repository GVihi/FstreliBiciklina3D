extends Node3D
# Fstreli Biciklina 3D - full v4 port in first person.
#
# Rules (rounds, riders, phones, bosses, hype, pickups, melee, upgrades) are ported from the
# web game. World lives in world.gd, models in models.gd, overlay in hud.gd, sound in sfx.gd.

# The name the player sees (title screen logo, window title, later the credits screen). Internal names keep
# "FstreliBiciklina3D" on purpose: the repository, the files, project.godot (`user://` follows its name, so the
# saves must keep loading) and the docs.
const GAME_TITLE = "FB3D"

const Lighting = preload("res://scripts/lighting.gd")
const Util = preload("res://scripts/util.gd")
const WorldBuilder = preload("res://scripts/world.gd")
const Models = preload("res://scripts/models.gd")
const HudScript = preload("res://scripts/hud.gd")
const Toon = preload("res://scripts/toon.gd")
const Rim = preload("res://scripts/rim.gd")
const ObjectiveScript = preload("res://scripts/objective.gd")
const AmbushScript = preload("res://scripts/ambush.gd")
const ExploreScript = preload("res://scripts/explore_map.gd")
const DevStartScript = preload("res://scripts/dev_start.gd")
const UnlocksScript = preload("res://scripts/unlocks.gd")
const BuildInfo = preload("res://scripts/build_info.gd")
const SfxScript = preload("res://scripts/sfx.gd")
const Content = preload("res://scripts/content.gd")
const WeaponSlots = preload("res://scripts/weapon_slots.gd")
const SettingsScript = preload("res://scripts/settings.gd")
const PedestriansScript = preload("res://scripts/pedestrians.gd")
const PickupsScript = preload("res://scripts/pickups.gd")
const PhonesScript = preload("res://scripts/phones.gd")
const GadgetsScript = preload("res://scripts/gadgets.gd")
const BossesScript = preload("res://scripts/bosses.gd")
const RidersScript = preload("res://scripts/riders.gd")
const ShopScript = preload("res://scripts/shop.gd")
const CombatScript = preload("res://scripts/combat.gd")
const EffectsScript = preload("res://scripts/effects.gd")
const InputScript = preload("res://scripts/input.gd")
const PlayerScript = preload("res://scripts/player.gd")
const ScoresScript = preload("res://scripts/scores.gd")
const MetaScript = preload("res://scripts/meta.gd")
const ChallengesScript = preload("res://scripts/challenges.gd")
const ViewmodelScript = preload("res://scripts/viewmodel.gd")
const DailyScript = preload("res://scripts/daily.gd")
const RunSave = preload("res://scripts/run_save.gd")
const ProgressReset = preload("res://scripts/progress_reset.gd")
const ArenaRoundaboutScript = preload("res://scripts/arena_roundabout.gd")
const MapGenScript = preload("res://scripts/map_gen.gd")
const ArenaGenScript = preload("res://scripts/arena_gen.gd")
const GeneratedArenaScript = preload("res://scripts/arena_generated.gd")
const WorldGeneratedScript = preload("res://scripts/world_generated.gd")
const ArenaTrainingScript = preload("res://scripts/arena_training.gd")
const WorldTrainingScript = preload("res://scripts/world_training.gd")

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
const FREE_SHOTS_COOLDOWN = 15.0  # seconds between two SLIDE SHOT / QUICK DRAW grants, however fast the dash recharges

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
var MAXSHELLS = int(Content.WEAPONS[WeaponSlots.PRIMARY_DEFAULT]["start_clip"])
var MAXHEARTS = 3
# game content tables live in content.gd; same names, so the HUD still reads g.NAME
var OVER_MSG = Content.OVER_MSG
var TYPES = Content.TYPES
var THEMES = Content.THEMES
var BOSS_KINDS = Content.BOSS_KINDS
var BOSS_INFO = Content.BOSS_INFO
var CHEER_PX = Content.CHEER_PX
var DROPS = Content.DROPS
var DROP_NEEDS = Content.DROP_NEEDS
var DROP_INFO = Content.DROP_INFO
var SHOP_POOL = Content.SHOP_POOL
var DUOS = Content.DUOS
var UPGRADES = Content.UPGRADES
var UNLOCKS = Content.UNLOCK_TABLE["unlocks"]
var WEAPONS = Content.WEAPONS

# ------------------------------------------------------------------ state
var state = "title"  # title / play / clear / upgrade / over
# The intro screen (hud.gd `_draw_intro`, README V5.0) is the first thing a real launch shows, before the title menu, and
# the place the launcher login of V5.2 will go on. It sits on top of the title state (state stays "title" and
# title_page stays ""), so every check that loads main.tscn with `--script` starts on the title menu as before: the
# flag is only turned on when the game runs as the main scene (see `wants_intro`). A key, a click or a gamepad button
# ends it (input.gd `intro_input`) and nothing turns it on again until the game is started anew.
var intro_active = false
const INTRO_MIN_TIME = 0.35  # seconds from the start before a key or a click is taken, so a key still held down while the window opens does not skip it
var paused = false
var force_captured = false  # test hook: headless Godot cannot capture the mouse, so a check sets this to play a round
var map_key_forced = false  # test hook: a check sets this to act as if the map button is held down (see `map_held`)
var round_n = 1
var score = 0
var hi = 0  # the HI score: the best leaderboard entry at start-up, raised during a ranked run (`hi_check`)
var daily_date = ""  # UTC date the daily seed belongs to, "YYYY-MM-DD"
var daily_seed = 0  # same for every player on that date (daily.gd); a Daily Run uses it as its run seed
var daily_label = ""  # title-screen text for the above
var daily_arena = ""  # the arena style of the daily seed, shown under it on the title screen
var arena_rules_cache = {}  # `data/arena_rules.json`, read on first use by `arena_style_text`
var daily_mode = false  # true while a Daily Run is in progress (own scoreboard later, no normal high score)
var custom_seed_run = false  # true while a run with a seed typed in on the title screen is in progress (kept off the normal high score and Top 10, like a Daily Run; a restart replays the same seed)
var run_seed = 0  # the seed this run started with: today's daily seed in a Daily Run, a random one in a normal run
var run_map = {}  # the run map generated from run_seed (map_gen.gd); the run walks it one node per round (see "run map walk" below)
var map_floor = -1  # floor index (0-based) of the node being played, -1 before the first pick
var map_lane = 0  # lane of the node being played
# map node types that are a screen of their own and not a fight: no riders, no extraction point, no ambush, no
# round XP, no `challenges.on_round_cleared`, no entry in `round_times`, and never a perfect round. Their time is
# counted in `shop_time` (the update loop counts the "shop" and "rest" states there). The rest node (alpha B3)
# joined the shop here.
const SCREEN_NODES = ["shop", "rest"]
var rest_opts = []  # the two choices on the rest screen (built by `shop_sys.enter_rest`)
var rest_upgrade = false  # true while the upgrade pick on screen is the rest node's EXTRA UPGRADE, not a cleared round's
var upgrade_extra = 0  # upgrade picks still to come after the one on screen (an elite clear gives 1, README alpha B4)
var upgrade_part = "upgrade"  # the `offer_shuffle` part of the pick on screen: the extra pick has its own, so its offers differ

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
var hints_seen = {}  # first-run hint id -> true once it was shown (saved in settings.cfg under [hints], see settings.gd)
var hints_on = true  # HINTS setting (README alpha E1.4): false = no first-run hint is shown; saved as [game] show_hints
var hint_txt = ""  # the first-run hint line on screen (E1.2), "" = none; drawn bottom centre by Hud._draw_hint
var hint_t0 = -100.0  # g.time when hint_txt was set; the line fades out after Settings.HINT_SECONDS
var name_entry = false  # true on the run summary while the player is typing a name for a new leaderboard entry
var name_buf = ""
var new_unlocks = []  # names of the unlocks this run's coins put within reach for the first time (set in Meta.award_run)
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
var primary = WeaponSlots.PRIMARY_DEFAULT  # the weapon in the primary slot (an id of data/weapons.json), see weapon_slots.gd
var melee_weapon = WeaponSlots.NO_MELEE  # the weapon in the melee slot (an id of data/weapons.json, "" = empty)
var gadget = WeaponSlots.NO_GADGET  # the gadget in the gadget slot (an id of data/weapons.json, "" = empty)
var melee = false  # true while the melee weapon is the one in the player's hands
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
var pump_base = float(Content.WEAPONS[WeaponSlots.PRIMARY_DEFAULT]["pump_start"])
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
var gun = {}  # the model of the weapon in the primary slot (a value of `guns`), see sync_gun_model
var guns = {}  # primary weapon id -> its first-person model (models.gd); only the one in the slot is shown
var gun_id = ""  # the id of the weapon `gun` is the model of
var rubber = {}  # the first-person model of the weapon in the melee slot (a value of `rubbers`), see sync_melee_model
var rubbers = {}  # melee model key ("" = the gummy worm's club) -> its first-person model (models.gd)
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
# Milestone L: jumping. The whole player moves: `player.position.y` is the jump height (the camera and gun ride on the
# player node, and riders, phones and boss slams look at the height). clamp_walk and obstacle_at only look at x and z,
# so the arena bounds hold in the air.
var jump_h = 0.0  # metres above the ground, 0 = standing on it (the same number as player.position.y)
var jump_v = 0.0  # vertical speed (m/s, up is positive)
var jump_buf = 0.0  # > 0 for a moment after Space / A was pressed, so a press just before landing still jumps
var coyote_t = 0.0  # > 0 while a jump is still allowed (grace after leaving the ground; the ground is flat for now)
var air_speed = 0.0  # the speed air steering aims for: what the player had when taking off
var carry_speed = 0.0  # speed kept through a landing: the ground steers at least this fast while it lasts (fades quickly)
var since_land = 99.0  # seconds on the ground since the last landing; a jump soon after it is a chained hop
var chain = 0  # chained hops in a row (each adds a little speed, up to a cap); back to 0 after a pause on the ground
var side_t = 0.0  # > 0 while a side dash runs
var side_dir = Vector3.ZERO
var side_carry = Vector3.ZERO  # the velocity the player had when the side dash began; it is given back when it ends
var slide_dir = Vector3.ZERO
var was_sprint = false
var crouch_prev = false
var free_shots = 0  # darts that cost no ammo (SLIDE SHOT perk)
var free_shots_cd = 0.0  # > 0 while SLIDE SHOT / QUICK DRAW cannot grant free darts again (not saved: a loaded run starts ready)
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
var rim_outline = true  # fresnel rim on characters: red on foes, green on bystanders (rim.gd)
var fx_scale = 1.0  # 0 to 1: how strong screen shake and screen flashes are (accessibility setting)
var drag_id = ""
# the game version, written in one place: `config/version` in project.godot (shown on the title screen)
var game_version = str(ProjectSettings.get_setting("application/config/version", ""))
# which build this is: version, git hash, channel (build_info.json, see build_info.gd; no file = "dev")
var build_info = BuildInfo.load_info()
var title_page = ""  # "" = main menu, otherwise settings / loadout / unlocks / scores
var pause_page = ""  # "" = pause menu, "settings" = settings panel, "controls", "confirm" = restart / quit confirmation
var pause_sel = 0  # highlighted pause-menu entry (keyboard / gamepad)
var setting_sel = 0  # highlighted row of the settings panel (keyboard / gamepad / mouse hover)
var confirm_id = ""  # what the confirmation asks about: "restart", "title", or "reset1" / "reset2" (the two RESET ALL PROGRESS warnings)
var progress_wiped_t0 = -100.0  # g.time of the last RESET ALL PROGRESS, for the "ALL PROGRESS WIPED" line under the settings panel
var progress_wipe_failed = 0  # how many progress files that wipe could not delete (0 = all gone)
var confirm_sel = 0  # highlighted confirmation button: 0 = NO (the safe default), 1 = YES
var confirm_t0 = 0.0  # g.time when the confirmation opened; YES is ignored for a moment after (double clicks)
var seed_buf = ""  # the hex digits typed on the custom seed page of the title screen (up to 8)
var title_sel = 0  # highlighted title-menu entry (keyboard / gamepad)
var saved_run = {}  # the run on file that the title screen's CONTINUE resumes (run_save.gd), {} when there is none
var saved_run_rounds = 0  # how many rounds that run has, for the CONTINUE button
var run_save_enabled = false  # true in the game itself: a check that builds a main leaves user://run.json alone
var unlock_sel = 0  # highlighted entry (index into UNLOCKS) of the Unlocks page of the title screen
var summary_sel = 0  # highlighted button of the run summary (index into hud.SUMMARY_ITEMS: NEW RUN, UNLOCKS, TITLE); starts on summary_default_sel()
var loadout_sel = 0  # highlighted row of the Loadout page (index into loadout_options)
var loadout_col = 0  # which list of the Loadout page is active: 0 = starting perks, 1 = the three weapon slots
var loadout_slot = 0  # highlighted weapon slot of the Loadout page (index into WeaponSlots.SLOTS)
var unlock_msg = ""  # the last result shown on the Unlocks page ("BOUGHT", "NOT ENOUGH COINS", ...)
var unlock_msg_t0 = -10.0  # g.time when unlock_msg was set; it fades after a few seconds

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
# "v0.3.0 (a1b2c3d)" for the title screen, "" when there is no game version
func version_label() -> String:
	if game_version == "":
		return ""
	return BuildInfo.title_text(build_info)


func _ready() -> void:
	print(BuildInfo.console_line(build_info))
	get_window().title = GAME_TITLE
	randomize()
	refresh_daily_seed()
	hi = scores.best()
	run_save_enabled = get_tree().current_scene == self
	refresh_saved_run()
	settings.load_settings()
	var dev_opts = {}
	if get_tree().current_scene == self:
		dev_opts = start_dev_options(OS.get_cmdline_user_args())
	intro_active = wants_intro(
		get_tree().current_scene == self, bool(dev_opts.get("applied", false))
	)
	hearts = MAXHEARTS
	shells = MAXSHELLS

	generated_arena = wants_generated_arena(
		OS.get_cmdline_user_args(), get_tree().current_scene == self, generated_arena
	)
	var wants_training = wants_training_room(
		OS.get_cmdline_user_args(), get_tree().current_scene == self, training_room
	)
	if wants_training:
		use_training_room()  # the room is the arena of the whole session: runs do not switch to a generated one
	elif not (generated_arena and use_generated_arena(daily_seed)):
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
	guns = {}
	for weapon_id in WeaponSlots.PRIMARY_WEAPONS:  # a weapon without a model of its own is shown with the default's
		var built = Models.build_viewmodel(WeaponSlots.model_of(weapon_id))
		if not built.is_empty():
			guns[weapon_id] = built
	var gun_roots = []
	for gun_key in guns:
		cam.add_child(guns[gun_key]["root"])
		guns[gun_key]["root"].visible = false
		gun_roots.append(guns[gun_key]["root"])
	sync_gun_model()
	rubbers = {}
	var rubber_keys = [""]  # a melee weapon without a model of its own is shown with the club
	for melee_id in WeaponSlots.MELEE_WEAPONS:
		if not rubber_keys.has(WeaponSlots.model_of(melee_id)):
			rubber_keys.append(WeaponSlots.model_of(melee_id))
	var rubber_roots = []
	for key in rubber_keys:
		var built_rubber = Models.build_melee_viewmodel(key)
		if built_rubber.is_empty():
			push_error("melee model '%s' has no builder in Models.build_melee_viewmodel" % key)
			continue
		rubbers[key] = built_rubber
		cam.add_child(built_rubber["root"])
		built_rubber["root"].visible = false
		rubber_roots.append(built_rubber["root"])
	rubber = rubbers[""]
	if VIEWMODEL_PASS:
		viewmodel = ViewmodelScript.new(self)
		viewmodel.setup(cam, gun_roots + rubber_roots, world["env"])

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
		rim_apply(m["root"], Rim.FRIEND)
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
		rim_apply(m["root"], Rim.FOE)
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
		rim_apply(c["root"], Rim.FRIEND)
		x += 1.6
	for i in range(2):
		var cl = Models.build_cheer(i)
		holder.add_child(cl["root"])
		rim_apply(cl["root"], Rim.FRIEND)
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
# The generated arena (README Milestone K) is the arena of the game: the title screen shows the arena made from
# today's daily seed and every run plays on the arena made from its run seed (arena_generated.gd,
# world_generated.gd). The roundabout is kept behind the user argument --roundabout
# (godot --path . -- --roundabout). The `main` of a check script (made by the script, not started as the game)
# stays on the roundabout unless the check sets `generated_arena` before adding it to the tree. --generated-arena is still
# accepted and means the same as the default.
const GENERATED_ARENA_ARG = "--generated-arena"
const ROUNDABOUT_ARG = "--roundabout"
var generated_arena = false
# The training room (arena_training.gd, world_training.gd): a small dark gridded box for the tutorial and for trying
# a weapon or a gadget before buying it. Nothing in the menus opens it yet; the user argument --training-room
# (godot --path . -- --training-room) makes it the arena of the whole session, and a check sets `training_room`
# before adding its `main` to the tree. Runs on it keep it (they do not switch to a generated arena).
const TRAINING_ARG = "--training-room"
var training_room = false
# Practice (try before buying): the TRY button of the Unlocks page takes the player and one weapon into the training
# room. It is a round that never ends and counts for nothing: no life is lost, nothing is scored, paid or saved, and
# the pause menu has BACK TO UNLOCKS instead of RESTART RUN and QUIT TO TITLE. start_practice / end_practice below.
var practice = false
var practice_unlock = {}  # the entry of data/unlocks.json being tried
var practice_was_training = false  # the session already was in the room (--training-room): it stays there afterwards
var world_root: Node3D = null  # the generated arena's world (the roundabout's is built straight into this node)
var settings = SettingsScript.new(self)  # settings.gd: saved settings, graphics quality, high score file
var gadget_sys = GadgetsScript.new(self)  # gadgets.gd: Gadgets: the gadget use key, its uses and cooldown, and the banana peel trap.
var phone_sys = PhonesScript.new(self)  # phones.gd: Phones: riders throwing phones at the player and the phones in flight.
var objective_sys = ObjectiveScript.new(self)  # objective.gd: Objectives: supply caches and the extraction point on generated arenas.
var ambush_sys = AmbushScript.new(self)  # ambush.gd: the last wave of riders when the extraction point opens on a generated arena.
var explore_sys = ExploreScript.new(self)  # explore_map.gd: what the player has found of the arena, for the map shown while M is held.
var pickup_sys = PickupsScript.new(self)  # pickups.gd: Pickups: drops from kills, floating collectibles, magnet and collection.
var civ_sys = PedestriansScript.new(self)  # pedestrians.gd: Pedestrians (civilians): spawning, walking, getting hit.
var boss_sys = BossesScript.new(self)  # bosses.gd: Bosses: spawning, telegraphed attacks, weak points, phases and defeat.
var rider_sys = RidersScript.new(self)  # riders.gd: Riders: spawning waves, movement and sound, collisions, hits and losing parts.
var shop_sys = ShopScript.new(self)  # shop.gd: Shop: between-round upgrades, the shop and its prices, perks and duos, plus style meter and cash.
var combat_sys = CombatScript.new(self)  # combat.gd: Combat: shotgun and reload, melee swing, deflecting phones and the dart projectiles.
var fx_sys = EffectsScript.new(self)  # effects.gd: Effects: pooled particles, bursts, plastic debris and confetti.
var scores = ScoresScript.new(self)  # scores.gd: Scores: the local Top 10 leaderboard saved to user://scores.json.
var meta = MetaScript.new(self)  # meta.gd: Meta currency: earned from finished runs, saved to user://meta.json, separate from run cash.
var challenges = ChallengesScript.new(self)  # challenges.gd: Meta challenges from data/challenges.json: tracked in a run, paid out by meta.award_run().
var input_sys = InputScript.new(self)  # input.gd: Input: mouse, keyboard and gamepad handling, menu clicks and weapon switching.
var player_sys = PlayerScript.new(self)  # player.gd: Player: movement, dash and slide, perfect dodges, aim assist, spread and gun handling.


# True when the intro screen is shown at the start: the game runs as the main scene (a check that loads main.tscn with
# `--script` is not the game), and no developer start option is in use (`--dev-coins` and the like are for getting into
# a run quickly, so they go straight to the title menu).
static func wants_intro(is_game: bool, dev_start_applied: bool) -> bool:
	return is_game and not dev_start_applied


# leave the intro screen for the title menu; false when it was not up or it is too early to take a key (INTRO_MIN_TIME)
func dismiss_intro() -> bool:
	if not intro_active or time < INTRO_MIN_TIME:
		return false
	intro_active = false
	sfx.play("click")
	return true


# Which arena the game starts on. `args` are the user arguments (after `--`), `is_game` is true when this `main` is
# the scene the engine started (not one a check script made) and `already` is what the caller set before the scene
# entered the tree. --roundabout always wins, --generated-arena always asks for the generated arena.
static func wants_generated_arena(args: PackedStringArray, is_game: bool, already: bool) -> bool:
	if args.has(ROUNDABOUT_ARG):
		return false
	if args.has(GENERATED_ARENA_ARG):
		return true
	return already or is_game


# Whether the game starts in the training room: `args` are the user arguments (after `--`), `is_game` is true when this
# `main` is the scene the engine started and `already` is what the caller set before the scene entered the tree.
# Only --training-room on the game, or a check that sets the flag, asks for it; it wins over --roundabout.
static func wants_training_room(args: PackedStringArray, is_game: bool, already: bool) -> bool:
	return already or (is_game and args.has(TRAINING_ARG))


# The developer start options (dev_start.gd, roadmap alpha D2.1): `args` are the user arguments (after `--`). Without
# --dev-coins or --dev-unlocks nothing happens. In an exported game they are ignored. Otherwise the coins and the
# unlocks are set in memory, nothing is saved for the whole session (SaveUtil.read_only), and one line says so.
# Returns what DevStart.parse found, with "applied" added, for the check.
func start_dev_options(args: PackedStringArray) -> Dictionary:
	var opts = DevStartScript.parse(args, UnlocksScript.load_table()["unlocks"])
	opts["applied"] = false
	if not opts["active"]:
		return opts
	if not DevStartScript.allowed():
		print(
			"[dev start] ignored: the developer start options only work when run from the Godot editor"
		)
		return opts
	meta.apply_dev_start(opts)
	opts["applied"] = true
	for problem in opts["problems"]:
		push_warning("[dev start] " + str(problem))
	print(
		(
			"[dev start] coins %s, owned unlocks %s. NOTHING IS SAVED in this session (settings, scores, coins, run)."
			% [str(meta.balance), str(opts["unlocks"])]
		)
	)
	return opts


# Recomputes today's daily seed (UTC date). Called at start-up and whenever the title screen opens,
# so a game left running past midnight UTC picks up the new day's seed.
func refresh_daily_seed() -> void:
	daily_date = DailyScript.date_string()
	daily_seed = DailyScript.seed_for(daily_date)
	daily_label = "DAILY SEED %s   %s UTC" % [DailyScript.seed_text(daily_seed), daily_date]
	daily_arena = arena_style_text(daily_seed)


# What the arena style of a run seed is called on the screen (STREET CANYON, MARKET, ...), the same style the run
# gets: `ArenaGen.generate` takes it from `pick_style` with the run seed as it is. "" when the rules have no styles.
# The rules are read once, because the seed page asks on every frame.
func arena_style_text(run_seed: int) -> String:
	if arena_rules_cache.is_empty():
		arena_rules_cache = ArenaGenScript.load_rules()
	var style = ArenaGenScript.pick_style(run_seed, arena_rules_cache)
	return ArenaGenScript.style_label(arena_rules_cache, style)


# the HUD calls these two on main, so they stay as thin wrappers
func get_setting(id: String):
	return settings.get_setting(id)


func set_setting(id: String, v) -> void:
	settings.set_setting(id, v)


# the rows of the Loadout page: "no starting perk" first, then every starting perk the player owns, in table order
func loadout_options() -> Array:
	var out = [
		{
			"id": "",
			"perk": "",
			"name": "NO STARTING PERK",
			"desc": "START EVERY RUN WITH NOTHING EXTRA"
		}
	]
	for u in UNLOCKS:
		if u["kind"] == "starting_perk" and meta.owns(u["id"]):
			out.append({"id": u["id"], "perk": u["target"], "name": u["name"], "desc": u["desc"]})
	return out


# true when the player may use a weapon: every weapon is available from the first run unless data/unlocks.json
# holds it back as a "weapon" unlock, and then it has to be bought (the gummy worm is one of those: a new player
# starts with the dart pistol only)
func weapon_owned(id: String) -> bool:
	for u in UNLOCKS:
		if u["kind"] == "weapon" and u["target"] == id:
			return meta.owns(u["id"])
	return true


# true when the shop may sell an item: an item that data/unlocks.json lists as a "shop_item" unlock stays out of every
# shop (a normal run, the Daily Run and a custom seed alike) until it is bought; every other item is always allowed
func shop_item_owned(id: String) -> bool:
	for u in UNLOCKS:
		if u["kind"] == "shop_item" and u["target"] == id:
			return meta.owns(u["id"])
	return true


# the rows of one weapon slot on the Loadout page: the weapons the player owns that fit the slot, the slot's
# default first (the gadget slot starts with "NO GADGET"). Each row is {"id", "name", "desc"}.
func loadout_weapon_options(slot: String) -> Array:
	var out = []
	var first = WeaponSlots.default_of(slot)
	var ids = [first]
	for id in WeaponSlots.table_of(slot):
		if id != first:
			ids.append(id)
	for id in ids:
		if id == first or (weapon_owned(id) and WEAPONS.has(id)):
			out.append(
				{
					"id": id,
					"name": WeaponSlots.display_name(slot, id),
					"desc": WeaponSlots.display_desc(slot, id)
				}
			)
	return out


# the weapon a run starts with in a slot: the one chosen on the Loadout page while it is still owned, otherwise
# the slot's default
func loadout_weapon_id(slot: String) -> String:
	var want = str(meta.weapon_choice.get(slot, ""))
	for o in loadout_weapon_options(slot):
		if o["id"] == want:
			return want
	return WeaponSlots.default_of(slot)


# puts the three chosen weapons in their slots (every run, the Daily Run and a typed seed too)
func apply_loadout() -> void:
	equip_primary(loadout_weapon_id(WeaponSlots.PRIMARY))
	equip_melee(loadout_weapon_id(WeaponSlots.MELEE))
	equip_gadget(loadout_weapon_id(WeaponSlots.GADGET))


# the perk a normal run starts with: the one chosen on the Loadout page while it is still owned, "" for none
func start_perk_id() -> String:
	for o in loadout_options():
		if o["id"] != "" and o["id"] == meta.start_perk:
			return str(o["perk"])
	return ""


# true when this run counts for the normal high score and Top 10: not a Daily Run and not a typed-in seed
# (a seed everybody can replay would let one easy seed be farmed)
func ranked_run() -> bool:
	return not daily_mode and not custom_seed_run


func hi_check() -> void:
	if not ranked_run():  # daily and custom-seed runs stay off the normal high score
		return
	if score > hi:
		hi = score  # only for this session: the run reaches the file through the leaderboard (`Scores.submit_run`)


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


# Makes the training room the arena of the game and builds its world (a generated world is freed). The caller puts the
# player on arena.start_position(). The room is one fixed place, so this cannot fail.
func use_training_room() -> void:
	if world_root != null:
		remove_child(world_root)
		world_root.free()
	training_room = true
	arena = ArenaTrainingScript.new()
	civ_sys.clear_civs()  # a pedestrian walks between the gates of the arena it was made for
	world_root = Node3D.new()
	world_root.name = "TrainingWorld"
	add_child(world_root)
	world = WorldTrainingScript.build(world_root, arena)
	print(
		(
			"training room: %d gates, %d triangles, %d draw calls"
			% [arena.gates().size(), world["tris"], world["draw_calls"]]
		)
	)


# true when the unlock is a weapon the game has: only those can be tried (a planned weapon has no entry in
# data/weapons.json yet, and a perk, a shop item or a cosmetic is not something to hold)
func can_try(u: Dictionary) -> bool:
	if str(u.get("kind", "")) != "weapon":
		return false
	var id = str(u.get("target", ""))
	return WEAPONS.has(id) and WeaponSlots.WEAPON_INFO.has(id)


# Takes the player and the unlock's weapon into the training room (TRY on the Unlocks page, only from the title
# screen). The weapon is put in its slot whether it is owned or not and the run's other state is reset, so nothing
# the player has bought changes the test. Returns false and changes nothing when the weapon cannot be tried, or when
# the session has no world that can be swapped for the room (the roundabout of the checks).
func start_practice(u: Dictionary) -> bool:
	if state != "title" or not can_try(u):
		return false
	if not training_room and not generated_arena:
		return false
	practice_was_training = training_room
	if not training_room:
		use_training_room()
	practice = true
	practice_unlock = u
	reset_run()
	run_map = {}
	round_n = 1
	map_floor = -1
	map_lane = 0
	daily_mode = false
	custom_seed_run = false
	run_seed = 1
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
	yaw = 0.0
	pitch = 0.0
	player.position = arena.start_position()
	pvel = Vector3.ZERO
	var id = str(u["target"])
	var slot = str(WeaponSlots.WEAPON_INFO[id]["slot"])
	if slot == WeaponSlots.MELEE:
		equip_melee(id)
		melee = true  # the weapon is in the player's hands, Q or the wheel goes back to the pistol
	elif slot == WeaponSlots.PRIMARY:
		equip_primary(id)
	else:
		equip_gadget(id)
	update_arena_dressing()
	settings.apply_quality()
	paused = false
	pause_sel = 0
	pause_page = ""
	start_round()
	objective_sys.clear()  # no way out to look for and no supply caches: the room is only for trying the weapon
	explore_sys.clear()
	wait = 2.0
	wait_msg = "TRYING THE " + str(u["name"])
	return true


# Back to the Unlocks page from the room: the world the session had before is made again (the room stays when the
# session started in it), the run state is cleared and the page is on the weapon that was tried.
func end_practice() -> void:
	if not practice:
		return
	clear_riders()
	clear_bosses()
	clear_phones()
	clear_pickups()
	objective_sys.clear()
	ambush_sys.clear()
	explore_sys.clear()
	practice = false
	reset_run()
	go_to_title()
	if not practice_was_training:
		training_room = false
		if generated_arena and use_generated_arena(daily_seed):
			update_arena_dressing()
			settings.apply_quality()
			apply_theme(theme_idx)
		else:
			training_room = true  # no generated arena could be made: keep the room rather than a broken world
	for n in range(hud.TITLE_ITEMS.size()):
		if hud.TITLE_ITEMS[n]["id"] == "unlocks":
			title_sel = n
	for i in range(UNLOCKS.size()):
		if UNLOCKS[i]["id"] == practice_unlock.get("id", ""):
			unlock_sel = i
	unlock_msg = ""
	title_page = "unlocks"
	sfx.play("click")
	practice_unlock = {}


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
	if not arena.fixed_lighting():  # the training room keeps its own light
		Lighting.apply_theme(THEMES[i], world)
	if viewmodel != null:
		viewmodel.sync_env(world["env"])


func col_mat(hex: String) -> Material:
	if not mat_cache.has(hex):
		mat_cache[hex] = Util.unshaded(Color.html(hex))
	return mat_cache[hex]


func set_flash(node: Node, on: bool) -> void:
	if node is MeshInstance3D:
		# when the flash ends the mesh goes back to its rim outline (rim.gd), or to nothing
		node.material_overlay = flash_mat if on else Rim.resting_overlay(node)
	for ch in node.get_children():
		set_flash(ch, on)


# put the rim outline on a character model (or take it off again when the setting is off); `kind` is Rim.FOE
# (riders, bosses) or Rim.FRIEND (pedestrians, cheerleaders)
func rim_apply(root: Node, kind: String) -> void:
	Rim.apply(root, kind, rim_outline)


# the setting changed: every character on screen gets or loses its rim
func refresh_rims() -> void:
	for r in riders:
		rim_apply(r["model"]["root"], Rim.FOE)
	for b in bosses:
		rim_apply(b["model"]["root"], Rim.FOE)
	for c in civs:
		rim_apply(c["model"]["root"], Rim.FRIEND)
	for m in cheerleaders:
		rim_apply(m["root"], Rim.FRIEND)


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


# ================================================================== weapon slots
# Shows the first-person model of the weapon in the primary slot and hides the others (a weapon without a model of its
# own, `model` in data/weapons.json, uses the default weapon's). Called every frame by `update_gun`, so every way a weapon gets into the slot (equipping,
# a new run, a saved run) is covered; it only does something when the weapon has changed.
func sync_gun_model() -> void:
	var id = primary if guns.has(primary) else WeaponSlots.PRIMARY_DEFAULT
	if id == gun_id or not guns.has(id):
		return
	gun_id = id
	gun = guns[id]
	for key in guns:
		guns[key]["root"].visible = false
		guns[key]["light"].light_energy = 0.0
	player_sys.ammo_text = ""  # the number on the new model has to be set again
	player_sys.pump_slide = 0.0


# Same for the melee slot: `rubber` is the model of the weapon in the slot (`model` in data/weapons.json, "" = the
# club), the others are hidden. Called every frame by `update_gun`, like sync_gun_model.
func sync_melee_model() -> void:
	var key = WeaponSlots.model_of(melee_weapon)
	var next = rubbers.get(key, rubbers.get(""))
	if next == null or next == rubber:
		return
	for k in rubbers:
		rubbers[k]["root"].visible = false
	rubber = next


# The tuning numbers (data/weapons.json) of the weapon in the primary slot.
func primary_stats() -> Dictionary:
	return WEAPONS[primary]


# The tuning numbers (data/weapons.json) of the weapon in the melee slot; empty when the slot is empty.
func melee_stats() -> Dictionary:
	return WEAPONS[melee_weapon] if has_melee() else {}


# true when the melee slot holds a weapon (a new player's runs start with it empty, see `weapon_owned`)
func has_melee() -> bool:
	return WeaponSlots.is_melee_weapon(melee_weapon) and WEAPONS.has(melee_weapon)


# The tuning numbers (data/weapons.json) of the gadget in the gadget slot; empty when the slot is empty.
func gadget_stats() -> Dictionary:
	return WEAPONS[gadget] if WeaponSlots.is_gadget(gadget) and WEAPONS.has(gadget) else {}


# Puts a gadget in the gadget slot, or empties it (an empty id). Refuses (returns false and changes nothing) an id
# that cannot be in the gadget slot. The use key (G, D-pad up) is read by `gadget_sys` (scripts/gadgets.gd).
func equip_gadget(id) -> bool:
	if typeof(id) == TYPE_STRING and id == WeaponSlots.NO_GADGET:
		gadget = WeaponSlots.NO_GADGET
		return true
	if not WeaponSlots.is_gadget(id) or not WEAPONS.has(id):
		return false
	gadget = id
	return true


# Puts a weapon in the melee slot, or empties it (an empty id: the player's hands go back to the primary weapon).
# Refuses (returns false and changes nothing) an id that cannot be in the melee slot. A swing in progress finishes
# with the numbers it started with. `apply_loadout` calls this at the start of every run.
func equip_melee(id) -> bool:
	if typeof(id) == TYPE_STRING and id == WeaponSlots.NO_MELEE:
		melee_weapon = WeaponSlots.NO_MELEE
		melee = false
		return true
	if not WeaponSlots.is_melee_weapon(id) or not WEAPONS.has(id):
		return false
	melee_weapon = id
	return true


# Puts a weapon in the primary slot and gives it its starting magazine and pump time. Refuses (returns false and
# changes nothing) an id that cannot be in the primary slot. A reload in progress is stopped, because it was
# loading the old weapon. Nothing calls this yet but the checks: choosing a starting weapon is the Loadout
# screen (Milestone I) and finding or buying one is the Milestone C weapons.
func equip_primary(id) -> bool:
	if not WeaponSlots.is_primary_weapon(id) or not WEAPONS.has(id):
		return false
	if id == primary:
		return true
	combat_sys.interrupt_load()
	primary = id
	MAXSHELLS = int(primary_stats()["start_clip"])
	shells = MAXSHELLS
	pump_base = float(primary_stats()["pump_start"])
	return true


# ================================================================== game flow
func reset_run() -> void:
	primary = WeaponSlots.PRIMARY_DEFAULT
	melee_weapon = WeaponSlots.NO_MELEE
	gadget = WeaponSlots.NO_GADGET
	MAXSHELLS = int(primary_stats()["start_clip"])
	pump_base = float(primary_stats()["pump_start"])
	pump_dur = 0.2
	MAXHEARTS = 3
	melee = false
	swing_t = 0.0
	swing_cd = 0.0
	cash = 0
	style = 0.0
	perks = {}
	free_shots = 0
	free_shots_cd = 0.0
	dash_cd = 0.0
	dash_t = 0.0
	dash_inv = 0.0
	slide_t = 0.0
	player_sys.reset_air()
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
	refresh_saved_run()
	if not saved_run.is_empty():
		title_sel = hud.TITLE_CONTINUE  # a run is waiting: CONTINUE is the first thing the keyboard lands on
	elif title_sel >= hud.TITLE_ITEMS.size():
		title_sel = 0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


# leave a run in progress (pause menu: quit to title); the run is simply dropped
func abandon_run() -> void:
	clear_riders()
	clear_bosses()
	clear_phones()
	clear_pickups()
	go_to_title()


# ---- saved run (CONTINUE on the title screen, run_save.gd). A checkpoint is written every time the run map screen
# opens, and cleared when the run ends. Only runs with a map are saved: a run without one plays in a line.
# Loads user://run.json again and keeps the run in `saved_run` if it can be played: its map position has to fit
# the map the run seed makes. A damaged or too new file is not an error, there is just nothing to continue.
func refresh_saved_run() -> void:
	saved_run = {}
	saved_run_rounds = 0
	if not run_save_enabled:
		return
	var data = RunSave.load_file()
	if data.is_empty():
		return
	var map = MapGenScript.generate(int(data["run_seed"]))
	if not RunSave.fits_map(data, map):
		return
	saved_run = data
	saved_run_rounds = map["floors"].size()


# writes the checkpoint of the run on the map screen
func save_checkpoint() -> void:
	if run_save_enabled and not run_map.is_empty():
		RunSave.save(self)


# the run ended (lost or won): nothing is left to continue
func clear_saved_run() -> void:
	saved_run = {}
	saved_run_rounds = 0
	if run_save_enabled:
		RunSave.clear()


# RESET ALL PROGRESS (last row of the settings panel, after two warnings; the flow is in input.gd): deletes the meta,
# leaderboard and saved run files with every backup copy (progress_reset.gd), and puts what the game holds in memory
# back to a new player's values: coins, unlocks, loadout, challenge counts, XP, the leaderboard, the HI score and the
# CONTINUE button. The settings and the leaderboard name are kept. Returns how many files could not be deleted; those
# are written over with the empty state so the old progress cannot come back at the next start.
func reset_all_progress() -> int:
	var failed = ProgressReset.delete_files()
	meta.reset_all()
	scores.entries = []
	hi = 0
	last_rank = -1
	new_unlocks = []
	meta_earned = 0
	unlock_msg = ""
	clear_saved_run()
	if not failed.is_empty():
		meta.save_meta()
		scores.save_scores()
		RunSave.clear()
	if title_sel >= hud.TITLE_ITEMS.size():
		title_sel = 0  # the CONTINUE button is gone
	progress_wiped_t0 = time
	progress_wipe_failed = failed.size()
	return failed.size()


# CONTINUE: plays the saved run on from its map screen, with everything the player had there
func continue_run() -> void:
	if saved_run.is_empty():
		return
	var data = saved_run
	reset_run()
	meta.begin_run()
	challenges.begin_run()
	RunSave.apply(self, data)
	if generated_arena and not training_room and use_generated_arena(run_seed):  # the arena is made from the run seed, as at the start
		update_arena_dressing()
		settings.apply_quality()
	run_map = MapGenScript.generate(run_seed)
	print(MapGenScript.to_text(run_map))
	MAX_ROUNDS = run_map["floors"].size()
	run_won = false
	round_times = data["round_times"].duplicate()
	last_rank = -1
	name_entry = false
	new_unlocks = []
	yaw = 0.0
	pitch = 0.0
	player.position = arena.start_position()
	pvel = Vector3.ZERO
	player_sys.reset_air()
	enter_map()


# Starts the next run the way the one in front of the player was started (pause menu RESTART RUN, run summary NEW RUN):
# a normal run draws a new seed, a Daily Run plays today's daily seed again, a run on a typed-in seed replays that seed.
func restart_run() -> void:
	start_game(daily_mode, run_seed if custom_seed_run else -1)


# `daily`: a Daily Run (today's seed). `custom_seed`: 0 to 4294967295 to play that seed (typed in on the title
# screen); -1 draws a random one.
func start_game(daily: bool = false, custom_seed: int = -1) -> void:
	if run_save_enabled:
		RunSave.backup_before_replace()  # a new run replaces the saved one at its first map screen
	reset_run()
	meta.begin_run()
	challenges.begin_run()
	daily_mode = daily
	custom_seed_run = not daily and custom_seed >= 0
	if daily:
		refresh_daily_seed()
		run_seed = daily_seed
	elif custom_seed_run:
		run_seed = custom_seed & 0xFFFFFFFF
	else:
		run_seed = DailyScript.random_seed()
	if generated_arena and not training_room and use_generated_arena(run_seed):  # one arena per run, made from the run seed
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
	rest_upgrade = false
	upgrade_extra = 0
	upgrade_part = "upgrade"
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
	player_sys.reset_air()
	var start_perk_name = start_perk_id()
	if start_perk_name != "":  # the Daily Run and a typed seed start with the chosen perk and weapons too
		perks[start_perk_name] = true
	apply_loadout()
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


# true if a node of this type ("shop", "boss", ...) is still ahead of the player: on a later floor and reachable from
# the node being played (every node of floor 1 before the first pick). A run without a map (the roundabout) has a shop
# after every round and bosses in its rounds, so it answers true. Read by the `shop_ahead` and `boss_ahead` needs
# (needs.gd), which is how cash and boss-only entries stop being offered once no shop or boss is left.
func node_type_ahead(type: String) -> bool:
	if run_map.is_empty():
		return true
	var floors = run_map["floors"]
	var lanes = next_lanes()
	var f = map_floor + 1
	while f < floors.size() and not lanes.is_empty():
		var seen = {}
		for lane in lanes:
			if int(lane) >= floors[f].size():
				continue
			var node = floors[f][int(lane)]
			if str(node.get("type", "")) == type:
				return true
			for j in node.get("next", []):
				seen[int(j)] = true
		lanes = seen.keys()
		f += 1
	return false


# opens the map screen with the choices for the next round
func enter_map() -> void:
	map_choices = next_lanes()
	map_sel = 0
	state = "map"
	state_t = 0.0
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	settings.trigger_hint("map")  # first-run hint (README alpha E1.3), shown once
	save_checkpoint()


# plays the i-th choice of the map screen as the next round
func pick_node(i: int) -> void:
	if state != "map" or i < 0 or i >= map_choices.size():
		return
	map_lane = int(map_choices[i])
	map_floor += 1
	map_path.append(map_lane)
	round_n = map_floor + 1
	sfx.play("click")
	if node_is_screen(current_node()):
		# a shop or rest node is a screen, not a round: no arena, no riders (README alpha B2, B3)
		if str(current_node().get("type", "")) == "rest":
			shop_sys.enter_rest()
		else:
			shop_sys.enter_shop()
		return
	start_round()


func node_is_screen(node: Dictionary) -> bool:
	return SCREEN_NODES.has(str(node.get("type", "")))


# how many of the nodes the player walked through before the one they are on were screens, not rounds
func screens_passed() -> int:
	var n = 0
	if run_map.is_empty():
		return 0
	var floors = run_map["floors"]
	for f in range(mini(map_path.size() - 1, floors.size())):
		var lane = int(map_path[f])
		if lane >= 0 and lane < floors[f].size() and node_is_screen(floors[f][lane]):
			n += 1
	return n


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
	gadget_sys.clear()  # the traps on the ground belong to the round like the phones in flight
	for ph in phones:
		free_phone(ph)
	phones.clear()


func free_phone(ph: Dictionary) -> void:
	ph["node"].queue_free()
	ph["ring"].queue_free()


func clear_pickups() -> void:
	objective_sys.clear()  # the caches and the extraction point belong to the round like the pick-ups do
	ambush_sys.clear()
	explore_sys.clear()
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
	objective_sys.setup_round()
	explore_sys.setup_round()  # after the objectives: it keeps one "found" flag per cache
	gadget_sys.begin_round()
	round_t = 0.0
	hits.clear()
	for i in range(PER_ROUND):
		hits.append(null)
	next_idx = 0
	round_lives_lost = 0
	challenges.begin_round()
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
	if practice:  # the next rider comes out of the door soon, the gadget has its uses back, and it goes on for ever
		next_idx = 0
		for i in range(hits.size()):
			hits[i] = null
		gadget_sys.begin_round()
		wait = 1.5
		wait_msg = ""
		return
	if objective_sys.extracting:
		return  # the way out is open: the ambush riders (ambush.gd) going down does not end the round, reaching the point does
	if need_boss():
		pending_boss = true
		wait = 1.4
		wait_msg = "FINAL BOSS" if is_final_round() else "BOSS FIGHT"
		return
	if next_idx >= PER_ROUND:
		finish_wave_set()
	else:
		wait = 0.75
		wait_msg = "GOT AWAY" if wave_miss else ""


# Every rider (and boss) of the round is down. On a generated arena the round is not over yet: the way out opens and
# the player walks to the extraction point (objective.gd); anywhere else, or if the round was lost, it ends now.
func finish_wave_set() -> void:
	if (
		objective_sys.enabled()
		and objective_sys.has_goal()
		and not objective_sys.extracting
		and count_hits() >= hits_needed()
	):
		objective_sys.begin_extraction()
		ambush_sys.start()
		wait = 0.0
		wait_msg = ""
		return
	end_round()


# the player stepped into the extraction point
func objective_reached() -> void:
	end_round()


func end_round() -> void:
	if practice:
		return  # a practice round has no end: nothing is scored, paid or saved
	objective_sys.clear()
	ambush_sys.clear()
	clear_riders()  # ambush riders still on the way in when the player gets out
	explore_sys.clear()
	var n = count_hits()
	round_times.append(round_t)
	print(
		(
			"[run timer] round %d: %s fighting, run so far %s (+%s in shops)"
			% [round_n, fmt_time(round_t), fmt_time(play_time), fmt_time(shop_time)]
		)
	)
	if n >= hits_needed():
		challenges.on_round_cleared()
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
		clear_saved_run()
		meta.award_run()
		summary_sel = summary_default_sel()
		scores.submit_run()
		sfx.play("over")
		sfx.v_groan()
		sfx.say("game_over")


# The button the run summary starts on (alpha C5.2): UNLOCKS when this run's coins put something within reach for the
# first time (`new_unlocks`, filled by meta.award_run, so call this after it), otherwise NEW RUN.
func summary_default_sel() -> int:
	var want = "new_run" if new_unlocks.is_empty() else "unlocks"
	for i in range(hud.SUMMARY_ITEMS.size()):
		if hud.SUMMARY_ITEMS[i]["id"] == want:
			return i
	return 0


# the last round was cleared: the run is won. It ends on the same summary screen as a loss.
func win_run() -> void:
	if practice:
		return
	run_won = true
	state = "over"
	over_reason = "victory"
	clear_saved_run()
	challenges.on_run_won(play_time + shop_time)
	meta.award_run()
	summary_sel = summary_default_sel()
	scores.submit_run()
	fx_sys.confetti()
	sfx.play("clear")
	sfx.v_cheer()
	sfx.say("round_clear")


func game_over(reason: String) -> void:
	if practice:
		return  # a practice round has no end, so nothing is scored, paid or saved
	objective_sys.clear()
	ambush_sys.clear()
	explore_sys.clear()
	clear_riders()
	clear_bosses()
	clear_phones()
	state = "over"
	state_t = 0.0
	over_reason = reason
	clear_saved_run()
	hi_check()
	meta.award_run()
	summary_sel = summary_default_sel()
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
	if practice:
		return  # the training room: nothing hurts
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
	challenges.on_life_lost()
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


# True while the arena map is up: M (or the gamepad's Back / View button) is held down during a round that is not
# paused. The map is drawn by the HUD (`_draw_map_overlay`) and goes away the moment the button is released; the
# round keeps running behind it.
func map_held() -> bool:
	if state != "play" or paused:
		return false
	return (
		map_key_forced
		or Input.is_key_pressed(KEY_M)
		or Input.is_joy_button_pressed(0, JOY_BUTTON_BACK)
	)


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


# move a walking body from one point to another, sliding along a wall in the way (the player's step each frame)
func slide_walk(from: Vector3, to: Vector3, who: String = "player") -> Vector3:
	return arena.slide_walk(from, to, who)


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
	elif (
		state == "clear"
		or state == "upgrade"
		or state == "shop"
		or state == "rest"
		or state == "map"
	):
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
		if state == "play" and combat_sys.deflecting():
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
		# Loading only starts here when the magazine is empty. The old top-up between waves (no riders left,
		# waiting for the next one) is gone: a part-empty gun is reloaded by hand (R / gamepad X, `input.gd`).
		# While rapid fire or free darts can still shoot, an empty gun waits: every shot stops a reload, so it
		# would only start again after each shot (and fire reload_started / reload_interrupted every time).
		if (
			shells == 0
			and not loading
			and pump_t <= 0.15
			and buffs["rapid"] <= 0.0
			and free_shots <= 0
		):
			combat_sys.start_load()
	if loading and pump_t <= 0.0:
		load_t -= dt
		if load_t <= 0.0:
			combat_sys.load_one_shell()

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
	objective_sys.update(dt)
	ambush_sys.update(gdt)
	explore_sys.update(dt)
	phone_sys.update_phones(gdt)
	gadget_sys.update(gdt)
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
