-- Phase 6: Custom RSS sources per user
-- Run in Supabase SQL editor before deploying this version.

-- User-defined RSS feed URLs
create table if not exists public.user_rss_sources (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null references auth.users(id) on delete cascade,
  url         text not null,
  label       text not null,             -- user-defined display name
  enabled     boolean not null default true,
  added_at    timestamptz not null default now(),
  last_error  text,                      -- last fetch error message, null if ok
  unique (user_id, url)
);

alter table public.user_rss_sources enable row level security;

create policy "user_rss_sources: users access own rows"
  on public.user_rss_sources
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists user_rss_sources_user_id_idx
  on public.user_rss_sources (user_id);

-- Add submitted_by column to articles for user-scoped feed entries
-- (nullable — null means global/curated article)
alter table public.articles
  add column if not exists submitted_by uuid
  references auth.users(id) on delete set null;

create index if not exists articles_submitted_by_idx
  on public.articles (submitted_by)
  where submitted_by is not null;

-- RLS: global articles visible to all; user articles visible to owner only.
-- IMPORTANT: run this only if RLS is not yet enabled on articles.
-- If it is already enabled, only add the new policy.
alter table public.articles enable row level security;

create policy "articles: global rows visible to all"
  on public.articles for select
  using (submitted_by is null);

create policy "articles: user rows visible to owner"
  on public.articles for select
  using (auth.uid() = submitted_by);

-- Service-role key (used by scraper) bypasses RLS automatically.
-- No insert/update policy needed for the app — only scraper writes articles.
