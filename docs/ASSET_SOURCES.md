# Free asset sources

Compiled 2026-10-20 from a game-asset licence guide and, for Pixabay, its own terms page; the other sites' terms were not read first-hand. Licence terms change, so **always confirm the licence on the page of each asset you download**, and record it in `CREDITS.md` (source URL, author, licence, any changes). Items marked *(not re-checked)* come from general knowledge, not from a check made for this list.

## Licence cheat sheet

| Licence | Commercial game OK? | What you must do |
|---|---|---|
| CC0 | Yes | Nothing (credit anyway if you like) |
| CC-BY | Yes | Credit the author, name the licence, link it, note changes |
| CC-BY-NC | **No** if the game is sold, has ads or paid extras | Do not use |
| CC-BY-SA / GPL | Awkward | Share-alike obligations; avoid in a closed game |
| "Royalty-free" (Sonniss, Pixabay...) | Yes, with each site's own terms | Usually no credit; you may not resell or redistribute the raw files |

## Sound effects and ambience

| Source | Licence | Notes |
|---|---|---|
| [Sonniss GameAudioGDC bundle](https://gdc.sonniss.com) | Royalty-free, no attribution | Free yearly bundles from many professional sound vendors, several GB each (the 2026 one is reported at about 7.5 GB). Best quality for free. Terms forbid redistributing the raw files and AI/ML training. Read the licence PDF that ships with the bundle. |
| [Freesound](https://freesound.org) | Per sound: CC0, CC-BY or CC-BY-NC | Huge library. Use the licence filter to hide CC-BY-NC. Free account needed to download. Great for ambience, bikes, phones, footsteps. |
| [Kenney audio](https://kenney.nl/assets/category:Audio) | CC0 | Clean UI, impact and interface sounds. Good for menu sounds. |
| [OpenGameArt](https://opengameart.org) | Per item: CC0, CC-BY, OGA-BY, GPL | Accepts only open licences, but check each item and avoid GPL. |
| [Mixkit](https://mixkit.co/free-sound-effects/) | Mixkit licence, no attribution | Music and effects have separate licences, so read both. |
| [Pixabay sound effects](https://pixabay.com/sound-effects/) | Pixabay Content License | Commercial use allowed, no attribution needed. You may not resell or redistribute files standalone. Its terms prohibit bulk copying/scraping, so download by hand. |
| [ZapSplat](https://www.zapsplat.com) | ZapSplat licence | Free tier requires attribution. |
| BBC Sound Effects | RemArc licence | **Non-commercial only. Do not use for a game you may sell.** |
| [itch.io audio packs](https://itch.io/game-assets/free/tag-audio) | Set per pack | Often CC0; read each pack. |

## Music (for the dynamic music item)

| Source | Licence | Notes |
|---|---|---|
| [Incompetech](https://incompetech.com) (Kevin MacLeod) | CC-BY 4.0 | Credit line required per track; a paid no-attribution licence exists. |
| [Free Music Archive](https://freemusicarchive.org) | Per track | Many tracks are NC or share-alike; filter carefully. |
| [Pixabay music](https://pixabay.com/music/) | Pixabay Content License | As above. |
| [Jamendo](https://www.jamendo.com) | Personal use free; commercial needs a paid licence | Not usable for a commercial game without paying. |
| FreePD *(not re-checked)* | Public domain / CC0 | Public domain music; verify per track. |

Dynamic music works best with **stems or loops that share one tempo and key**. Most free tracks are single mixes, so plan either to pick several tracks in the same key/tempo, or to commission or compose a short loop set.

## Graphics (models, textures) *(not re-checked)*

The art direction is chunky low-poly, so these fit well and can be edited:

| Source | Licence | Use for |
|---|---|---|
| Kenney, Quaternius | CC0 | Low-poly props, vehicles, characters to modify |
| Poly Haven, ambientCG | CC0 | Reference and base textures (paint over them to stay stylised) |
| Sketchfab (filter: downloadable) | Per model, often CC-BY | Check each licence; credit required for CC-BY |
| Mixamo | Free with an Adobe account; check its terms | Humanoid rigging and animation; its terms restrict redistributing the raw animation files |

## Rules for this project
1. One [`CREDITS.md`](../CREDITS.md) entry per third-party file or pack, written when the file is added (the entry template is in that file).
2. Keep the original download (zip or page link) noted, in case a licence needs proving later.
3. Never mix an unclear-licence file into the project "for now".
4. The in-game credits screen (Milestone E) is generated from `CREDITS.md`.
5. Your own voice recordings in `audio/voice/` stay yours; keep a note of who recorded each line.
