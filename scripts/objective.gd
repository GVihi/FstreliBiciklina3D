extends RefCounted
# Exploration objectives on generated arenas (README Milestone K, "Exploration and extraction").
#
#   Supply caches   A few glowing crates spread over the arena, far from the start. Each one is marked by a gold
#                   light column that rises above the rooftops, so a curious player can see where to go. Walking
#                   into one pays cash, score and a random pick-up; all of them pays a bonus. They are there from the
#                   first second of the round, so a fight can be taken across the map.
#                   Some caches carry a catch (README Milestone K, "Caches with a catch"): `pick_variants()` rolls
#                   them from their own seeded stream, so a Daily Run gives everybody the same ones. Built so far:
#                   VANISHING (a countdown starts when the player comes within VANISH_TRIGGER, and a cache that is
#                   not taken in time is gone for the round and does not count towards the every-cache bonus),
#                   CURSED (pays CURSED_MULT times the cash and score, but taking it calls a few riders out of the gate
#                   nearest to the cache, one after another, like a small ambush that the player chose) and
#                   LOCKED (pays LOCKED_MULT times, but only opens with a key, which another plain cache of the same
#                   round holds; `assign_keys()` pairs them, so a locked cache can always be opened).
#                   A cache may also hold 1 meta coin (`pick_coins()`, from a seeded stream of its own, so a Daily Run gives
#                   everybody the same ones, whatever its variant). The coin is paid with the run
#                   (`meta.add_cache_coin`), so a quit run pays nothing, like the coins of a boss. Nothing in the world
#                   shows which cache holds one; the player sees "+1 META COIN" when it is taken.
#   Extraction      Once every rider (and boss) is down the round does not end by itself any more: a green light
#                   column opens and the round is cleared when the player reaches it. The point is one spot, at a
#                   random place in the arena each round (seeded, so a Daily Run gives everybody the same one), never
#                   a gate. Before that it is shown dimmed, so the player knows where the run will end.
#
# One round at a time: `setup_round()` builds both from the arena's layout and a stream seeded by the run seed and
# the round number (so a Daily Run gives everybody the same spots), `clear()` takes them away again.
# The roundabout has neither (`enabled()` is false there) and plays as before.

const Util = preload("res://scripts/util.gd")
const DailyScript = preload("res://scripts/daily.gd")

const CACHE_COUNT = 4
const CACHE_RADIUS = 1.7  # metres: walk this close to take a cache
const GOAL_RADIUS = 2.6  # metres: walk this close to the extraction point to leave
const CACHE_CASH = 25
const CACHE_SCORE = 750
const ALL_CACHES_SCORE = 2500
const ALL_CACHES_CASH = 50
const SENSE_RANGE = 45.0  # metres: caches show on the radar and as HUD markers inside this range
const GOLD = Color(0.95, 0.71, 0.19)
const GREEN = Color(0.35, 1.0, 0.55)
const LOCKED = Color(1.0, 0.45, 0.3)
const BEAM_HEIGHT = 34.0
const REWARDS = ["ammo", "ammo", "cash", "cash", "rapid", "big", "slow", "shield", "heart"]

# Cache variants. VARIANTS is what can be rolled.
const VARIANT_PLAIN = "plain"
const VARIANT_VANISHING = "vanishing"
const VARIANT_CURSED = "cursed"
const VARIANT_LOCKED = "locked"
const VARIANTS = [VARIANT_VANISHING, VARIANT_CURSED, VARIANT_LOCKED]
const VARIANT_CHANCE = 0.4  # per cache, first guess
const VARIANT_MAX = 2  # at most this many of a round's caches get a variant, so plain ones are always left
const VANISH_TRIGGER = 12.0  # metres: the countdown of a vanishing cache starts when the player is this close
const VANISH_TIME = 8.0  # seconds from the trigger until it is gone (first guess, tuned by playing)
const VANISH_COL = Color(0.45, 0.85, 1.0)
const VANISH_GONE = Color(0.7, 0.7, 0.72)
# The cursed cache (first guesses, tuned by playing). It pays CURSED_MULT times the cash and the score of a plain
# cache and calls riders when it is taken: CURSE_MIN_RIDERS, and CURSE_MAX_RIDERS from round CURSE_BIG_ROUND on. The
# first comes CURSE_DELAY seconds after the take, then one every CURSE_GAP seconds, out of the gate nearest to the cache.
const CURSED_COL = Color(0.78, 0.35, 1.0)
const CURSED_MULT = 2
const CURSE_MIN_RIDERS = 2
const CURSE_MAX_RIDERS = 3
const CURSE_BIG_ROUND = 6
const CURSE_DELAY = 1.0
const CURSE_GAP = 1.4
# The locked cache (first guesses, tuned by playing): pays LOCKED_MULT times the cash and the score of a plain cache,
# and the key is used up when it opens. The reminder that it is locked shows at most every LOCK_NOTE_GAP seconds.
const LOCKED_COL = Color(1.0, 0.55, 0.15)
const LOCKED_MULT = 2
const LOCK_NOTE_GAP = 2.5
const KEY_COL = Color(0.95, 0.95, 0.4)

