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

-- Red Hat lifecycle data, refreshed by scraper/sources/ocp_lifecycles.py.
-- `eus_end` is the latest end date from EUS base, Term 2, and Term 3.
alter table public.ocp_versions
  add column if not exists ga date,
  add column if not exists is_eus boolean,
  add column if not exists full_support_end date,
  add column if not exists maintenance_end date,
  add column if not exists eus_end date;