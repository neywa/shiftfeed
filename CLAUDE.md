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
# google-auth needs the [requests] extra — the FCM sender uses google.auth.transport.requests.
pip install httpx feedparser supabase python-dotenv beautifulsoup4 "google-auth[requests]" anthropic pyyaml
# or
pip install -e scraper/

# Run the full scrape (RSS + GitHub releases + Red Hat CVEs → upsert → notify → digest)
python -m scraper.main
```

Loads `.env` from CWD (root `.env`). Required: `SUPABASE_URL`, `SUPABASE_SECRET_KEY`. Optional: `GITHUB_TOKEN` (raises GitHub API rate limit), `ANTHROPIC_API_KEY` (digest generation), `FIREBASE_SERVICE_ACCOUNT_JSON` or `FIREBASE_SERVICE_ACCOUNT_FILE` (FCM push), `NVD_API_KEY` (raises the NVD rate limit for CVE enrichment from 5 to 50 requests/30s; without it NVD calls are spaced 6.5s apart). Without the optional ones the scraper still runs — it just skips that feature with a warning.

```bash
# One-time backfill of CVSS scores onto historical cve-tagged articles.
# NOT part of the hourly job — the ingest hook keeps new articles scored.
python -m scraper.backfill_cve_scores            # dry run (default, writes nothing)
python -m scraper.backfill_cve_scores --commit   # apply
```

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

1. **Fetch + tag** — `sources/rss.py::fetch_all_rss()`, `sources/github_releases.py::fetch_github_releases()`, `sources/security.py::fetch_security_advisories()`, `sources/ocp_versions.py::fetch_ocp_version_updates()`, `sources/operator_lifecycles.py::fetch_operator_lifecycles()`. Each result is run through `sources/cve_tagger.py::enrich_with_cve_tags()` which scans title+summary for `CVE-YYYY-N` patterns and adds `cve` / `security` / `CVE-…` tags. After the curated fetches, `sources/user_rss.py::fetch_user_sources()` pulls every enabled row from `user_rss_sources` and ingests each user feed via `fetch_articles_for_source()` — those articles are stamped with `submitted_by=user_id` and tagged `custom_feed`. Per-user fetch errors are recorded back to `user_rss_sources.last_error` (cleared on success). `security.py` additionally emits a `cvss:X.X` tag from the Hydra payload — that string is the contract read by `sources/alert_rule_matcher.py`.
1b. **Score CVEs** — `sources/cve_enrichment.py::enrich_articles()` runs after CVE tagging and **before** the upsert. The `cve_tagger` regex path mints cve-tagged articles with no score (Istio bulletins, blog mentions), and an unscored article can never satisfy a Pro CVSS-threshold rule, so this closes the gap at ingest. Looks up Red Hat Hydra's *detail* endpoint first, NVD on 404. Rejected CVEs are dropped (the article is skipped) when the article IS the CVE record, otherwise just de-tagged. **It reads `cve_alerts` as a score cache first** — RSS re-serves the same articles hourly, so without the cache this would re-fetch every unscored CVE article every run (~350 calls/day instead of ~0.1/run).
2. **Upsert** — `SupabaseClient.upsert_article()` writes to `articles` (`ON CONFLICT url`). For each `CVE-…` tag found, also upserts a row into `cve_alerts` (`ON CONFLICT cve_id`) with the article's `cvss` + `severity`.
3. **Notify** — `FCMSender` + `NotifiedCache`. `notified_cache.py` uses the `articles.notified` boolean column as the dedupe ledger; only un-notified articles tagged `cve` or `release` produce pushes. A single new alert sends a detailed notification; multiple new alerts collapse into one batch notification. Releases go to the `releases` topic. CVEs are **routed by severity** through `main.py::push_cve_alerts()` — one of four `cve_*` topics per [sources/cve_severity.py](scraper/sources/cve_severity.py) (see "CVE severity routing" below); each bucket decides single-vs-batch on its own count, so one new critical plus three new highs is a detailed critical push and a high batch, not one lump. `python -m scraper.main --dry-run-push` reports what the stage *would* send (topic + CVE id + severity) without calling Firebase or touching the ledger, then exits before the release/alert-rule/digest stages. After the curated pushes, `sources/alert_rules.py` + `sources/alert_rule_matcher.py` walk every newly-arrived article from this run against each Pro user's enabled rules and dispatch per-token FCM pushes via `FCMSender.send_to_token()`. 404/410 from FCM trigger `fcm.prune_stale_token()` against `user_device_tokens`.
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
- `articles` (after [phase6_custom_rss.sql](app/lib/sql/phase6_custom_rss.sql)): two select policies — global rows where `submitted_by IS NULL` are visible to everyone; rows where `submitted_by = auth.uid()` are visible only to the owner. **History:** a legacy broad `using (true)` select policy once OR-combined with these and leaked one user's custom feed into the global firehose — when touching `articles` policies, make sure no permissive `using (true)` survives alongside them.
- The scraper uses the service-role key (`SUPABASE_SECRET_KEY`) which bypasses RLS entirely — no insert/update policies are needed for it.

**Client-side mirror of the `articles` RLS policies.** Every `articles` read in [article_repository.dart](app/lib/repositories/article_repository.dart) is wrapped in `_visibleToCurrentUser()`, which applies `submitted_by IS NULL` (signed out) or `submitted_by.is.null,submitted_by.eq.<uid>` (signed in) as defense-in-depth. RLS is still authoritative — this is a second layer so a future RLS regression can't silently leak custom feeds. If you change the `articles` select policies, change this helper to match (and vice-versa); they are a paired contract.

When adding a new per-user feature: add the table with `user_id uuid references auth.users(id) on delete cascade`, the matching RLS policy, and a singleton service that guards every method on `UserService.instance.currentUser?.id` (no-op when null). Pattern: see [alert_rule_service.dart](app/lib/services/alert_rule_service.dart) or [custom_rss_service.dart](app/lib/services/custom_rss_service.dart).

### Deduplication invariants

- `articles.url` is the unique key. Anything that changes how URLs are extracted (canonicalization, query-string trimming) will create duplicates. **Caveat (Phase 6):** because `url` is global, two users adding the same custom feed race on `submitted_by` — the last writer wins and the loser loses RLS visibility. Fixing this needs a compound key or per-user article copies; out of scope today but worth knowing.
- `cve_alerts.cve_id` is the unique key for the CVE table.
- `digests.digest_date` is the unique key for daily digests.
- All per-entry failures inside fetcher loops are swallowed and logged — one bad feed entry never kills the run. Don't add `raise`s inside those loops without reconsidering this.

### Tag conventions

Tags on `articles.tags` aren't just labels — several are read by other modules as a contract:

- `cve` / `release` — drive the global FCM topic pushes in stage 3. `cve` selects an article for CVE routing; its *severity* tag then picks which topic (below). `security` is just a label now — it once named the single CVE topic, which is retired.
- `CVE-YYYY-N` (uppercase) — triggers `cve_alerts` upserts in stage 2. Note `cve_alerts` has no schema file anywhere: it was created ad hoc in the dashboard. Live columns are `id, cve_id, title, article_url, severity, cvss, detected_at, notified` (`cvss numeric(3,1)` added 2026-07-16 for enrichment; `severity` existed but was NULL on every row until then).
- `cvss:X.X` — the CVSS base score. Format is `cvss:` + one-decimal float; consumed by [alert_rule_matcher.py](scraper/sources/alert_rule_matcher.py) for the CVSS threshold check on Pro alert rules. Emitted by `security.py` for its own Hydra fetches, and by [cve_enrichment.py](scraper/sources/cve_enrichment.py) for everything the `cve_tagger` regex path mints. **Exactly one `cvss:` tag per article, always** — `alert_rule_matcher` iterates a *set* of tags keeping the last one it sees with no `break`, so a second tag makes the winning score vary between runs. A multi-CVE article carries the **max** score of its CVEs plus that CVE's severity.
- **Severity is two vocabularies, deliberately not merged.** Red Hat says `low/moderate/important/critical`; NVD says `low/medium/high/critical`. They are different scales (Red Hat's `important` spans NVD's `high` *and* `critical`), so `cve_enrichment` never maps between them — it records which source won in `CveScore.source`. Both appear in `articles.tags` and `cve_alerts.severity`; anything filtering by severity must handle both. `article_card.dart` currently styles only `critical`/`important`/`moderate`, so NVD-sourced `high`/`medium` render as a plain `SECURITY` badge.

  **Red Hat's vocabulary carries almost all the traffic — this is a silent-failure trap.** Measured over all 331 cve-tagged articles (2026-07-17): `important` 194, `moderate` 111, `high` 11, `medium` 2, `critical` 6, `low` 5, no severity 2. Red Hat outnumbers NVD ~15:1. Code that handles only the NVD words looks correct, compiles, and passes any test asserting `high → High` — while silently dropping **307 of 331 articles (93%)**. Never treat `important`/`moderate` as droppable synonyms.
- `custom_feed` — Phase 6 marker on user-RSS articles; combined with `submitted_by != NULL` on the row.
- `layered-release` + `layered-product` — a Red Hat layered-product GA from [operator_lifecycles.py](scraper/sources/operator_lifecycles.py). **Deliberately NOT tagged `release`**, so these are push-silent: `release` is the exact string [main.py:358](scraper/main.py#L358) tests to build the `releases` topic push list, and `layered-release` matches nothing in any FCM path. The decision is to hold pushes until we've seen the real GA volume across ~60 operators; re-adding `release` here silently turns pushes back on. Tripwire tests live in `scraper/tests/test_operator_lifecycles.py` under "Push silence". Caveat: a Pro user's *custom alert rule* with empty categories matches every new article regardless of tag, so it can still push these per-token — the guarantee is zero **topic** pushes, not zero pushes.

### CVE severity routing (a cross-language paired contract)

A `cve`-tagged article pushes to one of four per-severity topics —
`cve_critical` / `cve_high` / `cve_medium` / `cve_low` — chosen from its severity
tag. Two mappings implement this, in two languages, and **they must agree**:

| | |
|---|---|
| [scraper/sources/cve_severity.py](scraper/sources/cve_severity.py) | `SEVERITY_TOPICS` — raw word → FCM topic. Read at push time. |
| [app/lib/models/cve_severity.dart](app/lib/models/cve_severity.dart) | `CveSeverity.fromWord` — raw word → display bucket. Drives the CVE screen's severity filter *and* the notification topics (`kCveTopics` in `notification_service.dart` derives them from the enum). |

The mapping, both vocabularies, all six words:

```
critical  → cve_critical      moderate → cve_medium   (Red Hat)
important → cve_high  (Red Hat)   medium → cve_medium   (NVD)
high      → cve_high  (NVD)          low → cve_low
```

Why it's a contract and not a coincidence: a user filters the CVE screen to HIGH
and enables the HIGH switch expecting the same set of CVEs. `app/` and `scraper/`
never import from each other, so nothing at compile time connects the two — but
`scraper/tests/test_cve_severity.py::TestDartContract` **parses the Dart source
text** and fails if either side is edited alone (same trick `nav_tabs_test.dart`
uses for tab order). If that parser breaks, fix it; deleting it silently retires
the only thing checking the contract.

Rules when touching any of this:
- **Never drop `important`/`moderate`** as apparent synonyms — see the traffic
  numbers under "Tag conventions". That edit passes review and kills 93% of pushes.
- Both sides take the **max** severity on a multi-CVE article, matching the max
  `cvss:` score the scraper already stamps. Take-first would disagree the day a
  second severity word appears.
- **Unmapped or missing severity is logged and skipped, never guessed** — a guess
  either wakes people for a low or swallows a critical. 2 of 331 live articles are
  in this state (Istio 2019 bulletins the regex path minted with no score). They
  are still marked notified, so they don't re-log hourly forever.
- Topic strings are the wire format. Renaming one on either side yields an app
  subscribed to a topic nobody publishes to — pushes stop, nothing errors.
  `app/test/cve_notifications_test.dart` pins the four names as literals.

**Retired: the `security` topic.** It once carried every CVE at every severity.
The scraper no longer sends to it, and `kRetiredTopics` in
[notification_service.dart](app/lib/services/notification_service.dart) unsubscribes
every device from it on **every launch, Pro or not** — dropping a topic from
`kProNotificationTopics` without retiring it leaves old installs subscribed forever
with no switch to turn it off. Unsubscribe is idempotent, so retirement is
self-healing across offline launches.

### Adding a source

- **RSS feed (curated):** append a `{url, source, tags}` dict to `RSS_SOURCES` in `scraper/sources/rss.py`.
- **GitHub repo releases:** append a `{repo, source, tags}` dict to `GITHUB_REPOS` in `scraper/sources/github_releases.py`. Drafts and prereleases are filtered out.
- **Security advisories:** the Red Hat Hydra Security Data API is queried per package keyword in `_PACKAGE_QUERIES` in `scraper/sources/security.py`; relevance is filtered by `_RELEVANT_KEYWORDS` against title + affected_packages.
- **OCP stable-channel versions:** auto-discovered by [scraper/sources/ocp_versions.py](scraper/sources/ocp_versions.py) from the `stable-4.*.yaml` files in `openshift/cincinnati-graph-data`. Upserts into `ocp_versions` (`ON CONFLICT minor_version`) and emits an `Article` for new channels and new stable promotions. There is no per-source config — the fetcher enumerates active minors itself, gated by `ACTIVE_MINOR_MINIMUM` ([scraper/sources/ocp_versions.py:32](scraper/sources/ocp_versions.py#L32)). **Mirror constant on the Flutter side:** `kOcpActiveMinorMinimum` in [app/lib/models/ocp_version.dart](app/lib/models/ocp_version.dart) — bump both together when Red Hat EOLs a minor. First-ever run uses `seed_only=True` so the table is primed without flooding the feed with historical articles. The Flutter side reads the table directly for [app/lib/screens/versions_screen.dart](app/lib/screens/versions_screen.dart) and the desktop sidebar widget.

- **Layered-product (operator) GAs:** auto-discovered by [scraper/sources/operator_lifecycles.py](scraper/sources/operator_lifecycles.py) by scraping the Red Hat Operator Life Cycles page. There is no operator list in code — operators are enumerated from the page. Unlike every other fetcher this source has **no release event**, only page state, so new GAs are detected by diffing each operator's version against the `operator_versions` table (`ON CONFLICT operator_key`); the schema is documented in the module header, as with `ocp_versions.py`. Notes when touching it:
  - The **hardcoded landmarks** are the tier `<h1>` ids (`platform-agnostic`, `rolling-stream`) and nothing else. `platform-aligned` is deliberately skipped — those operators track OCP and are `ocp_versions.py`'s job. If either section can't be found the fetcher aborts cleanly, emitting nothing and leaving state untouched.
  - State is keyed on the accordion `data-id` (`operator_key`), **not the operator name** — some operators appear in two tiers (Red Hat Connectivity Link is both Agnostic and Rolling) and a name key would cross-contaminate them.
  - Only `latest_version` is compared. The page churns constantly on support-end dates; date-only edits must stay invisible.
  - `articles.url` gets an operator+version fragment (`…openshift_operators#redHatOpenshiftGitops-Agnostic-1-21`) precisely because `url` is the global unique key — a version-less URL would overwrite the prior GA in place and, with `notified` still true, silently stop all future pushes for that operator.
  - First-ever run uses `seed_only=True` (same pattern as `ocp_versions.py`): ~60 operators would otherwise land in the feed at once. The `operator_versions` table was seeded against the live page on 2026-07-16, so this path is already spent — it only re-arms if the table is emptied.
  - Tests parse a pruned fixture of the real page at `scraper/tests/fixtures/openshift_operators.html`. It intentionally retains the page's real malformed entries (a prose table row, an `N/A` version, a name-only entry) — don't "clean it up".

