# Art Direction Brief (draft)

Status: **draft for review.** Written from the code as it is today and your request: *a complete overhaul with modern graphics, completely stripping the current cartoony style.* Decisions marked **[confirm]** are my recommendation, not yet agreed.

## 1. What changes and what stays

| Today | Direction |
|---|---|
| Toon look: flat colours, black outline pass (`toon.gd`, F10 outlines) | **Removed.** Physically based materials, real lighting, no outlines |
| Models assembled from primitive shapes in code (`models.gd`) | Authored 3D models with rigs and textures (glTF) |
| Procedural sky, 4 hand-tuned lighting themes (DAY, GOLDEN HOUR, DUSK, NIGHT) | Same four moods, rebuilt with an HDRI sky, global illumination and colour grading |
| Pooled box and quad particles | Real particle systems, decals, light flashes |
| HUD drawn by hand in `hud.gd` with outlined all-caps text | Themed UI (fonts, icons, panels), cleaner and smaller |

**What stays:** the game design, the roundabout arena layout (fountain in the middle, lanes, tunnel at the seam), the rules, the boss and rider roster, the humour of the voice lines, and every gameplay readability rule in section 4.

## 2. Direction **[confirm]**

**Grounded, modern realism with a dry, deadpan tone.** Think believable Central European city street in real light, shot like a contemporary first-person game: PBR materials, soft real shadows, bounce light, atmospheric haze, filmic colour. The comedy lives in the situation, the voice lines and the animation timing, not in the rendering. Absurd things (a rogue robot lawnmower, a golden president, a giant gummy worm) are rendered as if they were real objects, which is funnier and keeps the style consistent.

Not in scope: gore. Darts, rubber and slapstick crashes stay non-graphic, so the rating stays low.

### Pillars
1. **Real light.** The mood comes from the sun, sky and lamps, not from saturated colours.
2. **Readable at speed.** A rider crossing the screen must be identifiable in a quarter second (section 4).
3. **Believable, then absurd.** Everything is photographed-real until the joke needs it not to be.
4. **One world.** Every asset obeys the same scale, material and colour rules. No mixed styles.

## 3. Look

**Light and colour**
- One authored HDRI sky per lighting theme, plus a sun light; global illumination on (SDFGI or baked probes) so shadow areas pick up bounce.
- Themes map to times of day: DAY (clear, neutral), GOLDEN HOUR (low warm sun, long shadows), DUSK (blue sky, warm lamps start), NIGHT (street lamps, lit windows, wet-looking asphalt).
- Filmic tone mapping and a light colour grade per theme. Keep saturation realistic; use colour sparingly for gameplay objects (pickups, telegraphs, weak spots).
- Light haze/fog for depth, stronger at dusk and night.

**Materials**
- PBR only (albedo, normal, roughness/metal/AO). No unshaded or toon materials except HUD and gameplay overlays.
- Wear and variation: scuffed paint, dirt in seams, worn asphalt, slightly different bike and clothing per rider.

**Characters**
- Realistic proportions, readable clothing silhouettes, helmets and bikes in recognisable categories (road, courier with bag, sprinter, armoured).
- Pedestrians must look clearly different from riders (clothes, posture, no bikes).

**First-person view**
- Gun and gummy worm are rendered on a separate viewmodel pass (own FOV) so they never clip into walls.
- Real animation: sway, recoil, pump reload, melee swing.

## 4. Gameplay readability rules (non-negotiable)

Removing the outlines and flat colours takes away what currently makes things easy to see, so the new look has to earn it back:
1. **Riders read against the background** by value contrast and clothing colour; the road and buildings stay mid-tone and desaturated.
2. **Telegraphs stay stylised.** Boss lane strips, slam circles, phone warnings and weak-spot rings stay as clear, high-contrast overlays or decals, not realistic ones. Their colours must pass a colourblind check (see Milestone E).
3. **The weak spot stays marked** (armoured or open state remains obvious).
4. **Pedestrians vs riders:** shooting a pedestrian ends runs, so this distinction is checked at distance in every lighting theme, including NIGHT.
5. **Hit feedback must stay punchy** even without cartoon squash: hit sparks, sound, screen response and short slow-downs carry it.

## 5. Technical targets (starting values, adjust after profiling)

- Renderer: Forward+ (project default).
- Target 60 fps on a mid-range GPU at 1080p; the F9 quality presets are redefined around this (high: GI + shadows + AA; medium: baked GI, cheaper shadows; low: no GI, no volumetric fog).
- Up to about 8 riders plus 1 boss on screen. Starting budgets per model: rider + bike ~20k triangles with 2 LODs; boss ~40k; props ~2-5k; texture sets 2K for hero assets, 1K for the rest.
- Anti-aliasing: TAA or FSR in place of the current 2x MSAA.
- Scale: 1 unit = 1 metre. Models exported as `.glb` from Blender, Y up, applied transforms, named per `assets/` folder rules (set up in the foundation steps of the roadmap).

## 6. Asset sourcing

Mix of custom models and CC0 libraries (see `docs/ASSET_SOURCES.md`). Whatever the source, every asset gets an entry in `CREDITS.md` with its source and licence, and anything not CC0 is checked before it ships.

## 7. How the work is split

The roadmap (Milestone F in `README.md`) breaks the overhaul into small steps, one asset or screen each, in this order: foundation (baseline, pipeline, lighting) → gun → melee → riders → phones → pedestrians and cheerleaders → bosses → pickups → world → effects → UI and menus → final pass. Each step is done when:
- it replaces the old version completely (no mixed styles left in that area),
- it passes the readability rules in section 4,
- frame time is checked against the budget,
- there is a before/after screenshot.

## 8. Open questions for you

1. **Realism level:** fully photoreal, or "stylised realism" (real materials, slightly simplified shapes)? I recommended the second for the budget a small team can finish; the first is possible but much more work for characters.
2. **Models:** do you (or someone) make 3D models, or should the plan lean on CC0 libraries and modify them?
3. **Minimum PC spec** you want to support, since it decides how aggressive GI and fog can be.
4. **Reference images:** a handful of screenshots from games or photos you like would fix the look faster than any description.
5. **Keep the humour visible** in costumes and props (for example the golden president), or make everything more serious?
