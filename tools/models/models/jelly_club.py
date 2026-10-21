"""First-person melee weapon (Milestone F3): a giant glossy, glittery pink jelly-rubber club, held by the knob.

It replaces the procedural gummy worm in scripts/models.gd (build_rubber): same reach and same hand position, so the
swing, the reach ring and the deflect range do not move. One colour (no alternating light / dark ribs), no eyes.

Shape (from the owner's reference photo, a glittery translucent pink toy): a flanged end and a ribbed grip collar and a
fat round knob at the held end, a narrow neck, a long gently curved shaft whose lower part has raised rings and whose
upper part has spiral ridges, and a rounded head with a ridge under it. Detail like the dart gun has: a flange and
groove on the end, a moulded seam running down one side, two kinds of ridges, and glitter in two sizes.
It is built as one lofted faceted tube (`geo.tube`), so every ridge is real geometry and the facets catch the sun
(low roughness material: glossy rubber), plus the glitter flecks as a second surface.

Orientation: the tip points to +Y in Blender, which the glTF export turns into -Z in Godot (the viewmodel's forward),
so no rotation is needed. The held end (the knob) is at y = -0.2, which is z = +0.2 in Godot, and the tip is at
y = 1.0 (z = -1.0): the same extents as the old worm, so the viewmodel placement stays valid.
"""
import math

from kit import geo

INFO = {"category": "viewmodel"}

Y_BASE = -0.20          # the knob in your hand
Y_TIP = 1.00            # the head
SIDES = 16
RINGS = 130

# (t along the club, radius in metres): the silhouette. t = 0 is the knob end, t = 1 the tip of the head.
PROFILE = [
    (0.000, 0.046), (0.006, 0.058), (0.020, 0.058),     # flange on the held end
    (0.030, 0.047), (0.042, 0.047),                      # groove behind it
    (0.052, 0.060), (0.100, 0.062), (0.130, 0.053),      # ribbed grip collar
    (0.165, 0.066), (0.220, 0.092), (0.280, 0.104),      # fat round knob
    (0.340, 0.094), (0.410, 0.072), (0.470, 0.060),      # down to the neck
    (0.560, 0.064), (0.700, 0.072), (0.820, 0.079),      # shaft thickens towards the head
    (0.860, 0.078), (0.878, 0.060),                      # groove under the head
    (0.905, 0.100), (0.945, 0.092),                      # ridge, then the head
    (0.975, 0.072), (0.992, 0.050), (1.000, 0.026),      # rounded tip
]

# raised rings: (t_start, t_end, count, height in metres)
RIBS = [
    (0.055, 0.125, 3, 0.0075),     # grip collar
    (0.470, 0.600, 3, 0.0050),     # lower shaft
]

# spiral ridges on the upper shaft: (t_start, t_end, ridges around, turns along the section, height in metres)
SPIRAL = (0.600, 0.850, 4, 1.5, 0.0085)

# the moulded seam: a thin ridge down one side, from the collar to the groove under the head
SEAM = (0.050, 0.870, 0.0042)


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


def _ridges(i, ang):
    """Spiral ridges and the seam, added to the radius at ring i, angle ang."""
    t = i / (RINGS - 1)
    extra = 0.0
    t0, t1, n, turns, h = SPIRAL
    if t0 <= t <= t1:
        u = (t - t0) / (t1 - t0)
        wave = 0.5 + 0.5 * math.cos(n * ang - 2.0 * math.pi * turns * u)
        extra += h * (wave ** 2) * math.sin(math.pi * u) ** 0.5
    s0, s1, sh = SEAM
    if s0 <= t <= s1:
        d = math.atan2(math.sin(ang), math.cos(ang))                    # 0 at the seam side, +-pi opposite
        extra += sh * max(0.0, 1.0 - abs(d) / 0.28)
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
    geo.tube("jelly", rings, "jelly_pink", sides=SIDES, radius_fn=_ridges)
    geo.sparkles("glitter", rings, "glitter", count=260, size=0.0085, seed=7, sides=SIDES)
    geo.sparkles("glitter_big", rings, "glitter", count=22, size=0.016, seed=11, sides=SIDES, lift=0.003)
    geo.join_all("jelly_club")
