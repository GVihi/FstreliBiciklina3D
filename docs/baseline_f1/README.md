# F1 "before" baseline (2026-10-22)

Raw output of `tools/baseline.gd` (see `tools/BASELINE.md`), run once per renderer with Godot 4.7.2.
`forward_plus/` has every screenshot; `compatibility/` has the report and data plus only the DAY and
preset screenshots, to keep the repo small.

## Machine (owner decision: this counts as the baseline)

Intel Core Ultra 7 155U laptop, Intel integrated graphics, Windows 10.0.26300, window 1280x720 on a
1920x1080 screen. The minimum spec in `docs/ART_DIRECTION.md` is an i5-7500, GTX 1060 3 GB at 1080p, so
these numbers come from a development laptop. The owner has no minimum-spec machine and decided to take this
run as the baseline.

## Frame times (8 s per row, vsync off)

| | Forward+ | Compatibility |
|---|---|---|
| HIGH avg fps (range over themes) | 184 to 196 | 164 to 182 |
| HIGH 1% low fps | 142 to 162 | 37 to 53 |
| HIGH frames over 16.7 ms | 0.0 to 0.1% | 2.6 to 5.9% |
| HIGH worst frame | 10.5 ms (one 16.7 ms spike at NIGHT) | 28.9 to 32.1 ms |
| MEDIUM avg fps | 337 to 368 | 210 to 222 |
| MEDIUM 1% low fps | 238 to 266 | 65 to 70 |
| LOW avg fps | 369 to 401 | 247 to 278 |
| LOW 1% low fps | 209 to 271 | 76 to 88 |
| Video memory (HIGH / MEDIUM / LOW) | 292 / 236 / 221 MB | 116 / 88 / 81 MB |

## What it shows on this machine

- Forward+ stays far under 16.7 ms in every preset and theme; the HIGH preset (2x MSAA) costs about
  twice the frame time of MEDIUM (about 5.2 ms against 2.8 ms).
- Compatibility averages well above 60 fps too, but HIGH has stutter: 1% lows of 37 to 53 fps and up to
  5.9% of frames over budget. MEDIUM and LOW are clean.
- In Compatibility the MEDIUM preset has no anti-aliasing (FXAA is Forward+ only), as the code and
  `docs/ART_DIRECTION.md` already say; the report confirms `screen_space_aa=0`.
- Compatibility uses far less video memory (3 GB is a limit on the minimum-spec card).

## Notes

- Save files were untouched by both runs.
- In the `04_play_day_preset_*` and `03_play_*` screenshots the HUD round label shows the wrong theme name
  (NIGHT or GOLDEN HOUR on a DAY scene). Cause: the script called `apply_theme` without setting
  `theme_idx`, which the HUD label reads; the game sets both in `start_round`. Fixed in `tools/baseline.gd`
  (`_set_theme`); the frame times are practically unaffected (only the bird sound reads `theme_idx`), and the screenshots in this folder still show the old
  label until the baseline is run again.
