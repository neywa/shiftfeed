# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

ShiftFeed — OpenShift / Kubernetes news + intelligence aggregator. Two independent subprojects share a single Supabase backend:

- `scraper/` — Python 3.11 ingestion job (RSS + GitHub Releases + Red Hat CVE API → Supabase). Also generates a daily AI briefing and sends FCM push notifications.
- `app/` — Flutter client (Android, iOS, web, desktop) that reads from the same Supabase tables and subscribes to FCM topics.

They never import from each other. The contract is the Supabase schema (curated tables: `articles`, `cve_alerts`, `digests`, `ocp_versions`, `submissions`; per-user tables: `user_bookmarks`, `user_alert_rules`, `user_device_tokens`, `user_digest_prefs`, `user_rss_sources`) plus FCM topic names and the per-token push payload shape.

## Commands

### Scraper (run from repo root, not from `scraper/`)

```bash
# Install deps. The CI workflow installs them inline; pyproject.toml lists the same set.
pip install httpx feedparser supabase python-dotenv beautifulsoup4 google-auth anthropic pyyaml
# or
pip install -e scraper/

# Run the full scrape (RSS + GitHub releases + Red Hat CVEs → upsert → notify → digest)
python -m scraper.main
```

Loads `.env` from CWD (root `.env`). Required: `SUPABASE_URL`, `SUPABASE_SECRET_KEY`. Optional: `GITHUB_TOKEN` (raises GitHub API rate limit), `ANTHROPIC_API_KEY` (digest generation), `FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_SERVICE_ACCOUNT_FILE` (FCM push). Without the optional ones the scraper still runs — it just skips that feature with a warning.

### Flutter app (from `app/`)

```bash
flutter pub get
flutter run                        # picks a connected device/emulator
flutter test                       # all tests
flutter test test/widget_test.dart # single test file
flutter analyze                    # lints (uses analysis_options.yaml → flutter_lints)

# Web build (matches deploy_web.yml)
flutter build web --release \
  --dart-define=SUPABASE_URL=... \
  --dart-define=SUPABASE_ANON_KEY=...
```

The app prefers `--dart-define`d Supabase creds; if those are empty it falls back to `assets/.env` (loaded via `flutter_dotenv`). Web CI uses `--dart-define` and writes an empty `assets/.env` placeholder so the asset bundle doesn't fail.

## Architecture notes

### Scraper data flow

`scraper/main.py` orchestrates five stages:

1. **Fetch + tag** — `sources/rss.py::fetch_all_rss()`, `sources/github_releases.py::fetch_github_releases()`, `sources/security.py::fetch_security_advisories()`, `sources/ocp_versions.py::fetch_ocp_version_updates()`. Each result is run through `sources/cve_tagger.py::enrich_with_cve_tags()` which scans title+summary for `CVE-YYYY-N` patterns and adds `cve` / `security` / `CVE-…` tags. After the curated fetches, `sources/user_rss.py::fetch_user_sources()` pulls every enabled row from `user_rss_sources` and ingests each user feed via `fetch_articles_for_source()` — those articles are stamped with `submitted_by=user_id` and tagged `custom_feed`. Per-user fetch errors are recorded back to `user_rss_sources.last_error` (cleared on success). `security.py` additionally emits a `cvss:X.X` tag from the Hydra payload — that string is the contract read by `sources/alert_rule_matcher.py`.
2. **Upsert** — `SupabaseClient.upsert_article()` writes to `articles` (`ON CONFLICT url`). For each `CVE-…` tag found, also upserts a row into `cve_alerts` (`ON CONFLICT cve_id`).
3. **Notify** — `FCMSender` + `NotifiedCache`. `notified_cache.py` uses the `articles.notified` boolean column as the dedupe ledger; only un-notified articles tagged `cve` or `release` produce pushes. A single new alert sends a detailed notification; multiple new alerts collapse into one batch notification (topics: `security`, `releases`). After the curated pushes, `sources/alert_rules.py` + `sources/alert_rule_matcher.py` walk every newly-arrived article from this run against each Pro user's enabled rules and dispatch per-token FCM pushes via `FCMSender.send_to_token()`. 404/410 from FCM trigger `fcm.prune_stale_token()` against `user_device_tokens`.
4. **Digest** — `digest.py::DigestGenerator.generate()` queries today's articles, calls Claude Haiku (`claude-haiku-4-5-20251001`) with a fixed briefing-format prompt, upserts into `digests` (`ON CONFLICT digest_date`), and sends an FCM push to topic `all`. Idempotent per day via `_already_generated_today()`.
5. **Personalised digests** — `digest_personal.py::run_personal_digests()` joins `user_digest_prefs` with `user_device_tokens` and matches each Pro user's `delivery_hour` against their IANA timezone vs UTC-now (uses stdlib `zoneinfo`). For matching users it calls `DigestGenerator.generate_filtered()` (no `digests` upsert, no FCM topic broadcast), then per-token pushes the result. Personal digests are ephemeral — only the curated digest hits the `digests` table.

