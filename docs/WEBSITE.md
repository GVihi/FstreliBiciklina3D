# The website: what it is and what the game can rely on

This file answers alpha item W1.1 ("look at the existing site and write down what you find") and V3.1 of the
Web Integration Roadmap. W1.1 was ticked in `docs/ALPHA_ROADMAP.md` but this file was never committed, so it did not
exist until V3.1. It was written on 2026-10-30 from the site's own repository (the `web.zip` the owner supplied),
by reading the code; the owner then confirmed the server facts and chose DRF. Nothing here was run against the live server.

**This repository is public.** Hostnames of the live site, the contents of its `.env`, database names and keys are not
written here and must not be. Where a fact lives only on the server (nginx, gunicorn, the real `.env`), the line says
**unknown** and the owner fills it in.

## Where things live

- **The site's code** is in the site's own repository (decided in W1.2). It is one Django project (`app/`) with three
  apps: `users` (accounts), `core` (the owner's other tools: clips, maps, chat, shopping list) and `fb3d` (this game:
  Info articles, Feedback, the article editor).
- **The API document** (`docs/WEBSITE_API.md`, V3.2) lives **in this repository**, because the game depends on it and
  this repository is where the game's roadmap is ticked. The site's code implements it, and the site's tests point
  back to it. (First guess; the owner can move it.)
- **Editor notes of W3** are in the site's repository, `docs/WEBSITE_W3.md` (own editor instead of CKEditor, upload
  limits, nginx snippet). They stay there.

## Versions and packages

| Thing | What the code says |
|---|---|
| Django | **6.1.1**, pinned in `requirements.txt`, the same on the server |
| Python | **3.12.3** on the server (confirmed by the owner) |
| Database | PostgreSQL (`psycopg` 3 and `psycopg2-binary` are installed); engine, name and login come from environment variables. A **second database `errors`** is used by the error logger (`app/error_logger.py`, `ErrorLoggingMiddleware`) |
| Django REST Framework | **not installed yet**, nothing imports `rest_framework`; it is added in V3.3 (see the decision below) |
| CORS package | not installed (nothing needs one: the game is not a browser) |
| Other packages | `nh3` (cleans article HTML), `pillow` (image copies), `requests`, `python-dotenv`, `psutil`, `beautifulsoup4`, `lxml` |
| Tests | `python manage.py test fb3d`, 19 tests in `fb3d/test_feedback.py`; `fb3d/tests.py` and `users/tests.py` are empty |

## Accounts

