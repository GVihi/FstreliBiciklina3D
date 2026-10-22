# Baseline report: oldpc-forward

## This machine

- **label**: oldpc-forward
- **date**: 2026-10-22T12:56:41
- **godot**: 4.7.2-stable (steam)
- **os**: Windows 10.0.26300
- **cpu**: Intel(R) Core(TM) Ultra 7 155U
- **cpu_threads**: 14
- **gpu**: Intel(R) Graphics
- **gpu_vendor**: Intel
- **gpu_api**: 1.4.348
- **renderer_requested**: forward_plus
- **renderer_actual**: forward_plus
- **driver**: vulkan
- **window_size**: 1280x720
- **screen_size**: 1920x1080
- **has_rendering_device**: true

Save files (settings, scores, meta, high score) untouched by this run: **yes**

## Frame times

8 seconds measured per row after 2 seconds warm-up, vsync off, view turning and gun firing. Budget for 60 fps is 16.67 ms per frame.

| Preset | Theme | avg fps | 1% low fps | avg ms | p95 ms | p99 ms | max ms | frames over 16.7 ms | draw calls | gpu ms | video MB |
|---|---|---|---|---|---|---|---|---|---|---|---|
| HIGH | DAY | 184 | 142 | 5.43 | 6.27 | 7.06 | 10.2 | 0.0% | 193 | 4.16 | 292 |
| HIGH | GOLDEN HOUR | 192 | 158 | 5.20 | 6.01 | 6.32 | 9.3 | 0.0% | 201 | 3.94 | 292 |
| HIGH | DUSK | 190 | 149 | 5.26 | 6.33 | 6.72 | 10.5 | 0.0% | 215 | 3.96 | 292 |
| HIGH | NIGHT | 196 | 162 | 5.09 | 5.89 | 6.17 | 16.7 | 0.1% | 165 | 3.82 | 292 |
| MEDIUM | DAY | 337 | 238 | 2.96 | 3.68 | 4.21 | 9.8 | 0.0% | 143 | 2.30 | 236 |
| MEDIUM | GOLDEN HOUR | 368 | 266 | 2.72 | 3.38 | 3.76 | 9.2 | 0.0% | 137 | 2.05 | 236 |
| MEDIUM | DUSK | 367 | 255 | 2.72 | 3.42 | 3.93 | 8.5 | 0.0% | 128 | 2.06 | 236 |
| MEDIUM | NIGHT | 358 | 246 | 2.80 | 3.54 | 4.06 | 8.8 | 0.0% | 122 | 2.13 | 236 |
| LOW | DAY | 378 | 209 | 2.65 | 3.63 | 4.80 | 11.2 | 0.0% | 153 | 2.02 | 221 |
| LOW | GOLDEN HOUR | 386 | 240 | 2.59 | 3.49 | 4.16 | 8.3 | 0.0% | 153 | 1.93 | 221 |
| LOW | DUSK | 369 | 229 | 2.71 | 3.74 | 4.36 | 11.3 | 0.0% | 144 | 2.07 | 221 |
| LOW | NIGHT | 401 | 271 | 2.49 | 3.20 | 3.69 | 9.1 | 0.0% | 137 | 1.85 | 221 |

`gpu ms` is 0 when the renderer or driver does not report GPU time.

## Anti-aliasing state per preset

- preset HIGH: msaa_3d=1 screen_space_aa=0
- preset MEDIUM: msaa_3d=0 screen_space_aa=1
- preset LOW: msaa_3d=0 screen_space_aa=0

## Screenshots (folder `screens/`)

- 01_title_menu.png
- 02_title_loadout.png
- 02_title_unlocks.png
- 02_title_scores.png
- 02_title_settings.png
- 03_play_0_day.png
- 03_play_1_golden_hour.png
- 03_play_2_dusk.png
- 03_play_3_night.png
- 04_play_day_preset_0_high.png
- 04_play_day_preset_1_medium.png
- 04_play_day_preset_2_low.png
- 05_pause_menu.png
- 05_pause_settings.png
- 05_pause_confirm.png
- 06_round_clear.png
- 07_upgrade.png
- 08_shop.png
- 09_run_over_riders.png
- 09_run_over_victory.png
