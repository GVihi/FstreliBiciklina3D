extends RefCounted
# Toon look: one full-screen depth-edge outline pass (a single quad, much cheaper than a second copy
# of every mesh) plus a little bloom. Lit materials use Godot's built-in toon diffuse (see util.gd).

const SHADER_CODE = """
shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform vec4 line_color : source_color = vec4(0.05, 0.04, 0.07, 1.0);
uniform float threshold = 0.07;
uniform float compat = 0.0;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float lin_depth(float d, vec2 uv, mat4 inv_proj) {
	float z = mix(d, d * 2.0 - 1.0, compat);
	vec4 v = inv_proj * vec4(uv * 2.0 - 1.0, z, 1.0);
	v.xyz /= v.w;
	return -v.z;
}

void fragment() {
	vec2 px = 1.0 / VIEWPORT_SIZE;
	vec2 uc = SCREEN_UV;
	vec2 ul = SCREEN_UV + vec2(-px.x, 0.0);
	vec2 ur = SCREEN_UV + vec2(px.x, 0.0);
	vec2 uu = SCREEN_UV + vec2(0.0, -px.y);
	vec2 ud = SCREEN_UV + vec2(0.0, px.y);
	float dc = textureLod(depth_texture, uc, 0.0).r;
	float dl = textureLod(depth_texture, ul, 0.0).r;
	float dr = textureLod(depth_texture, ur, 0.0).r;
	float du = textureLod(depth_texture, uu, 0.0).r;
	float dd = textureLod(depth_texture, ud, 0.0).r;
	float c = lin_depth(dc, uc, INV_PROJECTION_MATRIX);
	float l = lin_depth(dl, ul, INV_PROJECTION_MATRIX);
	float r = lin_depth(dr, ur, INV_PROJECTION_MATRIX);
	float u = lin_depth(du, uu, INV_PROJECTION_MATRIX);
	float d = lin_depth(dd, ud, INV_PROJECTION_MATRIX);
	float e = (abs(l + r - 2.0 * c) + abs(u + d - 2.0 * c)) / max(c, 0.01);
	float line = smoothstep(threshold, threshold * 2.0, e);
	line *= 1.0 - smoothstep(60.0, 180.0, c);
	vec3 col = texture(screen_texture, SCREEN_UV).rgb;
	vec3 outc = mix(col, line_color.rgb, line * line_color.a);
	ALBEDO = mix(outc, pow(outc, vec3(0.55)), compat);
}
"""


static func make_outline_quad() -> MeshInstance3D:
	var mi = MeshInstance3D.new()
	var qm = QuadMesh.new()
	qm.size = Vector2(2.0, 2.0)
	qm.flip_faces = true
	mi.mesh = qm
	mi.extra_cull_margin = 16384.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var sh = Shader.new()
	sh.code = SHADER_CODE
	var m = ShaderMaterial.new()
	m.shader = sh
	m.render_priority = -128  # draw before every other see-through thing, so strips, rings and fades stay on top of it
	m.set_shader_parameter("compat", 1.0 if RenderingServer.get_rendering_device() == null else 0.0)
	mi.material_override = m
	return mi


static func setup_glow(env: Environment) -> void:
	env.glow_enabled = true
	env.glow_intensity = 0.5
	env.glow_strength = 0.9
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