For curated sources there is no config file — everything is in code. **Per-user RSS feeds (Phase 6) are different:** they live in `user_rss_sources` and are added by Pro users via the app, not in code. The scraper picks them up automatically each run via [`fetch_user_sources()`](scraper/sources/user_rss.py).

**Untrusted-URL safety.** Because Pro users supply arbitrary feed URLs, [`sources/rss.py`](scraper/sources/rss.py) fetches feed bytes through [`sources/safe_fetch.py::fetch_feed_bytes()`](scraper/sources/safe_fetch.py) — a scheme allowlist (http/https only), DNS+IP guard that rejects loopback/link-local/private/cloud-metadata addresses, redirect re-validation on every hop, and connect/read timeouts plus a hard response-size cap. feedparser is deliberately handed the already-fetched bytes, **never the URL**, because it would otherwise do its own unguarded network I/O (and would resolve `file://`). Keep that invariant when touching feed fetching.

### FCM: topics + per-token sends

Two delivery modes coexist:

1. **Topic broadcasts** — used for the curated firehose. The Flutter client subscribes on launch (Android/iOS only) to:
   - `all` — daily digest notifications
   - `releases` — release alerts (single + batch)
   - `cve_critical` / `cve_high` / `cve_medium` / `cve_low` — CVE alerts (single + batch), one topic per severity bucket; see "CVE severity routing" above. These four default **off** (`defaultTopicEnabled`) — a Pro user opts into each level on the CVE notifications screen. `all` and `releases` keep the historical opt-out default.
   - `security` — **retired.** Nothing publishes to it; every device unsubscribes on launch. See "CVE severity routing".

   Subscription is decided by `NotificationService.planTopicSubscriptions()` (pure, prefs-only, testable) and performed by `applyTopicSubscriptions()` (the Firebase I/O). Keep that split — the reconcile rules are untestable otherwise, since `FirebaseMessaging.instance` throws without a live Firebase. For the same reason every `FirebaseMessaging.instance` access sits *inside* a try/catch: a failed Firebase init must not propagate out of a settings toggle.
