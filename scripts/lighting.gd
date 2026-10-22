extends RefCounted
# Shared lighting setup for the new look (README Milestone F1, docs/ART_DIRECTION.md "Light and colour").
# world.gd calls these once when it builds the arena; the per-theme colours and sun angle live in
# Content.THEMES and are applied by main.gd apply_theme().
#
# DAY baseline: a bright sun, soft readable shadows, a light sky, Filmic tone mapping (ACES was tried and
# washed the yellow kerb stripe out to white) and glow only on things that are brighter than the scene
# (pickups, lamps, lit windows, telegraphs), so the glow marks gameplay accents and not the whole picture.


static func setup_environment(env: Environment) -> void:
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.glow_hdr_threshold = 1.0  # only emissive things above 1.0 glow
	env.glow_bloom = 0.0
	env.glow_intensity = 0.6
	env.glow_strength = 1.0


static func setup_sun(sun: DirectionalLight3D) -> void:
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL  # 1 shadow map instead of 4 splits
	sun.directional_shadow_max_distance = 36.0
	sun.shadow_blur = 2.0  # soft edges on the one shadow map, cheaper than percentage-closer soft shadows
	sun.shadow_bias = 0.04
	sun.shadow_normal_bias = 1.2


# ---- themes (README Milestone K, "Theme lighting and lit windows on generated arenas")
# The one place a Content.THEMES entry is applied to a world, so the roundabout (main.gd) and generated arenas
# (WorldDress) light the same way.
const MAX_LAMP_LIGHTS = 8  # lamp lights on at once: more cost frame time (and Compatibility drops lights past 8 per mesh)
const LAMP_HEAD_GLOW = 3.0  # emission of a lit lamp head


# A fresh sky and environment, not yet in a scene: {"env": Environment, "sky_mat": ProceduralSkyMaterial}.
static func make_environment() -> Dictionary:
	var env = Environment.new()
	var sky_mat = ProceduralSkyMaterial.new()
	var sky = Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_energy = 0.8
	setup_environment(env)
	return {"env": env, "sky_mat": sky_mat}


# Applies a Content.THEMES entry to a world: {"sky_mat", "sun", "env", "lamps": [OmniLight3D], "lamp_mat",
# "win_mat"}. The sky, sun and ambient light follow the theme; windows glow at its "lit" strength; when it has
# lamps on, every lamp head glows and the lights of at most MAX_LAMP_LIGHTS lamps come on, the ones nearest
# `focus` (a world position, such as the start) when the world has more than that, the first ones otherwise.
static func apply_theme(th: Dictionary, world: Dictionary, focus: Vector3 = Vector3.INF) -> void:
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
	var lamps: Array = world["lamps"]
	var on = []
	if th["lamps"]:
		on = lamps.duplicate()
		if focus != Vector3.INF:
			on.sort_custom(
				func(a, b):
					return (
						a.position.distance_squared_to(focus)
						< b.position.distance_squared_to(focus)
					)
			)
		on = on.slice(0, MAX_LAMP_LIGHTS)
	for l in lamps:
		l.visible = on.has(l)
	world["lamp_mat"].emission_energy_multiplier = LAMP_HEAD_GLOW if th["lamps"] else 0.0
	world["win_mat"].emission_energy_multiplier = th["lit"]
