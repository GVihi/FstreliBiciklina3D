extends RefCounted
# Exploration objectives on generated arenas (README Milestone K, "Exploration and extraction").
#
#   Supply caches   A few glowing crates spread over the arena, far from the start. Each one is marked by a gold
#                   light column that rises above the rooftops, so a curious player can see where to go. Walking
#                   into one pays cash, score and a random pick-up; all of them pays a bonus. They are there from the
#                   first second of the round, so a fight can be taken across the map.
#   Extraction      Once every rider (and boss) is down the round does not end by itself any more: a green light
#                   column opens at the far end of the arena and the round is cleared when the player reaches it.
#                   Before that it is shown dimmed, so the player knows where the run will end.
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

var g = null
var caches: Array = []  # each {"pos": Vector3, "node": Node3D, "taken": bool}
var goal: Dictionary = {}  # {"pos": Vector3, "node": Node3D, "beam_mat": StandardMaterial3D, "ring_mat": ...}
var extracting = false  # every rider is down and the way out is open
var taken = 0  # caches taken this round
var _t = 0.0


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
	for sp in g.arena.cache_spots(CACHE_COUNT, gp, rng):
		caches.append(_make_cache(sp))


func clear() -> void:
	for c in caches:
		var n: Node = c["node"]
		n.queue_free()
	caches.clear()
	if not goal.is_empty():
		var gn: Node = goal["node"]
		gn.queue_free()
	goal = {}
	extracting = false
	taken = 0


# The riders (and boss) are down: open the way out.
func begin_extraction() -> void:
	if goal.is_empty() or extracting:
		return
	extracting = true
	_style_goal(true)
	g.add_note("ALL DOWN - REACH THE EXTRACTION POINT", GREEN)
	g.sfx.play("pickup")


func update(dt: float) -> void:
	if goal.is_empty():
		return
	_t += dt
	var pulse = 0.5 + 0.5 * sin(_t * (4.0 if extracting else 1.6))
	var bm: StandardMaterial3D = goal["beam_mat"]
	var col: Color = GREEN if extracting else LOCKED
	bm.albedo_color = Color(
		col.r, col.g, col.b, (0.16 + 0.1 * pulse) if extracting else 0.05 + 0.03 * pulse
	)
	var ring: Node3D = goal["ring"]
	ring.rotation.y += dt * (1.2 if extracting else 0.3)
	for c in caches:
		if c["taken"]:
			continue
		var cn: Node3D = c["crate"]
		cn.rotation.y += dt * 1.6
		cn.position.y = 0.8 + 0.12 * sin(_t * 2.4 + c["pos"].x)
		if dist_to(c["pos"]) < CACHE_RADIUS:
			_take(c)
	if extracting and dist_to(goal["pos"]) < GOAL_RADIUS:
		extracting = false
		g.objective_reached()


func _take(c: Dictionary) -> void:
	c["taken"] = true
	taken += 1
	var n: Node = c["node"]
	n.queue_free()
	var at: Vector3 = c["pos"]
	g.add_popup(at + Vector3(0, 1.4, 0), "CACHE  +%d" % CACHE_SCORE, GOLD)
	g.score += CACHE_SCORE * (2 if g.hype_t > 0.0 else 1)
	g.shop_sys.add_cash(CACHE_CASH)
	var kind = REWARDS[randi() % REWARDS.size()]
	if kind == "heart" and g.hearts >= g.MAXHEARTS:
		kind = "cash"
	g.pickup_sys.spawn_pickup(kind, at + Vector3(0, 1.0, 0))
	g.sfx.play("pickup")
	g.add_hype(10.0)
	g.hi_check()
	if taken == caches.size():
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


func _make_cache(pos: Vector3) -> Dictionary:
	var root = Node3D.new()
	root.position = Vector3(pos.x, 0.0, pos.z)
	g.add_child(root)
	_beam(root, 0.45, Color(GOLD.r, GOLD.g, GOLD.b, 0.2))
	var crate = Node3D.new()
	crate.position.y = 0.8
	root.add_child(crate)
	Util.box(crate, Vector3(0.7, 0.5, 0.5), Vector3.ZERO, Util.mat(Color.html("#7a4e1f"), 0.7))
	Util.box(crate, Vector3(0.74, 0.1, 0.54), Vector3(0, 0.0, 0), Util.glow_shared(GOLD, 1.6))
	Util.box(crate, Vector3(0.12, 0.54, 0.54), Vector3(0, 0, 0), Util.glow_shared(GOLD, 1.6))
	return {"pos": Vector3(pos.x, 0.0, pos.z), "node": root, "crate": crate, "taken": false}


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