### The wire format

`scraper/models.py::Article` is the single dataclass between fetchers and Supabase. `Article.to_dict()` defines the exact row shape — adding a column means updating both this method and the Supabase table. The Flutter side mirrors it in `app/lib/models/article.dart::Article.fromJson` (note `published_at` → `publishedAt`, plus a `created_at` field that the scraper does not set explicitly — Supabase fills it). `submitted_by` is set on the scraper side for user-RSS rows and read by Supabase RLS to scope visibility — the Flutter `Article` model can ignore it.

### What lives where

- **Supabase reads** from the Flutter client go through [app/lib/repositories/article_repository.dart](app/lib/repositories/article_repository.dart): `articles`, `cve_alerts`, `digests`, `ocp_versions`. The repository uses a `_client` getter that re-reads `Supabase.instance.client` at call time so mid-session auth changes are picked up immediately.
- **Supabase writes** from the Flutter client (anon key + RLS):
  - `submissions` — anonymous link submissions ([submit_screen.dart](app/lib/screens/submit_screen.dart); unique `url` → `23505` surfaces as "already submitted").
  - `user_bookmarks` — cross-device bookmark sync ([bookmark_service.dart](app/lib/services/bookmark_service.dart)).
  - `user_alert_rules` — custom Pro alert rules ([alert_rule_service.dart](app/lib/services/alert_rule_service.dart)).
  - `user_device_tokens` — FCM tokens for per-user push ([device_token_service.dart](app/lib/services/device_token_service.dart)).
  - `user_digest_prefs` — personalised digest schedule ([digest_pref_service.dart](app/lib/services/digest_pref_service.dart)).
  - `user_rss_sources` — Pro custom feeds ([custom_rss_service.dart](app/lib/services/custom_rss_service.dart)).

  Every `user_*` table follows the same shape: `user_id uuid references auth.users(id)`, RLS scoping `select` / `all` to `auth.uid() = user_id`. All article writes still come from the scraper using the service-role key (which bypasses RLS).
- **On-device only** (not in Supabase): nothing user-facing — bookmarks now sync via Supabase. `SharedPreferences` is still used for transient client preferences (theme, last-seen counters) but not for portable user data.

### Authentication, Pro tier, and RLS

Two stacked auth systems on the app side:
- [`UserService`](app/lib/services/user_service.dart) wraps Supabase magic-link auth (deep-link redirect). The signed-in `auth.users.id` is the foreign key for every `user_*` table.
- [`EntitlementService`](app/lib/services/entitlement_service.dart) wraps RevenueCat and exposes `isPro()`. Most user-scoped features (alert rules, digest scheduling, custom RSS feeds, notifications) are paywall-gated via [`PaywallSheet`](app/lib/widgets/paywall_sheet.dart) with `PaywallReason.{briefing, notifications, sync}`.

RLS rules:
- All `user_*` tables: `select`/`all` policy = `auth.uid() = user_id`. The anon key sees nothing without a session JWT.
- `articles` (after [phase6_custom_rss.sql](app/lib/sql/phase6_custom_rss.sql)): two select policies — global rows where `submitted_by IS NULL` are visible to everyone; rows where `submitted_by = auth.uid()` are visible only to the owner.
- The scraper uses the service-role key (`SUPABASE_SECRET_KEY`) which bypasses RLS entirely — no insert/update policies are needed for it.