# A cache may hold 1 meta coin (a first guess of 12 %, between the 10 and 15 % the owner asked for on 2026-11-02)
const COIN_CHANCE = 0.12
const COIN_COL = Color(1.0, 0.85, 0.35)

var g = null
# each {"pos": Vector3, "node": Node3D, "crate": Node3D, "beam_mat": StandardMaterial3D, "taken": bool,
# "gone": bool, "variant": String, "left": float (seconds left of a vanishing cache, -1 until it starts),
# "key": bool (taking it gives the player a key), "warn": float (seconds until a locked cache may remind again),
# "coin": bool (the cache holds 1 meta coin)}
var caches: Array = []
var goal: Dictionary = {}  # {"pos": Vector3, "node": Node3D, "beam_mat": StandardMaterial3D, "ring_mat": ...}
var extracting = false  # every rider is down and the way out is open
var taken = 0  # caches taken this round
var keys = 0  # keys the player holds this round: a locked cache takes one
var _t = 0.0
# riders a cursed cache has called and that are still to come: one entry per rider, the gate it comes out of
var _curse_gates: Array = []
var _curse_wait = 0.0
var _curse_rng = RandomNumberGenerator.new()  # kinds and lanes of the called riders (seeded in setup_round)


func _init(game) -> void:
	g = game


# true where this round has objectives: arenas with open-ground play (the generated arena)
func enabled() -> bool:
	return g.arena.rider_pursuit()


func has_goal() -> bool:
	return not goal.is_empty()


# metres over the ground from the player to a world point
func dist_to(p: Vector3) -> float:
	return Vector2(p.x - g.player.position.x, p.z - g.player.position.z).length()


# Build the caches and the (still locked) extraction point for this round.
func setup_round() -> void:
	clear()
	if not enabled():
		return
	var rng = RandomNumberGenerator.new()
	rng.seed = DailyScript.stream_seed(g.run_seed, g.round_n, "objective")
	var gp: Vector3 = g.arena.goal_spot(rng)
	goal = _make_goal(gp)
	var spots = g.arena.cache_spots(CACHE_COUNT, gp, rng)
	# the variants have a stream of their own, so the spots above never move when a variant is added
	var vrng = RandomNumberGenerator.new()
	vrng.seed = DailyScript.stream_seed(g.run_seed, g.round_n, "cache_variant")
	var variants = pick_variants(spots.size(), vrng)
	# the riders a cursed cache calls and the meta coins have a stream of their own, so no roll moves another
	_curse_rng.seed = DailyScript.stream_seed(g.run_seed, g.round_n, "cache_curse")
	var holds = assign_keys(variants)
	keys = 0
	var crng = RandomNumberGenerator.new()
	crng.seed = DailyScript.stream_seed(g.run_seed, g.round_n, "cache_coin")
	var coins = pick_coins(spots.size(), crng)
	for i in range(spots.size()):
		caches.append(_make_cache(spots[i], variants[i], holds[i], coins[i]))


