"""The one shared palette and material set. Every model uses only these names, so all assets match.

Colours are sRGB hex (what you see in a colour picker). Bright, hi-vis and hazard colours are reserved for
gameplay and accents; the neutrals (concrete, asphalt, brick, metals, rubber) make the base of the world.
Each entry: (hex colour, roughness, metallic, glows)
"""

PALETTE = {
    # neutrals: the world
    "concrete":      ("#C9C5BC", 0.90, 0.0, False),
    "asphalt":       ("#5A5D63", 0.95, 0.0, False),
    "brick":         ("#B5573C", 0.90, 0.0, False),
    "paint_white":   ("#F2F0EA", 0.60, 0.0, False),
    "rubber":        ("#2A2C31", 0.85, 0.0, False),
    # metals
    "metal_dark":    ("#353A42", 0.50, 0.6, False),
    "metal_mid":     ("#747B85", 0.45, 0.7, False),
    "metal_light":   ("#B4BAC3", 0.40, 0.8, False),
    # hazard and hi-vis: the recurring motif
    "hazard_yellow": ("#FFC400", 0.55, 0.0, False),
    "hazard_black":  ("#1C1E22", 0.70, 0.0, False),
    "safety_orange": ("#FF6B2B", 0.55, 0.0, False),   # the game's accent colour
    "hivis_lime":    ("#C8F02A", 0.60, 0.0, False),
    # accent colours for characters and bosses
    "teal":          ("#19B5A5", 0.50, 0.0, False),
    "red":           ("#E5392B", 0.55, 0.0, False),
    "blue":          ("#2F7FE0", 0.50, 0.0, False),
    # glowing parts (lamps, strips, screens, weak spots)
    "glow_amber":    ("#FFB02E", 0.40, 0.0, True),
    "glow_cyan":     ("#38E8FF", 0.40, 0.0, True),
    "glow_red":      ("#FF4A3A", 0.40, 0.0, True),
}

# triangle budgets per category (docs/ART_DIRECTION.md section 5)
BUDGETS = {
    "prop": 2000,
    "rider": 6000,
    "boss": 15000,
    "viewmodel": 10000,   # first-person gun / melee: seen up close, one at a time
    "building": 2000,
}