2. **Per-token sends** — used for Pro user-scoped pushes (custom alert rules, personalised digests). [`DeviceTokenService`](app/lib/services/device_token_service.dart) registers the device's FCM token in `user_device_tokens` after sign-in / token refresh; the scraper joins that table when dispatching via [`FCMSender.send_to_token()`](scraper/fcm.py). On 404/410 the token is pruned automatically.

Notification channel ID is `shiftfeed_alerts` and must match between [scraper/fcm.py](scraper/fcm.py) and [app/lib/services/notification_service.dart](app/lib/services/notification_service.dart). The Firebase project ID is hardcoded in `scraper/fcm.py::FCM_URL`.

### Flutter app shape

[app/lib/main.dart](app/lib/main.dart) initializes Supabase, then conditionally initializes Firebase + `NotificationService` only when `!kIsWeb && (Android || iOS)` — Linux/macOS/Windows/web skip Firebase. `ArticleRepository` ([app/lib/repositories/article_repository.dart](app/lib/repositories/article_repository.dart)) is the only Supabase reader; both `HomeScreen` and `DigestScreen` go through it. `ThemeNotifier` + `provider` drive light/dark switching.

**Mobile vs desktop layout split.** `HomeScreen.build` routes at `_desktopBreakpoint = 900` between `_buildMobile` (BottomNav + IndexedStack of feed/versions/cves/saved/settings) and `_buildDesktop` (left sidebar nav + grid + right sidebar with OCP versions, latest CVEs, top sources, popular tags). Same state, repository, and search backing — completely different shells. Editing the feed UI usually means updating both paths.

