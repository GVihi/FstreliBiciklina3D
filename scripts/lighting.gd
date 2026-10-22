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
