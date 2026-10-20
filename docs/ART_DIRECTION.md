# Art Direction Brief (draft 2)

Status: **draft for review.** Direction from the owner: *not realistic, it is still a video game, it must run on lower-end PCs. Main inspiration: the Deep Rock Galactic franchise (including Deep Rock Galactic: Survivor), but not alien or dwarf themed.*

## 1. The idea in one line

**Chunky, rugged, low-poly with strong light and dark contrast and glowing accents, set in a city street.** Heavy, utilitarian shapes; a handful of bold colours; everything readable at a glance; cheap to render.

What I could confirm about the Deep Rock look (developer interview and a style write-up; nothing specific to *Survivor* was found, so I apply the franchise traits):
- Low-poly, with simple textures and a "consistent chunky feel": boxy, heavy-duty weapons, rough-hewn outfits, creatures built from large chunks.
- The team chose variety over fidelity ("ten types of stylized monsters rather than one really high-def one"), and tried normal-mapped detailed models and moved away from them.
- The look depends on stark contrast between light and dark, with glowing light sources (crystals, flares) giving colour; colours are real light colours, not a screen tint.

This is inspiration for *principles*. Nothing is copied: no assets, characters, logos or recognisable designs, and no dwarf or alien themes. Our world is a city roundabout, our enemies are cyclists and absurd office-and-garden machines.

## 2. What goes, what stays

| Goes | Stays |
|---|---|
| Black outline pass (`toon.gd`, F10 outlines) | Game design, rules, rider and boss roster |
| Flat unlit toon shading and candy palette | The roundabout arena layout (fountain, lanes, tunnel) |
| Smooth capsule-and-sphere models assembled in code | The humour of the voice lines |
| Procedural sky and plain ambient light | Every readability rule in section 5 |
| Pooled box and quad effects | The four moods (DAY, GOLDEN HOUR, DUSK, NIGHT) |

## 3. Look

**Shapes**
- Chunky, slightly exaggerated proportions: big helmets, big boots and gloves, thick frames. Hard edges and bevels, faceted forms, few curves.
- Strong silhouettes first. If a character is a flat black shape it must still be identifiable as pro, sprinter, courier or armoured.
- Utilitarian "heavy duty" props: hazard stripes, hi-vis vests, reflectors, dented metal, delivery boxes.
- Variety over detail: many distinct simple models beat a few detailed ones.

**Materials**
- Simple lit materials: a single colour or gradient, a small hand-painted texture or shared atlas for grime and wear, no normal maps on most assets.
- A little roughness variation so metal and rubber look different; emissive for lights, screens, glowing parts.
- No outlines. Edges are defined by lighting and value contrast.

**Light and colour**
- Stark contrast: bright key light and deep shadow, then coloured pools of light on top (street lamps, lit windows, shop signs, boss glow).
- Keep the arena itself always playable-bright; contrast comes from shadow shapes, not from hiding enemies in the dark.
- Four moods: DAY (clean, high contrast), GOLDEN HOUR (warm low sun, long shadows), DUSK (blue sky, lamps coming on), NIGHT (dark blue with strong warm lamps).
- A restrained base palette (concrete, asphalt, brick, painted metal) so gameplay colours stand out: pickups, telegraphs, weak spots, hit effects.
- Glow and bloom on gameplay accents, since it is cheap and effective.

**Characters and bosses**
- Riders as enemy "species" like the roster in other roguelites: each type has its own silhouette and key colour (pro, sprinter, courier with a big bag, armoured with plates).
- Bosses are bigger, chunkier versions of the same rules, with a clearly lit weak spot.

**First-person view**
- Gun and gummy worm are chunky, readable and bright, on a separate viewmodel pass (own FOV, no wall clipping).
- Punchy animation: recoil, pump, swing; screen response does the rest.

## 4. Technical targets for low-end PCs (starting values, adjust after profiling)

| Item | Target |
|---|---|
| Frame rate | 60 fps on an integrated GPU (720p to 1080p) **[confirm minimum spec]** |
| Rider + bike | about 3,000 to 6,000 triangles, 1 LOD |
| Boss | about 8,000 to 15,000 triangles |
| Props and buildings | 200 to 2,000 triangles each, instanced |
| Textures | shared 512 to 1024 px atlases, hand-painted; no normal maps on most assets |
| Lighting | one directional sun with soft shadows, a few real lights, baked light for the static world (arena is static) where it helps |
| Not used | SDFGI, volumetric fog, SSR, SSAO (unless a "high" preset can afford them) |
| Anti-aliasing | keep MSAA or use cheaper FXAA; no temporal AA required |
| Effects | cheap GPU particles, few overdraw-heavy layers |
| Quality presets | F9 stays: high (shadows, MSAA, glow), medium (no MSAA), low (no shadows, no glow) |

Open technical decision: test whether the **Compatibility renderer** (broadest hardware support) looks and performs acceptably on an old GPU, versus Forward+ (current default). It is a roadmap item in F1.

## 5. Gameplay readability rules (non-negotiable)

1. **Riders read against the background** by silhouette, value contrast and key colour; the road and buildings stay mid-tone and desaturated.
2. **Telegraphs stay stylised and glowing.** Boss lane strips, slam circles, phone warnings and weak-spot rings are bold, high-contrast overlays or decals, and must pass a colourblind check (Milestone E).
3. **The weak spot is clearly marked** (open vs armoured stays obvious).
4. **Pedestrians vs riders:** hitting a pedestrian ends the run, so they are checked at distance in every theme, NIGHT included.
5. **Hit feedback stays punchy:** sparks, sound, screen response and short slow-downs.

## 6. Asset sourcing

Low-poly CC0 libraries are a good match for this style and can be modified (see `docs/ASSET_SOURCES.md`). Custom models are still needed for the hero assets (gun, riders, bosses). Every third-party asset gets a `CREDITS.md` entry.

## 7. How the work is split

Milestone F in `README.md` lists small steps in this order: foundation → dart gun → melee → riders → phones → pedestrians and cheerleaders → bosses → pickups → world → effects → UI and menus → final pass. A step is done when the old version is fully replaced, it passes section 5, frame time is within the targets above, and there is a before/after screenshot.

## 8. Open questions for you

1. **Minimum PC spec:** the oldest hardware you want to run at 60 fps (it sets how many lights and shadows we can afford).
2. **Who makes the 3D models?** If nobody does, the plan leans on CC0 low-poly packs plus simple models built in Blender, and the look will be a bit more generic.
3. **Reference images:** a few Deep Rock screenshots you love (which areas, which enemies, which UI), so I can describe the exact feel rather than guess.
4. **Grit level:** clean and colourful, or dirtier and moodier? Deep Rock leans dark and moody; a sunny city arena might want to stay brighter.
5. **Humour in costumes and props:** keep the golden president and other absurd bosses as they are, only re-styled chunky?
