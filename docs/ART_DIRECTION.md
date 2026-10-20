# Art Direction Brief (draft 3)

Status: **draft, owner answers included.** Direction: *not realistic, it must run on lower-end PCs, inspired by the Deep Rock franchise (Deep Rock Galactic, Rogue Core, Deep Rock Galactic: Survivor) but not alien or dwarf themed, and the game stays bright: it is a bicycle shooter, not a horror game.*

**Decisions so far**
- Minimum spec: **Intel i5-7500, GTX 1060 3 GB, 8 GB RAM, 1080p at 60 fps.**
- Models: **built by Claude** with scripted Blender (see section 7).
- Brightness: **bright and readable.** Dark and moody is out.
- Style: chunky, bevelled low-poly with bold colour, strong light/dark shapes and glowing accents. No outlines.

## 1. The idea in one line

**A bright city street built from chunky, bevelled, hand-painted low-poly shapes, with bold hi-vis and hazard colours, glowing accents and one clear UI language.** Heavy, utilitarian, readable at a glance, cheap to render.

This takes the *principles* of the Deep Rock look. Nothing is copied: no assets, characters, logos or recognisable designs, no dwarf or alien theme. Our world is a roundabout, our enemies are cyclists and absurd office-and-garden machines.

## 2. What your reference screenshots show

| Reference | What to take from it |
|---|---|
| **First-person combat (cave, flamethrower, green splatter)** | Faceted low-poly surfaces; the **gun is the star**: chunky, bevelled, panel lines, a bold painted stripe, glowing cyan strips. Hit effects are saturated and unmistakable (acid green splatter, magenta glow, blue-white energy). Warm muzzle flash lights the surroundings. Enemies are simple, chunky shapes with clear limbs. |
| **Rogue Core corridor (blue gun, ammo counter)** | The **ammo count is on the weapon itself** (diegetic), so the HUD can stay small. Boxy industrial panels, glowing green screens as light sources. |
| **Orbital hub (red, teal, yellow, hazard stripes)** | Proof that the style can be **very colourful and bright**: saturated red, teal, yellow and orange, hazard-stripe floor markings, bevelled panels everywhere, glowing signs, a holographic hero object. Characters have oversized chunky armour, faceted. Text signage is part of the world. |
| **Survivor, top-down boss fight** | Dark scene made readable by **glowing accents**: cyan pickups, orange boss rim light, warm light pools. Minimal HUD: round minimap top-left, weapon icons and a thick health bar at the bottom, a thin progress bar. Boss health bar with a skull. |
| **Survivor level-up cards** | **Our upgrade and shop cards, almost directly:** dark translucent panels, amber header, an icon, a rarity tag (blue rare, grey common, green uncommon), short stat text, a "Reroll all" button with its cost, a blurred game behind, key-hint chips in the corner ("ESC details, SPACE select"). Condensed bold type. |
| **Pause menu** | Dark panel with a thick amber outline, large amber buttons with dark text, the hovered button turns bright yellow, hazard-stripe footer, small info panel on the side. |

**What we change for "bright":** all of these references are dark scenes lit by glowing accents. Ours is a sunny city, so the lighting is brighter and the *colour contrast* does the job the darkness does there. The accent colours (orange, yellow, teal, hi-vis) stay; the black cave becomes pale concrete and asphalt with deep, soft shadows.

## 3. Look

**Shapes**
- Chunky, slightly exaggerated proportions: big helmets, boots, gloves, thick frames. Bevelled hard edges, faceted forms, few curves.
- Strong silhouettes first: pro, sprinter, courier and armoured must be tell-apart-able as flat black shapes.
- Utilitarian props: hazard stripes, hi-vis vests, reflectors, dented metal, delivery boxes, road signs.
- Variety over detail.

**Materials**
- Simple lit materials: one colour or gradient, a small hand-painted texture or a shared atlas for wear, **no normal maps** on most assets.
- Roughness differences between metal, rubber and plastic; emissive for lamps, signs, screens and glowing parts.
- No outlines. Edges are defined by bevel highlights and value contrast.

**Light and colour (bright)**
- DAY and GOLDEN HOUR are the main look: a clear bright sun, soft readable shadows, a light blue sky.
- DUSK and NIGHT stay readable: warm street lamps, lit windows and glowing gameplay accents, a medium-dark blue sky rather than black. No pitch black anywhere in the arena.
- Neutral base (concrete, asphalt, brick, painted metal) with strong accent colours reserved for gameplay: pickups, telegraphs, weak spots, hit effects.
- Glow and bloom on gameplay accents.

**Characters and bosses**
- Riders are enemy "species", each with its own silhouette and key colour (pro, sprinter, courier with a big bag, armoured with plates).
- Bosses are bigger, chunkier versions of the same rules, with a clearly lit weak spot.

**First-person view**
- The gun and the gummy worm are the stars: chunky, bright, bevelled, with glowing strips. Separate viewmodel pass (own FOV, no wall clipping).
- Ammo count shown on the weapon.
- Punchy animation: recoil, pump, swing; screen response does the rest.

