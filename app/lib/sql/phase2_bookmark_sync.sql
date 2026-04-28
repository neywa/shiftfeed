-- Phase 2: Cross-device bookmark sync
-- Run in Supabase SQL editor before deploying this version.

create table if not exists public.user_bookmarks (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  article_url  text not null,
  saved_at     timestamptz not null default now(),
  unique (user_id, article_url)
);

alter table public.user_bookmarks enable row level security;

create policy "user_bookmarks: users access own rows"
  on public.user_bookmarks
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Index for fast per-user lookups
create index if not exists user_bookmarks_user_id_idx
  on public.user_bookmarks (user_id);
