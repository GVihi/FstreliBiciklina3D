# FstreliBiciklina3D
Mostly vibe coded Godot game

## Note to self: keep AI sessions cheap
- **Every step re-reads the whole conversation**, so cost grows with each tool call. Fewer, bigger steps beat many small ones.
- **Combine checks into one command** (for example the self-test, the scan and `git status` together) instead of one call each.
- **Show only the lines that matter** (`grep -n`, `sed -n 10,30p`, `| head`, `--stat`). Do not print whole files, the whole roadmap or whole workflow files into the conversation.
- **Commit before any risky test.** Never `git reset --hard` or `git checkout .` with uncommitted work in the tree; test breaks on a copy or a throw-away branch. Redoing lost edits doubles the cost.
- **Run checks once, at the end**, not after every small edit. Run only the checks that cover the touched code (see the testing rule below).
- **Keep notes short.** A `docs/ROADMAP_HISTORY.md` entry and a commit body need what was built, decisions, what was checked and what is not covered, in a few lines each, not pages.
- **One roadmap item per session.** Start a fresh session for the next item; a long thread makes every later step more expensive.

## Testing rule
- **One command runs every check: `python tools/run_checks.py`** (on Windows, double click `tools\run_checks.bat`). It finds Godot by itself and remembers the path after the first time, so there is no path to type. It runs every `tools/*_check.gd`, each with its own empty save folder (your real settings, scores, meta coins and saved run are never touched), prints PASSED or FAILED for each one with the lines that explain a failure, kills a check that hangs, and writes `check_logs/summary.txt` and one log per check (send `summary.txt` back when something fails). `python tools/run_checks.py unlocks xp` runs only the checks whose name contains those words, `--list` lists them, `--full` uses the bigger seed and arena counts of the slow ones, `--lint` also runs gdlint and gdformat, `--godot PATH` sets the Godot path, `--help` shows the rest. Exit code 0 = everything passed.
- **While building an item, run only the checks that cover the code it touched** (for example `python tools/run_checks.py pickup rider`), not the whole suite, which takes about 14 minutes. The whole suite is for the gate items (B7.3 and E3.1 in `docs/ALPHA_ROADMAP.md`, V10.1 in the Web Integration Roadmap) and for when the owner asks for it. Decided with the owner on 2026-10-27.
- A new check is a file `tools/<name>_check.gd` that prints its problems and ends with `quit(0)` or `quit(1)`. The runner finds it by its name, so nothing else needs editing, and **a `.bat` is no longer needed**: this replaces the old rule that every check gets its own `.bat` next to it. The old `tools\run_*_check.bat` files still work and can be deleted later (item A2.7 in `docs/ALPHA_ROADMAP.md`); notes below that name one are talking about the same check.
- Many item notes below say "written in a session without Godot, only gdformat and gdlint were run, so run the .bat once". On 2026-10-27 the whole suite was run headless with Godot 4.7 (results under "Roadmap audit" in `docs/ALPHA_ROADMAP.md`): 41 of the 44 checks passed and the other three are listed there with their causes. What those items still wait for is the **in-game check** by a person, which no script can do.

## Roadmap history
- The long notes written after ticked roadmap items (what was built, decisions, checks run, what still waits for an in-game check) are in [`docs/ROADMAP_HISTORY.md`](docs/ROADMAP_HISTORY.md), grouped under the same milestone and section headings as here. A ticked item below keeps only its title.
- **Rule for new notes:** when an item is ticked, write its note (what was built, decisions, checks run, what still waits for an in-game check) in `docs/ROADMAP_HISTORY.md`, under the same milestone and section heading, with the item title as the entry heading. The README line keeps only the checkbox and the title, so the README stays short. Notes on open items that are still being worked on can stay in the README until the item is ticked.
- **Finished work moves out of this file.** A whole roadmap or milestone with no open box, a section with no open box, and every ticked item without an open box inside it go to docs (a heading stays, with a pointer, where a milestone lost something), so references like "Milestone G" or "alpha D1" still find them: [`docs/ALPHA_ROADMAP.md`](docs/ALPHA_ROADMAP.md) (the early alpha, 0.2.0) and [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) (finished milestones).

## Running and developing
- How to run the game from the Godot editor (fullscreen, the embedded game view) and the developer start options (`--dev-coins`, `--dev-unlocks`, nothing saved in such a session) are in [`docs/DEVELOPING.md`](docs/DEVELOPING.md). Save file rules: [`docs/SAVE_FILES.md`](docs/SAVE_FILES.md). Check for the start options: `python tools/run_checks.py dev_start`.

## Secrets and credentials (this repository is public)
> **WARNING: never commit or push secrets.** Everything in this repository, including every old commit, is visible to the whole internet, and deleting a secret in a later commit does not remove it from the history. Once a key has been pushed, treat it as stolen and replace it.
- Never commit: API keys (including the game-to-website key from Milestone N), passwords, login or refresh tokens, Django `SECRET_KEY`, database or server credentials, SSH keys, `.env` files, code signing certificates, Godot encryption keys (`script_encryption_key` and the save encryption key), or a player's save and settings files.
- Keep secrets outside the repository: in environment variables or an untracked local file (for example `secrets.local.cfg` or `.env`, listed in `.gitignore` before the file is created), and in GitHub Actions secrets for CI. The repository only holds a template with fake values (for example `secrets.example.cfg`).
- Real values for development: copy `secrets.example.cfg` (fake values only) to `secrets.local.cfg` in the project folder (git-ignored), or set the environment variables it names (`FB3D_API_BASE_URL`, `FB3D_API_KEY`). `scripts/secrets.gd` reads them, only when the game runs from the Godot editor binary, and never prints a value. With neither, the game starts and plays offline as before. Check: `python tools/run_checks.py secrets_loader`.
- Check before every commit: run `git status` and `git diff --staged` and read what is going in. If a key was pushed by mistake, tell the owner right away, replace the key first (the old one is burned), and only then clean the history. Where each key lives and the full steps: [`docs/SECRETS.md`](docs/SECRETS.md).
- **Install the automatic check once in every clone: `python tools/secrets_check.py --install-hook`.** It makes `git commit` run `tools/secrets_check.py` on the staged changes and stop on anything key-like (a private key, `api_key="..."`, `password=`, `SECRET_KEY`, well-known token formats, a password in a URL, a long random string, or a staged `.env` / `*.pem` file). It prints the file and line number and never the value; a deliberate fake (a test) carries `secrets-check: ignore` in a comment. `python tools/secrets_check.py --self-test` proves the scanner on made-up secrets. It can be skipped (`--no-verify`), so it is one layer: GitHub push protection (V1.3) and the CI scan (V1.5, `python tools/secrets_check.py --range BASE..HEAD`) are the others.
- Godot warning: `export_presets.cfg` is tracked. If PCK encryption is ever switched on, its key is written into that file, so keep the key out of the tracked file (set it with the `GODOT_SCRIPT_ENCRYPTION_KEY` environment variable at export time, and leave the key field empty in the repository).
- The same rule applies to anyone working on this repository, including AI coding sessions: do not paste real keys into prompts, code, commit messages, docs or screenshots.
- The plan for automatic checks (secret scanning, push protection, a pre-commit hook and a CI check) is in "Keeping secrets out of the public repository" in Milestone N, and is built first, as V1 of the Web Integration Roadmap (v0.3.0).

## Big Design Choice

> Finished sections and ticked items of this section moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-11-04, under "Big Design Choice" > "Recommended Roguelite Structure". Nothing is open here.

---

# Milestone A: Menu, Game Flow, Saves & High Scores

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone A: Menu, Game Flow, Saves & High Scores". Only what is still open stays here.

## High Scores

- [ ] Support separate leaderboards per difficulty (needs a difficulty system first: build it together with Heat in Milestone B, then split the boards by Heat level)

### Daily Seed Mode

- [ ] Make the Daily Run feel different from a normal run
  - [ ] One shared daily modifier for everybody that day (chosen from the seed, shown on the title screen and in the run bar), such as double riders, rain or fast riders
  - [ ] Shareable result card: the date, seed, score, time, rounds and caches, as an image or text the player can copy

### Deferred

- [ ] Online leaderboard (future feature; the website, the login and the API it needs are planned in Milestone N)
  - [ ] Submit scores to Django web leaderboard
    - [ ] Implement REST API on Django web service
    - [ ] Implement Seed and leaderboard display

---

# Milestone B: Meta Currency, Unlocks & Skins

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone B: Meta Currency, Unlocks & Skins". Only what is still open stays here.

## Difficulty Scaling

> **Heat, broken into chunks (2026-11-04).** Heat is a number the player picks before a run; Heat 0 is the game as it is today, and every step above it makes the run harder and pays more. Nothing about Heat exists in the code yet. **Order of work:** the three items below in order, and inside an item top to bottom, one chunk per session and one branch per chunk. Assumed, to tune or change by saying so: (1) a Heat level is a fixed ladder first (H1 to H5, each level adds one effect on top of the last) and becomes a set of switchable modifiers in the second item; (2) **the map, the arena and the rider mix stay exactly the same for a seed at every Heat**, so Heat is applied when a round is played (`plan_riders`, `riders.gd`, the shop, `Meta.award_run`), never in `map_gen.gd` or `map_content.gd`; (3) the Daily Run is always Heat 0 and a custom-seed run may use Heat but stays unranked, as today (`Main.ranked_run`); (4) every chunk has a check, and **a Heat 0 run must give the same numbers as before Heat** (that check is the safety net for the whole section).

