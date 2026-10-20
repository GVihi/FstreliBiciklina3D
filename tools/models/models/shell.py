"""The shotgun shell (Milestone F2): a chunky red plastic shell with a metal base, thrown out of the gun when you
pump it. About 0.07 m long and 0.03 m across, centred on its middle.

Orientation: the front of the shell points to +Y in Blender (-Z in Godot), the base to -Y.
"""
from kit import geo

INFO = {"category": "prop"}


def build():
    geo.cyl("body", 0.0125, 0.046, (0, 0.006, 0), "red", sides=8, bevel=0.002, rot=(90, 0, 0))
    geo.cyl("base", 0.0138, 0.022, (0, -0.026, 0), "metal_light", sides=8, bevel=0.002, rot=(90, 0, 0))
    geo.cyl("rim", 0.0152, 0.005, (0, -0.0365, 0), "metal_mid", sides=8, rot=(90, 0, 0))
    geo.cyl("band", 0.0132, 0.008, (0, 0.012, 0), "hazard_yellow", sides=8, rot=(90, 0, 0))
    geo.cyl("crimp", 0.0105, 0.006, (0, 0.032, 0), "hazard_black", sides=8, rot=(90, 0, 0))
    geo.join_all("shell")
