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

# Web Integration Roadmap (v0.3.0)

> **Goal:** the game stops being a file the owner hands out and becomes a **connected game with a home on the web**. It knows exactly which build it is (version and git hash), asks the website whether a newer build exists, starts through its own launcher screen (log in, or play without an account), updates itself, keeps a copy of the player's progress on the website, and shows what the player is doing in Discord. Written on 2026-10-29, right after the early alpha (0.2.0, [`docs/ALPHA_ROADMAP.md`](docs/ALPHA_ROADMAP.md)) was finished. `config/version` becomes `0.3.0` at the gate (V10); the number is a first guess and the owner decides. This is the first real build of **Milestone N**: an item here that also exists in Milestone N is the same work, so tick both. New ids use the letter **V** (A to N are milestones, A to E and W are the alpha), so "V4.2" never clashes with anything.
>
> **Rules that already hold** (decided in Milestone N, not reopened here): the game talks to the website only through a REST API, and the website is the authority on accounts, XP, leaderboards and which build is current. An account is optional: the whole game works offline and without a login, and a missing network or a down website never blocks or delays a run, it only delays syncing. The launcher is the game's first screen, not a separate program. Only the superuser can publish a build. The website's code lives in the site's own repository (alpha W1.2); this repository is public, so no secret ever goes into it (see "Secrets and credentials"). Anything inside a build can be extracted by a determined player, so a client check is one layer and the server checks everything.
>
> **Two decisions this roadmap makes that Milestone N left open** (first guesses, the owner can change them): (1) **"Update required" never blocks local play.** A build older than the minimum version only loses the online features (score submit, cloud sync) and is told to update; the title screen, the loadout and local runs keep working. Milestone N says the launcher shows "Update required" but not what it stops. (2) **The update path (V4, V6) is built before save protection and cloud sync (V7, V8)**, so testers who get the sync release receive it by auto update. Milestone N's suggested order put the installer and updates last; the update path never touches saves or accounts, so moving it earlier risks nothing.
>
> **Working order:** V1, V2, V3, V4, V5, V6, V7, V8, V10, with **V9 (Discord) at any time after V2**, because it needs no website. One checkbox at a time on its own branch (`roadmap/<id>-<short-name>`), the checks of the code it touched (`python tools/run_checks.py <name>`), a tick here and in Milestone N, and the long note in `docs/ROADMAP_HISTORY.md` under the heading "Web Integration Roadmap (v0.3.0)". Website code is built in the site's repository and has its own tests (`python manage.py test fb3d`). Steps that need Windows, the real website, Discord, GitHub settings or a person at a PC are marked **Owner:**.

- [x] **V1. Repository hygiene before any secret exists** (Milestone N "Keeping secrets out of the public repository"). Done when a key-like string cannot be pushed by accident: ignored, scanned before commit and in CI, and the procedure for a leak is written down.
  - [x] V1.1 Extend `.gitignore`.
  - [x] V1.2 `secrets.example.cfg` and the loader `scripts/secrets.gd`.
  - [x] V1.3 **Owner:** turn on GitHub secret scanning and push protection (Settings > Code security) and tell Claude when it is on.
  - [x] V1.4 `tools/secrets_check.py`, the scan of the staged changes, with `--self-test` and `--install-hook`.
  - [x] V1.5 CI runs the same scan on every pull request.
  - [x] V1.6 One look through the whole git history for anything key-like before the web work starts (nothing was found in the current files), and the result written down.
  - [x] V1.7 `docs/SECRETS.md`: where each real key lives, who has it, how to rotate it, and the "a key leaked" procedure.
- [ ] **V2. Build identity: version and git hash** (Milestone N "Decide how the version number is kept in step", and the Windows version info). Done when every build can say exactly which commit it was made from, and the hash reaches the title screen, the log and the API.
  - [x] V2.1 `tools/make_build_info.py` writes `build_info.json` at the project root: `version` (read from `config/version`, which stays the one place the version is written), `commit` and `short` (7 characters), `dirty` (uncommitted changes in the tree), `built_utc` and `channel` (`dev`, `alpha` or `release`). The file is generated, untracked (V1.1) and added to the export preset's `include_filter`, which holds only `data/*.json` today, so a file in the project root would otherwise be left out of the exe.
  - [ ] V2.2 `scripts/build_info.gd` reads it. No file (an editor run, a fresh clone) means the version from `config/version` and the commit `dev`; a damaged file never crashes the game. The title screen shows `v0.3.0 (a1b2c3d)` instead of the bare version, a dirty build shows a `+`, and the first console line is `FB3D 0.3.0 (a1b2c3d)`. `tools/version_check.gd` is extended (format, missing file, damaged file, dirty flag).
  - [ ] V2.3 One version comparison (`0.3.0` against `0.3.0-alpha`, and `0.10.0` is newer than `0.9.0`), used by the update check (V4.4) and written again in the website code, with the test cases kept in one shared JSON file so the game and the site cannot disagree.
  - [ ] V2.4 Windows file information: fill `application/file_version` and `application/product_version` in `export_presets.cfg` (empty today) from `config/version`, by the build script and not by hand. Windows file versions are four numbers, so the hash goes in a text field of the preset or stays out; look at which fields the preset has. The tracked preset must never hold a key (see "Secrets and credentials").
  - [ ] V2.5 `tools/build_release.py` (**Owner** runs it on Windows): writes the build info, exports with Godot (it remembers the path like `run_checks.py`), computes the SHA-256 of the result and writes `release_manifest.json` (version, commit, file name, size, SHA-256, build time) into the untracked release folder. V4.3, V6.2 and V6.4 build on that file.
- [ ] **V3. The API: write it down, build it, protect it** (Milestone N "Website: Django app and REST API" and "API key"). Done when the website answers `ping`, rejects calls without a valid key, and `docs/WEBSITE_API.md` says what every call will look like.
  - [ ] V3.1 Find where the website notes went. Alpha W1.1 says to write `docs/WEBSITE.md` in this repository, and W1.2 decided the site's code lives in its own repository, but `docs/WEBSITE.md` is not in `docs/`. Decide where the API doc lives (first guess: here, because the game depends on it), write what is known about the site (Django and Python versions, how accounts work, whether Django REST Framework is installed) and choose DRF or plain Django views.
  - [ ] V3.2 `docs/WEBSITE_API.md`: base path `/fb3d/api/v1/` (the version is in the URL so an old build keeps working), the calls this roadmap needs with example request and response JSON (`GET ping`, `GET releases/current` for V4, `POST auth/login`, `auth/refresh` and `auth/logout` for V5, `GET me`, and `GET` and `PUT saves/...` for V8; the leaderboard calls stay in Milestone N, after 0.3.0), the headers (`Authorization: Bearer`, `X-FB3D-Key`, `X-FB3D-Version`, `X-FB3D-Build`), one JSON error shape with stable `code` strings that the game maps to its own messages, rate limits, size limits, and the rule for a breaking change (a new `/v2/`, with the old one kept while a supported build still uses it).
  - [ ] V3.3 Build the skeleton in the site's repository: HTTPS only, CORS closed (the game is not a browser), a request size limit per call (and the same in nginx `client_max_body_size`), throttling per IP and per account, JSON errors, `ping`, and tests. Nothing else yet.
  - [ ] V3.4 The game's API key: the server stores only a hash, several keys can be active at once (rotation: the old and the new one both work for a while), a key can be switched off in the Django admin, and the key is checked on every call that is not a human login (version check, score and save calls). A missing or wrong key gets a clear error code, never a stack trace. `docs/WEBSITE_API.md` says plainly that a key inside a game can be extracted, so the server still checks tokens and every value.
  - [ ] V3.5 **Owner:** create the first real key on the server and put it in the build machine's environment (never in the repository, see V1.7).
