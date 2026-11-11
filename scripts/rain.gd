extends RefCounted
# Rain: how a round with the "rain" modifier looks (README MD6.2, docs/MAP_GENERATION.md "Round modifiers: rain").
# It is the look only; the one rule of rain is `pursuit_accel` in riders.gd (MD6.4). Three small parts:
#   rainy_theme   a theme with its colours moved toward grey and dimmer, never below the NIGHT theme (a pure function)
#   set_wet       the ground parts of the generated world drawn with a darker, glossier copy of their material, and
#                 the original put back (no shared material is changed, so nothing can be left wet behind)
#   update        the streaks: one MultiMesh of at most STREAKS thin quads (one draw call) around the camera
# Everything is undone by the same calls that did it. main.gd `apply_theme(i, rainy)` always goes through
# rainy_theme and set_wet, so a round without rain gets the plain theme and the original materials, and `update` hides
# the streaks in every state but a rain round that is being played, so no way out of a round needs its own call.

const STREAKS = 400  # the most streaks drawn at once (first guess, README MD6.2: measured on both renderers)
const BOX_HALF = 16.0  # the streaks fall in a box this many metres to each side of the camera
const BOX_HEIGHT = 14.0  # ... and this tall, the top of it BOX_HEIGHT - BOX_BELOW above the camera
const BOX_BELOW = 2.0  # the bottom of the box is this far under the camera: about the ground at eye height
const STREAK_LENGTH = 0.8
const STREAK_WIDTH = 0.012
const FALL_SPEED = 20.0  # metres per second
const STREAK_COLOR = Color(0.8, 0.87, 0.95, 0.25)  # thin and low in opacity: at most 0.25
const GREY_SHIFT = 0.35  # the share of a sky, sun and ambient colour that moves to its own grey
const DIM = 0.82  # the sky and ambient colours are this much of what they were, after the grey shift
const SUN_DIM = 0.75  # the sun's energy, after which it never goes below the NIGHT theme's
const WET_DARKEN = 0.7  # a wet ground colour is this much of the dry one
const WET_ROUGHNESS = 0.35  # a wet ground is glossier than the 0.95 of the dry one
# the parts of `world["ground_parts"]` that get wet: the ground a rider and the player move on, not the paint, the
# hazard frame at the start (a marker that has to stay readable), the buildings or the unshaded tunnels
const WET_PARTS = ["ground_grass", "ground_plaza", "ground_sidewalk", "ground_road", "curbs"]
const STREAK_SEED = 6021  # the streaks have their own random numbers: no seed of a run or a map is touched

var g = null
var round_rain = false  # the round being played has the rain modifier (set by start_round)
var holder: MultiMeshInstance3D = null
var offsets = PackedVector3Array()  # per streak: x and z in the box, y the phase of its fall
var fall_t = 0.0
var swapped = {}  # MeshInstance3D -> the material it had before it was made wet
var wet_of = {}  # material -> its wet copy


func _init(game) -> void:
	g = game