**Bottom-nav tabs are declared in [nav_tabs.dart](app/lib/screens/nav_tabs.dart), never as integer literals.** The `NavTab` enum is the source of truth for tab order; `bottomNavItems` builds the bar from it, and `NavTab.isValidIndex` is the bounds guard. This exists because the nav previously used bare indices (`_bottomNavIndex == 2` driving the Versions self-heal refetch and the Saved swipe hint, plus an `i > 3` guard), and inserting a tab meant hand-shifting every one — **a missed shift fails silently**: it still compiles, the analyzer says nothing, and the swipe hint just quietly fires on the wrong tab or a real tab routes to "Coming soon". Compare `_bottomNavIndex` to `NavTab.<tab>.index` only. The one invariant the enum can't enforce is that the `IndexedStack` children stay in the same order; `test/nav_tabs_test.dart` pins that (and the no-bare-literal rule) by asserting against the source text.

**Screen names are a trap.** [settings_screen.dart](app/lib/screens/settings_screen.dart) (`SettingsScreen`) is the *Settings* tab — the thing users change. [about_screen.dart](app/lib/screens/about_screen.dart) (`AboutScreen`) is a separate screen pushed from a row at the bottom of Settings, holding app identity (icon, version via `release_info.dart`, tagline), the Data section, external links, and the RevenueCat ID copy. Historically `AboutScreen` *was* the settings tab; don't conflate them.

