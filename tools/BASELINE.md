# Baseline capture and frame-time test

`tools/baseline.gd` records the "before" baseline for Milestone F1: a screenshot of every screen and
lighting theme, and the frame time of every graphics preset in every theme. Run it once per renderer
(Forward+ and Compatibility) on the minimum-spec machine. The two runs also settle the open item
"Compatibility renderer vs Forward+".

It plays by itself, so do not touch the mouse or keyboard while it runs. A full run takes a few
minutes per renderer (18 frame-time rows of 10 seconds each, about 3 minutes, plus the screenshots): 12 rows
are the three presets in the four themes, and 6 are the rain pass (see "The rain pass" below).

## Windows, Godot from Steam (easiest)

1. Close Godot if it is open.
2. Double-click `tools\run_baseline.bat`, or run it from a command prompt in the project folder:

   ```
   tools\run_baseline.bat
   ```

   It looks for Godot in the default Steam folder. If it cannot find it (Steam library on another
   drive, for example), pass the path to the Godot exe as the first argument:

   ```
   tools\run_baseline.bat "D:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.editor.x86_64.console.exe"
   ```

   To find the exe: in Steam, right-click Godot Engine, Manage, Browse local files. Use the file with
   `console` in its name if there is one, because it prints progress in the window.
3. It runs the test twice, first Forward+ and then Compatibility, and writes two folders under
   `baseline_out\` in the project folder.

`godot` is not a command on Windows when Godot comes from Steam, which is why the plain
`godot --path . ...` line fails: Steam does not add Godot to the PATH. The launcher replaces it.

## Any other setup (manual commands)

Replace `godot` with the path to your Godot executable if it is not on the PATH. Run both from the
project folder:

```
godot --path . --rendering-method forward_plus --script res://tools/baseline.gd -- --label=oldpc-forward --requested=forward_plus
godot --path . --rendering-method gl_compatibility --script res://tools/baseline.gd -- --label=oldpc-compat --requested=gl_compatibility
```

Options after `--`:

| Option | Meaning |
|---|---|
| `--label=NAME` | Name of the run, used in the output folder name |
| `--out=DIR` | Output folder (default `baseline_out/<label>_<time>` in the project) |
| `--seed=HEX` | The run seed, which decides the generated arena (default `7F3A91C2`, the PLAZA style). Use the same seed for runs you want to compare |
| `--roundabout` | Measure the old roundabout arena instead of the generated one, to compare with `docs/baseline_f1/` (that baseline is a roundabout baseline) |
| `--seconds=N` | Measurement time per row, default 8 (plus 2 seconds of warm-up) |
| `--requested=NAME` | Renderer you asked for; the report warns if Godot ended up using another one |
| `--no-screens` / `--no-frametime` | Run only one half |
| `--no-rain` | Leave out the rain pass (its two screenshots and its 6 frame-time rows): the run is then exactly as long as before the rain modifier |
| `--raw` | Also write every single frame time to `frames_raw.csv` |

## What you get

One folder per run in `baseline_out/` (ignored by git):

- `report.md`: read this first. Machine info (CPU, GPU, driver, renderer actually used, window size), a
  frame-time table (average fps, 1% low fps, p95 / p99 / max ms, share of frames over 16.7 ms, draw
  calls, GPU ms, video memory), the anti-aliasing state per preset, and a list of screenshots.
- `screens/*.png`: the screenshots.
- `results.json` and `frametime.csv`: the same numbers for spreadsheets.

The report also says whether the save files (settings, scores, meta, high score) were left untouched.
The scripted play keeps the score at 0 and the hearts full, so it should always say `yes`.

## The rain pass (README MD6.2)

Unless `--no-rain` is given, the run also draws the look of the rain modifier (`scripts/rain.gd`: the streaks,
the greyer sky, the wet ground) over DAY and NIGHT, the brightest and the darkest theme, which is what the
README item "Rain modifier: the look" asks a screenshot and a frame time for. No node holds rain yet (its weight
in `data/map_rules.json` is 0 until MD6.5), so the script puts the look on by hand with the same two calls
`start_round` makes for a rain node.

- Screenshots `03_play_4_day_rain.png` and `03_play_5_night_rain.png`, after the four theme shots. What to
  judge: riders, phones, pickups and pedestrians still readable at distance, the sky grey and not black, the
  ground wet but the lane paint and the start frame still clear, the streaks thin and not over the crosshair.
  The streaks stand still in these shots, because the script does not capture the mouse and the game then
  counts as paused; in play they fall.
- Frame-time rows named `DAY + RAIN` and `NIGHT + RAIN` for each preset, after the four dry rows of that preset.
  The cost of rain is the difference to the dry row of the same preset and theme (`DAY`, `NIGHT`); the number
  to compare with `docs/PERFORMANCE_BUDGET.md` is the `+ RAIN` row, and the cap of 400 streaks in
  `scripts/rain.gd` is what to lower if it is too dear.

## What to send back

Zip the two folders in `baseline_out/` and attach them to the conversation, or at least the two
`report.md` files and the `screens/` folders. Then the README items "Record the before baseline" and
"Test the Compatibility renderer against Forward+" can be filled in and checked.

## If something looks wrong

- Report says the renderer asked for is not the one running: the graphics card or driver does not
  support it (Forward+ needs Vulkan). That is a result, keep the report.
- `gpu ms` is 0: the driver does not report GPU time. The other columns are still valid.
- The window opens and closes at once, or nothing is written: run the command from a command prompt
  and send the text it prints.
- Frame times look capped at 60 fps: the script turns vsync off, but a driver setting can force it
  on. Note it in your reply.