**Effects**
- Saturated, short, unmistakable: bright sparks, colour bursts, glow. Hit effects colour-code what happened (weak spot, armour, rider, pedestrian).

## 4. UI direction

Based on the Survivor and Deep Rock screens (section 2):
- One language: **dark translucent panels, amber/orange accents, bold condensed type, small key-hint chips.** Our current orange accent already matches.
- Upgrade and shop cards, pause menu, settings and run summary all follow it.
- Rarity colours on upgrades (common grey, uncommon green, rare blue, and so on), which also fits the shop's perks and duos.
- Small, tidy HUD: minimap or radar top-left, health and weapons bottom-centre, progress bar along the bottom.
- Hazard-stripe details as decoration, not clutter.

## 5. Technical targets for the minimum spec (starting values, adjust after profiling)

Target machine: **i5-7500 (4 cores), GTX 1060 3 GB, 8 GB RAM, 1080p at 60 fps.** The 3 GB of video memory and the 4-core CPU are the real limits.

| Item | Target |
|---|---|
| Frame time | 16.6 ms at 1080p on the target machine |
| Rider + bike | about 3,000 to 6,000 triangles |
| Boss | about 8,000 to 15,000 triangles |
| Props and buildings | 200 to 2,000 triangles each, instanced |
| Draw calls | keep low: shared materials and atlases, MultiMesh for repeated props and particles |
| Video memory | all textures together well under about 1 GB; shared 512 to 1024 px atlases, no normal maps on most assets |
| Lighting | one directional sun with soft shadows (cascades limited), a small number of real lights, baked light for the static arena where it helps |
| Not used | SDFGI, volumetric fog, SSR, SSAO (a "high" preset may include SSAO if it fits) |
| Anti-aliasing | MSAA 2x or cheaper FXAA |
| CPU | keep the per-frame script work and entity counts in check; a GTX 1060 will not be the first bottleneck |
| Quality presets | F9 stays: high (shadows, MSAA, glow), medium (no MSAA), low (no shadows, no glow) |

Open technical test: **Compatibility renderer vs Forward+** on this class of hardware. With a GTX 1060 either works, so the decision is made on measured frame time and look, not on assumptions.

## 6. Gameplay readability rules (non-negotiable)

1. **Riders read against the background** by silhouette, value contrast and key colour; the road and buildings stay mid-tone and less saturated than gameplay colours.
2. **Telegraphs are bold and glowing.** Boss lane strips, slam circles, phone warnings and weak-spot rings are high-contrast overlays or decals and pass a colourblind check (Milestone E).
3. **The weak spot is clearly marked** (open vs armoured stays obvious).
4. **Pedestrians vs riders:** hitting a pedestrian ends the run, so they are checked at distance in every theme, NIGHT included.
5. **Hit feedback stays punchy:** sparks, sound, screen response and short slow-downs.
6. **Brightness:** no area of the arena may hide a rider or a telegraph in the dark.

## 7. How the models get made

**Claude builds them with scripted Blender** (`bpy`, the Blender Python module). I tested this in the working environment: it installs, builds a bevelled model, renders a preview with the CPU renderer and exports `.glb`.

- Scripts live in `tools/models/`, one per asset, so every model can be rebuilt and tweaked later (change a number, rerun).
- Output goes to `assets/models/*.glb`, with a turntable preview image per model for review.
- A shared kit keeps the style consistent: chunky bevelled primitives, a common palette, one material set, one scale (1 unit = 1 metre), consistent naming.
- Rigs and animation: simple skeletons and animation clips built in the same scripts (pedal cycle, recoil, swing). Complex animation may later need hand polish in Blender.

**Honest limits.** I cannot run Godot in the working environment, so I can verify a model in Blender preview renders and check the `.glb` is valid, but you confirm how it looks and performs in the game. Each model step in the roadmap therefore ends with a check from you. Very organic or highly detailed art is not what scripted modelling does best, which suits this chunky style well.

CC0 low-poly packs (see `docs/ASSET_SOURCES.md`) remain an option for props and filler. Every third-party asset gets a `CREDITS.md` entry.

## 8. How the work is split

Milestone F in `README.md`: foundation → dart gun → melee → riders → phones → pedestrians and cheerleaders → bosses → pickups → world → effects → UI and menus → final pass. A step is done when the old version is fully replaced, it passes section 6, frame time is within section 5, you have checked it in the game, and there is a before/after screenshot.

## 9. Remaining questions for you

1. **UI language:** go with the dark translucent panels and amber accents from section 4 (it matches your current orange), or something brighter to suit the sunny look?
2. **Ammo on the weapon** (like the Rogue Core screenshot) instead of in the HUD: yes?
3. **Rarity colours** on upgrades and shop items (common, uncommon, rare, ...): yes?
4. **Hazard stripes and hi-vis** as the recurring visual motif for the game: yes? It fits cyclists and road works naturally.
5. **Name and logo:** the title screen will need a logo. Text-only chunky logo, or should it include a small emblem?
