"""The foam dart (Milestone F2), flying through the world: a chunky orange body, a blue suction-cup tip, a white
collar and hi-vis lime tail fins, so it reads against the sky, the road and the riders.

Replaces the two primitives in scripts/combat.gd spawn_dart (a box and a sphere). About 0.17 m long, the same
colours as before (orange body, blue tip). Centred on its middle.

Orientation: the tip points to +Y in Blender, which the glTF export turns into -Z in Godot, and Godot's look_at
points -Z at the target, so the dart flies tip first with no rotation.
"""
from kit import geo

INFO = {"category": "prop"}


def build():
    # body, collar, tip
    geo.cyl("body", 0.012, 0.100, (0, -0.010, 0), "safety_orange", sides=6, bevel=0.002, rot=(90, 0, 0))
    geo.cyl("collar", 0.0145, 0.012, (0, 0.046, 0), "paint_white", sides=6, bevel=0.002, rot=(90, 0, 0))
    geo.cyl("tip", 0.0155, 0.036, (0, 0.070, 0), "blue", sides=6, bevel=0.002, rot=(-90, 0, 0), radius_top=0.009)
    # rear cap and two crossed tail fins
    geo.cyl("cap", 0.010, 0.012, (0, -0.066, 0), "metal_dark", sides=6, rot=(90, 0, 0))
    geo.box("fin_h", (0.040, 0.034, 0.003), (0, -0.068, 0), "hivis_lime", bevel=0.0008)
    geo.box("fin_v", (0.003, 0.034, 0.040), (0, -0.068, 0), "hivis_lime", bevel=0.0008)
    geo.join_all("dart")