- [ ] Implement Heat system
  - [x] H1.1 Design note, no code (`docs/HEAT.md`)
  - [x] H1.2 The table and the level (`data/heat.json`, `scripts/heat.gd`, `Main.heat`, `tools/heat_check.gd`)
  - [x] H1.3 Save it (`heat` in `run.json` and in `settings.cfg`, `docs/SAVE_FILES.md`)
  - [x] H1.4 Choose the level before a run: a HEAT entry in the menu after clicking PLAY (`scripts/hud.gd`, `scripts/input.gd`; keyboard and gamepad), with what the level adds written under it. All levels open for now (levels will later become available after reaching XP levels in steps of 5); not offered for the Daily Run (fixed 0); a RESTART RUN keeps the level
  - [x] H1.5 Effect: faster riders. The rider speed growth in `riders.gd` (`diff`) gets a Heat factor, still capped by `RIDER_SPEED_CAP`
  - [x] H1.6 Effect: more riders. A node's rider count (`plan_riders`) goes up by a share per level, taken from the mix in the same proportions, so the seed's mix does not change
  - [x] H1.7 Effect: fewer hearts (2 instead of 3 from H3, see `docs/HEAT.md`). Heart drops, PATCH UP and the heart on a round clear stay as they are (decided in H1.1)
  - [x] H1.8 Effect: tougher riders and bosses (rider health in `riders.gd`, boss health in `bosses.gd`; a boss weak spot is still one hit of the right kind)
  - [x] H1.9 Effect: a tighter economy (shop prices and cash from drops in `shop.gd` and `pickups.gd`). `shop_price` gets the `price` factor (x1.2 at H5, before HAGGLER) and `add_cash`, the one place every cash source goes through, the `cash` factor (x0.8 at H5, before BOUNTY, never below the `cash_min` cap); the reroll cost is not a shop price and stays as it is
  - [x] H1.10 Show it: the Heat level in the run bar and pause menu, on the run summary, and in the run record (the `scores.json` entry gets a `heat` field, an old entry reads as 0); the split boards stay the Milestone A item "Support separate leaderboards per difficulty"
  - [x] H1.11 Unlock the ladder: the next level opens when a run is won at the highest open level (kept in `meta.json`, an old file reads as only H0 open and the heat check says so), with the title screen showing the locked levels
  - [ ] H1.12 Playtest and tune with the bot balance harness (Milestone A) at H0, H3 and H5: run length, lives lost and clear rate per level
- [ ] Allow multiple Heat modifiers
  - [x] H2.1 Design note in `docs/HEAT.md`: the effects of H1.5 to H1.9 become separate modifiers with ranks (for example SWIFT RIDERS 0 to 3), each rank worth some Heat points, and the Heat of a run is the sum; list the modifiers, their ranks and points, which pairs clash, and the top total
  - [x] H2.2 Data and code: `data/heat.json` becomes modifiers with ranks and points; `Heat` computes the total from a set of ranks; the old ladder is kept as presets (H1 to H5 each name a set), so the H1 checks still pass. Check: the total of every preset equals the Heat it names
  - [x] H2.3 Stacking rules: caps on the sum of each effect (rider speed, rider count, hearts never below one), clashing pairs refused, and a top total; check that the all-ranks-maxed set still starts a round and every rider speed stays under `RIDER_SPEED_CAP`
  - [x] H2.4 Choose modifiers: a page opened from the title screen's HEAT entry with one line per modifier (rank up and down, the Heat points of each rank and the total at the top), a PRESET row, and RESET; keyboard and gamepad, and written out for a player who cannot see colours (note in `docs/ROADMAP_HISTORY.md`; written in a session without Godot, only gdformat and gdlint were run, so run `python tools/run_checks.py heat` once; waits for an in-game look by the owner)
  - [x] H2.5 Save the chosen set in the run save and `settings.cfg` (old files with only a level read as the preset of that level), and show the active modifiers, not only the number, on the run bar, pause menu and run summary (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game look by the owner)
  - [ ] H2.6 Check and playtest: every modifier alone and the maxed set through the scripted run (`tools/generated_run_check.gd`), then a balance pass with the harness
- [ ] Increase rewards for higher Heat levels
  - [x] H3.1 Decide the formula in `docs/HEAT.md`: a coin and XP bonus per Heat point (first guess: +10 % per point, rounded, never less than +1 coin at Heat 1 or more), whether the score itself is multiplied (first guess: no, so the boards of different Heat stay comparable once they are split), and that the bonus applies to coins from rounds, bosses and caches
  - [x] H3.2 Pay it: `Meta.award_run` and `XpScript.run_xp` apply the bonus (`SCORE_COINS_MAX` still caps the score part); a Heat 0 run pays exactly as before. Check `tools/heat_check.gd`: Heat 0 unchanged, a higher Heat pays more, a quit run still pays nothing
  - [x] H3.3 Show it: the title screen's HEAT entry says what the level pays, and the run summary has a line with the bonus
  - [x] H3.4 Heat rewards beyond coins: unlocks or challenges that need a Heat level (an entry in `data/unlocks.json` and `data/challenges.json`, for example "win a run at Heat 3"), first guess one of each (the owner asked for the framework only on the unlock side: the optional `heat` key exists and nothing uses it yet; three Heat challenges, win at Heat 1, 3 and 5; note in `docs/ROADMAP_HISTORY.md`; checked with Godot 4.7.2, `python tools/run_checks.py unlocks unlocks_buy challenges heat`; the CHALLENGES page with 8 rows was rendered at 1280x720 and looked at; waits for an in-game look by the owner)
  - [ ] H3.5 Tune the numbers once the harness runs (the same pass as H1.12), so a higher Heat is worth it without making Heat 0 feel like a waste

---

# Milestone C: Weapon System Expansion

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone C: Weapon System Expansion". Only what is still open stays here.

## New Weapons

### Dart Nerf Pistol

> A small, single-dart nerf pistol: one dart per trigger pull, no pump, light and quick. It is meant to **replace the dart gun as the starting primary weapon** (the starting weapon is switched last, once the pistol is built and its upgrades work, so the game stays playable meanwhile). Assumed: it is a primary weapon (`PRIMARY_WEAPONS` in `scripts/weapon_slots.gd`) with its tuning in `data/weapons.json`, the dart gun stays in the game as a primary weapon that can be unlocked later (say if it should go instead), and all numbers below are first guesses to tune by playing.

