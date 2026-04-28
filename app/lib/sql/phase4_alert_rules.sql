-- Phase 4: Custom alert rules + device token registry
-- Run in Supabase SQL editor before deploying this version.

-- Device token registry (needed for targeted FCM pushes)
create table if not exists public.user_device_tokens (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  fcm_token    text not null,
  platform     text not null check (platform in ('android', 'ios')),
  updated_at   timestamptz not null default now(),
  unique (user_id, fcm_token)
);

alter table public.user_device_tokens enable row level security;

create policy "user_device_tokens: users access own rows"
  on public.user_device_tokens
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- Alert rules
create table if not exists public.user_alert_rules (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  enabled         boolean not null default true,
  categories      text[] not null default '{}',
  -- e.g. ['security','releases','ocp']
  -- empty array means all categories
  cvss_minimum    numeric(3,1),
  -- null means no threshold; only applied when security is in categories
  keywords        text[] not null default '{}',
  -- empty array means no keyword filter; matched against article title+summary
  created_at      timestamptz not null default now()
);

alter table public.user_alert_rules enable row level security;

create policy "user_alert_rules: users access own rows"
  on public.user_alert_rules
  for all
  using  (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create index if not exists user_alert_rules_user_id_idx
  on public.user_alert_rules (user_id);
