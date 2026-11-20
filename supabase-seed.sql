-- ShiftFeed core schema
--
-- This migration owns the curated tables written by the Python scraper.
-- The user-scoped tables and their RLS policies remain in app/lib/sql/phase*.sql
-- (copied to seeds/ in this local Supabase project).

-- Curated feed entries. `url` is the scraper's global idempotency key.
create table if not exists public.articles (
  id           uuid primary key default gen_random_uuid(),
  title        text not null,
  url          text not null unique,
  source       text not null,
  tags         text[] not null default '{}',
  summary      text,
  published_at timestamptz,
  created_at   timestamptz not null default now(),
  notified     boolean not null default false,
  -- Phase 6's custom RSS feature writes this as null for curated entries.
  submitted_by uuid references auth.users(id) on delete set null,
  search_vector tsvector generated always as (
    to_tsvector(
      'english',
      coalesce(title, '') || ' ' || coalesce(summary, '')
    )
  ) stored
);

create index if not exists articles_published_at_idx
  on public.articles (published_at desc);
create index if not exists articles_created_at_idx
  on public.articles (created_at desc);
create index if not exists articles_source_idx
  on public.articles (source);
create index if not exists articles_tags_idx
  on public.articles using gin (tags);
create index if not exists articles_search_vector_idx
  on public.articles using gin (search_vector);

-- Phase 6 owns articles RLS because its policies distinguish global rows
-- from custom-feed rows. Run phase6_custom_rss.sql before using the app.

-- A per-CVE cache and sidebar index. `article_url` intentionally remains a
-- plain value rather than a foreign key: one CVE may be discovered in
-- multiple articles and historical alert records should survive feed cleanup.
create table if not exists public.cve_alerts (
  id          uuid primary key default gen_random_uuid(),
  cve_id      text not null unique,
  title       text not null,
  article_url text not null,
  severity    text,
  cvss        numeric(3, 1) check (cvss between 0 and 10),
  detected_at timestamptz not null default now(),
  notified    boolean not null default false
);

create index if not exists cve_alerts_detected_at_idx
  on public.cve_alerts (detected_at desc);

alter table public.cve_alerts enable row level security;
create policy "cve_alerts: public read"
  on public.cve_alerts for select using (true);

-- One generated shared briefing per calendar day.
create table if not exists public.digests (
  id           uuid primary key default gen_random_uuid(),
  digest_date  date not null unique,
  summary      text not null,
  top_articles jsonb not null default '[]'::jsonb,
  generated_at timestamptz not null default now()
);

create index if not exists digests_digest_date_idx
  on public.digests (digest_date desc);

alter table public.digests enable row level security;
create policy "digests: public read"
  on public.digests for select using (true);

-- Latest stable release in each OpenShift stable channel.
create table if not exists public.ocp_versions (
  id            uuid primary key default gen_random_uuid(),
  minor_version text not null unique,
  latest_stable text not null,
  ga            date,
  is_eus        boolean,
  full_support_end date,
  maintenance_end  date,
  eus_end          date,
  updated_at    timestamptz not null default now()
);

alter table public.ocp_versions enable row level security;
create policy "ocp_versions: public read"
  on public.ocp_versions for select using (true);

-- Latest GA release for each non-platform-aligned operator.
create table if not exists public.operator_versions (
  id             uuid primary key default gen_random_uuid(),
  operator_key   text not null unique,
  operator_name  text not null,
  tier           text not null,
  latest_version text not null,
  updated_at     timestamptz not null default now()
);

alter table public.operator_versions enable row level security;
create policy "operator_versions: public read"
  on public.operator_versions for select using (true);

-- Anonymous link submissions are inserted by the Flutter client. No read
-- policy is deliberately provided: reviewing submissions is an admin task.
create table if not exists public.submissions (
  id           uuid primary key default gen_random_uuid(),
  url          text not null unique,
  title        text,
  submitted_at timestamptz not null default now()
);

alter table public.submissions enable row level security;
create policy "submissions: public insert"
  on public.submissions for insert with check (true);