When adding a new per-user feature: add the table with `user_id uuid references auth.users(id) on delete cascade`, the matching RLS policy, and a singleton service that guards every method on `UserService.instance.currentUser?.id` (no-op when null). Pattern: see [alert_rule_service.dart](app/lib/services/alert_rule_service.dart) or [custom_rss_service.dart](app/lib/services/custom_rss_service.dart).

### Deduplication invariants

- `articles.url` is the unique key. Anything that changes how URLs are extracted (canonicalization, query-string trimming) will create duplicates. **Caveat (Phase 6):** because `url` is global, two users adding the same custom feed race on `submitted_by` — the last writer wins and the loser loses RLS visibility. Fixing this needs a compound key or per-user article copies; out of scope today but worth knowing.
- `cve_alerts.cve_id` is the unique key for the CVE table.
- `digests.digest_date` is the unique key for daily digests.
- All per-entry failures inside fetcher loops are swallowed and logged — one bad feed entry never kills the run. Don't add `raise`s inside those loops without reconsidering this.

### Tag conventions

Tags on `articles.tags` aren't just labels — several are read by other modules as a contract:

- `cve` / `release` / `security` — drive the global FCM topic pushes in stage 3.
- `CVE-YYYY-N` (uppercase) — triggers `cve_alerts` upserts in stage 2.
- `cvss:X.X` — emitted by `security.py::_extract_cvss_score()` from the Hydra payload; consumed by [alert_rule_matcher.py](scraper/sources/alert_rule_matcher.py) for the CVSS threshold check on Pro alert rules. Format is `cvss:` + one-decimal float.
- `custom_feed` — Phase 6 marker on user-RSS articles; combined with `submitted_by != NULL` on the row.

### Adding a source