**Settings' Notifications section is two switches plus a tile.** `_NotificationsSection` holds the `all` and `releases` switches inline; CVE alerts are a `ListTile` pushing [cve_notifications_screen.dart](app/lib/screens/cve_notifications_screen.dart), because four independent per-severity subscriptions don't collapse into one on/off. That screen's rows are generated from `CveSeverity.values` (labels, order and colours from the same enum the CVE screen filters by) — don't hand-write the four rows, or the notification labels drift from the badges. Pro-gating is the shared pattern: re-check `EntitlementService.isPro()` on **every flip** rather than trusting a cached value, revert the switch and show `PaywallSheet(reason: PaywallReason.notifications)` when it fails.

**One app bar across the four tabs.** [main_app_bar.dart](app/lib/widgets/main_app_bar.dart) renders the wordmark ([brand_title.dart](app/lib/widgets/brand_title.dart), which resolves the PRO badge itself off `EntitlementService`) plus four actions: search, view-mode toggle, AI Briefing (Pro-gated via the shared top-level `openDigest(context)` — web exempt), theme toggle. Actions a screen can't act on are **greyed, not dropped**, so the bar's shape never shifts: `onSearch` is null everywhere but the feed, `viewToggleEnabled` is true only on feed + Saved. `VersionsScreen` / `BookmarksScreen` / `SettingsScreen` each take an `isTab` flag — true inside the `IndexedStack` (wear `MainAppBar`), false when the desktop sidebar pushes them as routes (keep their own descriptive title + back arrow). Both paths exist in every one of those files.

