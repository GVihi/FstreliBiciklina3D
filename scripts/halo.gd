extends RefCounted
# Phone halo: a glow that follows a thrown phone and never gets smaller on screen than a set size, so a phone
# far away across the arena is still a bright, pulsing dot you can see and dodge. Close up it fades out, because
# there the phone itself is easy to see and a big glow would only cover the view.
#
# It is one flat quad that always faces the camera. The size is worked out in the vertex shader from the distance,
# so no script runs per frame, and every halo shares one mesh and one material (one extra draw call per phone in
# the air). It does not test depth, so a phone low over the ground is not cut in half by the road; a phone cannot
# fly behind a building anyway (phones.gd smashes it on the wall), so it never shows through one in a way that
# matters. A phone that was deflected is no longer a danger, so `hide_on` switches its halo off.
# Turn it off with `ENABLED` here.

const ENABLED = true
const NODE_NAME = "Halo"
const MIN_ANGLE = 0.045  # glow size as a share of the distance (about 2.6 degrees: 35 pixels at 1080p)
const FADE_NEAR = 4.0  # metres: the glow is gone inside this distance
const FADE_FAR = 16.0  # metres: and fully there from this distance on
const STRENGTH = 1.1
const PULSE_SPEED = 9.0

const SHADER = """
shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;

uniform float min_angle = 0.045;
uniform float fade_near = 4.0;
uniform float fade_far = 16.0;
uniform float strength = 1.1;
uniform float pulse_speed = 9.0;

varying float cam_dist;

void vertex() {
	vec4 c = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	cam_dist = max(-c.z, 0.1);
	float s = cam_dist * min_angle * 2.0;
	POSITION = PROJECTION_MATRIX * vec4(c.xyz + vec3(VERTEX.xy * s, 0.0), 1.0);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float core = clamp(1.0 - r, 0.0, 1.0);
	vec3 col = mix(vec3(1.0, 0.3, 0.08), vec3(1.0, 0.9, 0.5), core * core);
	float a = core * core * strength;
	a *= 0.8 + 0.2 * sin(TIME * pulse_speed);
	a *= smoothstep(fade_near, fade_far, cam_dist);
	ALBEDO = col;
	ALPHA = clamp(a, 0.0, 1.0);
}
"""

static var _shader: Shader = null
static var _mat: ShaderMaterial = null
static var _mesh: QuadMesh = null


static func material() -> ShaderMaterial:
	if _mat != null:
		return _mat
	_shader = Shader.new()
	_shader.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = _shader
	_mat.set_shader_parameter("min_angle", MIN_ANGLE)
	_mat.set_shader_parameter("fade_near", FADE_NEAR)
	_mat.set_shader_parameter("fade_far", FADE_FAR)
	_mat.set_shader_parameter("strength", STRENGTH)
	_mat.set_shader_parameter("pulse_speed", PULSE_SPEED)
	return _mat


# Put the halo on `node` (a phone): a child called NODE_NAME. Does nothing when ENABLED is false.
static func attach(node: Node3D) -> void:
	if not ENABLED:
		return
	if _mesh == null:
		_mesh = QuadMesh.new()
		_mesh.size = Vector2(1.0, 1.0)
	var mi = MeshInstance3D.new()
	mi.name = NODE_NAME
	mi.mesh = _mesh
	mi.material_override = material()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0  # the quad is drawn bigger than its mesh, so keep it from being culled early
	node.add_child(mi)


# The halo of `node`, or null.
static func of(node: Node) -> Node3D:
	var h = node.get_node_or_null(NODE_NAME)
	if h is Node3D:
		return h
	return null


# A deflected phone is no longer a danger: its halo goes off.
static func hide_on(node: Node) -> void:
	var h = of(node)
	if h != null:
		h.visible = false
