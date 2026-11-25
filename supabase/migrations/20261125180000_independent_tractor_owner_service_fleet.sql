create table if not exists public.tractor_owner_service_fleet (
  id uuid primary key default gen_random_uuid(),
  owner_profile_id uuid not null references public.tractor_owner_profiles(id) on delete cascade,
  tractor_name text not null,
  make_model text,
  ownership_type text not null default 'owned' check (ownership_type in ('owned','borrowed','leased')),
  operating_county text,
  operating_region text,
  operating_village text,
  services text[] not null default array['ploughing']::text[],
  status text not null default 'available' check (status in ('available','busy','maintenance','inactive')),
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tractor_owner_service_fleet_owner_idx on public.tractor_owner_service_fleet(owner_profile_id,created_at desc);
alter table public.tractor_owner_service_fleet enable row level security;
drop policy if exists tractor_owner_service_fleet_owner_select on public.tractor_owner_service_fleet;
create policy tractor_owner_service_fleet_owner_select on public.tractor_owner_service_fleet for select to authenticated
using (exists(select 1 from public.tractor_owner_profiles o where o.id=owner_profile_id and o.profile_id=auth.uid()));
drop policy if exists tractor_owner_service_fleet_owner_insert on public.tractor_owner_service_fleet;
create policy tractor_owner_service_fleet_owner_insert on public.tractor_owner_service_fleet for insert to authenticated
with check (exists(select 1 from public.tractor_owner_profiles o where o.id=owner_profile_id and o.profile_id=auth.uid()));
drop policy if exists tractor_owner_service_fleet_owner_update on public.tractor_owner_service_fleet;
create policy tractor_owner_service_fleet_owner_update on public.tractor_owner_service_fleet for update to authenticated
using (exists(select 1 from public.tractor_owner_profiles o where o.id=owner_profile_id and o.profile_id=auth.uid()))
with check (exists(select 1 from public.tractor_owner_profiles o where o.id=owner_profile_id and o.profile_id=auth.uid()));
drop policy if exists tractor_owner_service_fleet_director_read on public.tractor_owner_service_fleet;
create policy tractor_owner_service_fleet_director_read on public.tractor_owner_service_fleet for select to authenticated
using (private.has_app_role('director'));
grant select,insert,update on public.tractor_owner_service_fleet to authenticated;