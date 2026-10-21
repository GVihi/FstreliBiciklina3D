"""First-person melee weapon (Milestone F3): a giant glossy, glittery pink jelly-rubber club, held by the knob.

It replaces the procedural gummy worm in scripts/models.gd (build_rubber): same reach and same hand position, so the
swing, the reach ring and the deflect range do not move. One colour (no alternating light / dark ribs), no eyes.

Shape (from the owner's reference photo, a glittery translucent pink toy): a ribbed grip collar and a fat round knob
at the held end, a narrow neck, a long gently curved shaft with raised rings, and a rounded head with a ridge under it.
It is built as one lofted faceted tube (`geo.tube`), so the ribs are real geometry and the facets catch the sun
(low roughness material: glossy rubber), plus a sprinkle of tiny glitter flecks as a second surface.

Orientation: the tip points to +Y in Blender, which the glTF export turns into -Z in Godot (the viewmodel's forward),
so no rotation is needed. The held end (the knob) is at y = -0.2, which is z = +0.2 in Godot, and the tip is at
y = 1.0 (z = -1.0): the same extents as the old worm, so the viewmodel placement stays valid.
"""
import math

from kit import geo

INFO = {"category": "viewmodel"}

Y_BASE = -0.20          # the knob in your hand
Y_TIP = 1.00            # the head
SIDES = 12
RINGS = 96

# (t along the club, radius in metres): the silhouette. t = 0 is the knob end, t = 1 the tip of the head.
PROFILE = [
    (0.000, 0.034), (0.012, 0.050), (0.030, 0.058),     # rounded end of the grip collar
    (0.100, 0.060), (0.130, 0.052),                      # ribbed grip collar
    (0.165, 0.066), (0.220, 0.092), (0.280, 0.104),      # fat round knob
    (0.340, 0.094), (0.410, 0.072), (0.470, 0.060),      # down to the neck
    (0.560, 0.064), (0.700, 0.072), (0.820, 0.079),      # shaft thickens towards the head
    (0.860, 0.078), (0.878, 0.060),                      # groove under the head
    (0.905, 0.100), (0.945, 0.092),                      # ridge, then the head
    (0.975, 0.072), (0.992, 0.050), (1.000, 0.026),      # rounded tip
]

# raised rings: (t_start, t_end, count, height in metres)
RIBS = [
    (0.040, 0.125, 4, 0.0075),     # grip collar
    (0.470, 0.850, 7, 0.0055),     # shaft
]


def _profile(t):
    for (t0, r0), (t1, r1) in zip(PROFILE, PROFILE[1:]):
        if t0 <= t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-9)
            u = u * u * (3.0 - 2.0 * u)            # smoothstep: soft transitions, faceted result
            return r0 + (r1 - r0) * u
    return PROFILE[-1][1]


def _rib(t):
    extra = 0.0
    for t0, t1, count, h in RIBS:
        if t0 <= t <= t1:
            u = (t - t0) / (t1 - t0)
            wave = 0.5 - 0.5 * math.cos(2.0 * math.pi * count * u)      # 0..1, count bumps
            fade = math.sin(math.pi * u) ** 0.5                          # ribs die out at both ends
            extra += h * wave * fade
    return extra


def _centre(t):
    """Gentle S-curve like the old worm, with the head lifting up a little like the reference."""
    y = Y_BASE + (Y_TIP - Y_BASE) * t
    x = 0.040 * math.sin(t * math.pi * 1.6)
    z = 0.045 * math.sin(t * math.pi) + 0.03 * t * t
    return (x, y, z)


def build():
    rings = []
    for i in range(RINGS):
        t = i / (RINGS - 1)
        rings.append((_centre(t), _profile(t) + _rib(t)))
    geo.tube("jelly", rings, "jelly_pink", sides=SIDES)
    geo.sparkles("glitter", rings, "glitter", count=150, size=0.0085, seed=7, sides=SIDES)
    geo.join_all("jelly_club")
