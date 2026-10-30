extends RefCounted
# Rim outline (fresnel) for characters: a soft glow along the silhouette that tells friend from foe at a glance.
#   foes (riders, bosses)                    red
#   bystanders (pedestrians, cheerleaders)   green
# It is a shared overlay material (one per colour) put on the bigger meshes of a model, so it costs one extra
# draw call per mesh and no new materials per spawn. It is depth tested like any other surface: it never shows
# through walls. The hit flash (`Main.set_flash`) uses the same overlay slot, so it puts the rim back when it ends.
# Turn it off with `ENABLED` here or the RIM OUTLINE row in settings.
#
# Distance: from FAR_START to FAR_END metres from the camera the rim gets thicker, brighter and gets a soft fill
# inside the silhouette, so a rider or pedestrian far across the arena is still a clear coloured shape instead of
# a thin line. Up close nothing changes. The fill is the part that matters most: a thin rim is under a pixel wide
# at 60 m, a filled shape is not. Playtester report 2026-10-30.
#
# Red against green is the hardest pair for colour-blind players, so the foe tint is a hot red-orange and the
# bystander tint a cool green-cyan, and the setting can switch the whole effect off.

const FOE = "foe"
const FRIEND = "friend"
const ENABLED = true
const MIN_SIZE = 0.16  # metres: meshes smaller than this (bolts, spokes, eyes) get no rim, like trim_shadows
const META = "rim_mat"  # meta key on a MeshInstance3D holding the rim material it was given

const COLORS = {FOE: Color(1.0, 0.25, 0.1), FRIEND: Color(0.2, 0.95, 0.6)}
const STRENGTH = 0.55  # peak opacity of the glow at the silhouette
const POWER = 2.6  # higher = thinner rim
const FAR_START = 18.0  # metres: the rim starts to grow
const FAR_END = 75.0  # metres: fully grown from here on (the dart gun reaches 80 m)
const FAR_STRENGTH = 0.9  # peak opacity of the rim at FAR_END
const FAR_POWER = 1.2  # a much thicker rim at FAR_END
const FAR_FILL = 0.4  # how much of the colour fills the whole shape at FAR_END
const FAR_BOOST = 1.5  # the colour is brighter by this factor at FAR_END (glow picks it up)

const SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_back, depth_draw_never, fog_disabled;

uniform vec3 rim_color : source_color = vec3(1.0, 0.25, 0.1);
uniform float strength = 0.55;
uniform float power = 2.6;
uniform float far_start = 18.0;
uniform float far_end = 75.0;
uniform float far_strength = 0.9;
uniform float far_power = 1.2;
uniform float far_fill = 0.4;
uniform float far_boost = 1.5;

void fragment() {
	float k = smoothstep(far_start, far_end, length(VERTEX));
	float p = mix(power, far_power, k);
	float f = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), p);
	float a = max(f * mix(strength, far_strength, k), far_fill * k);
	ALBEDO = rim_color * mix(1.0, far_boost, k);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _shader: Shader = null
static var _mats := {}


static func material_for(kind: String) -> ShaderMaterial:
	if _mats.has(kind):
		return _mats[kind]
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER
	var m = ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("rim_color", COLORS[kind])
	m.set_shader_parameter("strength", STRENGTH)
	m.set_shader_parameter("power", POWER)
	m.set_shader_parameter("far_start", FAR_START)
	m.set_shader_parameter("far_end", FAR_END)
	m.set_shader_parameter("far_strength", FAR_STRENGTH)
	m.set_shader_parameter("far_power", FAR_POWER)
	m.set_shader_parameter("far_fill", FAR_FILL)
	m.set_shader_parameter("far_boost", FAR_BOOST)
	_mats[kind] = m
	return m


# Put the rim on every mesh of `node` that is big enough. `on` false takes it off again (the setting).
static func apply(node: Node, kind: String, on: bool = true) -> void:
	if node is MeshInstance3D:
		var mi: MeshInstance3D = node
		if mi.mesh != null:
			var ext = mi.mesh.get_aabb().size * mi.scale
			if maxf(ext.x, maxf(ext.y, ext.z)) >= MIN_SIZE:
				if on and ENABLED:
					var rm = material_for(kind)
					mi.set_meta(META, rm)
					mi.material_overlay = rm
				else:
					if mi.has_meta(META):
						mi.remove_meta(META)
					mi.material_overlay = null
	for ch in node.get_children():
		apply(ch, kind, on)


# What a mesh's overlay slot goes back to when the hit flash ends: its rim, or nothing.
static func resting_overlay(mi: MeshInstance3D) -> Material:
	if mi.has_meta(META):
		return mi.get_meta(META)
	return null


# Count the meshes under `node` that carry a rim (used by the check).
static func count(node: Node) -> int:
	var n = 0
	if node is MeshInstance3D and node.has_meta(META):
		n += 1
	for ch in node.get_children():
		n += count(ch)
	return n
