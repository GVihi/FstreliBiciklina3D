# Website API, version 1

The contract between the game (`scripts/web_api.gd`, V4.1) and the website (a Django REST Framework app in the site's
own repository, built from V3.3). Written on 2026-10-30 for V3.2, **before anything is built**: every example below is a
plan, and the first build that disagrees with it must change this file in the same commit. What the site is like today
is in [`docs/WEBSITE.md`](WEBSITE.md); where each secret lives is in [`docs/SECRETS.md`](SECRETS.md).

**Status of the calls**

| Call | Needed by | Status |
|---|---|---|
| `GET ping` | V3.3 | specified here, built in V3.3 |
| `GET releases/current` | V4 | specified |
| `POST auth/login`, `auth/refresh`, `auth/logout` | V5 | specified |
| `GET me` | V5 | specified |
| `GET saves/current`, `PUT saves/current`, `GET saves/versions`, `GET saves/versions/<n>` | V8 | **draft**: V8.1 may change the body shape after it measures the real save files |
| leaderboards, scores, account page, bug reports | Milestone N, after 0.3.0 | not specified yet |

## Rules for every call

- **Base path:** `/fb3d/api/v1/` on the website's HTTPS host. The host is not written in this repository; the build
  carries it (V4.1). Plain HTTP is refused (a redirect is not enough, see `docs/WEBSITE.md`, fact 4): a call over HTTP
  gets `https_required` and the game never sends a password or token over it.
- **Format:** requests with a body are `Content-Type: application/json`, UTF-8. Responses are always JSON (except 204
  with no body). Anything else gets `unsupported_media_type`. No cookies are read or set; a session cookie is ignored.
- **Times** are UTC, ISO 8601 with a `Z`: `2026-10-30T10:02:02Z`. **Sizes** are bytes.
- **Unknown fields** in a response must be ignored by the game, so a field can be added inside `/v1/`. Unknown fields
  in a request are rejected (`bad_request`), so a typo does not pass silently.
- **No redirects.** The API never answers a call with a 3xx; the game does not follow one.

### Headers the game sends

| Header | Value | Required on |
|---|---|---|
| `X-FB3D-Key` | the game key (see "The game key") | every call |
| `X-FB3D-Version` | the version from `config/version`, e.g. `0.3.0` or `0.3.0-alpha` | every call |
| `X-FB3D-Build` | the short hash from `build_info.json`, e.g. `a1b2c3d`; `a1b2c3d+` for a dirty build, `dev` with no build info | every call |
| `Authorization` | `Bearer <access token>` | `auth/logout`, `me`, every `saves` call |
| `Content-Type` | `application/json` | calls with a body |
| `If-Match` | the save revision the client last saw | `PUT saves/current` |

`X-FB3D-Version` and `X-FB3D-Build` are **information, not proof**: the server uses them to decide "update required" and
to write logs, and never to trust anything. A missing or malformed `X-FB3D-Version` is `bad_request`. The key is checked
**before** these headers (see "The game key"), so a call with no good key gets `key_missing` or `key_rejected`, never `bad_request`.

### The one error shape

Every failure, including 404, 405, throttling and an unexpected server error, has this body and no other:

```json
{
  "error": {
    "code": "key_rejected",
    "message": "The game key was not accepted.",
    "retry_after": null
  }
}
```

- `code` is the stable part: lower case, digits and underscores, never renamed inside `/v1/`. **The game maps `code` to
  its own text and never shows `message`**, which is for logs and for a person reading a trace.
- `retry_after` is a number of seconds for `throttled` and `maintenance`, otherwise `null`. The same number is sent as a
  `Retry-After` header.
- A body never contains a stack trace, a SQL error, a file path, a token, a key or a password.