- **One account system, `users.CustomUser`** (a subclass of Django's `AbstractUser`). The game must use it and not add a
  second one (the rule of W1.1).
- **Registration is by invite code only** (`/register/`): the form asks for a username, a password and an invite code
  made by the owner (`users.InviteCode`: active flag, optional expiry, redeemed time, a note). There is **no email
  address** on an account. So "Register on the website" in the launcher (V5) leads to a form a stranger cannot fill in
  without a code; the launcher text should say so.
- **Login is a session cookie** (`/login/`, `ThrottledLoginView`): Django's login with one extra rule, a wait of 5 s
  between attempts for the same username, kept in the cache.
- **Password reset has no email step.** The owner makes a reset link for a user in the Django admin
  (`users/admin.py`, "generate reset link"), and the player opens `/reset/<uid>/<token>/`. Milestone N's item
  "Password reset and email confirmation through the website (reuse what the site already has)" therefore reuses an
  owner-made link, not a self-service mail. Whether to add email is a decision for the owner, not for V3.
- **Superuser** is Django's `is_superuser`. The clip quota code already treats superusers differently, so the idea
  "only the superuser can publish a build" (V4) fits how the site already works.

## Facts that matter for the API (V3.3 to V5)

1. **The cache is per process, and that is fine.** `settings.py` has no `CACHES`, so Django uses its default in-memory
   cache (`LocMemCache`), which is not shared between gunicorn workers. The owner confirmed on 2026-10-30 that the site
   runs **one worker** and that the game is a hobby project with at most 3 or 4 players, so every request sees the same
   counters and no shared cache is needed. A restart resets the counters. If more workers are ever started, switch
   `CACHES` to a shared cache first, or DRF's limits multiply by the number of workers.
2. **CSRF is on for every view** (`CsrfViewMiddleware`). API views are called with a bearer token and a key, not a
   cookie, so they must be exempt from CSRF and must **ignore session cookies completely**, or a browser logged into
   the site could be tricked into calling them.
3. **`SECRET_KEY` is written in `settings.py`** as a `django-insecure-...` value, not read from the environment (the zip
   the owner supplied is a local dev copy, so whether the live key is the same is unknown). If the site's repository
   is public, or if V5 signs tokens with it, that is a problem: move it to an environment variable
   first and replace it (see `docs/SECRETS.md`). Raised here, not changed here. Tokens of V5 should not depend on it.
4. **HTTPS:** `SECURE_PROXY_SSL_HEADER` is set (TLS ends at nginx). There is no `SECURE_SSL_REDIRECT`, HSTS or secure
   cookie setting, so "HTTPS only" for the API (V3.3) means either nginx redirects or the API refuses plain HTTP itself.
   Which one is **unknown**.
5. **Request size:** `DATA_UPLOAD_MAX_MEMORY_SIZE` is Django's default (2.5 MB for a body that is not a file upload),
   which already stops a huge JSON body. The only nginx value written down is `client_max_body_size 55m` for article
   uploads (W3); the API needs a **smaller** limit on its own `location` (V3.3).
6. **Debug and hosts:** `DEBUG` is `not PRODUCTION`, and `ALLOWED_HOSTS` is the real hostname when `PRODUCTION=True` and
   `*` otherwise. The owner confirmed `PRODUCTION=True` on the server; a local dev copy has `DEBUG` on, so API tests
   must not depend on it.
7. **Error logging:** every unhandled exception goes to the `errors` database through `ErrorLoggingMiddleware`. API
   errors that are handled (a wrong key, a bad password) must **not** go there, or the log fills with noise; and no
   header (`Authorization`, `X-FB3D-Key`) or password may ever be written to it.
8. **Static and media:** static files are collected into `STATIC_ROOT` in production, uploads go to `MEDIA_ROOT` (an
   environment variable, default `media/` in the project) and nginx serves `/media/`. The base template is
   `templates/base.html`; the game's pages extend it and add `static/fb3d/` files. None of this touches the API.
9. **Rich text editor:** none installed; the article editor is the site's own (`fb3d/static/fb3d/js/editor.js`).

## Decision: Django REST Framework (decided by the owner, 2026-10-30)

An earlier draft of this file recommended plain Django views. The owner decided on **Django REST Framework** instead,
and that is the plan. `djangorestframework` 3.18.3 lists Django 6.1 among its supported versions and installs on
Python 3.12; it is added to the site's `requirements.txt` pinned to an exact version (V3.3).

DRF's defaults are made for a browser and a website, and this API is for one game client, so V3.3 configures it
**closed** instead of taking the defaults:

- **JSON only.** `DEFAULT_RENDERER_CLASSES` is `JSONRenderer` only (no browsable API, no HTML form renderer) and
  `DEFAULT_PARSER_CLASSES` is `JSONParser` only, so form and multipart bodies are refused with a stable error code.
- **No session authentication.** `SessionAuthentication` is not in `DEFAULT_AUTHENTICATION_CLASSES`. DRF only enforces
  CSRF for session authentication, so with it absent a browser cookie is never accepted as a login (fact 2). The two
  checks of a call are the game key ("The game key" in `docs/WEBSITE_API.md`; built in V3.4 as a check in `ApiView.initial`
  right after the throttles, not as a DRF authentication class, so a rejected key still counts against the rate limit)
  and the bearer token of V5.
- **One error shape.** A custom `EXCEPTION_HANDLER` turns every DRF and Django error, including 404, 405, 415 and
  throttling, into the `{"error": {"code": ..., "message": ...}}` shape of `docs/WEBSITE_API.md`, and never returns a
  traceback or a DRF default body.
- **URL versioning.** `URLPathVersioning` with `/fb3d/api/v1/`, so a `/v2/` can be added next to it.
- **Throttling.** DRF throttles keep their counters in the Django cache. With one gunicorn worker (fact 1) the default
  in-memory cache is enough and V3.3 uses it; more workers would need a shared cache first.
- **Not used:** serializers for model-wide exposure, viewsets with a router and `ModelSerializer` over `CustomUser`.
  Every response is written as an explicit small serializer or dict, so a new column on `CustomUser` can never leak
  through the API by accident.

What DRF costs: one more package that must follow every Django release (the site pins Django exactly), and a larger
default surface that the settings above exist to close. Both are accepted by the owner.

## Confirmed by the owner (2026-10-30)

- The live server runs **Python 3.12.3 and Django 6.1.1** with **`PRODUCTION=True`** (fact 6 is satisfied there), with
  **one gunicorn worker** (fact 1).

## What is still unknown (the owner fills these in)

- Whether nginx redirects HTTP to HTTPS, and the nginx `location` rules for `/fb3d/` (fact 4 and 5).
- Whether the live `SECRET_KEY` is the one in `settings.py` (fact 3).
- Whether accounts should get an email address (a note under "Accounts").