# ---------------------------------------------------------------- the theme
static func luma(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


# `c` moved toward its own grey and dimmed, but raised again to the brightness of `low` when that left it darker
static func greyer(c: Color, low: Color, dim: float) -> Color:
	var l = luma(c)
	var out = c.lerp(Color(l, l, l, c.a), GREY_SHIFT)
	out = Color(out.r * dim, out.g * dim, out.b * dim, c.a)
	var lo = luma(out)
	var lf = luma(low)
	if lo > 0.0 and lo < lf:
		var k = lf / lo
		out = Color(minf(out.r * k, 1.0), minf(out.g * k, 1.0), minf(out.b * k, 1.0), c.a)
	return out


# A copy of the theme `th` (a Content.THEMES entry) as rain makes it: sky, horizon and ambient light greyer and a little
# darker, the sun greyer and weaker. `low` is the theme that sets how dark rain may get (NIGHT): no colour is darker
# than that theme's own, so the arena has no pitch black (docs/ART_DIRECTION.md). `th` is not changed, and neither
# are the lamps, the lit windows or the ambient energy.
static func rainy_theme(th: Dictionary, low: Dictionary = {}) -> Dictionary:
	var out = th.duplicate()
	for key in ["top", "hor", "amb"]:
		out[key] = greyer(th[key], low.get(key, Color(0, 0, 0)), DIM)
	out["sun"] = greyer(th["sun"], low.get("sun", Color(0, 0, 0)), 1.0)
	var dimmed = maxf(float(th["sun_e"]) * SUN_DIM, float(low.get("sun_e", 0.0)))
	out["sun_e"] = minf(float(th["sun_e"]), dimmed)
	return out


# ---------------------------------------------------------------- the ground
func wet_material(m: Material) -> Material:
	if not (m is BaseMaterial3D):
		return m
	if not wet_of.has(m):
		var dry: BaseMaterial3D = m
		var w = dry.duplicate() as BaseMaterial3D
		var c: Color = dry.albedo_color
		w.albedo_color = Color(c.r * WET_DARKEN, c.g * WET_DARKEN, c.b * WET_DARKEN, c.a)
		w.roughness = WET_ROUGHNESS
		wet_of[m] = w
	return wet_of[m]


# Draws the ground of the world in `g.world` wet (on), or as it was (off). A world that has no "ground_parts" (the
# roundabout, the training room) stays as it is. Safe to call again and again, and after the world was rebuilt: a part
# that was freed with its old world is forgotten.
func set_wet(on: bool) -> void:
	for mi in swapped.keys():
		if not is_instance_valid(mi):
			swapped.erase(mi)
	if not on:
		for mi in swapped:
			mi.material_override = swapped[mi]
		swapped.clear()
		return
	var parts: Dictionary = g.world.get("ground_parts", {})
	for part_name in WET_PARTS:
		var mi = parts.get(part_name)
		if mi == null or not is_instance_valid(mi) or swapped.has(mi):
			continue
		var own = mi.material_override
		if own == null:
			continue
		swapped[mi] = own
		mi.material_override = wet_material(own)


# ---------------------------------------------------------------- the streaks
# how many streaks are drawn at the SHAKE AND FLASH setting `fx` (0 to 1): none at 0, so only the greyer sky and the
# wet ground remain
static func streak_count(fx: float) -> int:
	return int(round(float(STREAKS) * clampf(fx, 0.0, 1.0)))


func _build() -> void:
	var quad = QuadMesh.new()
	quad.size = Vector2(STREAK_WIDTH, STREAK_LENGTH)
	var m = StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = STREAK_COLOR
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y  # upright, turned to face the camera
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = m
	var mm = MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = STREAKS
	mm.visible_instance_count = 0
	holder = MultiMeshInstance3D.new()
	holder.name = "RainStreaks"
	holder.multimesh = mm
	holder.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# the instances move every frame inside the box around the holder, which sits on the camera: say so once
	holder.custom_aabb = AABB(
		Vector3(-BOX_HALF, -BOX_BELOW, -BOX_HALF),
		Vector3(BOX_HALF * 2.0, BOX_HEIGHT, BOX_HALF * 2.0)
	)
	holder.visible = false
	g.add_child(holder)
	var rng = RandomNumberGenerator.new()
	rng.seed = STREAK_SEED
	offsets.resize(STREAKS)
	for i in range(STREAKS):
		offsets[i] = Vector3(
			rng.randf_range(-BOX_HALF, BOX_HALF),
			rng.randf() * BOX_HEIGHT,
			rng.randf_range(-BOX_HALF, BOX_HALF)
		)


# Called every frame with the time that passed in the game (0 while paused). Shows the streaks in a rain round that is
# being played and hides them in every other state, so a clear, a death, a quit and a practice round need no call.
func update(dt: float) -> void:
	var count = streak_count(g.fx_scale)
	var on = round_rain and g.state == "play" and count > 0 and g.cam != null
	if not on:
		if holder != null:
			holder.visible = false
		return
	if holder == null:
		_build()
	holder.visible = true
	fall_t += dt
	var cp: Vector3 = g.cam.global_position
	holder.global_position = cp
	var mm = holder.multimesh
	mm.visible_instance_count = count
	for i in range(count):
		var o = offsets[i]
		# x and z are wrapped around the camera, so a streak stays where it is in the world while the camera moves and
		# comes back on the far side when it leaves the box
		var x = wrapf(o.x - cp.x, -BOX_HALF, BOX_HALF)
		var z = wrapf(o.z - cp.z, -BOX_HALF, BOX_HALF)
		var y = BOX_HEIGHT - BOX_BELOW - fposmod(o.y + fall_t * FALL_SPEED, BOX_HEIGHT)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