| HTTP | `code` | Meaning | Game result type (V4.1) |
|---|---|---|---|
| 400 | `bad_request` | wrong or missing field, unknown field, bad `X-FB3D-Version` | SERVER_ERROR |
| 400 | `invalid_json` | the body is not valid JSON | SERVER_ERROR |
| 401 | `key_missing` | no `X-FB3D-Key` | KEY_REJECTED |
| 401 | `invalid_credentials` | wrong username or password (the same answer for an unknown user) | UNAUTHORIZED |
| 401 | `token_missing` | no `Authorization` header on a call that needs one | UNAUTHORIZED |
| 401 | `token_expired` | the access token ran out: refresh, then repeat once | UNAUTHORIZED |
| 401 | `token_invalid` | the token is unknown, damaged or was revoked: log in again | UNAUTHORIZED |
| 401 | `token_reused` | a refresh token was used twice: the whole session was revoked, log in again | UNAUTHORIZED |
| 403 | `key_rejected` | the key is wrong, switched off or expired | KEY_REJECTED |
| 403 | `https_required` | the call came over plain HTTP | SERVER_ERROR |
| 403 | `forbidden` | the call is understood but not allowed for this account | SERVER_ERROR |
| 404 | `not_found` | no such path, release or save version | SERVER_ERROR |
| 405 | `method_not_allowed` | wrong HTTP method for this path | SERVER_ERROR |
| 409 | `save_conflict` | `If-Match` does not match the stored revision (see "Saves") | OK-with-conflict |
| 413 | `payload_too_large` | the body is over the limit of that call | SERVER_ERROR |
| 415 | `unsupported_media_type` | not `application/json` | SERVER_ERROR |
| 422 | `save_invalid` | the save failed the server's checks (see "Saves") | SERVER_ERROR |
| 422 | `save_format_too_new` | the save's format is newer than this server understands | SERVER_ERROR |
| 426 | `update_required` | this build is older than `minimum_version`; the call is online-only | UPDATE_REQUIRED |
| 429 | `throttled` | too many calls; wait `retry_after` seconds | SERVER_ERROR |
| 500 | `server_error` | a bug on the server | SERVER_ERROR |
| 503 | `maintenance` | the site is down for work | OFFLINE |

OFFLINE and TIMEOUT never come from the server: they are what the game reports when it got no answer. A status the
table does not list is treated as `server_error`.

### Limits

All numbers are **first guesses** to be measured in V3.3 and V8.1; the doc and the code are changed together.

