# Secrets: where they live, who has them, how to rotate them

This repository is **public**, with every old commit. A secret that was ever pushed is stolen, and deleting it in a later commit does not help. The rules for what never goes in are in [`README.md`](../README.md) ("Secrets and credentials"); this file says **where each real key lives**, **who has it** and **how to replace it**, and what to do when one leaks.

Most of these keys do not exist yet. The table says which ones are planned, so the place is decided before the key is made. **Owner** means the repository owner. Nobody else holds any key until this file says so; when someone gets one, write it here.

## Where each key lives

| Secret | Lives in (and only there) | Who has it | Status |
|---|---|---|---|
| Game-to-website **API key** (`X-FB3D-Key`, V3.4) | Website: only a **hash** of it (HMAC-SHA256 with the key pepper below), in the site's database, several keys can be active. Build machine: the environment variable `FB3D_API_KEY`, which `tools/build_release.py` (V4.1) writes into an untracked, obfuscated file that the export includes. Development: `FB3D_API_KEY` or the untracked `secrets.local.cfg` | Owner | Planned (V3.5, **Owner** creates it) |
| Website **key pepper** (`FB3D_API_KEY_PEPPER`, V3.4): the secret the API keys are hashed with | The **website server's** environment (the site's `app/.env`), never in the database, this repository or the build machine. Set it **before** the first key is made | Owner | Planned (V3.4 deploy, **Owner** sets it) |
| API base URL (`FB3D_API_BASE_URL`) | Same places as the key. Not a secret on its own, but a debug build reads it from the same file | Owner | Planned |
| Django `SECRET_KEY`, database password, other site settings | The **website server's** environment or a settings file outside the site's repository | Owner | Exists on the site; not in this repository and not to be copied here |
| Player login and refresh tokens (V5) | The player's PC, in an encrypted file in `user://` (V5.4); on the server only as revoked or valid records | The player | Planned. Never in a log, a commit or a screenshot |
| Release **manifest signing key** (V6.4) | The owner's machine only. **Never on the server, never in the repository.** The game carries the public half | Owner | Planned |
| Windows **code signing certificate** (`.pfx`) and its password (Milestone E "Code signing") | The owner's Windows machine. The password only in the environment variable `GODOT_WINDOWS_CODESIGN_PASSWORD` (also `GODOT_WINDOWS_CODESIGN_IDENTITY` and `GODOT_WINDOWS_CODESIGN_IDENTITY_TYPE`), never in `export_presets.cfg` | Owner | Planned |
| Godot encryption keys (`GODOT_SCRIPT_ENCRYPTION_KEY`, the save encryption key of V7.2) | The build machine's environment; the key field in the tracked `export_presets.cfg` stays **empty** | Owner | Planned |
| CI and release keys (anything a GitHub workflow needs) | **GitHub Actions secrets** (Settings > Secrets and variables > Actions). A workflow reads them as `${{ secrets.NAME }}` and the log hides them; never echo one | Owner (repository admin) | None yet: CI needs no secret today |
| Discord application ID (V9.2) | One data file or constant in the game. It is **not** a secret. A Discord client secret or token, if the chosen way ever asks for one, follows this table and is never committed | Owner | Planned |

Rule of thumb: a value goes in the environment of the machine that needs it. The repository holds only `secrets.example.cfg` with fake values.

## Rotating a key (a planned change, nothing has leaked)

Rotation must work before it is needed, so it is tried once at the 0.3.0 gate (V10.4).

1. **API key (V3.4).** Make a new key on the server (Django admin) so the old and the new one are both active. Put the new one in the build machine's environment (`FB3D_API_KEY`) and build and publish a release that carries it. Wait until the builds that carry the old key are no longer supported or in use (the key's "last used" time in the Django admin shows whether the old key is still in use). Then switch the old key off in the Django admin. Builds that still carry the old key then get `KEY_REJECTED` and the game tells the player to update. Changing `FB3D_API_KEY_PEPPER` is the same as replacing **every** key at once (all stored hashes stop matching), so do it only as part of a leak of the pepper: make new keys first, then change the pepper.
2. **Django `SECRET_KEY` and database password.** Change the value in the server's environment, restart the app. Changing `SECRET_KEY` logs everyone out and invalidates reset links; that is expected.
3. **Manifest signing key (V6.4).** Make a new key pair on the owner's machine and ship a release that carries the new **public** half signed with the old key, so installed games learn to trust the new one. Only then sign with the new key. If the old private key leaked, an attacker can sign packages the installed games accept, so this needs a release the players install by hand; write that case down before the first signed release.
4. **Code signing certificate.** Get a new certificate and sign the next build with it. A leaked certificate cannot be recalled by us; tell the certificate authority so they revoke it.
5. **GitHub Actions secret.** Create the new value at the service it belongs to, update the secret in the repository settings, run the workflow once, then revoke the old value at the service.

After any rotation, update the "Status" column above and the date in the log at the end of this file.

## A key leaked

A key leaked when it was pushed to this repository (or any fork), pasted into a chat, an issue, a log or a screenshot, or put in a file that was shared. **Do the steps in this order. Cleaning the history comes last, because the key is burned the moment it was public.**

1. **Tell the owner right away** (anyone, including an AI coding session, who finds one).
2. **Replace the key first.** Make a new one and switch the old one off or delete it at the service where it works (Django admin for the API key, the server's environment for Django secrets, GitHub's token page for a token, the certificate authority for a certificate). Put the new value only in the places listed in the table. Do not wait for the history clean-up.
3. **Check for misuse.** Look at the website's logs and the admin for calls made with the old key since it was pushed (unknown IPs, a burst of calls, scores or saves that do not fit a real player), and at the service's own activity page for any other key. Note what you found, even if it is nothing.
4. **Remove it from the repository.** Delete it in a normal commit so it is not in the current files. Then clean the history with `git filter-repo` (for example `git filter-repo --replace-text expressions.txt`, run on a fresh clone) and force-push the cleaned branches, which only the owner does. If GitHub's secret scanning raised an alert, close it only after step 2.
5. **Accept the limit.** Forks, clones, pull request refs and caches keep the old history, and anything that already read it keeps it. Step 4 does not make the key safe again; step 2 does. For a leak that GitHub still shows after the force push, ask GitHub Support to remove the cached views and the pull request refs.
6. **Write it down.** Add a line to the log below (date, which key, how it was found, what was done) without the value, and, if the way it got in was a gap in the checks, fix that gap (the scanner in `tools/secrets_check.py`, `.gitignore`, this table).

If the leaked thing is a **player's** data (a login token or a save from a log or an issue), delete it from where it was posted and tell the owner.

## The layers that try to stop it

1. `.gitignore` hides `secrets.local.*`, `.env`, `*.pem`, `*.key`, `*.pfx` and similar (V1.1).
2. `python tools/secrets_check.py --install-hook` makes `git commit` scan what is staged (V1.4). It can be skipped with `--no-verify`.
3. GitHub secret scanning and push protection block known key formats at `git push` (V1.3, the **Owner** turns it on in Settings > Code security).
4. CI runs `python tools/secrets_check.py --range BASE..HEAD` on every pull request (V1.5).
5. A look through the old history before the web work starts (V1.6).

None of them is complete: a short password with no name next to it passes the scanner. The habit that matters is reading `git diff --staged` before every commit.

## Log

| Date | What | Notes |
|---|---|---|
| 2026-10-30 | File written (V1.7) | No real key exists yet, nothing to rotate |
