create table if not exists public.land_measurements (
  id text primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  area_m2 double precision not null check (area_m2 >= 0),
  area_acres double precision not null check (area_acres >= 0),
  perimeter_m double precision not null check (perimeter_m >= 0),
  points jsonb not null default '[]'::jsonb,
  point_count integer not null default 0,
  max_accuracy_m double precision,
  measured_at timestamptz not null default now(),
  sync_status text not null default 'synced',
  created_at timestamptz not null default now()
);
alter table public.land_measurements enable row level security;
drop policy if exists "Users create own land measurements" on public.land_measurements;
create policy "Users create own land measurements" on public.land_measurements
for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Users and directors view land measurements" on public.land_measurements;
create policy "Users and directors view land measurements" on public.land_measurements
for select to authenticated using (
  user_id = auth.uid() or private.has_app_role('director'::text)
);
drop policy if exists "Users update own land measurements" on public.land_measurements;
create policy "Users update own land measurements" on public.land_measurements
for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
grant select, insert, update on public.land_measurements to authenticated;