# The variant of each of `count` caches. Every cache draws the same two numbers whatever the cap does, so the
# stream stays in step and the same seed gives the same answer.
static func pick_variants(count: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	var used = 0
	for _i in range(count):
		var roll = rng.randf()
		var which = rng.randi() % VARIANTS.size()
		if roll < VARIANT_CHANCE and used < VARIANT_MAX:
			out.append(VARIANTS[which])
			used += 1
		else:
			out.append(VARIANT_PLAIN)
	return out


# riders a cursed cache calls in round n: CURSE_MIN_RIDERS, one more from round CURSE_BIG_ROUND
static func curse_count(n: int) -> int:
	return CURSE_MAX_RIDERS if n >= CURSE_BIG_ROUND else CURSE_MIN_RIDERS


# Pairs every locked cache with a plain one that holds its key (the first plain cache not yet a holder). A locked cache
# with no plain cache left to hold its key turns plain, so a locked cache can always be opened. Changes `variants` and
# returns, for each cache, whether it holds a key. No random number is drawn, so the same seed gives the same pairs.
static func assign_keys(variants: Array) -> Array:
	var holds: Array = []
	holds.resize(variants.size())
	holds.fill(false)
	for i in range(variants.size()):
		if variants[i] != VARIANT_LOCKED:
			continue
		var holder = -1
		for j in range(variants.size()):
			if variants[j] == VARIANT_PLAIN and not holds[j]:
				holder = j
				break
		if holder < 0:
			variants[i] = VARIANT_PLAIN
		else:
			holds[holder] = true
	return holds


# the colour of a cache's light column and glow
static func variant_color(variant: String) -> Color:
	if variant == VARIANT_VANISHING:
		return VANISH_COL
	if variant == VARIANT_CURSED:
		return CURSED_COL
	if variant == VARIANT_LOCKED:
		return LOCKED_COL
	return GOLD


# riders a cursed cache called that have not come out of their gate yet
func curse_pending() -> int:
	return _curse_gates.size()


# Which of `count` caches hold a meta coin: each draws one number, COIN_CHANCE of them are true, the same seed gives
# the same answer.
static func pick_coins(count: int, rng: RandomNumberGenerator) -> Array:
	var out: Array = []
	for _i in range(count):
		out.append(rng.randf() < COIN_CHANCE)
	return out


# a cache still on the ground: not taken and not vanished (the radar, the markers and the map only show these)
static func is_open(c: Dictionary) -> bool:
	return not c["taken"] and not c["gone"]


# the seconds left of a vanishing cache whose countdown is running, "" otherwise (the HUD marker label)
static func countdown_label(c: Dictionary) -> String:
	if c["variant"] == VARIANT_VANISHING and c["left"] >= 0.0 and is_open(c):
		return "%d" % int(ceil(c["left"]))
	return ""


# "LOCKED" on a locked cache that is still shut ("OPEN" once the player holds a key), "" otherwise (HUD marker label)
func lock_label(c: Dictionary) -> String:
	if c["variant"] == VARIANT_LOCKED and is_open(c):
		return "OPEN" if keys > 0 else "LOCKED"
	return ""


func clear() -> void:
	for c in caches:
		# a taken cache was already queue_free()d in _take(), and once it is really freed the
		# dictionary holds a dead reference that cannot even be assigned to a typed variable
		var n = c["node"]
		if is_instance_valid(n):
			n.queue_free()
	caches.clear()
	if not goal.is_empty():
		var gn = goal["node"]
		if is_instance_valid(gn):
			gn.queue_free()
	goal = {}
	extracting = false
	taken = 0
	_curse_gates.clear()
	_curse_wait = 0.0
	keys = 0


# The riders (and boss) are down: open the way out.
func begin_extraction() -> void:
	if goal.is_empty() or extracting:
		return
	extracting = true
	_style_goal(true)
	g.add_note("ALL DOWN - REACH THE EXTRACTION POINT", GREEN)
	g.sfx.play("pickup")
	g.settings.trigger_hint("extract")  # first-run hint (README alpha E1.3), shown once


func update(dt: float) -> void:
	if goal.is_empty():
		return
	_t += dt
	_tick_curse(dt)
	var pulse = 0.5 + 0.5 * sin(_t * (4.0 if extracting else 1.6))
	var bm: StandardMaterial3D = goal["beam_mat"]
	var col: Color = GREEN if extracting else LOCKED
	bm.albedo_color = Color(
		col.r, col.g, col.b, (0.16 + 0.1 * pulse) if extracting else 0.05 + 0.03 * pulse
	)
	var ring: Node3D = goal["ring"]
	ring.rotation.y += dt * (1.2 if extracting else 0.3)
	for c in caches:
		if not is_open(c):
			continue
		var cn: Node3D = c["crate"]
		cn.rotation.y += dt * 1.6
		cn.position.y = 0.8 + 0.12 * sin(_t * 2.4 + c["pos"].x)
		var d = dist_to(c["pos"])
		if d < SENSE_RANGE:
			g.settings.trigger_hint("cache")  # first-run hint (README alpha E1.3): the first cache in sense range
		c["warn"] = maxf(0.0, c["warn"] - dt)
		if d < CACHE_RADIUS:
			if c["variant"] == VARIANT_LOCKED and keys <= 0:
				_remind_locked(c)
			else:
				_take(c)  # taking wins over a countdown that runs out in the same frame
		elif c["variant"] == VARIANT_VANISHING:
			_tick_vanishing(c, d, dt)
	if extracting and dist_to(goal["pos"]) < GOAL_RADIUS:
		extracting = false
		g.objective_reached()


# The countdown of a vanishing cache: it starts the first time the player is within VANISH_TRIGGER and then runs
# whatever the player does (walking away does not stop it). The crate shrinks and the light column blinks faster
# towards the end; at zero the cache is gone for the round.
func _tick_vanishing(c: Dictionary, d: float, dt: float) -> void:
	if c["left"] < 0.0:
		if d >= VANISH_TRIGGER:
			return
		c["left"] = VANISH_TIME
		g.add_popup(c["pos"] + Vector3(0, 1.8, 0), "VANISHING  %d s" % int(VANISH_TIME), VANISH_COL)
		g.sfx.play("whoosh")
	c["left"] = maxf(0.0, c["left"] - dt)
	var frac = c["left"] / VANISH_TIME
	var crate: Node3D = c["crate"]
	crate.scale = Vector3.ONE * (0.5 + 0.5 * frac)
	var bm: StandardMaterial3D = c["beam_mat"]
	var blink = 1.0 if frac > 0.35 else 0.5 + 0.5 * sin(_t * (14.0 + 20.0 * (1.0 - frac)))
	bm.albedo_color = Color(VANISH_COL.r, VANISH_COL.g, VANISH_COL.b, 0.2 * blink)
	if c["left"] <= 0.0:
		_vanish(c)


func _vanish(c: Dictionary) -> void:
	c["gone"] = true
	var n = c["node"]
	if is_instance_valid(n):
		n.queue_free()
	g.add_popup(c["pos"] + Vector3(0, 1.4, 0), "CACHE GONE", VANISH_GONE)
	g.sfx.play("clank2")


# The riders a cursed cache called come out one after another, each out of the gate that was nearest to the cache.
# They are extra riders (ambush riders in riders.gd): they take no place in the round's `hits`, so they never change
# what clears the round, and they come from a random stream of their own (`_curse_rng`), so when the player takes the
# cache never changes the riders of the round's own waves. Nothing is sent while the game is not in a round.
func _tick_curse(dt: float) -> void:
	if _curse_gates.is_empty():
		return
	if g.state != "play":
		_curse_gates.clear()
		return
	_curse_wait -= dt
	if _curse_wait > 0.0:
		return
	var gate: Dictionary = _curse_gates.pop_front()
	g.rider_sys.spawn_rider(_curse_rng.randi() % 3, 1, true, _curse_rng, gate)
	_curse_wait = CURSE_GAP


# Taking a cursed cache: line up its riders at the gate nearest to it.
func _call_riders(at: Vector3) -> void:
	var gate = g.rider_sys.nearest_open_gate(at)
	if gate.is_empty():
		return
	if _curse_gates.is_empty():
		_curse_wait = CURSE_DELAY
	for _i in range(curse_count(g.round_n)):
		_curse_gates.append(gate)
	g.add_note("CURSED CACHE - RIDERS COMING", CURSED_COL)
	g.sfx.play("boss_intro", -4.0)


# The player stands at a locked cache with no key: say so, not more often than every LOCK_NOTE_GAP seconds
func _remind_locked(c: Dictionary) -> void:
	if c["warn"] > 0.0:
		return
	c["warn"] = LOCK_NOTE_GAP
	g.add_popup(c["pos"] + Vector3(0, 1.8, 0), "LOCKED - FIND A KEY", LOCKED_COL)
	g.sfx.play("clank2")


func _take(c: Dictionary) -> void:
	c["taken"] = true
	taken += 1
	var n: Node = c["node"]
	n.queue_free()
	var at: Vector3 = c["pos"]
	var cursed = c["variant"] == VARIANT_CURSED
	var locked = c["variant"] == VARIANT_LOCKED
	var mult = CURSED_MULT if cursed else (LOCKED_MULT if locked else 1)
	if locked:
		keys -= 1
	g.add_popup(
		at + Vector3(0, 1.4, 0),
		"CACHE  +%d" % (CACHE_SCORE * mult),
		CURSED_COL if cursed else (LOCKED_COL if locked else GOLD)
	)
	g.score += CACHE_SCORE * mult * (2 if g.hype_t > 0.0 else 1)
	g.shop_sys.add_cash(CACHE_CASH * mult)
	if c["key"]:
		keys += 1
		g.add_popup(at + Vector3(0, 2.2, 0), "KEY FOUND", KEY_COL)
	var kind = g.pickup_sys.matter_drop(REWARDS[randi() % REWARDS.size()])
	if kind != "":
		g.pickup_sys.spawn_pickup(kind, at + Vector3(0, 1.0, 0))
	if cursed:
		_call_riders(at)
	if c["coin"]:
		g.meta.add_cache_coin()
		g.add_popup(at + Vector3(0, 2.2, 0), "+1 META COIN", COIN_COL)
	g.sfx.play("pickup")
	g.add_hype(10.0)
	g.hi_check()
	if taken == caches.size():
		g.challenges.on_all_caches(not extracting)
		g.score += ALL_CACHES_SCORE
		g.shop_sys.add_cash(ALL_CACHES_CASH)
		g.add_note("EVERY CACHE FOUND  +%d" % ALL_CACHES_SCORE, GOLD)
		g.sfx.play("clear")


# ------------------------------------------------------------------ visuals
func _beam_material(col: Color) -> StandardMaterial3D:
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	m.albedo_color = col
	return m


func _beam(root: Node3D, radius: float, col: Color) -> StandardMaterial3D:
	var m = _beam_material(col)
	var mi = MeshInstance3D.new()
	mi.mesh = Util.cyl_mesh(radius, radius, BEAM_HEIGHT)
	mi.material_override = m
	mi.position.y = BEAM_HEIGHT * 0.5
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)
	return m