**View mode is global.** `LayoutNotifier` (`ViewMode.grid` = full card, `ViewMode.list` = compact) is an app-wide provider persisted to `SharedPreferences`; the feed *and* the Saved list both pass `compact:` to `ArticleCard` from it. A new card list should honour it too.

**Saved screen.** Removal is swipe-only (`Dismissible` + Undo snackbar) plus the in-card bookmark icon; there is deliberately no bulk clear-all and no bookmark export — `ExportService` now shares the AI briefing and nothing else. Because the swipe isn't discoverable, the first card demos it on every visit (slide out, bounce back) until the user really swipe-deletes once, which sets the `saved_swipe_hint_done` pref. The replay hangs off the same `isActive` flag pattern `VersionsScreen` uses: the `IndexedStack` keeps the State alive, so `initState` fires once and `didUpdateWidget` is what sees a tab revisit.

**Theme awareness.** Don't hardcode `kSurface` / `kTextPrimary` etc. in widgets — use the helpers in [app/lib/theme/app_theme.dart](app/lib/theme/app_theme.dart) (`surfaceOf(context)`, `borderOf(context)`, `textMutedOf(context)`, etc.) or the theme-aware getters on widgets like `HomeScreen`'s `_textPrimary` / `_surface` / `_border`. That's how light mode stays correct.

**Selection controls are shared: [filter_pill.dart](app/lib/widgets/filter_pill.dart) (multi/single-select chips) and [toggle_button.dart](app/lib/widgets/toggle_button.dart) (single-select).** Both are used by the feed and the CVE screen; reuse them rather than rolling a new chip. The CVE screen originally did roll its own, with a transparent fill and `kTextMuted` text — 2.61:1 in dark mode, under WCAG's 4.5:1 for text and even its 3:1 for UI. **Both now use a 6dp radius, matching the info cards** (CVE rows, version cards, submit form) so controls and content read as one language; `FilterPill` was squared off from 20. Consequence: on the CVE screen the `ToggleButton` sort row and the `FilterPill` severity row below it now share both radius **and** height (`ToggleButton(dense: true)` pins its height to `FilterPill.heightOf`), so the only remaining cues that one is single-select and the other multi are the SORT / FILTER labels and the fill colors. If they ever need to read as more distinct, change fill or type — not radius or height, which are now deliberately shared. `dense` is opt-in: the feed's desktop Latest/Top toggle keeps Material's full-size button. Note the feed's `ArticleCard` is still 8dp, the one card that doesn't match the 6dp majority.

**`dense` has to defeat two Material defaults, not just padding.** `FilledButton` carries a 48dp `minimumSize` *and* `MaterialTapTargetSize.padded`, which inflates the laid-out box to the 48dp tap target. Setting padding alone leaves a dense button measuring 48 next to a 28 pill; `minimumSize`/`maximumSize`/`tapTargetSize: shrinkWrap` are all required. `test/cve_controls_layout_test.dart` pins the match at two text scales and checks the shrunken button is still tappable.

