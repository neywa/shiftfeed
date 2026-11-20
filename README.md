# ShiftFeed

OpenShift community news and intelligence — scrapes public OpenShift/Red Hat news sources and stores them in Supabase.

Live at: https://neywa.github.io/shiftfeed/

## Local Setup

### Prerequisites

- Python 3.11+
- Flutter (stable channel)
- Node.js 20+ and Docker Desktop, if you want to run Supabase locally

Clone the repository, then install the dependencies for the scraper and the
Flutter app:

```bash
git clone https://github.com/tihender-rh/shiftfeed.git
cd shiftfeed

python -m venv .venv
source .venv/bin/activate
python -m pip install \
  httpx "feedparser>=6.0.12,<7" supabase python-dotenv \
  "beautifulsoup4>=4.14.3,<5" "google-auth[requests]" anthropic pyyaml

cd app
flutter pub get
cd ..
```

### Environment variables

The scraper loads a root-level `.env` file automatically. Copy the example and
fill in the URL and **secret/service-role** key for the Supabase project:

```bash
cp .env.example .env
```

```dotenv
SUPABASE_URL=https://<project-ref>.supabase.co
SUPABASE_SECRET_KEY=<supabase-secret-or-service-role-key>
```

Never expose `SUPABASE_SECRET_KEY` to the Flutter client or commit `.env`.

These scraper variables are optional, depending on which integrations you want
to use:

- `GITHUB_TOKEN` — raises GitHub API rate limits while checking releases and
  OpenShift versions.
- `NVD_API_KEY` — raises NVD API rate limits for CVE enrichment.
- `ANTHROPIC_API_KEY` — enables generation of the daily AI digest.
- `FIREBASE_SERVICE_ACCOUNT_JSON` — a one-line Firebase service-account JSON
  document used to send FCM notifications. Alternatively, set
  `FIREBASE_SERVICE_ACCOUNT_FILE` to a local service-account JSON file
  (defaults to `firebase-service-account.json`).

The Flutter app uses the public Supabase URL and anon key. For local web
development, pass them at launch time:

```bash
cd app
flutter run -d chrome \
  --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<supabase-anon-key>
```

For a local-only alternative, create `app/assets/.env` with those two values.
That file is bundled with the app, so it must contain only public client
credentials such as the Supabase anon key—never the secret/service-role key.

### Run the scraper

With the virtual environment active and the root `.env` configured:

```bash
python -m scraper.main
```

To exercise the CVE notification routing without sending FCM notifications or
updating the notification ledger, run:

```bash
python -m scraper.main --dry-run-push
```

### Supabase local development

The `supabase/` directory is CLI-generated/project-managed Supabase state. It
contains the pinned CLI dependency plus the generated `supabase/` configuration
directory, migrations, and seeds. Do not create those files by hand in a new
checkout; initialize them through the CLI instead:

```bash
cd supabase
npm ci
npx supabase start
npx supabase db reset
```

`supabase start` prints the local API URL and keys. Use its API URL with the
local anon key for the Flutter app, and its service-role key as
`SUPABASE_SECRET_KEY` for the scraper. `supabase db reset` applies all tracked
migrations and seed files. To create a fresh Supabase project directory from
scratch, run `npm install --save-dev supabase` followed by `npx supabase init`
from the directory that should contain the generated `supabase/` folder.

## Deployment

The web app is deployed to GitHub Pages from the `gh-pages` branch. Pushing to
`main` starts [the deploy workflow](.github/workflows/deploy_web.yml), which
installs Flutter, builds `app` with the `/shiftfeed/` base path, and publishes
`app/build/web` to `gh-pages` using `peaceiris/actions-gh-pages`.

Configure these repository Actions secrets before deploying:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

GitHub Pages should be configured to serve the `gh-pages` branch. The scraper
runs separately every hour (and can be started manually) through
[the scrape workflow](.github/workflows/scrape.yml); it requires its own
`SUPABASE_URL`, `SUPABASE_SECRET_KEY`, `GH_TOKEN`,
`FIREBASE_SERVICE_ACCOUNT_JSON`, and `ANTHROPIC_API_KEY` repository secrets.