func _make_cache(
	pos: Vector3, variant: String = VARIANT_PLAIN, key: bool = false, coin: bool = false
) -> Dictionary:
	var col = variant_color(variant)
	var root = Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	g.add_child(root)
	var bm = _beam(root, 0.45, Color(col.r, col.g, col.b, 0.2))
	var crate = Node3D.new()
	crate.position.y = 0.8
	root.add_child(crate)
	Util.box(crate, Vector3(0.7, 0.5, 0.5), Vector3.ZERO, Util.mat(Color.html("#7a4e1f"), 0.7))
	Util.box(crate, Vector3(0.74, 0.1, 0.54), Vector3(0, 0.0, 0), Util.glow_shared(col, 1.6))
	Util.box(crate, Vector3(0.12, 0.54, 0.54), Vector3(0, 0, 0), Util.glow_shared(col, 1.6))
	return {
		"pos": Vector3(pos.x, 0.0, pos.z),
		"node": root,
		"crate": crate,
		"beam_mat": bm,
		"taken": false,
		"gone": false,
		"variant": variant,
		"left": -1.0,
		"key": key,
		"warn": 0.0,
		"coin": coin
	}


func _make_goal(pos: Vector3) -> Dictionary:
	var root = Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	g.add_child(root)
	var bm = _beam(root, 1.1, Color(LOCKED.r, LOCKED.g, LOCKED.b, 0.06))
	var ring = Node3D.new()
	ring.position.y = 0.06
	root.add_child(ring)
	var rm = Util.glow(LOCKED, 1.4)
	var disc = MeshInstance3D.new()
	disc.mesh = Util.torus_mesh(GOAL_RADIUS - 0.18, GOAL_RADIUS, 40, 4)
	disc.material_override = rm
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.add_child(disc)
	for k in range(4):  # four chevrons so the turning ring reads as motion
		var a = float(k) * TAU / 4.0
		var tick = Util.box(
			ring,
			Vector3(0.5, 0.05, 0.22),
			Vector3(cos(a) * (GOAL_RADIUS - 0.5), 0.0, sin(a) * (GOAL_RADIUS - 0.5)),
			rm
		)
		tick.rotation.y = -a
	var out = {
		"pos": Vector3(pos.x, 0.0, pos.z),
		"node": root,
		"ring": ring,
		"beam_mat": bm,
		"ring_mat": rm
	}
	return out


func _style_goal(open: bool) -> void:
	var rm: StandardMaterial3D = goal["ring_mat"]
	var col: Color = GREEN if open else LOCKED
	rm.albedo_color = col
	rm.emission = col
	rm.emission_energy_multiplier = 2.4 if open else 1.0
