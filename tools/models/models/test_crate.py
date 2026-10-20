"""Test prop for the style kit: a delivery crate with hazard stripes, corner bumpers, a handle and a glowing lamp.
Exercises every part of the kit (bevelled boxes, taper, cylinders, hazard stripes, emissive material, join)
so the look can be checked in the game before any real model is built."""
from kit import geo

INFO = {"category": "prop"}


def build():
    w, d, h = 0.9, 0.6, 0.55          # width (x), depth (y), height (z)

    geo.box("body", (w, d, h), (0, 0, 0), "safety_orange", bevel=0.05, base=True)
    geo.box("lid", (w + 0.04, d + 0.04, 0.07), (0, 0, h), "metal_mid", bevel=0.02, base=True)

    # chunky corner bumpers
    for sx in (-1, 1):
        for sy in (-1, 1):
            for z0, sz in ((0.0, 0.11), (h - 0.11, 0.11)):
                geo.box("bumper", (0.13, 0.13, sz), (sx * (w / 2 - 0.045), sy * (d / 2 - 0.045), z0),
                        "metal_dark", bevel=0.025, base=True)

    # hazard-stripe band on the front (-Y) face
    geo.hazard_stripes("hazard", width=w - 0.30, height=0.14, center_x=0, bottom_z=0.07,
                       y_front=-d / 2 - 0.0, stripes=6)

    # white reflector strips
    geo.box("reflector_l", (0.14, 0.02, 0.05), (-0.28, -d / 2 - 0.005, 0.38), "paint_white", bevel=0.008)
    geo.box("reflector_r", (0.14, 0.02, 0.05), (0.28, -d / 2 - 0.005, 0.38), "paint_white", bevel=0.008)

    # carry handle on the lid: two posts and a bar
    geo.box("handle_post_l", (0.05, 0.05, 0.09), (-0.16, 0, h + 0.07), "metal_dark", bevel=0.01, base=True)
    geo.box("handle_post_r", (0.05, 0.05, 0.09), (0.16, 0, h + 0.07), "metal_dark", bevel=0.01, base=True)
    geo.box("handle_bar", (0.37, 0.06, 0.05), (0, 0, h + 0.16), "metal_dark", bevel=0.015, base=True)

    # glowing amber beacon on the lid
    geo.cyl("beacon_base", 0.07, 0.03, (0.32, 0.0, h + 0.07), "metal_dark", sides=8, base=True)
    geo.cyl("beacon_lamp", 0.055, 0.09, (0.32, 0.0, h + 0.10), "glow_amber", sides=8, base=True, radius_top=0.04)

    geo.join_all("test_crate")