| What | Limit |
|---|---|
| Request body, auth calls | 4 KiB |
| Request body, `PUT saves/current` | 256 KiB (the four save files are small; V8.1 measures) |
| nginx `client_max_body_size` for `/fb3d/api/` | 300k, a little above the largest call, so nginx stops oversized bodies before Django does |
| Rate, any call, per IP | 120 per minute (built in V3.3; the default in-memory cache is enough for the one-worker site). A call with a missing or wrong key counts too (V3.4) |
| Rate, `auth/login`, per IP | 10 per minute |
| Rate, `auth/login`, per username | 5 per 10 minutes (on top of the site's 5 s pause) |
| Rate, `auth/refresh`, per session | 30 per hour |
| Rate, `PUT saves/current`, per account | 30 per hour |
| Rate, other authenticated calls, per account | 120 per minute (the throttle is built in V3.3; it counts once tokens exist, V5) |
| Access token life | 15 minutes |
| Refresh token life | 30 days, **renewed on every refresh** (rotation) |
| Versions of a save kept per account | 5 (V8.1 decides) |

A throttle answer is `429 throttled` with `Retry-After`. The game never retries in a loop: one repeat after the
`Retry-After` time at most, and only when the player is waiting for it (V4.1).

### Breaking changes

A change is **breaking** if an old game build would misread or fail on it: removing or renaming a field, a path, a
`code` or a header, changing a type or a unit, or making an optional field required. A breaking change gets a new
**`/v2/`** with the whole set of changed calls. `/v1/` keeps running **as long as any supported build uses it**:
"supported" means at or above `minimum_version` of `releases/current`. Raising `minimum_version` is the way to retire a
version, and `/v1/` is switched off only after that. Not breaking, so allowed inside `/v1/`: a new call, a new optional
request field, a new response field, a new `code` on a call that already had an error case the game treats as
SERVER_ERROR. `docs/WEBSITE_API.md` changes in the same commit as any such change.

## The game key

Sent as `X-FB3D-Key` on **every** call, including `ping`, `auth/login` and `auth/refresh`. (Milestone N says the key is
checked on "every call that is not a human login", meaning the website's own browser login page, which does not use
this API. The game's login call is a game call, so it carries the key; this closes the password guessing route to
anything that is not a build of the game. The owner can change this.)

- The server stores only a **hash** of each key (a keyed or slow hash, so a stolen database does not give the keys), a
  label, a created time, an optional expiry and an active flag. Several keys are active at once: rotation is "add the
  new key, ship a build with it, switch the old one off in the Django admin when the old builds are retired".
- The key is **compared in constant time**. A missing key gives `key_missing`, a wrong, expired or switched-off key
  gives `key_rejected`. Neither writes the key to a log, to the `errors` database or to a response.
- A call with a rejected key still counts towards the per-IP rate limit, so key guessing is throttled.
- **As built (V3.4):**
  - **Shape.** The server makes every key; nobody types one. It is `fb3dk_` and 43 URL-safe characters from 32 random
    bytes (`fb3dk_` is there so a secret scanner can find a leaked one). The game sends it unchanged. A header that is not
    exactly that shape is `key_rejected` at once, without a database lookup.
  - **Storage.** HMAC-SHA256 of the key, keyed with a secret of the site (`FB3D_API_KEY_PEPPER`, in the site's environment,
    never in the database or in this repository). A stolen database alone gives no working key. Changing that secret
    makes every stored key stop working, which is the same as rotating all of them. Without it the site cannot check
    a key and answers `server_error`: it fails closed.
  - **Order.** The key is checked after the call was counted by the rate limit and before everything else in the call: the
    other headers, the method and the body (a `POST` to `ping` without a key is `key_missing`, not `method_not_allowed`,
    and its body is not read). Three answers come earlier because they need no key: an unknown path (`not_found`), plain HTTP
    (`https_required`) and a body over the hard limit (`payload_too_large`).
  - **Switching off.** In the Django admin (Ključi igre, superuser only) a key has a label, an on/off switch, an optional
    expiry and a "last used" time. Off and expired give `key_rejected` on the next call. "Last used" is written at most
    once an hour per key, so the owner can see whether an old key is still in use before switching it off.
  - **Not built yet:** limits per key (the next section's "per account as well as per key" is only per account and per IP so far).
- **The limit, stated plainly:** the key is inside a program that runs on the player's own PC, so a determined person
  can extract it. It stops casual and automated abuse and lets a leaked key be shut off; it is **not** a proof that a
  call comes from an honest build. So the server never trusts the client: every call also needs a valid token where the
  table says so, every score and save is checked by the server, and limits are per account as well as per key.
- The real key lives in the build machine's environment and the server's database, **never in this repository**.
  Creating the first one is the owner's step V3.5.

## Calls

### `GET /fb3d/api/v1/ping`

Is the site up, and is this key and build accepted? Needs the key headers only. Never needs a token. (**Built in V3.3 without the key check; V3.4 added it**, so `ping` now needs a good key like every call, and `update` is always
`none` until releases exist, V4.3.)

```
GET /fb3d/api/v1/ping
X-FB3D-Key: <key>
X-FB3D-Version: 0.3.0
X-FB3D-Build: a1b2c3d
```

```json
200 OK
{
  "status": "ok",
  "api_version": 1,
  "server_time": "2026-10-30T10:02:02Z",
  "update": "none"
}
```

`update` is `none`, `available` (a newer release is published) or `required` (this build is below `minimum_version`).
Unlike the other calls, `ping` still answers `200` with `"update": "required"` for an old build, so the launcher can
tell "offline" from "too old".

### `GET /fb3d/api/v1/releases/current`

The newest published build and the oldest build still allowed. Key headers only. Answers for an old build too.

```json
200 OK
{
  "update": "available",
  "minimum_version": "0.3.0",
  "current": {
    "version": "0.3.1",
    "channel": "release",
    "commit": "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678",
    "published_utc": "2026-11-05T09:00:00Z",
    "file_name": "FB3D-0.3.1-a1b2c3d.exe",
    "size": 94371840,
    "sha256": "<64 hex characters>",
    "download_url": "https://<site host>/media/fb3d/releases/FB3D-0.3.1-a1b2c3d.exe",
    "notes": "What changed, plain text, at most 4000 characters."
  }
}
```

- `update` is worked out by the server with the shared version comparison (`tools/version_compare_cases.json`).
- `current` is `null` when nothing is published yet.
- `size` and `sha256` are the values of `release_manifest.json` (V2.5); the game checks both after the download (V6).
  `download_url` is a plain file URL and not an API call, so nginx serves it. (A signature field is added by V6.4.)
- Only the **superuser** can publish a release (V4.3); this call only reads.

### `POST /fb3d/api/v1/auth/login`

Key headers, no token. The game has no sign-up: accounts are made on the website (with an invite code).

```json
POST
{ "username": "alice", "password": "<typed by the player, never stored by the game>", "device_name": "ALICE-PC" }
```

```json
200 OK
{
  "access_token": "<opaque string>",
  "access_expires_in": 900,
  "refresh_token": "<opaque string>",
  "refresh_expires_in": 2592000,
  "user": { "id": 17, "username": "alice" }
}
```

- `device_name` is optional (at most 64 characters) and is shown to the player on the website as the name of the
  session. It is a label, not an identity.
- Wrong username and wrong password give the **same** `invalid_credentials`, with the same timing as far as is
  practical. A deactivated account is also `invalid_credentials`.
- Tokens are **opaque random strings** (not JWTs), at least 32 bytes of randomness. The server stores only a hash of
  each, so a stolen database does not give working tokens, and a token can be revoked at once. They are not signed
  with Django's `SECRET_KEY` (`docs/WEBSITE.md`, fact 3).
- The password is only ever in this one request body, over HTTPS, and is never logged, by the game or the server.

### `POST /fb3d/api/v1/auth/refresh`

Key headers, no `Authorization` header. Exchanges a refresh token for a **new pair**; the old pair stops working.

```json
POST
{ "refresh_token": "<opaque string>" }
```

```json
200 OK
{ "access_token": "...", "access_expires_in": 900, "refresh_token": "...", "refresh_expires_in": 2592000,
  "user": { "id": 17, "username": "alice" } }
```

An unknown or revoked refresh token is `token_invalid`; an expired one is `token_expired`. A refresh token that was
**already used** gives `token_reused` and revokes the whole session: either the game or a thief used it first. The
game must therefore write the new pair to disk **before** it uses it, and must never send one refresh token twice.

### `POST /fb3d/api/v1/auth/logout`

Key headers and `Authorization: Bearer <access token>`. Revokes the session of that token and its refresh token.

```json
POST
{}
```

`204 No Content`. A token that is already invalid is also `204`, so logging out never fails because the token had
already expired; the game deletes its stored tokens either way.

### `GET /fb3d/api/v1/me`

Key headers and a bearer token. Who the token belongs to; the launcher uses it to check a remembered login (V5).

```json
200 OK
{
  "id": 17,
  "username": "alice",
  "date_joined": "2026-10-12T18:30:00Z",
  "cloud_save": { "exists": true, "revision": 12, "updated_utc": "2026-10-29T20:15:40Z" }
}
```

XP and level are **not** in `/v1/` yet: the website becomes their authority with the leaderboards after 0.3.0, and
adding them then is not a breaking change. Nothing that is not listed here (email, staff flags, invite code) is ever
returned.

### Saves (V8, draft)

One current save per account, plus the last few versions. The game's local files stay the truth for playing; the cloud
copy is only a copy (Milestone N). A save belongs to the account in the token and never to an id in the path.

**`GET /fb3d/api/v1/saves/current`** (key, token)

```json
200 OK
{
  "revision": 12,
  "save_format_version": 1,
  "game_version": "0.3.0",
  "saved_utc": "2026-10-29T20:15:40Z",
  "uploaded_utc": "2026-10-29T20:15:43Z",
  "data": { "meta.json": { "version": 1, "balance": 120, "...": "..." }, "scores.json": { "version": 1, "entries": [] } }
}
```

`404 not_found` when the account has no save. `data` holds the save files that are worth keeping, each as the same JSON
the game writes (`docs/SAVE_FILES.md`); which files go in is decided in V8.1 (`settings.cfg` is not JSON and probably
stays local). Every file keeps its own `version`.

**`PUT /fb3d/api/v1/saves/current`** (key, token, `If-Match: <revision>`; `If-Match: 0` for "I have never seen a cloud
save")

```json
PUT
{
  "save_format_version": 1,
  "game_version": "0.3.0",
  "saved_utc": "2026-10-29T20:20:01Z",
  "data": { "meta.json": { "...": "..." } }
}
```

```json
200 OK
{ "revision": 13, "uploaded_utc": "2026-10-29T20:20:04Z" }
```

- `If-Match` is **required** (a missing one is `bad_request`), so a second PC can never overwrite silently. If it does
  not equal the stored revision, nothing is written and the answer is `409 save_conflict` with the stored side's
  `revision`, `saved_utc` and `game_version` in an extra `conflict` object inside `error`, so the game can ask the player
  "use cloud save / use this PC's save" (never a silent merge).
- The server **checks every value** (`save_invalid`): known file names only, each file's `version` is an integer the
  server knows, coin balances, XP and counters are non-negative integers and within a possible range, lists are not
  longer than any real save, `saved_utc` is not in the future and not older than the stored one. A save that fails is
  kept nowhere. The exact rules are written in V8.2 and tested against edited saves.
- `save_format_version` newer than the server knows is **kept out**: `save_format_too_new`. A save from a **newer game
  version** than the downloader is **kept but never handed to an older build**: `GET` answers it with
  `save_format_too_new` to a build whose format is older (the game shows "update the game to use this save").
- Every accepted `PUT` increases `revision` by one and keeps the replaced save as a version, up to the limit above.

**`GET /fb3d/api/v1/saves/versions`** (key, token): the kept versions, newest first, without `data`.

```json
200 OK
{ "versions": [ { "revision": 12, "saved_utc": "...", "game_version": "0.3.0", "size": 5120 } ] }
```

**`GET /fb3d/api/v1/saves/versions/<revision>`** (key, token): one kept version, shaped like `saves/current`. Restoring
one is a normal `PUT` of its `data` by the game, so there is no separate "restore" call.

## How the site builds it (for V3.3 to V3.4)

Not part of the contract, written so V3.3 starts from one place. The code is `fb3d/api/` in the site's repository.

- Django REST Framework, configured closed as described in `docs/WEBSITE.md`: JSON renderer and parser only, no session
  authentication, `URLPathVersioning`, one `EXCEPTION_HANDLER` that produces the error shape above.
- Two checks: the **game key**, on every call, and `BearerTokenAuthentication` (the user, where the table asks for a
  token). A call can have a key and no user. **As built (V3.4) the key is not a DRF authentication class:** DRF authenticates
  before it throttles, so a rejected key would never be counted by the rate limit, which this file promises. It is checked in
  `ApiView.initial` (`fb3d/api/views.py`, `fb3d/api/keys.py`) right after the throttles. V5 must run the bearer step after it.
- Rate limits as DRF throttle classes keyed by IP, username, session and account, on a **shared** cache, which has to be
  chosen first (`docs/WEBSITE.md`, fact 1).
- Tests (`python manage.py test fb3d`) cover every `code` in the table above, the headers, the body limits, a session
  cookie being ignored, and that no response or log line contains a key, token or password.