- [ ] Create upgrade path (five tiers, bought in the run like the other upgrade tiers of `data/items.json`, each one stronger and dearer than the last; the pistol's tuning numbers grow with the tier):
  - [ ] Tier 1, Spare Darts: bigger clip
  - [ ] Tier 2, Quick Loader: shorter reload
  - [ ] Tier 3, Steady Grip: less spread and less bloom while shooting
  - [ ] Tier 4, Hair Trigger: faster fire rate
  - [ ] Tier 5, Hard-Tip Darts: more damage per dart (the last tier, so it pays off after the others)

### Suction-Dart Crossbow

- [ ] Implement weapon
- [ ] Add piercing mechanic
- [ ] Create upgrade path

### Confetti Cannon

- [ ] Implement weapon
- [ ] Add area damage mechanic
- [ ] Create upgrade path

### Stink Bomb

- [ ] Implement weapon
- [ ] Make riders swerve
- [ ] Create upgrade path

### Phone Launcher

- [ ] Implement weapon
- [ ] Create upgrade path

### Scoped Sniper Rifle

> A single-shot, long-range dart rifle with a zoom scope, for the player who wants to pick riders off across the 144 m arena instead of fighting in the street. A primary weapon, tier 4 (450 coins) as a first guess. It is slow and wants a steady aim, so it is strong at range and weak up close; the pistol and the dart gun stay the answer to a rider on top of you.

- [ ] Implement weapon: one dart per shot, a bolt-action pause after every shot (blocks the next shot, longer than the pistol's), a clip of 3 and a slow reload; damage high enough that one hit removes a normal rider, while armoured riders and bosses take it as a big hit and not an instant kill (check against the rider health in `data/`)
- [ ] Add the scope: hold the aim button to zoom (narrower field of view, a scope overlay with a crosshair, slower look speed so it stays controllable); leaving the scope is instant when the player is hit or switches weapon, and the overlay never covers the hearts or the ammo
- [ ] Add scope sway and a steady breath: the crosshair drifts slowly while zoomed, standing still or crouching shrinks it, moving makes it worse, and a short HOLD BREATH (own key and gamepad button, limited, recovers by itself) freezes it for a moment; the sway and any camera kick follow the SHAKE AND FLASH setting (`fx_scale`)
- [ ] Hip fire is deliberately bad (wide spread), so the scope is how the weapon is meant to be used; range well above the dart gun's 80 m (first guess 150 m, enough to cross the arena)
- [ ] Decide what a weak spot hit does with the rifle (weak spots already exist: DEADEYE gives +1 damage on one), since aiming through a scope is where a player will go for them; and note that the duo perk SNIPER (LAST SHELL plus DEADEYE, `data/perks.json`) already has that name, so the weapon is called the Scoped Sniper Rifle in the game's text and the duo keeps its name
- [ ] Make shots readable at a distance: a thin tracer or dart trail, a clear hit marker, and riders far away stay visible against each of the six arena styles
- [ ] `tools/sniper_check.gd`: the bolt pause, the zoom state, the sway (smaller when still, smaller while holding the breath), the range, and that leaving the scope on a hit or a weapon switch works
- [ ] Create upgrade path (five tiers, bought in the run like the pistol's):
  - [ ] Tier 1, Spare Darts: bigger clip
  - [ ] Tier 2, Smooth Bolt: shorter bolt pause and reload
  - [ ] Tier 3, Steady Scope: less sway and a longer held breath
  - [ ] Tier 4, Second Zoom: a second zoom level (mouse wheel while zoomed)
  - [ ] Tier 5, Sticky Tip: a rider hit by the rifle is marked for a few seconds and takes extra damage from every other weapon

### Marshmallow Blaster

> A short-range scatter gun: a cone of soft marshmallows that is brutal up close and useless at 30 m. A primary weapon, tier 3 (250 coins).

- [x] Implement weapon (note in `docs/ROADMAP_HISTORY.md`)
- [ ] Add falloff: full damage inside a few metres, close to nothing at the end of the range, so the weapon rewards getting close
- [ ] Add knockback: a close hit shoves the rider back and sideways, breaking its approach line (a rider that is pushed does not throw its phone that moment)
- [ ] Create upgrade path (five tiers: clip, reload, spread, knockback, damage)

### Super Soaker

> A water blaster that fires a continuous stream. A primary weapon, tier 4 (450 coins). Its quirk is a tank instead of a clip and the puddles it leaves.

- [ ] Implement weapon: the stream fires while the button is held and drains a tank, the tank refills slowly while not firing, damage is small per tick and adds up
- [ ] Decide what ammo means for a tank (the same question as B9.2): for example an ammo drop and the cache ammo reward refill a share of the tank, and write it in the table of `data/README.md`
- [ ] Add puddles: ground the stream lands on gets wet for a few seconds, and a rider that rides through slows down (and a slow rider is an easier target)
- [ ] Create upgrade path (five tiers: tank size, refill speed, range, puddle size and time, damage)

### Rubber Band Repeater

> A fast automatic gun that fires rubber bands: low damage per band, a big clip, wild bloom. A primary weapon, tier 3 (250 coins). Its quirk is that a band bounces once.

- [ ] Implement weapon: automatic fire (hold to shoot), a clip of 30, a short reload, heavy bloom that grows while the button is held and settles when released
- [ ] Add the bounce: a band that hits a wall or building bounces once and can still hit a rider, so corners can be shot around; use the same wall test as the other shots. Call it "bounce" in the game's text, because the duo perk RICOCHET (COUNTER plus BOOMERANG, deflected phones chain on) already owns that name
- [ ] Create upgrade path (five tiers: clip, reload, bloom, number of bounces, damage)

### Slingshot

> A hand slingshot with a draw: hold to pull back, release to fire. A primary weapon, tier 2 (120 coins), the cheapest new one. Its quirk is that how long you hold decides the shot.

- [ ] Implement weapon: the draw takes about a second, a tap fires a weak, slow, short shot and a full draw a fast, hard, long one; one shot at a time, and a very short reload (picking the next stone)
- [ ] Add the draw feedback: the band stretches on the weapon model, the camera narrows slightly (follows `fx_scale`), and a full draw is clearly marked (sound and a small pulse) so the player knows when to let go
- [ ] Create upgrade path (five tiers: draw speed, full-draw damage, range, a second stone on a full draw, a wobble-free hold)

## New Melee Weapons

> The gummy worm (`melee` in `data/weapons.json`: 0.3 s cooldown, damage 2, it deflects phones) is the baseline; it is bought on the Unlocks page for 30 coins (`weapon_gummy_worm`) and is no longer owned from the start. Each variant below has **one quirk that makes it play differently, not just a bigger number**. They sit in the melee slot (`MELEE_WEAPONS`, read through `melee_stats()`), are bought on the Unlocks page (tiers 1 to 3 as a first guess) and chosen on the Loadout page; the melee slot starts empty until a melee weapon is bought (see "Melee weapon is locked at the start"). Q, wheel, 1 and 2 switch between the primary and the melee weapon, and do nothing while the slot is empty. The Melee Reach upgrade (`reach_per_level`) applies to every variant, and every variant still deflects phones (a quirk may make it do that better or worse, never not at all).

- [x] Audit the melee code for what is tied to the gummy worm (the swing, the HUD name, the deflect, Melee Reach, the `round_no_gun` rule) and make it read `melee_stats()` everywhere, so the first variant does not need special cases (note in `docs/ROADMAP_HISTORY.md`)
- [x] **Pool Noodle** (tier 1, 60 coins), quirk **reach and sweep**: the longest reach and a wide arc, so one swing can hit several riders; damage 1, so it needs a few hits, and the longest deflect range of all
  - [x] Implement weapon, and the sweep (every rider inside the arc is hit once per swing) (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game check by the owner, and the floor ring does not show the arc yet)
  - [x] Animate the noodle so it is not stiff: a slight wobble when running and when hitting with it (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game check by the owner, the size of the wobble is a first guess)
- [ ] **Squeaky Hammer** (tier 2, 120 coins), quirk **slow slam and stun**: a slow wind-up and a heavy overhead hit, big damage and a short stun on every rider in a small ring around the impact; nothing is deflected during the wind-up, which is the price
  - [ ] Implement weapon, the wind-up and the stun ring
- [ ] **Fly Swatter** (tier 2, 120 coins), quirk **speed and combo**: a very fast swat (first guess 0.15 s cooldown) with damage 1; swats in a row inside a short window build a combo and the third is a big finisher, a miss resets it; the widest deflect cone, good at swatting phones out of the air
  - [ ] Implement weapon and the combo counter (shown in the HUD slot display)
- [ ] **Spring Glove** (tier 3, 250 coins), quirk **lunge**: a boxing glove on a spring that shoots the player forward about 4 m on a swing (a gap closer), with a long cooldown and the player exposed afterwards; the lunge never carries the player through a wall or off the arena
  - [ ] Implement weapon and the lunge (ground test as for the player's walking)
- [ ] **Tennis Racket** (tier 3, 250 coins), quirk **timed return**: a deflect inside a tight window sends the phone back at the rider that threw it, fast, and removes that rider; an early or late swing deflects normally; the hit itself is weak
  - [ ] Implement weapon and the timing window (first guess a tenth of a second, tuned by playing; shown by a short flash)
- [ ] `tools/melee_variants_check.gd`: every variant is in `MELEE_WEAPONS`, loads from `data/weapons.json`, deflects, respects Melee Reach, and its quirk happens (the sweep, the stun, the combo, the lunge, the return)

## New Gadgets

> Gadgets go in the gadget slot (`GADGET_WEAPONS`, read through `gadget_stats()`), which is empty until a gadget is bought and chosen on the Loadout page (the first one, the Banana Peel Trap, is built; the Stink Bomb above is still open). A gadget is used on the spot with its own key and gamepad button (the "Gadget use key" item above, built together with the first one) and has a **cooldown or a number of uses per round**, shown in the HUD slot display. The Stink Bomb above is the first gadget; these are more. Rules for all of them: a gadget never harms or affects a pedestrian or a cheerleader (a civilian hit loses the run), and no gadget effect is a chance roll, so the same seed plays the same in the Daily Run. Tiers 1 to 4 as a first guess; each gets a five-tier upgrade path later (uses, cooldown, area, duration).

- [x] **Banana Peel Trap** (tier 1; 75 coins in `data/unlocks.json`, the same as the Pool Noodle, which the price curve of tier 1 uses) (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game check by the owner)
- [ ] **Whoopee Decoy** (tier 2, 120 coins): a loud toy thrown to a spot; riders steer towards it for about 4 seconds (the opposite of the Stink Bomb, which pushes them away), cooldown about 20 s; good for pulling riders into a trap or a clear line of fire
- [ ] **Glitter Bomb** (tier 2, 120 coins): thrown; the cloud dazzles riders inside it, so for about 5 seconds they throw their phones wide
- [ ] **Roller Skates** (tier 3, 250 coins): a burst of speed and a long slide for about 3 seconds, cooldown about 15 s; no jumping, since jumping is Milestone L
- [ ] **Pool Float Shield** (tier 4, 450 coins): hold to raise an inflatable ring in front; it blocks phones from the front but the player moves slower and cannot shoot while it is up, and it deflates after a few hits and has to recover
- [ ] `tools/gadgets_check.gd`: every gadget is in `GADGET_WEAPONS`, uses or cooldown are counted and shown, a pedestrian is never affected, and the same seed gives the same result twice

## Synergies

- [ ] Create perk interactions
- [ ] Create duo synergies with existing perk system
- [ ] Decide which existing perks and duos work with the new weapons and gadgets (for example STEADY HANDS with the sniper's scope sway, DEADEYE with the sniper rifle's weak spot hits, the duo RICOCHET with the Tennis Racket's timed return, SLIDE SHOT with the Marshmallow Blaster, SPRINTER with the Roller Skates). Every perk and duo already says what it needs to matter (`needs`, B9.7), so say what each one needs for the new weapons, and check `offer_sense` still passes

---

# Milestone D: Run Map, Relics & Modifiers

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone D: Run Map, Relics & Modifiers". Only what is still open stays here.

> **Broken into chunks (2026-11-07).** Every open item below is split into steps with ids MD1 to MD7 (to tell them from the alpha ids D1 to D3 in `docs/ALPHA_ROADMAP.md`). One chunk per session and one branch per chunk, top to bottom inside an item. **Suggested order of work:** Round Modifiers first (MD5 night, MD6 rain, MD7 more modifiers: small, no new screens), then Relics (MD2, MD3), then Curses (MD4: a curse is a relic with a price), and Event (MD1) last, because its choices hand out relics, curses, coins and hearts. The items stay in the order of the file; the ids say which belongs to which. Assumed, to tune or change by saying so: (1) everything a run draws here (relic offers, curses, the event of a node) comes from its own stream of the run seed (`DailyScript.stream_seed`), so a seed gives the same offers every time and no stream of the map, the arena or the riders moves; (2) the Daily Run gets all of it, and stays Heat 0; (3) what a run holds (relics, curses) is saved in `run.json` (`docs/SAVE_FILES.md`), an old file reads as holding none; (4) every chunk has a check (`tools/<name>_check.gd`, picked up by `python tools/run_checks.py`), and **a run with no relic, no curse, no event and no new modifier must give the same numbers as before** (that check is the safety net for the whole milestone); (5) tables go in `data/*.json` like `data/perks.json`, with the format in `data/README.md`, so adding one later is an edit of a file.

## Run Structure

### Map Nodes

- [ ] Event (left out of the alpha, event weight set to 0 in alpha B5)
  - [ ] MD1.1 Design note, no code (`docs/EVENTS.md`): an event node is a screen like the shop and the rest node (`SCREEN_NODES` in `main.gd`, no arena, no riders), with a short text and 2 to 3 choices that each show their cost and reward in plain words; the first list of about 6 events, one line each (a trade, a gamble, a free pick with a catch); which rewards exist before relics and curses do (cash, a heart, ammo) and which wait for MD2 and MD4; whether a choice can be refused (assumed: a LEAVE button always exists)
  - [ ] MD1.2 The table: `data/events.json` (format in `data/README.md`), `scripts/events.gd` loads and cleans it the way `heat.gd` does (a bad entry is dropped with a message); `tools/events_check.gd` reads the shipped file and a made-up bad one (no choice, unknown effect, a cost nobody can pay)
  - [ ] MD1.3 Pick the event of a node: from the node's own `seed` (already in its content, see `docs/MAP_GENERATION.md`), the floor and what the run holds, so the same node shows the same event every time and a node never offers a choice the player cannot make; check over many seeds: the same event twice, no event twice on one map where the table has enough
  - [ ] MD1.4 The screen: a new state "event" entered by `pick_node` next to `enter_shop` and `enter_rest`, drawn in `hud.gd`, keyboard, gamepad and mouse like the rest node (note: written in a session without Godot means one in-game look by the owner); check in the style of `tools/rest_node_check.gd`, and the screen rendered at 1280x720 and looked at
  - [ ] MD1.5 The effects: a choice changes cash, hearts or ammo in one function (`events.gd`), never in the screen code; effects that need relics or curses are listed in the table but refused until MD2 and MD4 exist; check: every effect of the file changes exactly what it says and nothing else
  - [ ] MD1.6 Leave the node: the event ends on the map screen, whose checkpoint is what a saved run continues from (same as the rest node); check with `tools/run_save_check.gd` that CONTINUE after an event node gives the run back
  - [ ] MD1.7 Turn it on: the `event` weight in `data/map_rules.json` goes from 0 to a first guess of 10 (its `min_floor` 2 and `max_per_map` 3 stay), `docs/MAP_GENERATION.md` and the numbers in `tools/map_check.gd` follow; extend `tools/node_types_run_check.gd` so a run through an event node still continues; `docs/ALPHA_NOTES.md` stops saying event nodes are off
  - [ ] MD1.8 Playtest: a whole run with the bot harness (it leaves an event with the LEAVE button) at the new weight, and the in-game look at the `?` node on the map screen

## Relics

- [ ] Implement relic system
  - [ ] MD2.1 Design note, no code (`docs/RELICS.md`): what a relic is next to a perk (`data/perks.json`, chosen before a run) and an upgrade (`Content.UPGRADES`, picked after a round): assumed a relic lasts the whole run, is found and not bought, and has a rarity; where they come from (first guess: a pick after an elite node and after a boss, later events and the shop); how many can be held (assumed no limit at first); that no relic is offered twice in a run; the effects a relic may have in this item (numbers only, the rule changers are MD3); the questions for the owner at the end
  - [ ] MD2.2 The table and the holder: `data/relics.json` (id, name, one line of text, rarity, effects), `scripts/relics.gd` loads it, `Main.relics` holds the ids of the run (cleared in `reset_run`), `has_relic(id)`; this is also the item "Make relic additions easier" under "Technical Refactor, Future-Proofing" at the end of this file (tick both); `tools/relics_check.gd` reads the shipped file and a made-up bad one
  - [ ] MD2.3 One lookup for numbers: `Relics.factor(key)` returns the product of the relics that change that key and 1.0 with none, the way `Heat.value` does, so each effect is applied where it plays out and nowhere else; check: with no relic every key is neutral
  - [ ] MD2.4 The offers: 3 relics drawn with `offer_shuffle` (depends only on the run seed, the round and a part name, here "relic"), never one the run holds, never past the table; check: the same seed gives the same three, the Daily Run gives everybody the same three
  - [ ] MD2.5 The pick: a relic screen after an elite node and after a boss, reusing the upgrade screen (`state = "upgrade"` with `upgrade_part = "relic"`, the way an elite's second pick works), with keyboard, gamepad and mouse; check: a pick adds exactly one relic and leaves on the map; nothing is offered when the table is out
  - [ ] MD2.6 The first set: 6 to 8 relics that only change numbers (for example dart damage, dash cooldown, cash from drops, heart drop chance), each one a line in the file and one effect applied through `Relics.factor`; check: for every relic of the file the value it names is no longer neutral and a run with it plays clean on 4 seeds (`tools/generated_run_check.gd` style)
  - [ ] MD2.7 Show them: the relics on the run bar and the pause menu as short text chips (written out, not only an icon or a colour), a line on the run summary, and the relic named on the pick screen; in-game look by the owner
  - [ ] MD2.8 Save them: `relics` in `run.json` and `docs/SAVE_FILES.md`, an old file reads as none; check in `tools/run_save_check.gd`: CONTINUE gives the same relics back and an offer made before saving is the same after
  - [ ] MD2.9 Playtest: the bot harness takes the first relic offered (a `--relics` argument, off by default so the old numbers stay comparable) and the table of a run with and without relics is looked at

- [ ] Add rule-changing relic effects
  - [ ] MD3.1 Design note in `docs/RELICS.md`: 10 to 12 ideas, one line each, of relics that change a rule and not a number (for example a dash that hurts what it passes through, a dart that bounces, a heart on a streak); which hook each one needs; the first 4 to build; which pairs fight each other
  - [ ] MD3.2 The hooks: one small dispatcher in `relics.gd` that the game calls at a few named moments (round start, a kill, damage taken, a dash, a round clear), so no relic code is scattered through `combat.gd`, `riders.gd` and `player.gd`; check: with no relic the dispatcher does nothing, and each hook is called exactly once per moment
  - [ ] MD3.3 First rule-changing relic: the hook it needs, the entry in the file, its check
  - [ ] MD3.4 Second rule-changing relic, the same way
  - [ ] MD3.5 Third rule-changing relic, the same way
  - [ ] MD3.6 Fourth rule-changing relic, the same way
  - [ ] MD3.7 Clashing pairs: two relics that cannot be held together are listed in the file with the reason (like the Heat clashes) and the offer draw skips the second one; check over many seeds that no run holds a clashing pair
  - [ ] MD3.8 Check and playtest: every relic of the file alone and all of them in one run through the scripted run, no script error and every rider and boss still finite; then a balance pass with the bot harness (and the numbers of MD2.9)

## Curses

- [ ] Add risk/reward curse system
  - [ ] MD4.1 Design note, no code (`docs/CURSES.md`): what a curse is (assumed: a downside the player takes on purpose for a reward, held until the run ends or it is lifted); where it comes from (first guess: a third choice on the relic pick, "TAKE A CURSE, GET A BETTER RELIC", and event choices); whether and how one is lifted (assumed a rest node choice or a shop item, to decide); a cap on curses held; that curses do not count as Heat (Heat is chosen before the run, a curse during it), to confirm; the questions for the owner
  - [ ] MD4.2 The table and the holder: `data/curses.json`, `Main.curses` (cleared in `reset_run`), `Curses.factor(key)` neutral with none, the same shape as relics so the two can share code; `tools/curses_check.gd`
  - [ ] MD4.3 The first 4 curses, numbers only (for example fewer darts from drops, a higher shop price, a faster rider), each applied where it plays out; check: every curse of the file changes the value it names and a run with it plays clean
  - [ ] MD4.4 Take one for a reward: the third choice on the relic pick (MD2.5) offers a better relic (a rarity up) for a curse, both shown in full on the button; check: taking it adds exactly one relic and one curse, refusing adds neither
  - [ ] MD4.5 Lift one: the way chosen in MD4.1 (a rest node choice or a shop item), with its price; check: the curse is gone, the price is paid once, nothing is offered when there is no curse
  - [ ] MD4.6 Show and save them: curses on the run bar, pause menu and run summary written out and told apart from relics by their text, not only by colour; `curses` in `run.json`, an old file reads as none; check in `tools/run_save_check.gd`
  - [ ] MD4.7 Event hook: the event effects of MD1.5 that give or take a curse are switched on (needs MD1 and MD4.2)
  - [ ] MD4.8 Playtest: the bot harness takes the curse option (`--curses`, off by default) and the table with and without curses is looked at, so a curse is a real risk and a real reward

## Round Modifiers

- [ ] Night modifier (the NIGHT theme exists and nodes use it, but not as a modifier a node can add)
  - [x] MD5.1 Design note in `docs/MAP_GENERATION.md` ("Night modifier"): night as a modifier means a node carries `night` in its `modifiers` (still 0 or 1 per node) and the round plays under the NIGHT theme whatever theme the node drew; the rule is a radar at 60 % of its range, the threat arrows are not touched; the NIGHT theme alone stays a look; the theme draw and `theme_count` stay as they are; it stays readable by the rules of `docs/ART_DIRECTION.md`. Two questions for the owner are at the end of the note (the rule itself, and whether a NIGHT-themed node gets the rule too); no code
  - [x] MD5.2 The rule in the data: a `night` entry in `modifiers.types` of `data/map_rules.json` with weight 0 and `min_floor` 3; check with `tools/map_check.gd` that every map of a seed is exactly the same as before (a weight of 0 must move nothing, the modifier roll is always drawn)
  - [x] MD5.3 Apply the theme and the rule: `round_theme()` returns NIGHT when the node's own `modifiers` (read from `node_setup()`, because `start_round` calls `round_theme()` before `plan_riders()` fills `round_modifiers`, so `has_modifier` is not ready yet) hold `night`, and the next round goes back to its own theme; the radar range goes through one factor (0.6 in a night round, 1.0 otherwise) in `threats.gd`; check: a round with the modifier plays under NIGHT with the short radar, a round without it keeps its theme and the old radar numbers exactly, and the theme of a map's nodes is unchanged
  - [ ] MD5.4 What it feels like: window glow and lamp posts at night (`world_dress.gd` already glows windows at dusk and night); a before/after screenshot with riders, phones, pedestrians and pickups still readable at distance, the frame time inside the budget in `docs/PERFORMANCE_BUDGET.md` on both renderers, and a look at whether the short radar misses a cache the player already senses (`explore_map.gd` keeps the two ranges equal)
  - [ ] MD5.5 Show it: a node with the modifier says NIGHT on the map screen, in the round start banner and in the pause menu; in-game look by the owner
  - [ ] MD5.6 Turn it on: the weight goes from 0 to a first guess of 20, `docs/MAP_GENERATION.md` and the numbers in `tools/map_check.gd` follow; a run with the bot harness on 8 seeds still ends

- [ ] Rain modifier (nodes can carry it, but it has no effect; switched off in alpha B5)
  - [ ] MD6.1 Design note in `docs/MAP_GENERATION.md`: what rain does (first guess: rain and wet look, a rain sound, and one small rule such as a longer dash slide or slower riders at corners; no effect that makes a round unfair), checked against `docs/ART_DIRECTION.md`
  - [ ] MD6.2 The look: rain drawn over the generated arena (particles near the camera, a darker sky and a wet ground), one scene part that is switched off with no rain; a screenshot, and the frame time inside the budget on both renderers
  - [ ] MD6.3 The sound: a rain loop made with `tools/bake_audio.py`, started and stopped with the round (a loop is stopped on every way out of a round: clear, death, quit, practice); check that no loop plays after the round
  - [ ] MD6.4 The rule: the small effect of MD6.1 applied in one place, read through `has_modifier("rain")`; check: it changes only in a rain round and a round without rain is exactly as before
  - [ ] MD6.5 Show it and turn it on: RAIN on the map screen, the banner and the pause menu; the weight in `data/map_rules.json` goes from 0 to a first guess of 20 (`min_floor` 3 stays), docs and `tools/map_check.gd` numbers follow
  - [ ] MD6.6 Night and rain together: decide whether a node can carry two modifiers (today 0 or 1, in `map_content.gd`); first guess is no, so MD5 and MD6 never meet, and the answer goes in `docs/MAP_GENERATION.md`

- [ ] Additional modifier ideas
  - [ ] MD7.1 Collect the ideas in `docs/MODIFIERS.md`: 10 one-liners, each with what it does, which rule it touches, how the player counters it and a rough cost to build (for example fog, a rider swarm from one gate, a round with no pickups, a round with a timer, slippery ground); the first 3 to build
  - [ ] MD7.2 Write down how a modifier is added (in `docs/MAP_GENERATION.md`): an entry in `modifiers.types`, one read through `has_modifier` where it plays out, a banner line, a check; list the hooks that exist today (`double_riders` in `plan_riders`, `riders.gd`) so a new one needs no change in the map code
  - [ ] MD7.3 First modifier from the list of MD7.1: the rule, the banner, its check, weight 0 until MD7.6
  - [ ] MD7.4 Second modifier, the same way
  - [ ] MD7.5 Third modifier, the same way
  - [ ] MD7.6 Turn them on: weights and `min_floor` in `data/map_rules.json`, docs and `tools/map_check.gd` numbers; a run through every modifier alone on the scripted run (`tools/generated_run_check.gd`) and a balance pass with the bot harness

---

# Milestone E: Polish & Accessibility

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone E: Polish & Accessibility". Only what is still open stays here.

## Dynamic Presentation

- [ ] Dynamic music system
- [ ] Scale intensity with style rank

## Onboarding

- [x] Training room map for the tutorial and for trying a weapon before buying it (note in `docs/ROADMAP_HISTORY.md`; the tutorial and the menu entries are separate items)
- [x] Try before buying: a TRY IT button on the Unlocks page takes the player and the weapon into the training room (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game check by the owner)
- [x] Training room on the title menu: a TRAINING ROOM entry takes the player into the room with the chosen loadout, and the room has no pedestrians (note in `docs/ROADMAP_HISTORY.md`; not run here, waits for the checks and an in-game look by the owner)
- [x] Short tutorial in the training room: eight prompted steps, the first TRAINING ROOM visit starts it, TUTORIAL in the pause menu runs it again (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game look by the owner)
- [x] Key rebinding (note in `docs/ROADMAP_HISTORY.md`; `keybinds` and the checks of the code it touched not run yet, waits for an in-game check by the owner)

## Accessibility

- [x] Directional warning sounds for riders (note in `docs/ROADMAP_HISTORY.md`; waits for an in-game check by the owner)
- [x] Choose the window size: a WINDOW SIZE row in the settings, saved (note in `docs/ROADMAP_HISTORY.md`; `resolution` check not run yet, waits for an in-game check by the owner)

## Code signing

> Added 2026-10-27 at the owner's request. A certificate Windows trusts costs money, so the first step is a **self-signed** one, which is possible and free. What it gives and what it does not (checked against Microsoft's [Code signing options for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)): the exe carries a signature that shows it was not changed after signing, and Windows treats it as signed on a computer where the certificate was installed as trusted (the owner's, or a tester's who chooses to). It does **not** remove the SmartScreen or "unknown publisher" warning for anybody else: Windows does not trust a self-signed certificate by default, and Microsoft describes it as meant for development, testing and internal use, not for public downloads.

- [x] Before any certificate file exists, extend `.gitignore` with `*.pfx`, `*.p12`, `*.pem`, `*.key` and `*.crt` (done together with V1.1).
- [x] Create the self-signed code signing certificate on the owner's Windows machine (Godot's Windows export page links Microsoft's guide for creating one; in PowerShell `New-SelfSignedCertificate -Type CodeSigningCert` is the usual way). Export it as a `.pfx` with a password and keep the file and the password outside the repository (the owner's user folder and a password manager). Write the certificate's SHA-256 thumbprint and its expiry date in `docs/` (the thumbprint is public, the file and the password are secret) so testers can compare it.
- [x] Decide `binary_format/embed_pck` in `export_presets.cfg`. It is `true` today, and Godot's documentation says an exported exe with an embedded PCK breaks signing (it also says embedding can trigger antivirus false positives). Signing means `false`: the export becomes `FB3D.exe` and `FB3D.pck` side by side, and the E2 smoke test (E2.2, E2.3) and the installer in Milestone N have to treat the two files as one build.
- [x] Set up the export: `SignTool.exe` from the Windows SDK, its path in Editor Settings > Export > Windows (Sign Tool), and in the Windows preset `codesign/enable=true` with the identity type and the `.pfx` as identity. **Leave the password out of the tracked `export_presets.cfg`**: Godot reads it from the environment variable `GODOT_WINDOWS_CODESIGN_PASSWORD` (the identity type and the identity have `GODOT_WINDOWS_CODESIGN_IDENTITY_TYPE` and `GODOT_WINDOWS_CODESIGN_IDENTITY`), the same rule as the PCK encryption key under "Secrets and credentials". Decide whether to timestamp (`codesign/timestamp` is `true` and `codesign/timestamp_server_url` is empty today); a timestamp keeps the signature valid after the certificate expires.
- [x] Export and verify: FB3D.exe > Properties > Digital Signatures shows the signature, and `signtool verify /pa build\windows\FB3D.exe` reports it as untrusted on a computer without the certificate (expected) and as valid after the certificate was imported as a trusted root and trusted publisher on the owner's test machine. Then repeat E2.2 and E2.3 with the signed build: it starts and the saves are still found in `user://`.
- [x] Tell testers in `docs/ALPHA_NOTES.md` (E4.2): the build is self-signed, here is the thumbprint, Windows will still warn, and importing the certificate is optional and only for people who trust the owner (it makes Windows trust anything signed with it). Never ask a player to import it.
- [ ] Sign the installer as well once it exists (Milestone N); the update download there already says it checks "its checksum (and signature)".

---

# Milestone F: Graphics & Sound Overhaul

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone F: Graphics & Sound Overhaul". Only what is still open stays here.

> Complete, hard overhaul of how the game looks and sounds. The current toon look (outlines, flat unlit colours, smooth primitive models) is removed and replaced by a chunky, rugged low-poly style with strong light and dark contrast and glowing accents, inspired by the Deep Rock franchise and built to run on low-end PCs. Direction and rules: [`docs/ART_DIRECTION.md`](docs/ART_DIRECTION.md). Free asset sources and licences: [`docs/ASSET_SOURCES.md`](docs/ASSET_SOURCES.md).
>
> **3D models: Claude is the 3D modeler.** Models are written as Python scripts for **Blender used as a Python module (`bpy`)**, kept in `tools/models/`, and exported as `.glb` into `assets/models/`. Claude cannot run Godot in its working environment, so every model step ends with an in-game check by the owner.
>
> Work top to bottom, one checkbox at a time. Each step is done when the old version of that thing is fully replaced, it passes the readability rules in the art direction, frame time is within budget, and there is a before/after screenshot.

## Graphics

### F4. Riders and bikes

- [ ] Base rider and bike model ("pro") with a rig
- [ ] Pedal, lean and steer animation cycle
- [ ] Sprinter variant
- [ ] Courier variant
- [ ] Armoured ("tough") variant, including the dismount and charge animation
- [ ] Variation kit: helmets, clothes and bike colours (also the base for rider skins in Milestone B)
- [ ] Hit reactions, crash and the parts that fall off
- [ ] Readability check of all riders against all four themes

### F5. Thrown phones

- [ ] Desk phone model
- [ ] Throw, flight trail and smash effect
- [x] **Far visibility of foes and thrown phones** (not on the roadmap; added 2026-10-30 after a playtester report)

### F6. Pedestrians and cheerleaders

- [ ] Pedestrian models (several body types and outfits) and walk cycle
- [ ] Pedestrian hit reaction
- [ ] Pedestrian vs rider readability check, including NIGHT (the rim glow above is the first help for it; the check itself waits for the in-game look)
- [ ] Cheerleader models and animations

### F7. Bosses

- [ ] Rogue lawnmower (model, animation, attack telegraphs)
- [ ] Mesh wifi adapter (model, hover, animation, attack telegraphs)
- [ ] Minister (model, animation)
- [ ] Golden president / final boss (model, animation, intro moment) (a first version built in code exists, `Models.build_president` in `scripts/models.gd`, with its decree and entrance, see `docs/ROADMAP_HISTORY.md` "Give the final boss its own model, attacks and arena moment"; this item replaces the model with the proper low-poly one and keeps the attack timings and the entrance beat)
- [ ] Angry cyclist
- [ ] Boss health bar, weak-spot marker and defeat effects

### F8. Pickups

- [ ] Pickup models or icons for rapid fire, fat darts, slow motion, shield, extra life and cash
- [ ] Glow, pickup and magnet effects

### F9. World

- [ ] Road, lane markings and curbs (stylised asphalt and concrete)
- [ ] Central fountain
- [ ] Buildings (chunky facade kit with windows that light up at dusk and night)
- [ ] Tunnel
- [ ] Props: lamps, benches, trees, bins, signs
- [ ] Ambient life: passing cars, birds and other background motion
- [ ] Weather and atmosphere touches per theme

### F10. Effects

- [ ] Dart impact and hit sparks
- [ ] Dust, debris and rider crash effects
- [ ] Boss telegraphs (lane strip, slam circle, volley warning) as bold glowing overlays or decals
- [ ] Hype, shield and slow-motion screen effects
- [ ] Damage vignette and screen response
- [ ] Confetti (perfect round, victory)

### F11. UI and menus

- [ ] UI theme: condensed bold font, dark translucent panels with amber accents, icons, key-hint chips (see section 4 of the art direction)
- [x] Modern FPS HUD (owner request 2026-11-01): the arcade full-width top bar and the retro bottom texts are replaced by a corner layout like a current shooter: radar top left, round and progress segments top centre, score, high score, cash and combo top right, health segments and the hype meter bottom left, a big ammo counter with the weapon name and a [Q] key chip bottom right, dash and style rank bottom centre; dark translucent panels, no strips (note in `docs/ROADMAP_HISTORY.md`; check: `python tools/run_checks.py hud_modern`; waits for an in-game check by the owner)
- [x] Crosshair and hit marker in the same modern style: the hit marker pops out and settles in four kinds (plain hit white, boss weak spot gold, kill orange, pedestrian hit red; the bigger news is drawn bigger and thicker) and now shows on every rider and boss hit, not only on a pedestrian hit as before; the melee crosshair is a thin ring with a dot (note in `docs/ROADMAP_HISTORY.md`; check: `python tools/run_checks.py hit_marker`; waits for an in-game check by the owner)
- [ ] Threat arrows, radar and floating popups
- [ ] Upgrade and shop cards (header, icon, reroll button, key hints; rarity tags are optional and can come later)
- [ ] Title screen with a live 3D background and a text-only logo
- [ ] Pause menu and settings panel (amber buttons, hazard-stripe footer)
- [ ] Run summary and leaderboard screens
- [ ] Ultrawide and resolution scaling check

### F12. Final pass

- [ ] Remove `toon.gd`, the outline option and all leftover cartoon assets and code
- [ ] Performance pass on the minimum-spec machine (instancing, shadow and light counts, particle overdraw)
- [ ] Final colour grade and consistency review of every screen and theme
- [ ] Before / after comparison for the repo

## Sound

Where to get free assets, and the licence rules: [`docs/ASSET_SOURCES.md`](docs/ASSET_SOURCES.md). Plan: use professional free libraries for effects and ambience, keep your own voice recordings, and keep the existing synthesised sounds only until each is replaced.

### S1. Foundation

- [ ] Set up the audio pipeline: folders, naming, one loudness target, and a `CREDITS.md` entry for every file
- [ ] Download the sources worth mining (the latest Sonniss GDC bundle, Freesound CC0 / CC-BY searches, Kenney) and build a shortlist per sound category
- [ ] Bus layout: Master with Music, SFX, Voice, Ambience and UI buses; voice ducking
- [ ] One volume slider per bus in Settings (only one master slider today)

### S2. Weapons and combat

- [ ] Dart gun: shot, pump / reload, empty click, shell drops
- [ ] Dart impact on rider, pedestrian, boss armour and weak spot
- [ ] Melee: swing, hit and deflect
- [ ] Phone: throw whoosh, flight, smash

### S3. Riders and world

- [ ] Bike and rider loop (with pitch and volume by speed)
- [ ] Footsteps, landing, slide and dash
- [ ] Crashes and falling parts
- [ ] Ambience loops per theme (day, golden hour, dusk, night) and the tunnel
- [ ] Passing cars, birds, sirens and crowd cheer

### S4. Bosses

- [ ] Lawnmower and wifi loops, intro and hit sounds
- [ ] Minister and golden president sounds
- [ ] Boss defeat and final boss defeat stingers

### S5. UI and flow

- [ ] Menu sounds: hover, confirm, back, error
- [ ] Pickup, hype, shield and slow-motion sounds
- [ ] Stingers: round start, round clear, game over, run complete
- [ ] Leaderboard name entry sounds

### S6. Voice lines

- [ ] Normalise all 79 lines to one loudness and remove the unused `voice_old` files
- [ ] Record new lines: run start, final boss intro, victory
- [ ] Note who recorded each line (for the credits)

### S7. 3D audio and mixing pass

- [ ] Distance attenuation, doppler for riders, tunnel reverb
- [ ] Mix pass of every theme and boss fight
- [ ] Remove `tools/bake_audio.py` and the synthesised files once nothing uses them

### S8. Music

- [ ] Music: see "Dynamic music system" in Milestone E

---

# Milestone H: Run Start Sequence

- [ ] Design the opening sequence (storyboard: bed, house, door, nerf gun, street)
- [ ] Build the bedroom and house interior (small, low-poly, matches the art direction)
- [ ] Wake-up animation: the player stands up from the bed (first-person camera)
- [ ] Walk from the bed to the front door (scripted movement, no player control)
- [ ] Pick up the nerf gun on the way out (the starting one-dart gun appears in the viewmodel)
- [ ] Walk out the door onto the street
- [ ] Screen fades out, then fades back in on the generated map
- [ ] Allow the player to skip the sequence (button or key), and a setting to always skip it
- [ ] Keep the sequence short (target under 15 seconds) and skip it on a restart after dying
- [ ] Hook the sequence into Play and Daily Run, and make sure the seed is already chosen before it starts

---

# Milestone I: Roguelite Progression

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone I: Roguelite Progression". Only what is still open stays here.

> The player starts every run with the simplest possible loadout and earns everything else across runs.

- [ ] Unlock and buy new weapons with meta currency (adds them to the shop pool)
- [ ] **PARTLY BUILT:** XP is earned, saved and shown, but a level does nothing yet, on purpose for the alpha (decided in alpha C4). XP and levels (the in-game side; the website shows the same numbers, see Milestone N)
  - [x] Decide what earns XP (for example score, kills, boss kills, finished rounds and runs, challenges) and write the XP table and the level curve in a data table (like `data/items.json`), so the numbers can be tuned without touching code
  - [x] Keep XP and level in the versioned save files (see `docs/SAVE_FILES.md`), separate from meta currency (XP is never spent, it only goes up)
  - [x] Show XP, level and a progress bar to the next level on the title screen, and the XP gained and any level-up on the run summary screen
  - [x] Decide whether a level unlocks anything (items, cosmetics, titles) or is only a number to show off: **for the early alpha a level is only a number to show off** (title screen and run summary); the first use of levels comes after the alpha (alpha C4)
  - [ ] Send XP and level to the website with the other progress (needs the account and API in Milestone N; without an account XP and level still work locally and are only shown in the game), and make sure the server is the one that adds up XP from the runs it is sent, so an edited number in a save file cannot raise a level

---

# Milestone J: Manual Reload

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone J: Manual Reload". Only what is still open stays here.

- [ ] Add reload to the key rebinding list and the Controls page (the Controls page exists now and lists R and X for reload; key rebinding does not exist yet, so only the rebinding list is left)
- [ ] Rebalance darts per magazine and reload time now that reloading is not free

---

# Milestone K: Procedural Arenas

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone K: Procedural Arenas". Only what is still open stays here.

> Every run gets one generated arena, about four times bigger than the roundabout, that the player walks through freely and where riders can ride on roads, sidewalks, grass and anywhere open. Design, owner decisions, current-code notes and open questions: [`docs/PROCEDURAL_ARENAS.md`](docs/PROCEDURAL_ARENAS.md). Needs the seed from Milestone G; the world kit from Milestone F9 should be reused for the dressing. This replaces how riders, bosses and pedestrians move (street coordinates become world positions), so it is large: work top to bottom, and the first steps keep the roundabout playing as it does today.

## Decisions

- [ ] Set the performance budget (triangles, lights, shadows, draw distance) on the minimum-spec machine (deferred by the owner: not needed yet, but needed before the world is built)

## Rider variety and arena hazards

> Riders ride at the player, pass, turn and come back (`scripts/riders.gd`). On the bigger arena a few more patterns would make fights different from each other, and the buildings the arena already has could be part of the fight. Ideas to decide on before building; each must keep `rider_pursuit_check` and `round_clear_check` working (a round still ends when every rider is down, so no pattern may leave a rider that cannot be reached).

- [ ] Riders that flank in pairs: two riders that come in by different gates and reach the player from two sides, or one that peels off to the side while the other rides straight on
- [ ] Ambush rider: waits behind a building near the player's path and rides out when the player comes within range (needs `Arena.rider_blocked` and the sight rule `Threats.sight_clear` to pick the spot; show it on the radar only once it moves, and decide how it reads with the rim glow)
- [ ] Heavy rider that blocks a road: slow, tough and wide, it rides along a road and forces the player to go round or shoot it down; check that the other riders' obstacle avoidance (`avoid_obstacles`) copes with it
- [ ] Riders crash on the arena: a rider that hits a building, lamp post or tree at speed crashes (the crash and falling-parts effects of F4 and F10 are the model), and a startled pedestrian group can be ridden into, so the player can use the arena as a weapon. Decide what a crash pays (score, style, a `kill` for the round count) and make sure a rider that crashed by itself still counts as down
- [ ] Add the new rider kinds to the map content (`scripts/map_content.gd`, `rider_plan`) and the rider mix numbers in `data/map_rules.json`, so the node decides which of them appear

## Height: hills, walkways and stairs

> Every arena is flat today: the ground is made of flat meshes at y 0 (`WorldGen.build_ground`), and `Arena.surface_at` only says what the ground is made of, not how high it is. Small hills, raised walkways and stairs would turn the arena into real 3D ground to fight on. It is a big change because height touches the layout, the ground, the `Arena` interface, riders, aiming and jumping, so it is split into small steps, and the flat arenas and the roundabout must keep playing exactly as they do now until a step says otherwise. Milestone L (jumping) and this section affect each other (jump height, "Keep the player inside the arena while jumping"), so decide the numbers together.

> **Order of work (decided with the owner on 2026-11-02):** (1) decide the height model, no code, in `docs/HEIGHT_MODEL.md`; (2) add `height_at` to the `Arena` interface returning 0 everywhere and thread it through everything that touches the ground (player, riders, pedestrians, bosses, pickups, `clamp_walk`, the objectives), with flat arenas behaving exactly as before, so the existing checks are the safety net; (3) height in the layout, hills first, behind a rule that switches it off; (4) navigation and validation; (5) the ground meshes and the dress; (6) combat and sight over height, last, because that is where the surprises are expected; (7) tools and the playtest. The bot balance harness (Milestone A, "Bot playthrough balance harness") is a good thing to have before step 3, because height moves the run length and difficulty numbers.

- [ ] Raised terrain: small hills, walkways and stairs, so the arena is not just a flat map
  - [x] **Decided with the owner on 2026-11-02, written in `docs/HEIGHT_MODEL.md`:** one height per point, bikes use ramps and not stairs, top 3 m with a 0.5 m step-up, park, plaza, market and canyon get height. Decide the height model before building anything: a height per cell beside the ground grid (steps of about 0.5 m, smooth for hills, stepped for stairs and ledges), how much height there is (small, up to about 3 to 4 m, so sightlines and the radar still work), what counts as walkable (a maximum slope and a maximum step), and whether bikes can ride slopes and stairs
  - [ ] Layout: `ArenaGen.generate` adds a height per cell from the seed (hills on grass and parks, raised walkways over roads and plazas, stairs where two heights meet), with the numbers in `data/arena_rules.json`; the same seed still gives the same arena, and a rule can switch height off so the flat arenas stay
  - [ ] Navigation and validation: the nav grid and `ArenaGen.validate` know climbable and not climbable (a slope or step too steep is a wall), and every gate, cache and the extraction point must still be reachable on foot and by riders, with no cache or start spot inside a hill
  - [ ] Build the ground from the heights in `WorldGen` (hill meshes, stair treads and risers, walkway decks with edges or railings, retaining walls), and stand buildings, props and lamps at the right height in `WorldDress`; the surface, curbs and markings must follow the slope
  - [ ] Height in the `Arena` interface: a `height_at(p)` query, the roundabout and flat arenas answering 0; `clamp_walk`, `obstacle_at`, `surface_at` and `start_position` use it, and the player walks up slopes and stairs smoothly (step-up, no jitter) and stands on the ground height
  - [ ] Riders, pedestrians, bosses and pickups follow the ground height (steering and speed on slopes, spawning at the right height, `rider_speed_at` on stairs), and decide where a rider cannot go (stairs) and how `avoid_obstacles` treats it
  - [ ] Combat and sight with height: darts, aim assist, `ray_blocked`, `Threats.sight_clear`, the radar and the threat arrows, thrown phones and the boss attacks (strips, slam circles, volleys) still work when the rider is above or below the player
  - [ ] Show height in the tools: the arena viewer (`tools/viewer/arena_viewer.tscn`) shades or draws contour lines by height, and a check over many seeds (with a `.bat` script) tests reachability, slopes and that nothing clips into a hill
  - [ ] Playtest and balance: does height make fights better or does it hide riders, are stairs and walkways fun to use, and the cost in frame time on the minimum-spec machine

## Scale, variety and polish

- [ ] Performance pass for the bigger arena (draw distance, culling, shadow and light counts) on the minimum-spec machine (the arena is now 144 m square, about 8 to 12 times the roundabout instead of 4, so the walkable ground, the buildings, the lamps and the gates all grew, and the 4 gold and 1 green light column of the objectives are new draw cost; frame time on weak hardware is not known; the limits it checks against are in `docs/PERFORMANCE_BUDGET.md`)
- [x] Arena styles chosen by the seed: plaza, street canyon, market, bridge, tunnel, park (replaces the hand-built arenas in Milestone D)
  - [ ] Look and feel of the bridge and the tunnel: they are walled placeholder boxes with no water edge, no roof or ceiling and the same ground surfaces as the other styles; decide on water or a drop beside the deck, a roof or ceiling lights for the tunnel and a different ground (planks, tiles)
  - [ ] Playtest and balance each style: rider speed, sightlines and run length per style, how a bridge with only 2 gates plays against 3 to 6 riders, whether a tunnel's short sightlines are fair, and the weights (all 1 now; a style can be made rarer by lowering its `weight`)
  - [x] Show the style on the run map or the title screen
  - [x] Show the style on the run map screen too

---

# Milestone N: Website, Launcher & Online Services

The game gets a home on the web: a new Django app on the existing website (Django + PostgreSQL + nginx + gunicorn, already running), a launcher where players log in, cloud saves, leaderboards, bug reports, and a proper installer with auto updates. Planning only for now: nothing below is built yet, except what the early alpha's website milestone (W) builds first: the app `fb3d`, its Info articles and its Feedback section.

> **Being built now (2026-10-29):** the first release that builds this milestone has its own working plan, the **Web Integration Roadmap (v0.3.0)** near the top of this file (ids V1 to V10): secrets and `.gitignore`, the version and git hash, the API and its key, the update check, the launcher and login, the installer and auto updates, save protection, cloud saves, and Discord Rich Presence. An item there that also exists below is the same work: tick both, and write the long note under the V heading in `docs/ROADMAP_HISTORY.md`. Leaderboards, the account page and the game-side bug report log stay below for after 0.3.0.

> Design rules: the game talks to the website only through a REST API. The website, not the game, is the authority on accounts, XP and levels, leaderboards and which version is current. Only the superuser can publish a new game version. An account is optional (decided): the whole game, with its local saves, leaderboard, unlocks and XP, works without one, and a player who never logs in only misses the web features (cloud saves, online leaderboards, the account page, bug reports through the game). A missing network or a down website never blocks a run either, it only delays syncing.

## Website: Django app and REST API

- [x] Create a new Django app for the game on the existing website (**the app is called `fb3d`, decided 2026-10-28, and is built first for the early alpha as W1 to W4**; the URL prefix is a first guess `/fb3d/`), with its own models, migrations, templates and tests, so it does not touch the rest of the site
- [x] Write down the REST API in a short doc (`docs/WEBSITE_API.md`): endpoints, request and response shapes, error codes, auth headers, the API version in the URL (so an old game build keeps working after the API changes), and rate limits
- [ ] Set up the REST API (Django REST Framework or similar) behind nginx and gunicorn, with HTTPS only, CORS closed (the game is not a browser), and request size limits (saves are small)
- [ ] Keep the game's website code in the repo or next to it (decide which), and describe the deploy steps for Django + PostgreSQL + nginx + gunicorn (migrations, static files, restart) in `docs/`

## Accounts and login

- [ ] Account login through the REST API with username and password (decided: players register on the website only, so the game has no sign-up form, only a login and a "No account? Register on the website" link that opens the registration page; use the website's existing accounts if there are any)
- [ ] Token-based session after login: the launcher gets a token (and a refresh token), keeps it on the player's PC in a protected place (Windows Credential Manager or an encrypted file, never the password), and sends it with every call; logging out deletes it
- [ ] "Remember me": when ticked, the token is kept so the next start skips the login and goes straight on (the launcher checks the token with the website, and shows the login form again if it has expired or was revoked); when not ticked, the token is only kept for this session; a LOG OUT button on the launcher screen forgets it
- [ ] Password handling: the password only travels over HTTPS and is never stored or logged by the game, the website uses Django's password hashing, and failed logins are rate-limited
- [ ] Password reset and email confirmation through the website (reuse what the site already has)
- [ ] Playing without an account (decided: the account is optional): the game starts and plays fully with the local save, nothing in the game is locked behind a login, and the web features are simply not offered until the player logs in; the same goes for a player who is logged in but offline, who syncs later

## Launcher

- [ ] The launcher is the game's first screen (decided: no separate launcher program), shown before the title menu: login form (username, password, "remember me"), a "Register on the website" link, a PLAY button that works logged in or not (a "Play without an account" button next to the login form, and with a remembered "play without an account" choice the screen can be skipped), the installed game version, "update available" status, and a link to the website and the bug report page; with a remembered login it only shows briefly and goes on to the title menu by itself
- [ ] Offline and skip: if the website cannot be reached, the launcher screen says so and lets the player continue offline with the local save (see "Playing without an account" above); the login stays one click away in the title menu or settings (LOG IN / ACCOUNT entry) for a player who skipped it, so they can log in later without restarting
- [ ] Show what is missed without an account in a small, non-nagging way (for example a grey "Online features off: log in" line on the title menu), and never block, delay or repeatedly ask the player
- [ ] Build the launcher login against the REST API, with clear messages for a wrong password, no connection and a server error
- [ ] After login the game knows the account (name, token) for the whole session, so saves, scores and XP go to the right account without asking again; a log out or an expired token drops the game back to playing without an account, it never interrupts a run, but it always tells the player: a clear "You were logged out, log in again to use online features" message (a toast or a notice on the title menu, shown right away, or as soon as the run ends if it happens mid-run) with a LOG IN button, and the login form is shown again on the next start
- [ ] Show the account name, level and XP in the launcher after login

## API key (game to website, in the background)

- [ ] Create an API key for the game build and use it for the background calls between the game and the website (version check, score submit, save sync), next to the player's login token, so calls that do not come from a real build of the game can be rejected
- [x] Store the key encrypted (the server side is V3.4, the game side is V4.1: `api_key.bin`, obfuscated, see `docs/SECRETS.md`): on the server only a hash (or the key in an encrypted settings value, not in the repo or in plain text in the database), and in the game build encrypted and obfuscated, not as a plain string in a script or in `project.godot`; keys are never committed to the repository (`.gitignore` and a secrets check in CI)
- [ ] Support key rotation: the server accepts a new and an old key for a while, the game build carries the current one, and a leaked key can be switched off from the Django admin
- [x] Be honest about the limit in the docs: a key inside a game that runs on the player's PC can be extracted by someone determined, so it is one layer, not the only one. The server must still check the player's token, validate every submitted score and save, and rate-limit per account

## Cloud saves (like Steam Cloud)

- [ ] Keep the local save file exactly as it is today (see `docs/SAVE_FILES.md`): the game always reads and writes the local file, and the cloud is a copy
- [ ] Upload the save to the website for each user after a run ends, when the player quits, and on a timer, in the background and without blocking the game (one current save per account, plus a few older versions to roll back to; decide how many)
- [ ] On login on a new PC (or with no local save), offer to download the cloud save so the player can continue
- [ ] First login of a player who already played without an account: decide how the local progress joins the account (upload it as the account's first cloud save, or ask when the account already has a cloud save: use the cloud save, keep this PC's save, never merge silently), and decide whether runs played before logging in count for the website leaderboards and XP (they cannot be checked by the server, so probably they do not)
- [ ] Conflict handling when the local and the cloud save differ (for example two PCs played offline): compare the save version, the save time and the XP, and ask the player which one to keep ("Use cloud save / Use this PC's save"), never overwrite silently, and keep a `.bak` of whatever is replaced (same rule as the version safety in `docs/SAVE_FILES.md`)
- [ ] Sync status in the game and launcher (synced, syncing, offline, conflict), and a manual SYNC NOW button
- [ ] Server side: store saves per user in PostgreSQL (or on disk with the path in the database), with a size limit, a save-format version check, and the rule that a save from a newer game version is kept but never loaded by an older build

## Save file protection

- [ ] Check what the save files look like today (`settings`, `scores.json`, meta currency, unlocks): which ones hold anything worth cheating with (meta coins, unlocks, XP, level, scores) and which are only settings; protect the first group and leave plain settings readable
- [ ] Encrypt the save files so they cannot be opened in a text editor and edited (Godot's `FileAccess.open_encrypted_with_pass`, or an own format with authenticated encryption), with the key kept out of plain sight in the build (it must work without an account, so it cannot depend on the login)
- [ ] Add tamper detection on top of encryption: a signature or HMAC over the save contents, a check on load, and a clear rule for what happens when it fails (refuse to load that save, keep it as `.bad` for inspection, fall back to the last good backup or a fresh save, and tell the player)
- [ ] Keep it compatible with the versioned save files (see `docs/SAVE_FILES.md`): an old plain save from before this item is read once, upgraded and written back encrypted, and a `.bak` is made first
- [ ] Do not trust the client for anything that matters online: the server checks submitted scores, recomputes XP from the runs it is sent, and treats a cloud save that fails its signature or has impossible values as invalid
- [ ] Be honest about the limit in the docs: a determined player can always attack a game on their own PC, so the goal is to stop casual editing in a text editor, and to keep cheated saves and scores off the website's leaderboards
- [ ] Check: `tools/save_protection_check.gd` (with a `tools\run_save_protection_check.bat` next to it, as the testing rule asks) saves, loads, edits one byte, loads again and checks that the edit is caught

## Leaderboards and the player's account page

- [ ] Submit scores from the game to the website after a ranked run (builds on the local Top 10 and the Daily Run in Milestone A), with the run seed, score, time, kills, rounds and game version, and validate them on the server (sanity limits, the same seed rules as the game, and no scores from versions that are no longer allowed)
- [ ] Website leaderboards: all-time, daily (same seed for everyone that day, see Daily Seed Mode in Milestone A) and per difficulty once Heat exists (Milestone B), with the player's own rank highlighted
- [ ] Leaderboard in the game itself (an ONLINE tab next to the local High Scores page) that reads from the API and shows a clear message when offline
- [ ] Account overview page on the website: account name, level, XP and progress to the next level, runs played, best scores, total kills, bosses defeated and the unlocks the account owns
- [ ] Progression page: XP and level over time (a small chart), recent runs with their results, and challenges or achievements done (when they exist, see Milestone B)
- [ ] Show the same XP and level in the game (see "XP and levels" in Milestone I), and make the website the source when the two disagree
- [ ] Privacy basics: what the website stores about a player, a page that says so, and a way to delete the account and its saves

## Bug reports

- [ ] (The Feedback section of the early alpha, W4, already gives logged-in players a "bug report" category with images and videos and a status in the admin; this item adds what is missing: the game version and log filled in from the game, and the button in the launcher and the pause menu.) Bug report page on the website (logged-in players): title, what happened, what was expected, steps to repeat, game version and an optional screenshot, saved in the database and listed in the Django admin with a status (new, seen, fixed)
- [ ] "Report a bug" button in the launcher and on the pause menu that opens the report page, or sends a report through the API with the game version, the account name and the end of the game log filled in (decide which; the log must never include the password, the token or the API key)
- [ ] Limit abuse: one report form rate limit per account and a size limit on text and images
- [ ] Optional: email or message to the owner when a new report comes in

## Installer and auto updates

- [ ] Proper Windows installer (`.exe`), built from the export in `build/windows/FB3D.exe` (see "Configure Windows export presets" in Milestone E): installs into Program Files or the user's folder, adds a Start Menu entry and a desktop shortcut, and has an uninstaller that leaves the saves alone unless asked (decide the tool, for example Inno Setup or NSIS; written as a script in the repo so the build can be repeated)
- [ ] Fill in the Windows version information (`application/file_version` and `application/product_version` in `export_presets.cfg`, read from `config/version`) and decide about code signing the installer and the exe (without a signature Windows SmartScreen shows a warning; the self-signed first step and the choice of a certificate Windows trusts are under "Code signing" in Milestone E)
- [ ] Version check through the website: the launcher asks the API for the newest version (and the minimum version still allowed) when it starts, and shows "Update available" or "Update required"
- [ ] Download and install updates automatically: the launcher screen in the game downloads the new version from the website, checks its checksum (and signature) before using it, keeps the saves, and can roll back if the update fails; decide between a full installer download and a smaller patch
  - [ ] Since the launcher runs inside the game, the running game cannot replace its own files: the game downloads the update, then starts a small separate updater (or the installer in silent mode), quits, and the updater replaces the files and starts the game again; write down which of the two is used and how a failed update restores the old version
- [ ] Release publishing, superuser only: a page in the Django admin (or a small form) where only the superuser uploads a new build, enters its version and release notes, and marks it as the current one; the website stores the file's checksum, nobody else (not even logged-in staff) can publish, and old versions can be kept or withdrawn
- [ ] Show the release notes (what changed) in the launcher before or after an update
- [ ] Decide how the version number is kept in step: `config/version` in `project.godot` stays the one place the game's version is written (see "Show the game version on the title screen" in Milestone E), and the release page on the website reads or checks against it

## Suggested order inside this milestone

> Roughly: API doc and Django app, then accounts and login, then the launcher, then the API key, then save protection (before saves go online, so no unprotected save is ever uploaded), then cloud saves, then leaderboards, the account page and XP, then bug reports, and last the installer and auto updates (they need a stable launcher and API first). **For 0.3.0 the order differs on one point:** the installer and auto updates come right after the launcher and before save protection and cloud saves, because they never touch saves or accounts and testers then receive the sync release by auto update (see the Web Integration Roadmap).

---

# Tooling & QA

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Tooling & QA". Only what is still open stays here.

- [ ] Playtest pass of everything built in Milestone A (title, pause, settings, run, win / lose, leaderboard, name entry). It was written without running the game
- [x] Bot playthrough balance harness: a headless script (`tools/bot_run.gd` with a `tools\\run_bot_run.bat` next to it, as the testing rule asks) where a simple bot plays whole runs on many seeds (aims at the nearest rider, dashes away from a threat that is about to hit, takes the nearest cache, walks to the extraction point) and logs, for every round, the time, lives lost, damage taken, kills, caches taken and whether it reached the extraction point; a summary per seed and across seeds gives real numbers for the playtest and balance items in Milestone K, the 10-round difficulty curve and the run length target. Reuse `tools/generated_run_check.gd` for the scripted run; the bot does not have to be good, only the same every time, so changes show as changes in the numbers

---

# Technical Refactor (Recommended Before Milestone D)

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Technical Refactor (Recommended Before Milestone D)". Only what is still open stays here.

## Future-Proofing

- [x] Make weapon additions easier
- [ ] Make relic additions easier (there is no relic system to make easier yet: build it data-driven like `data/perks.json` when "Implement relic system" in Milestone D is done, and tick this with it)
- [ ] Prepare architecture for potential co-op support

---

# Suggested Development Order

- [ ] Milestone A: Menu, game flow, saves, high scores
- [ ] Milestone B: Meta currency, unlocks, skins
- [ ] Milestone C: Weapon slots and new weapons
- [ ] Milestone D: Run map, relics, modifiers
- [ ] Milestone E: Polish, tutorial, music
- [ ] Milestone F: Graphics and sound overhaul (art direction first; can start any time after Milestone A)
- [x] Milestone G: Procedural map generation (done, see `docs/COMPLETED_MILESTONES.md`)
- [ ] Milestone H: Run start sequence (needs the map from Milestone G to fade into)
- [ ] Milestone I: Roguelite progression (builds on the meta currency and unlocks in Milestone B)
- [x] Milestone J: Manual reload (small and independent, can be done at any time)
- [ ] Milestone K: Procedural arenas (big: replaces how riders and bosses move; start with the "Foundation" steps, which keep the roundabout playing as today)
- [x] Milestone L: Jumping (small and independent; dash has moved from Space to V, so Space is free); now also holds the fast S4 League style movement: wall-jumps and the side dash / dodge
- [ ] Milestone N: Website, launcher and online services (Django app and API, login, cloud saves, save protection, leaderboards, bug reports, installer and auto updates; mostly independent of the gameplay milestones, but XP and levels live in Milestone I, and the online leaderboard builds on Milestone A)