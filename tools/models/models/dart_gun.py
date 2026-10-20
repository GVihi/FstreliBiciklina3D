"""First-person foam-dart pump shotgun (Milestone F2): chunky, bevelled, safety-orange, with a blue pump slide,
hazard-yellow slashes, dark-metal barrel and glowing cyan strips.

It replaces the procedural gun in scripts/models.gd (build_gun). Same size and layout as that gun, so the viewmodel
placement, the muzzle point (0, 0.03, -0.66) and the pump animation (the pump moves back along Z) stay valid.

Orientation: the barrel points to +Y in Blender. The glTF export turns +Y into -Z, so in Godot the barrel already
points to -Z (Godot's forward) and no rotation is needed. (Props face -Y by the kit convention; a viewmodel is the
exception because the player looks down the barrel.)
Origin: the old gun's root, not the base: x centred, receiver centre 0.05 m in front of it, so nothing in the game moves.

Two objects are exported: "dart_gun" (everything fixed) and "pump" (the slide, its origin at its own centre so it can
slide on its own).
"""
import bpy

from kit import geo

INFO = {"category": "viewmodel"}


def _join(objs, name):
    """Join some objects into one with one surface per material, centred on its own bounding box."""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    return ob


def _centre_origin(ob):
    bpy.ops.object.select_all(action="DESELECT")
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.object.origin_set(type="ORIGIN_GEOMETRY", center="BOUNDS")


def build():
    fixed = []
    add = fixed.append

    # Blender: x right, y forward (barrel), z up. Old Godot (x, y, z) -> Blender (x, -z, y).

    # --- receiver: the big orange block, with a dark top rail and glowing side strips
    add(geo.box("receiver", (0.078, 0.36, 0.115), (0, 0.05, 0), "safety_orange", bevel=0.014))
    add(geo.box("receiver_cap", (0.086, 0.07, 0.100), (0, 0.235, -0.003), "metal_dark", bevel=0.012))
    add(geo.box("top_rail", (0.040, 0.30, 0.018), (0, 0.05, 0.062), "metal_dark", bevel=0.006))
    for sx in (-1, 1):
        add(geo.box("strip", (0.006, 0.20, 0.014), (sx * 0.0405, 0.03, 0.022), "glow_cyan", bevel=0.002))
        add(geo.box("receiver_plate", (0.008, 0.12, 0.05), (sx * 0.041, 0.10, -0.018), "metal_dark", bevel=0.003))

    # --- rear and front sights
    add(geo.box("rear_sight_l", (0.007, 0.012, 0.016), (-0.014, -0.08, 0.079), "metal_dark", bevel=0.002))
    add(geo.box("rear_sight_r", (0.007, 0.012, 0.016), (0.014, -0.08, 0.079), "metal_dark", bevel=0.002))
    add(geo.box("front_sight", (0.014, 0.018, 0.022), (0, 0.62, 0.066), "hivis_lime", bevel=0.003))

    # --- barrel and muzzle (muzzle point stays at y 0.66, z 0.03)
    add(geo.cyl("barrel", 0.024, 0.52, (0, 0.40, 0.03), "metal_dark", sides=8, bevel=0.003, rot=(90, 0, 0)))
    add(geo.cyl("muzzle_ring", 0.033, 0.045, (0, 0.638, 0.03), "safety_orange", sides=8, bevel=0.004, rot=(90, 0, 0)))
    add(geo.cyl("muzzle_tip", 0.026, 0.012, (0, 0.664, 0.03), "hazard_black", sides=8, rot=(90, 0, 0)))

    # --- magazine tube under the barrel, with a cap and a clamp
    add(geo.cyl("mag_tube", 0.019, 0.40, (0, 0.33, -0.022), "metal_mid", sides=8, bevel=0.002, rot=(90, 0, 0)))
    add(geo.cyl("mag_cap", 0.025, 0.03, (0, 0.545, -0.022), "metal_dark", sides=8, bevel=0.003, rot=(90, 0, 0)))
    add(geo.box("barrel_clamp", (0.052, 0.034, 0.088), (0, 0.50, 0.004), "metal_dark", bevel=0.007))

    # --- stock (tilted back and down) with a rubber butt pad and a hazard band
    add(geo.box("stock", (0.056, 0.25, 0.115), (0, -0.205, -0.034), "safety_orange", bevel=0.013,
                rot=(-7, 0, 0)))
    add(geo.box("butt_pad", (0.062, 0.035, 0.125), (0, -0.335, -0.05), "rubber", bevel=0.01, rot=(-7, 0, 0)))
    add(geo.box("stock_stripe_dark", (0.060, 0.045, 0.118), (0, -0.265, -0.042), "hazard_black", bevel=0.006,
                rot=(-7, 0, 0)))
    add(geo.box("stock_stripe_yel", (0.062, 0.022, 0.120), (0, -0.265, -0.042), "hazard_yellow", bevel=0.004,
                rot=(-7, 0, 0)))

    # --- pistol grip (tilted) with a rubber wrap, and a trigger guard with a trigger
    add(geo.box("grip", (0.050, 0.065, 0.125), (0, -0.075, -0.10), "safety_orange", bevel=0.011, rot=(-14, 0, 0)))
    add(geo.box("grip_wrap", (0.056, 0.05, 0.07), (0, -0.07, -0.125), "rubber", bevel=0.01, rot=(-14, 0, 0)))
    add(geo.box("guard_bottom", (0.012, 0.11, 0.012), (0, 0.045, -0.092), "metal_dark", bevel=0.003))
    add(geo.box("guard_front", (0.012, 0.014, 0.05), (0, 0.098, -0.068), "metal_dark", bevel=0.003))
    add(geo.box("trigger", (0.012, 0.016, 0.040), (0, 0.040, -0.062), "hazard_yellow", bevel=0.003, rot=(14, 0, 0)))

    # --- ejection port: a dark slot on the right side
    add(geo.box("port", (0.006, 0.07, 0.03), (0.0405, 0.0, 0.03), "hazard_black", bevel=0.002))

    body = _join(fixed, "dart_gun")

    # --- the pump slide: its own object, because it moves back and forth when you pump
    pump = []
    pump.append(geo.box("pump_body", (0.076, 0.19, 0.074), (0, 0.30, -0.05), "blue", bevel=0.012))
    for i, y in enumerate((0.226, 0.263, 0.300, 0.337, 0.374)):
        pump.append(geo.box("pump_rib%d" % i, (0.082, 0.014, 0.080), (0, y, -0.05), "metal_dark", bevel=0.003))
    for sx in (-1, 1):
        for i in range(3):
            pump.append(geo.box("pump_slash", (0.005, 0.030, 0.060), (sx * 0.0395, 0.255 + i * 0.045, -0.05),
                                "hazard_yellow", bevel=0.002, rot=(35, 0, 0)))
    slide = _join(pump, "pump")
    _centre_origin(slide)
    # body keeps the old gun root as its origin
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