- [ ] **V4. Knowing about updates** (Milestone N "Installer and auto updates": the version check and release publishing). Done when the title screen says "update available" for a newer published build, and only the superuser can publish one.
  - [ ] V4.1 `scripts/web_api.gd`, the one place in the game that talks to the website: the base URL comes from the build (a debug build may take `--dev-api=URL`; an exported build ignores it, like `--dev-coins`), the headers of V3.2, a timeout of a few seconds, never blocks a frame, nothing is retried in a loop, and every call ends in a small result type (OK, OFFLINE, TIMEOUT, UNAUTHORIZED, KEY_REJECTED, UPDATE_REQUIRED, SERVER_ERROR). Nothing it prints holds a token, key or password. `tools/build_release.py` writes the API key from the environment into an untracked file that the export includes, stored obfuscated and not as a plain string in a script or in `project.godot` (Milestone N).
  - [ ] V4.2 `tools/fake_api_server.py` (standard library only, so it runs on Windows too): plays the website for the checks, with a current release, a wrong key, a slow answer, a server error, damaged JSON and a dead connection, and counts the requests it gets. Every web check from here on runs headless against it.
  - [ ] V4.3 On the site: a `Release` model (version, commit, channel, release notes, the file, size and SHA-256, a "minimum supported" flag, a "current" flag, withdrawn, published time) and `GET releases/current`, which returns the newest published release for the caller's channel and the minimum supported version. **Only the superuser can publish** (an admin page or form; a staff user who is not a superuser cannot, and a test says so). The server computes the checksum from the uploaded file and compares it with `release_manifest.json` (V2.5). Old releases can be kept or withdrawn.
  - [ ] V4.4 The check itself: once when the game starts, in the background, and then at most every few hours while it is open. It sends the version, commit, channel and system only, no account and no id. The result is `UP_TO_DATE`, `UPDATE_AVAILABLE`, `UPDATE_REQUIRED` or `UNKNOWN` (offline or error), compared with V2.3. A new settings row **ONLINE FEATURES** (ON by default, a first guess) turns off everything that talks to the website: OFF sends nothing at all. Saved in `settings.cfg`, listed in `docs/SAVE_FILES.md`, and mentioned on the privacy page (alpha W4.9).
  - [ ] V4.5 Shown without nagging: one small line on the title screen (`UPDATE AVAILABLE: v0.3.1`, a grey `OFFLINE` when unknown, nothing when current), never anything in a round, and `UPDATE_REQUIRED` names what is switched off (decision 1 above).
  - [ ] V4.6 Release notes in the game: a plain text page opened from that line and from the settings, filled from the answer (Milestone N "Show the release notes").
  - [ ] V4.7 `tools/update_status_check.gd` against the fake server: each answer, no network, damaged and oversized JSON, wrong types, the version comparison edge cases, ONLINE FEATURES OFF sends nothing (the fake server's request count stays 0), and a frozen server never freezes a frame. Break each rule once on purpose and see the check fail, as in the alpha.
- [ ] **V5. The launcher screen and login** (Milestone N "Launcher" and "Accounts and login"). Done when the game starts on the launcher, a player can log in, play without an account, or go on offline, and a bad login, a lost connection or an expired token never interrupts a run.
  - [ ] V5.1 On the site: `auth/login`, `auth/refresh` and `auth/logout` for the site's existing accounts (alpha W1.1: do not add a second account system). Login returns an access token and a refresh token, logout revokes them, failed logins are rate-limited, the password is never logged, and tests cover all of it.
  - [ ] V5.2 The launcher page, drawn before the title menu like the other pages: the game name and `v0.3.0 (a1b2c3d)`, the update status from V4.4, a login form (username, password hidden, REMEMBER ME), REGISTER ON THE WEBSITE, PLAY WITHOUT AN ACCOUNT, and links to the website and the feedback page. Keyboard, gamepad and mouse work like every other page (see `settings_nav`). A remembered login, or a remembered "play without an account", shows it only for a moment. Offline it says WEBSITE NOT REACHABLE and offers PLAY OFFLINE.
  - [ ] V5.3 Opening links: `OS.shell_open` is only called with URLs from a fixed list in the build (website, registration, feedback), never with a URL taken from a server answer.
  - [ ] V5.4 Where the token lives: Godot has no call for the Windows Credential Manager, so the first guess is an encrypted file in `user://` (`FileAccess.open_encrypted_with_pass`), never `settings.cfg`, never the password; LOG OUT deletes it. Decide it and write it in `docs/SAVE_FILES.md`, together with whether RESET ALL PROGRESS also logs out (first guess: no, LOG OUT does).
  - [ ] V5.5 The session: after a login the game knows the name and token for the whole session and refreshes it in the background. An expired or revoked token drops the game to playing without an account, with the clear "You were logged out, log in again to use online features" message and a LOG IN button (right away, or as soon as the run ends if it happens in a round), and never interrupts a run.
  - [ ] V5.6 The title menu gets a LOG IN / ACCOUNT entry (name, level and XP after a login, and LOG OUT) and one quiet grey "Online features off: log in" line. Never a pop-up and never a block.
  - [ ] V5.7 A REPORT A BUG button in the launcher and the pause menu that opens the feedback form (alpha W4.3) with the game version and hash in the address (`?category=bug&version=0.3.0+a1b2c3d`, which the form must accept, in the site's repository). Log upload stays in Milestone N.
  - [ ] V5.8 `tools/launcher_check.gd` against the fake server: a wrong password, no connection, a server error, REMEMBER ME on and off, a token that expires in a round, LOG OUT, the page skipped when remembered, the layout at three window sizes, and that nothing in the game is locked without a login.
  - [ ] V5.9 **Owner:** log in with a real account on the real website from a clean Windows machine.
- [ ] **V6. Installer and auto update** (Milestone N "Installer and auto updates"). Done when an installed 0.3.0 can update itself to a newer published build, keep its saves, and go back if the update fails. The 0.2.0 alpha has no updater, so testers install 0.3.0 by hand once.
  - [ ] V6.1 Decide and write down in `docs/UPDATES.md`: the running game cannot replace its own files, so it hands over to a small separate updater (or to the new installer in silent mode, pick one). The install location, first guess **per user** (`%LOCALAPPDATA%\Programs\FB3D`) so an update never asks for administrator rights. Saves stay in `user://` and no update or uninstall touches them. A failed update keeps the old version folder until the new one has started once, so it can go back.
  - [ ] V6.2 The installer script in the repository (Inno Setup or NSIS, the owner picks): Start Menu entry, optional desktop shortcut, an uninstaller that leaves the saves alone unless asked, the version info from V2.4, a silent mode, and built by `tools/build_release.py` so the build can be repeated. **Owner:** install and uninstall on a clean machine.
  - [ ] V6.3 Code signing decision (Milestone E "Code signing", and the SmartScreen warning the alpha download page mentions): what is signed (the installer, the exe, both) and with what. If it stays unsigned for 0.3.0, the download page and the update screen say so.
  - [ ] V6.4 A signed manifest: the checksum on the website is only as trustworthy as the website, so `release_manifest.json` is also signed with a key that stays on the owner's machine (never on the server, never in the repository), and the game carries the public half and checks the signature and the SHA-256 before it runs anything. Check that Godot's `Crypto` class (RSA sign and verify) is enough; if not, pick another way.
  - [ ] V6.5 Downloading in the game: UPDATE NOW on the launcher or the title line, never during a round, nothing downloaded until the player presses it (first guess: no silent background download). A progress bar, CANCEL, a free disk space check, the file goes to a temporary folder and is checked (size, SHA-256, signature) before anything runs, and a bad file is deleted with a clear message.
  - [ ] V6.6 The handover: the game starts the updater with the checked package and quits, the updater waits for it to exit, replaces the files and starts the game again. The first start after an update shows the release notes once. A failure puts the old version back and writes a short log that the next start shows.
  - [ ] V6.7 Checks for the parts that can be scripted, against the fake server and a local folder: a good package, a wrong checksum, a wrong signature, a truncated file, a full disk, the game still running (locked files), and the power failing in the middle (the old version must still start). Anything that needs Windows is a script the owner runs, listed here.
  - [ ] V6.8 **Owner:** update a real 0.2.0-style install to a test 0.3.0 build, then to a 0.3.1 test build; the saves are still there; uninstall keeps them.
- [ ] **V7. Save protection** (Milestone N "Save file protection"). Done before any save goes online, so an unprotected save is never uploaded.
  - [ ] V7.1 Audit what is in `settings.cfg`, `scores.json`, `meta.json` and `run.json` (and their `.bak` copies): which hold anything worth cheating with and which are only settings. Write it into `docs/SAVE_FILES.md` together with **what will sync** (first guess: `meta.json` yes; `run.json` no, a run in progress stays on its PC; `scores.json` no, because the website will hold the verified scores; `settings.cfg` no).
  - [ ] V7.2 Make casual editing impossible and tampering detectable: encrypt the protected files and add a signature or HMAC checked on load, with the key kept in the build and not depending on a login (it must work without an account). A file that fails the check is refused, kept as `.bad`, replaced by the last good `.bak` or a fresh save, and the player is told.
  - [ ] V7.3 Migration: an old plain save is read once, upgraded and written back protected with a `.bak` made first. The safety rules of `scripts/save_util.gd`, `--dev-coins` (read-only sessions) and RESET ALL PROGRESS keep working.
  - [ ] V7.4 `tools/save_protection_check.gd`: save, load, change one byte, load again and see the edit caught; an old file migrates; a wrong key, a truncated file and an empty file behave; and `progress_reset`, `run_save` and `dev_start` still pass.
  - [ ] V7.5 Write the limit in the docs: a determined player can always attack a game on their own PC, so the goal is to stop editing in a text editor and to keep cheated saves and scores off the website.
- [ ] **V8. Save sync, "cloud saves"** (Milestone N "Cloud saves"). Done when progress follows the account to a second PC, a conflict is never resolved silently, and the game plays the same offline.
  - [ ] V8.1 The local file stays the master copy and the cloud is a copy. The synced file carries a `revision` counter and a `device_id` (first guess: comparing clock times alone breaks when two PCs disagree about the time); the conflict page also shows the save version, time and XP from Milestone N.
  - [ ] V8.2 Server: one `CloudSave` per account with the current save and the last few older ones (first guess: 5), a size limit, a save-format version check (a save from a newer game is kept but never loaded by an older build), and validation of the values (coins not negative, unlock ids that exist). An upload names the revision it was based on, and a mismatch answers `409` with a summary of the stored save. Tests.
  - [ ] V8.3 Uploads in the background after a run ends, when the player quits to the title or leaves, and on a timer. They never block the game; a failure marks the save as not yet synced and retries later with a back-off.
  - [ ] V8.4 First login (Milestone N): local progress and no cloud save uploads as the account's first cloud save; both exist asks USE CLOUD SAVE or KEEP THIS PC'S SAVE with a summary of each (level, coins, runs), never merges silently, and keeps a `.bak` of whatever is replaced. Runs played before the login do not count for the website's leaderboards or XP, because the server cannot check them.
  - [ ] V8.5 A new PC: a login with no local save offers to download the cloud save.
  - [ ] V8.6 The status (SYNCED, SYNCING, OFFLINE, CONFLICT) on the launcher and the title menu, a SYNC NOW button, and the conflict page for the two-PC case.
  - [ ] V8.7 RESET ALL PROGRESS and the cloud: the reset (alpha E5) left this open ("Milestone N items should add themselves to this wipe, or ask separately"). Decide it: after the local wipe, a second question "ALSO DELETE THE CLOUD SAVE?" with NO selected first, and the account deletion on the website (alpha W4.9, Milestone N "Privacy basics") deletes the saves too.
  - [ ] V8.8 `tools/cloud_sync_check.gd` against the fake server: upload, download, a conflict (`409`), a newer format, the offline queue, an upload cut off in the middle, and each rule broken once on purpose.
  - [ ] V8.9 **Owner:** play on two PCs with one account, go offline on both, and resolve the conflict.
- [ ] **V9. Discord Rich Presence** (new; it needs no website, so it can be built at any time after V2). Done when Discord shows what the player is doing, and the game behaves exactly the same when Discord is not installed, not running or switched off.
  - [ ] V9.1 Choose the approach and write it in `docs/DISCORD.md`. The Godot asset library has several (a wrapper of Discord's Game SDK, a pure GDScript one that talks to the Discord app on the same PC, and a Discord RPC plugin), and Discord has been moving to a newer Social SDK, so check each one for Godot 4.7, licence, whether it ships a native DLL (that changes the export and the "unsigned exe" story, and antivirus programs can complain), and whether it is still maintained. First guess: the pure GDScript way if it works, because it adds no binary.
  - [ ] V9.2 **Owner:** create the application in the Discord developer portal. The application ID is not a secret, but it lives in one place only (a data file or one constant); presence should need nothing else, and if the chosen way asks for a client secret or token, it follows the rules of V1 and is never committed. Upload the art (a large logo and small icons) in the portal; it must be art we own (`docs/ASSET_SOURCES.md`).
  - [ ] V9.3 `scripts/presence.gd`: one call to set the state (a state line, a details line, a start time), a backend that does nothing when Discord is missing, updates only when the state changes (Discord limits how fast presence may change), never per frame, and cleared on quit.
  - [ ] V9.4 The states, with their wording in one data table so it can change without code: menus, loadout and unlocks, the map ("Floor 4 of 10", marked DAILY RUN or seeded), a round (the round number and the time since it started), a boss fight (the boss's name), shop and rest, and the run summary (run over with the score, or run won). Nothing personal: no file paths, and no account name unless the player is logged in and has not turned the setting off.
  - [ ] V9.5 A settings row **DISCORD PRESENCE** (ON by default, a first guess); OFF clears it and stops sending. Listed in `docs/SAVE_FILES.md` and on the privacy page: presence goes only to the Discord app on the player's own PC, nothing goes to our website.
  - [ ] V9.6 `tools/presence_check.gd` with a recording backend: each state sets the right text, a long round does not spam updates (the updates are counted), OFF clears, a missing backend is harmless, and the texts fit Discord's current length limits (look them up).
  - [ ] V9.7 **Owner:** with Discord running, go through every state and read your own profile; close Discord in the middle of a run and start it again; play once with Discord not installed or closed.
  - [ ] V9.8 Optional: a button on the presence that opens the website's landing page `/fb3d/`. Join and invites are not part of 0.3.0.
- [ ] **V10. Gate: the 0.3.0 release**. Done when a stranger can install 0.3.0, log in, sync, update and uninstall without anything breaking.
  - [ ] V10.1 `python tools/run_checks.py --full` ends with ALL PASSED, the secrets scan (V1.4) is clean, the website tests pass, and CI is green with the new jobs.
  - [ ] V10.2 Soak tests: a first start offline; the website going down in the middle of a run; a token expiring in a round; two PCs in conflict; an update from 0.3.0 to a 0.3.1 test build; the game killed during a download; then read the Godot logs and open the save files, as in alpha E3.
  - [ ] V10.3 `config/version` to `0.3.0`, `docs/NOTES_0_3.md` (like `docs/ALPHA_NOTES.md`: how to run it, what is new, known issues, where to report, and that 0.2.0 does not update itself), and the tag `v0.3.0` (the owner decides).
  - [ ] V10.4 Website: deploy the API (migrations, nginx limits, gunicorn restart), check that the cloud saves are in the site's backups, update the privacy page (what the game sends: the version check; what is stored: the login and cloud saves; presence stays on the PC), and rotate the API key once to prove the rotation works.
  - [ ] V10.5 Publish the build through the superuser page, then the article for it on the site (alpha W5's rule: move things from planned to implemented), with what is still missing updated on it.
- **Not in 0.3.0, on purpose:** online leaderboards and score submission, the account overview and progression pages, log upload with bug reports, background (silent) downloads, anything for macOS or Linux (Windows only, like the alpha), Steam or itch.io, and Discord join and invites. They stay in Milestone N and the milestones below.

# Early Alpha Roadmap (v0.2.0): done

> The early alpha is finished: every box of its roadmap is ticked. The whole roadmap (the loop, the working order, sections A to E, the website milestone W, the "Not in the early alpha" list and the 2026-10-27 roadmap audit) moved to [`docs/ALPHA_ROADMAP.md`](docs/ALPHA_ROADMAP.md) on 2026-10-29, and what was shipped is in [`docs/ALPHA_NOTES.md`](docs/ALPHA_NOTES.md). Ids like "alpha D1", "A1.6", "C4" or "W5" elsewhere in this file point into that document.

---

# Roguelite Development Roadmap

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Roguelite Development Roadmap". Only what is still open stays here.

> The game is already most of the way to a roguelite. It has runs made of rounds, a shop, perks that pair into duos, and bosses. Almost everything on this list is a layer on top of that, plus the missing "between runs" progression.

## Big Design Choice

### Recommended Roguelite Structure

- [x] Add final boss encounter (reuses the golden president model)
  - [ ] Give the final boss its own model, attacks and arena moment

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

## Meta Unlocks

- [ ] Unlock additional weapons in shop pool (wording out of date: weapons are bought and then chosen on the Loadout page, never found in the shop; see alpha A1.6)
- [ ] Unlock cosmetics

## Difficulty Scaling

- [ ] Implement Heat system
- [ ] Allow multiple Heat modifiers
- [ ] Increase rewards for higher Heat levels

## Cosmetics & Skins

### Weapon Cosmetics

- [ ] Dart gun skins
- [ ] Worm skins

### UI Cosmetics

- [ ] Crosshair skins
- [ ] Hit effect skins

### World Cosmetics

- [ ] Cheerleader skins
- [ ] Rider bike skins
- [ ] Rider helmet skins

### Easy Cosmetic Variants

- [ ] Colour swaps
- [ ] Material swaps

---

# Milestone C: Weapon System Expansion

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone C: Weapon System Expansion". Only what is still open stays here.

## Weapon Slots

### Choosing weapons: unlock, then pick a loadout

> Decided with the owner. New weapons are **bought first** with meta coins on the Unlocks page (the four weapons are already in `data/unlocks.json` as `planned`; the dart gun is bought too since alpha C2, `weapon_dart_gun`; **the melee weapon is not meant to stay always owned: see "Melee weapon is locked at the start" below**). Before a run the player **chooses one weapon per slot** (primary, melee, gadget) on the Loadout screen, and the run starts with those three equipped through `equip_primary`, `equip_melee` and `equip_gadget`. Weapons are not found or bought inside a run, so they leave the shop pool (the "joins the shop pool" note in `data/README.md` changes when the first weapon is built). **A Daily Run still allows choosing a loadout** of weapons (everyone shares the seed, not the weapons). Q / wheel / 1 / 2 keep switching between the primary and the melee weapon; a gadget is used on the spot with its own key and is not switched to. Assumed slots for the new weapons: Suction-Dart Crossbow, Confetti Cannon and Phone Launcher are primary weapons, the Stink Bomb is a gadget (say if the Phone Launcher should be something else). Decided: a custom-seed run uses the chosen weapons too, and the starting perk of the Loadout page now applies in a Daily Run and a custom-seed run as well (it did not before).

- [ ] HUD slot display: show the primary, melee and gadget slots with the weapon in each and the one in the player's hands highlighted (replaces the `DARTS / [Q] SWITCH` text in the bottom right)
- [ ] Gadget use key (keyboard and gamepad button): uses the gadget on the spot, with a cooldown or a number of uses shown in the HUD slot display; built together with the first gadget (Stink Bomb)
- [ ] Melee weapon is locked at the start, and unlocks very fast: **after the alpha** (decided with the owner in C1: for the alpha the melee weapon stays owned from the start). The full text is under "Not in the early alpha" in the Early Alpha Roadmap.

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
> **Added 2026-10-28 (owner): a bunch of new weapons, melee variants and gadgets** (the rest of this section, up to "Synergies"). They follow the same rules as the weapons above: a new weapon is **bought first** on the Unlocks page (an entry in `data/unlocks.json` with `kind: "weapon"`, a name, a description and a tier of the price curve, `planned: true` until it is built), then **chosen on the Loadout page**, and never found in the shop pool. The tiers named below are first guesses (the price curve is 60, 120, 250, 450 and 750 coins), and so is every number. **A new weapon is done when:** (1) its numbers are in `data/weapons.json` and described in `data/README.md`; (2) it is listed in the constant of its slot in `scripts/weapon_slots.gd` (`PRIMARY_WEAPONS`, `MELEE_WEAPONS` or `GADGET_WEAPONS`); (3) a `tools/<name>_check.gd` covers what is special about it (the runner finds it by its name, no `.bat`); (4) `python tools/run_checks.py offer_sense` passes, because that check goes through every weapon in `PRIMARY_WEAPONS`: decide for each new primary weapon what the ammo drops, FREE DARTS, the cache ammo reward and the clip upgrades mean for it (the same question as B9.2), and give the entries that do nothing for it a `needs` (`data/README.md`, "What an entry needs to matter"); (5) the owner plays a run with it. Run only the checks of the code touched, not the whole suite (testing rule).

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

- [ ] Implement weapon: a cone of pellets per shot (first guess 8), a clip of 2, reload shell by shell (so a reload can be interrupted), range about 20 m
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

> The gummy worm (`melee` in `data/weapons.json`: 0.3 s cooldown, damage 2, it deflects phones) stays the starting melee weapon and the baseline. Each variant below has **one quirk that makes it play differently, not just a bigger number**. They sit in the melee slot (`MELEE_WEAPONS`, read through `melee_stats()`), are bought on the Unlocks page (tiers 1 to 3 as a first guess) and chosen on the Loadout page; the melee lock at level 5 stays out of the alpha (see "Not in the early alpha"). Q, wheel, 1 and 2 keep switching between the primary and the melee weapon. The Melee Reach upgrade (`reach_per_level`) applies to every variant, and every variant still deflects phones (a quirk may make it do that better or worse, never not at all).

- [ ] Audit the melee code for what is tied to the gummy worm (the swing, the HUD name, the deflect, Melee Reach, the `round_no_gun` rule) and make it read `melee_stats()` everywhere, so the first variant does not need special cases
- [ ] **Pool Noodle** (tier 1, 60 coins), quirk **reach and sweep**: the longest reach and a wide arc, so one swing can hit several riders; damage 1, so it needs a few hits, and the longest deflect range of all
  - [ ] Implement weapon, and the sweep (every rider inside the arc is hit once per swing)
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

> Gadgets go in the gadget slot (`GADGET_WEAPONS`, read through `gadget_stats()`), which is empty today because no gadget exists. A gadget is used on the spot with its own key and gamepad button (the "Gadget use key" item above, built together with the first one) and has a **cooldown or a number of uses per round**, shown in the HUD slot display. The Stink Bomb above is the first gadget; these are more. Rules for all of them: a gadget never harms or affects a pedestrian or a cheerleader (a civilian hit loses the run), and no gadget effect is a chance roll, so the same seed plays the same in the Daily Run. Tiers 1 to 4 as a first guess; each gets a five-tier upgrade path later (uses, cooldown, area, duration).

- [ ] **Banana Peel Trap** (tier 1, 60 coins): placed on the ground in front of the player, 3 uses per round; the first rider to ride over it crashes and is stunned for a few seconds; it stays until triggered or the round ends
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

## Run Structure

### Map Nodes

- [ ] Event (left out of the alpha, event weight set to 0 in alpha B5)

## Relics

- [ ] Implement relic system
- [ ] Add rule-changing relic effects

## Curses

- [ ] Add risk/reward curse system

## Round Modifiers

- [ ] Night modifier (the NIGHT theme exists and nodes use it, but not as a modifier a node can add)
- [ ] Rain modifier (nodes can carry it, but it has no effect; switched off in alpha B5)
- [ ] Additional modifier ideas

---

# Milestone E: Polish & Accessibility

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Milestone E: Polish & Accessibility". Only what is still open stays here.

## Dynamic Presentation

- [ ] Dynamic music system
- [ ] Scale intensity with style rank

## Onboarding

- [ ] Short tutorial
- [ ] Key rebinding

## Accessibility

- [ ] Directional warning sounds for riders: a bike bell or horn from a rider that is close and approaching from behind or the side (louder and panned by its direction, louder the closer it gets and the faster it closes), so a player can hear what the threat arrows and the radar show; also helps players who miss visual cues. Builds on the 3D audio item S7 and `closing` and `dist` in `threat_list` (`scripts/main.gd`); a setting to turn it off or make it quieter
- [ ] English localization

## Code signing

> Added 2026-10-27 at the owner's request. A certificate Windows trusts costs money, so the first step is a **self-signed** one, which is possible and free. What it gives and what it does not (checked against Microsoft's [Code signing options for Windows app developers](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options)): the exe carries a signature that shows it was not changed after signing, and Windows treats it as signed on a computer where the certificate was installed as trusted (the owner's, or a tester's who chooses to). It does **not** remove the SmartScreen or "unknown publisher" warning for anybody else: Windows does not trust a self-signed certificate by default, and Microsoft describes it as meant for development, testing and internal use, not for public downloads.

- [x] Before any certificate file exists, extend `.gitignore` with `*.pfx`, `*.p12`, `*.pem`, `*.key` and `*.crt` (done together with V1.1).
- [ ] Create the self-signed code signing certificate on the owner's Windows machine (Godot's Windows export page links Microsoft's guide for creating one; in PowerShell `New-SelfSignedCertificate -Type CodeSigningCert` is the usual way). Export it as a `.pfx` with a password and keep the file and the password outside the repository (the owner's user folder and a password manager). Write the certificate's SHA-256 thumbprint and its expiry date in `docs/` (the thumbprint is public, the file and the password are secret) so testers can compare it.
- [ ] Decide `binary_format/embed_pck` in `export_presets.cfg`. It is `true` today, and Godot's documentation says an exported exe with an embedded PCK breaks signing (it also says embedding can trigger antivirus false positives). Signing means `false`: the export becomes `FB3D.exe` and `FB3D.pck` side by side, and the E2 smoke test (E2.2, E2.3) and the installer in Milestone N have to treat the two files as one build.
- [ ] Set up the export: `SignTool.exe` from the Windows SDK, its path in Editor Settings > Export > Windows (Sign Tool), and in the Windows preset `codesign/enable=true` with the identity type and the `.pfx` as identity. **Leave the password out of the tracked `export_presets.cfg`**: Godot reads it from the environment variable `GODOT_WINDOWS_CODESIGN_PASSWORD` (the identity type and the identity have `GODOT_WINDOWS_CODESIGN_IDENTITY_TYPE` and `GODOT_WINDOWS_CODESIGN_IDENTITY`), the same rule as the PCK encryption key under "Secrets and credentials". Decide whether to timestamp (`codesign/timestamp` is `true` and `codesign/timestamp_server_url` is empty today); a timestamp keeps the signature valid after the certificate expires.
- [ ] Export and verify: FB3D.exe > Properties > Digital Signatures shows the signature, and `signtool verify /pa build\windows\FB3D.exe` reports it as untrusted on a computer without the certificate (expected) and as valid after the certificate was imported as a trusted root and trusted publisher on the owner's test machine. Then repeat E2.2 and E2.3 with the signed build: it starts and the saves are still found in `user://`.
- [ ] Tell testers in `docs/ALPHA_NOTES.md` (E4.2): the build is self-signed, here is the thumbprint, Windows will still warn, and importing the certificate is optional and only for people who trust the owner (it makes Windows trust anything signed with it). Never ask a player to import it.
- [ ] Before a public release, decide about a certificate Windows trusts (the "decide about code signing" part of Milestone N "Installer and auto updates"). The options on Microsoft's page, with prices as of 2026-10-27: Azure Artifact Signing, about $9.99 a month (individuals only in the USA and Canada, organisations in the USA, Canada, the EU and the UK); an OV certificate, $150 to $300 a year, worldwide, with the private key on a hardware token or HSM; an EV certificate, $400 or more a year, which since 2024 no longer skips SmartScreen and so is not worth the premium for that; and [SignPath Foundation](https://signpath.org/)'s free signing for open source projects, where the signature is issued to SignPath Foundation and not to the owner (this repository is public but has no `LICENSE` file today, so read their conditions first). All of them still show SmartScreen warnings until the signed program has built up a reputation.
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
- [ ] Golden president / final boss (model, animation, intro moment)
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
- [ ] HUD top bar (hearts, score, round, round progress)
- [ ] HUD bottom (ammo, dash, style rank), crosshair and hit marker
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

# Milestone G: Procedural Map Generation

> **Done, every item is ticked.** The full milestone (seed-based map generation, the generation rules, the completability check, the seed debug tool and the custom seed page) moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29. The rules are explained in [`docs/MAP_GENERATION.md`](docs/MAP_GENERATION.md). The heading stays here so references to "Milestone G" still find it.

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

## Exploration and extraction

> The round no longer ends by itself when the last rider falls. Supply caches are spread over the (now bigger) arena for the curious, and once every rider and boss is down an extraction point opens at the far end and the round is cleared when the player walks into it. Built on branch `rework/caches-extraction-point-fresnel-wip-crash-on-round-end`, which is a work in progress (commit "WIP rework", then "Crash fix"): nothing here is ticked off as playtested, and the lines that say "waiting for your in-game check" are still to be played. The roundabout has none of it (`objective_sys.enabled()` is false there) and plays as before.

- [ ] Caches with a catch (today they are pure reward): some of the 4 caches get a variant, chosen by the same seeded stream so the Daily Run gives everybody the same ones
  - [ ] Cursed cache: pays more but calls riders from the nearest gate when taken
  - [ ] Locked cache: needs a key that is found at another cache or dropped by a rider
  - [ ] Vanishing cache: a countdown starts when the player comes within range, so it has to be taken quickly
  - [ ] Mark the variants on the HUD and the radar so the player can tell them apart (colour and shape, not colour alone)
- [ ] Choose your exit: the arena has several gates and the run map branches, so the extraction point could be one per exit gate, each matching a next node on the map (the player leaves through the gate of the node they want), instead of one fixed point. Needs the node choice (`pick_node`, Milestone D) to be made on the way out instead of on the map screen, and the HUD, radar and world markers to show more than one point

## Rider variety and arena hazards

> Riders ride at the player, pass, turn and come back (`scripts/riders.gd`). On the bigger arena a few more patterns would make fights different from each other, and the buildings the arena already has could be part of the fight. Ideas to decide on before building; each must keep `rider_pursuit_check` and `round_clear_check` working (a round still ends when every rider is down, so no pattern may leave a rider that cannot be reached).

- [ ] Riders that flank in pairs: two riders that come in by different gates and reach the player from two sides, or one that peels off to the side while the other rides straight on
- [ ] Ambush rider: waits behind a building near the player's path and rides out when the player comes within range (needs `Arena.rider_blocked` and the sight rule `Threats.sight_clear` to pick the spot; show it on the radar only once it moves, and decide how it reads with the rim glow)
- [ ] Heavy rider that blocks a road: slow, tough and wide, it rides along a road and forces the player to go round or shoot it down; check that the other riders' obstacle avoidance (`avoid_obstacles`) copes with it
- [ ] Riders crash on the arena: a rider that hits a building, lamp post or tree at speed crashes (the crash and falling-parts effects of F4 and F10 are the model), and a startled pedestrian group can be ridden into, so the player can use the arena as a weapon. Decide what a crash pays (score, style, a `kill` for the round count) and make sure a rider that crashed by itself still counts as down
- [ ] Add the new rider kinds to the map content (`scripts/map_content.gd`, `rider_plan`) and the rider mix numbers in `data/map_rules.json`, so the node decides which of them appear

## Height: hills, walkways and stairs

> Every arena is flat today: the ground is made of flat meshes at y 0 (`WorldGen.build_ground`), and `Arena.surface_at` only says what the ground is made of, not how high it is. Small hills, raised walkways and stairs would turn the arena into real 3D ground to fight on. It is a big change because height touches the layout, the ground, the `Arena` interface, riders, aiming and jumping, so it is split into small steps, and the flat arenas and the roundabout must keep playing exactly as they do now until a step says otherwise. Milestone L (jumping) and this section affect each other (jump height, "Keep the player inside the arena while jumping"), so decide the numbers together.

- [ ] Raised terrain: small hills, walkways and stairs, so the arena is not just a flat map
  - [ ] Decide the height model before building anything: a height per cell beside the ground grid (steps of about 0.5 m, smooth for hills, stepped for stairs and ledges), how much height there is (small, up to about 3 to 4 m, so sightlines and the radar still work), what counts as walkable (a maximum slope and a maximum step), and whether bikes can ride slopes and stairs
  - [ ] Layout: `ArenaGen.generate` adds a height per cell from the seed (hills on grass and parks, raised walkways over roads and plazas, stairs where two heights meet), with the numbers in `data/arena_rules.json`; the same seed still gives the same arena, and a rule can switch height off so the flat arenas stay
  - [ ] Navigation and validation: the nav grid and `ArenaGen.validate` know climbable and not climbable (a slope or step too steep is a wall), and every gate, cache and the extraction point must still be reachable on foot and by riders, with no cache or start spot inside a hill
  - [ ] Build the ground from the heights in `WorldGen` (hill meshes, stair treads and risers, walkway decks with edges or railings, retaining walls), and stand buildings, props and lamps at the right height in `WorldDress`; the surface, curbs and markings must follow the slope
  - [ ] Height in the `Arena` interface: a `height_at(p)` query, the roundabout and flat arenas answering 0; `clamp_walk`, `obstacle_at`, `surface_at` and `start_position` use it, and the player walks up slopes and stairs smoothly (step-up, no jitter) and stands on the ground height
  - [ ] Riders, pedestrians, bosses and pickups follow the ground height (steering and speed on slopes, spawning at the right height, `rider_speed_at` on stairs), and decide where a rider cannot go (stairs) and how `avoid_obstacles` treats it
  - [ ] Combat and sight with height: darts, aim assist, `ray_blocked`, `Threats.sight_clear`, the radar and the threat arrows, thrown phones and the boss attacks (strips, slam circles, volleys) still work when the rider is above or below the player
  - [ ] Show height in the tools: the arena viewer (`tools/viewer/arena_viewer.tscn`) shades or draws contour lines by height, and a check over many seeds (with a `.bat` script) tests reachability, slopes and that nothing clips into a hill
  - [ ] Playtest and balance: does height make fights better or does it hide riders, are stairs and walkways fun to use, and the cost in frame time on the minimum-spec machine

## Scale, variety and polish

- [ ] Performance pass for the bigger arena (draw distance, culling, shadow and light counts) on the minimum-spec machine (the arena is now 144 m square, about 8 to 12 times the roundabout instead of 4, so the walkable ground, the buildings, the lamps and the gates all grew, and the 4 gold and 1 green light column of the objectives are new draw cost; frame time on weak hardware is not known)
- [x] Arena styles chosen by the seed: plaza, street canyon, market, bridge, tunnel, park (replaces the hand-built arenas in Milestone D)
  - [ ] Look and feel of the bridge and the tunnel: they are walled placeholder boxes with no water edge, no roof or ceiling and the same ground surfaces as the other styles; decide on water or a drop beside the deck, a roof or ceiling lights for the tunnel and a different ground (planks, tiles)
  - [ ] Playtest and balance each style: rider speed, sightlines and run length per style, how a bridge with only 2 gates plays against 3 to 6 riders, whether a tunnel's short sightlines are fair, and the weights (all 1 now; a style can be made rarer by lowering its `weight`)
  - [x] Show the style on the run map or the title screen
  - [x] Show the style on the run map screen too

---

# Milestone L: Jumping

Jumping on Space, so the movement feels like a modern FPS. Space is the dash key today (and the gamepad A button), so the first step is to give dash a new key.

> Feel goal: fast-paced, like a Quake game. Sprints, jumps and dashes chain into each other, and the player can aim and shoot while airborne. Every decision below should be judged against that.
>
> Movement inspiration: the game S4 League (fast, acrobatic third-person shooter movement with wall-jumps, dashes and dodges that chain into each other). Take the feel of the movement, not the exact rules or numbers.

- [ ] Decide the new dash key and gamepad button (Space and A are taken by jumping), and move dash there in the input map, the key rebinding list, the Controls page and the HUD hint under the dash bar
- [ ] Jump on Space: a short hop with gravity, a fixed jump height and some air control (decide the numbers while building it; coyote time and jump buffering make it feel right)
- [ ] Jump on the gamepad (A) and add it to the key rebinding list and the Controls page
- [ ] Decide how jumping mixes with sprint, crouch, slide and dash (can you jump out of a slide, dash in the air, shoot and aim while airborne)
- [ ] Fast, Quake-like movement flow: sprint into a jump without losing speed, start a dash from the air or out of a jump, keep momentum through the landing, and aim, shoot and throw while airborne with no penalty to aim; tune it so chaining sprint, jump and dash is clearly faster than walking and every step of it can be cancelled into the next (decide the numbers while building it, and check it does not make riders, bosses or the arena size feel too small)
- [ ] Wall-jumps (S4 League style): jump off a wall or other solid surface while airborne next to it to get pushed away from it and upwards, with a short window after contact, a limit on how many wall-jumps can chain before touching the ground, and momentum kept through the jump so a run of them climbs or crosses a gap; decide which arena surfaces allow it (buildings and walls yes, the fountain and props to be decided), and check the `Arena` bounds queries (`clamp_walk`, `obstacle_at`) so a wall-jump can never lift the player over the arena edge, which is covered by the "Keep the player inside the arena" item below
- [ ] Side dash / dodge (S4 League style): a quick sideways burst to the left or right, taken from the ground or from the air, with its own short cooldown and key or double-tap input (decide with the dash key above), that can be chained out of a jump, a wall-jump or a sprint and into the next move; decide how it relates to the existing dash and its bar (a separate charge or the same one), and whether a side dash at the right moment counts as a PERFECT DODGE (see the dodge item below)
- [ ] Decide whether jumping over a passing rider counts as a dodge, and keep the PERFECT DODGE rule working as it does now
- [ ] Keep the player inside the arena while jumping: the height must not let the player clear buildings, props or the fountain, so the `Arena` bounds queries (`clamp_walk`, `obstacle_at`) still hold in the air
- [ ] Camera and gun feedback for take-off and landing (viewmodel dip, a small camera kick) and the jump and landing sounds (builds on "Footsteps, landing, slide and dash" in S2)
- [ ] Check darts, melee, hit boxes, aim assist and the radar while airborne
- [ ] Playtest and tune the feel: jump height, gravity, air control, wall-jump push and side dash distance

---

# Milestone M: First and Third Person View

Today the game is first person only (the camera is the player's eyes and the gun and club are a separate viewmodel, see F2). This milestone adds a third-person view and a way to switch between the two at any time. It pairs well with the acrobatic movement in Milestone L, because wall-jumps and side dashes read much better when the player can see their own body, but it does not depend on it.

- [ ] Toggle between first and third person with a key and a gamepad button (decide which, for example a key near the camera and mouse controls), add it to the key rebinding list and the Controls page, and remember the choice in the settings file (see `docs/SAVE_FILES.md`); the switch works mid-round, in the air and while shooting, and pauses nothing
- [ ] Build the third-person camera: behind and over the shoulder, with the camera pulled in when a wall or prop is in the way (so it never clips through the arena), smooth follow and a short blend when switching from first person, plus a FOV and distance that keep riders and bosses readable
- [ ] Player body model for the third-person view (needs a model, since the player has no visible body in first person) built with the model pipeline in `tools/models/`, with idle, walk, sprint, slide, jump, dash and hit animations (the movement ones follow Milestone L); hidden or reduced in first person so it never blocks the view
- [ ] Weapons in third person: the dart gun and the jelly club held by the player model instead of the first-person viewmodel (`scripts/viewmodel.gd` is off in this view), with the muzzle flash, shell ejection, pump animation and club swing still working; the ammo count on the gun and the HUD ammo stay readable
- [ ] Aiming in third person: the crosshair shows where the dart really lands (no mismatch between the camera and the gun), aim-down-sights works with a closer camera, and aim assist, hit boxes and melee reach behave the same as in first person; decide whether a third-person shot starts at the gun or at the camera ray
- [ ] Check every system in both views: threat arrows and the radar, the damage and hit flashes, PERFECT DODGE, the caches and the extraction point, the map and menus, and the screen shake option (`fx_scale`); riders and bosses must not be able to hide behind the camera
- [ ] Playtest and tune both views: camera distance and height, blend speed and whether third person feels fair against riders coming from behind (it must not be a clear advantage or a clear disadvantage compared to first person)

---

# Milestone N: Website, Launcher & Online Services

The game gets a home on the web: a new Django app on the existing website (Django + PostgreSQL + nginx + gunicorn, already running), a launcher where players log in, cloud saves, leaderboards, bug reports, and a proper installer with auto updates. Planning only for now: nothing below is built yet, except what the early alpha's website milestone (W) builds first: the app `fb3d`, its Info articles and its Feedback section.

> **Being built now (2026-10-29):** the first release that builds this milestone has its own working plan, the **Web Integration Roadmap (v0.3.0)** near the top of this file (ids V1 to V10): secrets and `.gitignore`, the version and git hash, the API and its key, the update check, the launcher and login, the installer and auto updates, save protection, cloud saves, and Discord Rich Presence. An item there that also exists below is the same work: tick both, and write the long note under the V heading in `docs/ROADMAP_HISTORY.md`. Leaderboards, the account page and the game-side bug report log stay below for after 0.3.0.

> Design rules: the game talks to the website only through a REST API. The website, not the game, is the authority on accounts, XP and levels, leaderboards and which version is current. Only the superuser can publish a new game version. An account is optional (decided): the whole game, with its local saves, leaderboard, unlocks and XP, works without one, and a player who never logs in only misses the web features (cloud saves, online leaderboards, the account page, bug reports through the game). A missing network or a down website never blocks a run either, it only delays syncing.

## Website: Django app and REST API

- [x] Create a new Django app for the game on the existing website (**the app is called `fb3d`, decided 2026-10-28, and is built first for the early alpha as W1 to W4**; the URL prefix is a first guess `/fb3d/`), with its own models, migrations, templates and tests, so it does not touch the rest of the site
- [ ] Write down the REST API in a short doc (`docs/WEBSITE_API.md`): endpoints, request and response shapes, error codes, auth headers, the API version in the URL (so an old game build keeps working after the API changes), and rate limits
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
- [ ] Store the key encrypted: on the server only a hash (or the key in an encrypted settings value, not in the repo or in plain text in the database), and in the game build encrypted and obfuscated, not as a plain string in a script or in `project.godot`; keys are never committed to the repository (`.gitignore` and a secrets check in CI)
- [ ] Support key rotation: the server accepts a new and an old key for a while, the game build carries the current one, and a leaked key can be switched off from the Django admin
- [ ] Be honest about the limit in the docs: a key inside a game that runs on the player's PC can be extracted by someone determined, so it is one layer, not the only one. The server must still check the player's token, validate every submitted score and save, and rate-limit per account

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

## Keeping secrets out of the public repository

- [ ] Turn on GitHub secret scanning and push protection for the repository (Settings > Code security), so a push that contains a known key format is blocked
- [x] Extend `.gitignore` before any secret file exists (done as V1.1 of the Web Integration Roadmap)
- [x] Add an example file with fake values (for example `secrets.example.cfg`) that shows what the game or the build expects, and have the game, the launcher and the build scripts read the real values from an untracked file or an environment variable (the template and the game's loader are V1.2 of the Web Integration Roadmap; the build scripts do not exist yet and read the same environment variables when they are written, V2.5 and V4.1)
- [x] Add a pre-commit check that stops a commit if the staged changes contain a key-like string (done as V1.4 of the Web Integration Roadmap: `tools/secrets_check.py`, no `.bat` needed since the testing rule changed on 2026-10-27)
- [x] Add a secrets check to CI that fails a pull request when it finds one (done as V1.5 of the Web Integration Roadmap: the `secrets` job in `.github/workflows/ci.yml`)
- [x] Decide where the real keys live and write down who has them and how to rotate them (done as V1.7 of the Web Integration Roadmap: [`docs/SECRETS.md`](docs/SECRETS.md))
- [x] Write a short "a key leaked" procedure in `docs/` (done as V1.7: "A key leaked" in [`docs/SECRETS.md`](docs/SECRETS.md))
- [ ] Do a one-time look through the existing history for anything key-like before the web integration starts (nothing was found in the current files)

## Suggested order inside this milestone

> Roughly: API doc and Django app, then accounts and login, then the launcher, then the API key, then save protection (before saves go online, so no unprotected save is ever uploaded), then cloud saves, then leaderboards, the account page and XP, then bug reports, and last the installer and auto updates (they need a stable launcher and API first). **For 0.3.0 the order differs on one point:** the installer and auto updates come right after the launcher and before save protection and cloud saves, because they never touch saves or accounts and testers then receive the sync release by auto update (see the Web Integration Roadmap).

---

# Tooling & QA

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Tooling & QA". Only what is still open stays here.

- [ ] Playtest pass of everything built in Milestone A (title, pause, settings, run, win / lose, leaderboard, name entry). It was written without running the game
- [ ] Bot playthrough balance harness: a headless script (`tools/bot_run.gd` with a `tools\\run_bot_run.bat` next to it, as the testing rule asks) where a simple bot plays whole runs on many seeds (aims at the nearest rider, dashes away from a threat that is about to hit, takes the nearest cache, walks to the extraction point) and logs, for every round, the time, lives lost, damage taken, kills, caches taken and whether it reached the extraction point; a summary per seed and across seeds gives real numbers for the playtest and balance items in Milestone K, the 10-round difficulty curve and the run length target. Reuse `tools/generated_run_check.gd` for the scripted run; the bot does not have to be good, only the same every time, so changes show as changes in the numbers

---

# Technical Refactor (Recommended Before Milestone D)

> Finished sections and ticked items of this milestone moved to [`docs/COMPLETED_MILESTONES.md`](docs/COMPLETED_MILESTONES.md) on 2026-10-29, under "Technical Refactor (Recommended Before Milestone D)". Only what is still open stays here.

## Future-Proofing

- [ ] Make weapon additions easier
- [ ] Make relic additions easier
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
- [ ] Milestone J: Manual reload (small and independent, can be done at any time)
- [ ] Milestone K: Procedural arenas (big: replaces how riders and bosses move; start with the "Foundation" steps, which keep the roundabout playing as today)
- [ ] Milestone L: Jumping (small and independent; Space is the dash key today, so dash moves to another key first); now also holds the fast S4 League style movement: wall-jumps and the side dash / dodge
- [ ] Milestone M: First and third person view (needs a player body model; best after Milestone L, so the new movement can be seen on the character)
- [ ] Milestone N: Website, launcher and online services (Django app and API, login, cloud saves, save protection, leaderboards, bug reports, installer and auto updates; mostly independent of the gameplay milestones, but XP and levels live in Milestone I, and the online leaderboard builds on Milestone A)