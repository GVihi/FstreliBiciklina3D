extends RefCounted
# Wall-jump marks (README Milestone L, wall-jumps): the glow on a wall the player can jump off, and the ripple that
# runs over it when one happens.
#
# While the player is in the air, a wall within WALL_SHOW metres (player.gd) gets a flat panel of chevrons climbing it:
# dim and cool blue while the wall is still a few metres away, bright gold once it is close enough to push off, and a
# dull red panel without chevrons when the wall-jumps of this airtime are used up. On the ground nothing is drawn, so the
# walls look as they always did. A wall-jump sends a ring over the wall from the spot the player pushed off.
#
# Both are one flat quad with a small shader (unshaded, additive, no depth write), created the first time they are
# needed and then moved, so a round without wall-jumps costs nothing. `update` is called every frame by player.gd.

const PAD_SIZE = Vector2(2.4, 2.6)  # metres: the glow is about as tall as the player, a little wider than a doorway
const PAD_LIFT = 0.05  # metres in front of the wall face, so the glow never flickers with the wall behind it
const CHEST = 1.0  # metres above the player's feet: where the middle of the glow and the ripple are
const RIPPLE_SIZE = 2.2
const RIPPLE_TIME = 0.4  # seconds the ring takes to run out
const FADE_SPEED = 9.0  # glow strength per second

const PAD_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float u_strength = 0.0;
uniform float u_ready = 0.0;
uniform float u_spent = 0.0;

void fragment() {
	vec2 e = min(UV, 1.0 - UV);
	float edge = smoothstep(0.0, 0.25, min(e.x, e.y));
	float side = abs(UV.x - 0.5);
	// chevrons that point up and climb the wall (UV.y grows downwards)
	float f = fract(UV.y * 3.0 - side * 2.4 + TIME * 1.3);
	float chev = smoothstep(0.0, 0.1, f) * (1.0 - smoothstep(0.2, 0.34, f));
	vec3 col = mix(vec3(0.25, 0.85, 1.0), vec3(1.0, 0.92, 0.45), u_ready);
	col = mix(col, vec3(1.0, 0.25, 0.2), u_spent);
	float stripes = mix(chev, 0.0, u_spent);
	ALBEDO = col;
	ALPHA = clamp(edge * (0.12 + 0.88 * stripes) * u_strength, 0.0, 1.0);
}
"""

const RIPPLE_SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, fog_disabled;

uniform float u_t = 0.0;

void fragment() {
	float d = length(UV - vec2(0.5)) * 2.0;
	float ring = 1.0 - smoothstep(0.0, 0.14, abs(d - u_t));
	float fill = (1.0 - smoothstep(0.0, max(u_t, 0.001), d)) * 0.35;
	float a = (ring + fill) * (1.0 - u_t) * (1.0 - smoothstep(0.9, 1.0, d));
	ALBEDO = vec3(0.9, 1.0, 1.0);
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

var g = null
var pad: MeshInstance3D = null
var ripple: MeshInstance3D = null
var vis = 0.0  # how strongly the glow shows now (0 to 1), eased towards what the wall asks for
var ripple_t = -1.0  # 0 to 1 while a ring runs, below 0 when there is none


func _init(game) -> void:
	g = game


# One frame. `info` is the wall the arena found near the player (Arena.wall_near, an empty Dictionary when there is none),
# `near` how close it is to being usable (0 at the far edge of the range, 1 once the player can push off it) and `spent`
# whether the wall-jumps of this airtime are used up.
func update(dt: float, info: Dictionary, near: float, spent: bool) -> void:
	var want = 0.0
	if not info.is_empty():
		want = lerpf(0.3, 1.0, clampf(near, 0.0, 1.0))
		_ensure_pad()
		_place(pad, info["point"], info["normal"], PAD_LIFT)
		var mat: ShaderMaterial = pad.material_override
		mat.set_shader_parameter("u_ready", 1.0 if near >= 1.0 and not spent else 0.0)
		mat.set_shader_parameter("u_spent", 1.0 if spent else 0.0)
	vis = move_toward(vis, want, dt * FADE_SPEED)
	if pad != null:
		pad.visible = vis > 0.01
		(pad.material_override as ShaderMaterial).set_shader_parameter("u_strength", vis)
	if ripple_t >= 0.0:
		ripple_t += dt / RIPPLE_TIME
		if ripple_t >= 1.0:
			ripple_t = -1.0
			ripple.visible = false
		else:
			(ripple.material_override as ShaderMaterial).set_shader_parameter("u_t", ripple_t)


# a ring over the wall, from `point` (on the wall face, at the player's feet) with the wall's `normal`
func burst(point: Vector3, normal: Vector3) -> void:
	if ripple == null:
		ripple = _quad(Vector2(RIPPLE_SIZE, RIPPLE_SIZE), RIPPLE_SHADER)
	_place(ripple, point, normal, PAD_LIFT + 0.01)
	ripple_t = 0.0
	(ripple.material_override as ShaderMaterial).set_shader_parameter("u_t", 0.0)
	ripple.visible = true


# round start and new run: nothing is shown
func reset() -> void:
	vis = 0.0
	ripple_t = -1.0
	if pad != null:
		pad.visible = false
	if ripple != null:
		ripple.visible = false


func _ensure_pad() -> void:
	if pad == null:
		pad = _quad(PAD_SIZE, PAD_SHADER)


# put a quad on the wall: in front of the face by `lift`, a chest's height above the player's feet, facing out of the wall
func _place(node: MeshInstance3D, point: Vector3, normal: Vector3, lift: float) -> void:
	var x_axis = Vector3.UP.cross(normal).normalized()
	node.basis = Basis(x_axis, Vector3.UP, normal)
	node.position = point + normal * lift + Vector3(0.0, CHEST, 0.0)


func _quad(size: Vector2, shader_code: String) -> MeshInstance3D:
	var shader = Shader.new()
	shader.code = shader_code
	var mat = ShaderMaterial.new()
	mat.shader = shader
	var q = QuadMesh.new()
	q.size = size
	var mi = MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	g.add_child(mi)
	return mi