**The CVE control block runs on an 8dp rhythm** (`_gap` in [cve_screen.dart](app/lib/screens/cve_screen.dart)): red rule → sort row → filter row → grey divider → first card. The two row labels share a measured column width (`_labelColumnWidth`, a `TextPainter` over the merged style, same reasoning as `FilterPill.heightOf`) so the sort buttons and severity pills share a left edge — don't hardcode that width, 'FILTER' outgrows 'SORT' by an amount that depends on the font and text scale. Verify spacing by measuring pixel rows off a device screenshot: at 450dpi one 8dp gap is 22.5 device px, so it renders as 21-22 and the nominal numbers will not match what you measure.

Text on a selected (solid accent) fill must come from `onAccent(color)`, never a hardcoded `Colors.white`: the severity amber `#FFAA00` renders at 1.91:1 against white. `onAccent`'s `kAccentLuminanceThreshold` is **0.40, not the conventional 0.5, on purpose** — amber measures 0.5001, so a 0.5 rule decides it by 0.0001 and any palette tweak flips it silently. Every color the feed passes sits below 0.31, so they all resolve to white and render unchanged; `test/filter_pill_test.dart` pins both facts. Known gap: `CveSeverity.high` and the feed's SECURITY chip share `#FF6600` at 2.94:1 white — under the 3:1 UI floor. Darkening that one shared orange fixes both screens at once.

**`FilterPill.heightOf(context)` is measured, not computed.** `MainAppBar.bottomHeight` must be ≥ the chip row's real height (preferredSize is read before `bottom` is laid out), and the old call-site formula guessed `fontSize * 1.3 + padding` = 26.3dp against a real 28.0dp — the app bar had been silently under-reserving. There is no multiplier that predicts it: `Text` merges its style over the ambient `DefaultTextStyle`, so the line box depends on the theme's font metrics *and* its `height` multiplier. `heightOf` runs a `TextPainter` over the merged style. Same trap as [text_metrics.dart](app/lib/theme/text_metrics.dart) — measure, don't derive.

**Spacing is optical, and two things lie to you.** Gaps in this UI are measured to the *glyphs*, not the widget boxes, because a `Text`'s line box carries a blank strip above its glyphs and another below the baseline — a nominal 16dp can render as 21dp. [theme/text_metrics.dart](app/lib/theme/text_metrics.dart) (`inkTop(size, height)` / `inkBottom(size, height)`, constants measured off a device screenshot) is the shared compensation, used by [article_card.dart](app/lib/widgets/article_card.dart) and [settings_screen.dart](app/lib/screens/settings_screen.dart). It only applies to text that sets an explicit `height` + `leadingDistribution: TextLeadingDistribution.even`. Second liar: Material's `Card` defaults to a **4dp margin on every side** — set `margin: EdgeInsets.zero` or every gap between stacked cards is silently 8dp larger than written. When changing spacing, verify on a device (`adb exec-out screencap`) and measure pixel rows; the nominal numbers in the code will not match what you see otherwise.

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

When building a release AAB, follow the ritual in ~/coding/skills/flutter-aab-release.md. The version is tracked in three places that the ritual keeps in sync: `version: x.y.z+b` in [app/pubspec.yaml](app/pubspec.yaml), the `kAppVersion` / `kBuildNumber` / `kReleaseName` constants in [app/lib/release_info.dart](app/lib/release_info.dart) (rendered on the About screen alongside the live `package_info_plus` version), and a new row in [app/RELEASES.md](app/RELEASES.md). Codenames are alliterative and advance one letter per release.

### CI

- [.github/workflows/scrape.yml](.github/workflows/scrape.yml) runs `python -m scraper.main` hourly (`0 * * * *`) and on `workflow_dispatch`. **Deps are listed inline in the workflow's `pip install` line, not pulled from `pyproject.toml`. Adding a scraper dependency means updating BOTH [scraper/pyproject.toml](scraper/pyproject.toml) AND that pip install line.**
- [.github/workflows/deploy_web.yml](.github/workflows/deploy_web.yml) runs on every push to `main`: `flutter build web` with Supabase creds via `--dart-define`, then `peaceiris/actions-gh-pages` publishes `app/build/web` to the `gh-pages` branch (live at https://neywa.github.io/shiftfeed/, base href `/shiftfeed/`).

## Supabase migrations

SQL migration files live in `app/lib/sql/`. Run them manually in the Supabase dashboard SQL editor in phase order. They are not executed by the app.