- **RSS feed (curated):** append a `{url, source, tags}` dict to `RSS_SOURCES` in `scraper/sources/rss.py`.
- **GitHub repo releases:** append a `{repo, source, tags}` dict to `GITHUB_REPOS` in `scraper/sources/github_releases.py`. Drafts and prereleases are filtered out.
- **Security advisories:** the Red Hat Hydra Security Data API is queried per package keyword in `_PACKAGE_QUERIES` in `scraper/sources/security.py`; relevance is filtered by `_RELEVANT_KEYWORDS` against title + affected_packages.
- **OCP stable-channel versions:** auto-discovered by [scraper/sources/ocp_versions.py](scraper/sources/ocp_versions.py) from the `stable-4.*.yaml` files in `openshift/cincinnati-graph-data`. Upserts into `ocp_versions` (`ON CONFLICT minor_version`) and emits an `Article` for new channels and new stable promotions. There is no per-source config — the fetcher enumerates active minors itself, gated by `ACTIVE_MINOR_MINIMUM` ([scraper/sources/ocp_versions.py:32](scraper/sources/ocp_versions.py#L32)). **Mirror constant on the Flutter side:** `kOcpActiveMinorMinimum` in [app/lib/models/ocp_version.dart](app/lib/models/ocp_version.dart) — bump both together when Red Hat EOLs a minor. First-ever run uses `seed_only=True` so the table is primed without flooding the feed with historical articles. The Flutter side reads the table directly for [app/lib/screens/versions_screen.dart](app/lib/screens/versions_screen.dart) and the desktop sidebar widget.

For curated sources there is no config file — everything is in code. **Per-user RSS feeds (Phase 6) are different:** they live in `user_rss_sources` and are added by Pro users via the app, not in code. The scraper picks them up automatically each run via [`fetch_user_sources()`](scraper/sources/user_rss.py).

### FCM: topics + per-token sends

Two delivery modes coexist:

1. **Topic broadcasts** — used for the curated firehose. The Flutter client subscribes on launch (Android/iOS only) to:
   - `all` — daily digest notifications
   - `security` — CVE alerts (single + batch)
   - `releases` — release alerts (single + batch)
2. **Per-token sends** — used for Pro user-scoped pushes (custom alert rules, personalised digests). [`DeviceTokenService`](app/lib/services/device_token_service.dart) registers the device's FCM token in `user_device_tokens` after sign-in / token refresh; the scraper joins that table when dispatching via [`FCMSender.send_to_token()`](scraper/fcm.py). On 404/410 the token is pruned automatically.

Notification channel ID is `shiftfeed_alerts` and must match between [scraper/fcm.py](scraper/fcm.py) and [app/lib/services/notification_service.dart](app/lib/services/notification_service.dart). The Firebase project ID is hardcoded in `scraper/fcm.py::FCM_URL`.

### Flutter app shape

[app/lib/main.dart](app/lib/main.dart) initializes Supabase, then conditionally initializes Firebase + `NotificationService` only when `!kIsWeb && (Android || iOS)` — Linux/macOS/Windows/web skip Firebase. `ArticleRepository` ([app/lib/repositories/article_repository.dart](app/lib/repositories/article_repository.dart)) is the only Supabase reader; both `HomeScreen` and `DigestScreen` go through it. `ThemeNotifier` + `provider` drive light/dark switching.

**Mobile vs desktop layout split.** [home_screen.dart:431-441](app/lib/screens/home_screen.dart#L431-L441) routes at `_desktopBreakpoint = 900` between `_buildMobile` (BottomNav + collapsible search AppBar + IndexedStack of feed/versions/saved/settings) and `_buildDesktop` (left sidebar nav + grid + right sidebar with OCP versions, latest CVEs, top sources, popular tags). Same state, repository, and search backing — completely different shells. Editing the feed UI usually means updating both paths.

**Theme awareness.** Don't hardcode `kSurface` / `kTextPrimary` etc. in widgets — use the helpers in [app/lib/theme/app_theme.dart](app/lib/theme/app_theme.dart) (`surfaceOf(context)`, `borderOf(context)`, `textMutedOf(context)`, etc.) or the theme-aware getters on widgets like `HomeScreen`'s `_textPrimary` / `_surface` / `_border`. That's how light mode stays correct.

### Two env files, two keys

| File | Key type | Consumer |
|---|---|---|
| `/.env` (gitignored) | `SUPABASE_SECRET_KEY` (service role), `ANTHROPIC_API_KEY`, optional `GITHUB_TOKEN`, optional Firebase SA | scraper, CI |
| `/firebase-service-account.json` (gitignored) | Firebase service account | scraper, local FCM |
| `/app/assets/.env` (bundled asset) | `SUPABASE_ANON_KEY` (publishable) | Flutter app, local builds |
| `--dart-define` (build-time) | `SUPABASE_URL`, `SUPABASE_ANON_KEY` | Flutter web CI |

Never put the service-role key in `app/assets/.env` — that file ships inside the built app.

### Android release signing

[app/android/app/build.gradle.kts](app/android/app/build.gradle.kts) reads `app/android/key.properties` (gitignored) for the release keystore at `keystore/shiftfeed-keystore.jks` (also gitignored — both paths are explicitly excluded in `.gitignore`). If `key.properties` is absent, release builds fall back to the debug signing config — useful locally, never for Play Store uploads.

### CI

- [.github/workflows/scrape.yml](.github/workflows/scrape.yml) runs `python -m scraper.main` hourly (`0 * * * *`) and on `workflow_dispatch`. **Deps are listed inline in the workflow's `pip install` line, not pulled from `pyproject.toml`. Adding a scraper dependency means updating BOTH [scraper/pyproject.toml](scraper/pyproject.toml) AND that pip install line.**
- [.github/workflows/deploy_web.yml](.github/workflows/deploy_web.yml) runs on every push to `main`: `flutter build web` with Supabase creds via `--dart-define`, then `peaceiris/actions-gh-pages` publishes `app/build/web` to the `gh-pages` branch (live at https://neywa.github.io/shiftfeed/, base href `/shiftfeed/`).

## Supabase migrations

SQL migration files live in `app/lib/sql/`. Run them manually in the Supabase dashboard SQL editor in phase order. They are not executed by the app.
