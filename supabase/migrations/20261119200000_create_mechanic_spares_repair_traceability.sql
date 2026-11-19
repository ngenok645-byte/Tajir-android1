-- Mechanics, independent auto-spares shops, repair jobs and auditable parts movement.
create table if not exists public.mechanic_profiles (
 id uuid primary key default gen_random_uuid(), profile_id uuid not null unique references auth.users(id) on delete cascade,
 business_name text not null, phone text not null unique, location text not null, services text[] not null default '{}',
 status text not null default 'pending' check(status in ('pending','approved','suspended','rejected')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.auto_spares_profiles (
 id uuid primary key default gen_random_uuid(), profile_id uuid not null unique references auth.users(id) on delete cascade,
 shop_name text not null, phone text not null unique, location text not null,
 status text not null default 'pending' check(status in ('pending','approved','suspended','rejected')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.auto_spares_inventory (
 id uuid primary key default gen_random_uuid(), shop_id uuid not null references public.auto_spares_profiles(id) on delete cascade,
 part_name text not null, part_reference text, description text, quantity numeric(12,2) not null default 0 check(quantity>=0),
 unit text not null default 'piece', price_kes numeric(12,2) not null check(price_kes>=0),
 status text not null default 'active' check(status in ('active','paused','out_of_stock')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists auto_spares_inventory_shop_idx on public.auto_spares_inventory(shop_id,status);
create table if not exists public.tractor_repair_jobs (
 id uuid primary key default gen_random_uuid(), job_number text not null unique,
 owner_profile_id uuid not null references public.tractor_owner_profiles(id), tractor_id uuid references public.tractor_assets(id),
 owner_user_id uuid not null references auth.users(id), mechanic_id uuid not null references public.mechanic_profiles(id),
 issue_description text not null, location text not null,
 status text not null default 'requested' check(status in ('requested','accepted','in_progress','waiting_parts','completed','cancelled','disputed')),
 estimated_cost_kes numeric(12,2), final_cost_kes numeric(12,2), requested_at timestamptz not null default now(), completed_at timestamptz
);
create index if not exists tractor_repair_jobs_owner_idx on public.tractor_repair_jobs(owner_user_id,requested_at desc);
create index if not exists tractor_repair_jobs_mechanic_idx on public.tractor_repair_jobs(mechanic_id,status);
create table if not exists public.repair_part_requests (
 id uuid primary key default gen_random_uuid(), repair_job_id uuid not null references public.tractor_repair_jobs(id) on delete cascade,
 mechanic_id uuid not null references public.mechanic_profiles(id), shop_id uuid not null references public.auto_spares_profiles(id),
 inventory_id uuid not null references public.auto_spares_inventory(id), quantity numeric(12,2) not null check(quantity>0),
 agreed_unit_price_kes numeric(12,2) not null check(agreed_unit_price_kes>=0),
 status text not null default 'requested' check(status in ('requested','accepted','declined','supplied','installed','cancelled')),
 requested_at timestamptz not null default now(), supplied_at timestamptz, installed_at timestamptz
);
create index if not exists repair_part_requests_job_idx on public.repair_part_requests(repair_job_id);
create index if not exists repair_part_requests_shop_idx on public.repair_part_requests(shop_id,status);
alter table public.mechanic_profiles enable row level security;
alter table public.auto_spares_profiles enable row level security;
alter table public.auto_spares_inventory enable row level security;
alter table public.tractor_repair_jobs enable row level security;
alter table public.repair_part_requests enable row level security;
grant select,insert,update on public.mechanic_profiles,public.auto_spares_profiles to authenticated;
grant select,insert,update,delete on public.auto_spares_inventory to authenticated;
grant select,insert,update on public.tractor_repair_jobs,public.repair_part_requests to authenticated;
create policy mechanic_profiles_read on public.mechanic_profiles for select to authenticated using(status='approved' or profile_id=(select auth.uid()) or (select private.has_app_role('director')));
create policy mechanic_profiles_insert_self on public.mechanic_profiles for insert to authenticated with check(profile_id=(select auth.uid()) and status='pending');
create policy mechanic_profiles_update_self on public.mechanic_profiles for update to authenticated using(profile_id=(select auth.uid())) with check(profile_id=(select auth.uid()) and status in ('pending','approved'));
create policy auto_spares_profiles_read on public.auto_spares_profiles for select to authenticated using(status='approved' or profile_id=(select auth.uid()) or (select private.has_app_role('director')));
create policy auto_spares_profiles_insert_self on public.auto_spares_profiles for insert to authenticated with check(profile_id=(select auth.uid()) and status='pending');
create policy auto_spares_profiles_update_self on public.auto_spares_profiles for update to authenticated using(profile_id=(select auth.uid())) with check(profile_id=(select auth.uid()) and status in ('pending','approved'));
create policy auto_spares_inventory_read on public.auto_spares_inventory for select to authenticated using(status='active' or exists(select 1 from public.auto_spares_profiles p where p.id=shop_id and p.profile_id=(select auth.uid())) or (select private.has_app_role('director')));
create policy auto_spares_inventory_insert on public.auto_spares_inventory for insert to authenticated with check(exists(select 1 from public.auto_spares_profiles p where p.id=shop_id and p.profile_id=(select auth.uid()) and p.status='approved'));
create policy auto_spares_inventory_update on public.auto_spares_inventory for update to authenticated using(exists(select 1 from public.auto_spares_profiles p where p.id=shop_id and p.profile_id=(select auth.uid())) or (select private.has_app_role('director'))) with check(exists(select 1 from public.auto_spares_profiles p where p.id=shop_id and p.profile_id=(select auth.uid())) or (select private.has_app_role('director')));
create policy tractor_repair_jobs_read on public.tractor_repair_jobs for select to authenticated using(owner_user_id=(select auth.uid()) or exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.profile_id=(select auth.uid())) or (select private.has_app_role('director')));
create policy tractor_repair_jobs_insert_owner on public.tractor_repair_jobs for insert to authenticated with check(owner_user_id=(select auth.uid()) and exists(select 1 from public.tractor_owner_profiles o where o.id=owner_profile_id and o.profile_id=(select auth.uid())) and exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.status='approved'));
create policy tractor_repair_jobs_update_parties on public.tractor_repair_jobs for update to authenticated using(owner_user_id=(select auth.uid()) or exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.profile_id=(select auth.uid())) or (select private.has_app_role('director'))) with check(owner_user_id=(select auth.uid()) or exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.profile_id=(select auth.uid())) or (select private.has_app_role('director')));
create policy repair_part_requests_read on public.repair_part_requests for select to authenticated using(exists(select 1 from public.tractor_repair_jobs j where j.id=repair_job_id and (j.owner_user_id=(select auth.uid()) or exists(select 1 from public.mechanic_profiles m where m.id=j.mechanic_id and m.profile_id=(select auth.uid())))) or exists(select 1 from public.auto_spares_profiles s where s.id=shop_id and s.profile_id=(select auth.uid())) or (select private.has_app_role('director')));
create policy repair_part_requests_insert_mechanic on public.repair_part_requests for insert to authenticated with check(exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.profile_id=(select auth.uid()) and m.status='approved') and exists(select 1 from public.tractor_repair_jobs j where j.id=repair_job_id and j.mechanic_id=mechanic_id) and exists(select 1 from public.auto_spares_inventory i join public.auto_spares_profiles s on s.id=i.shop_id where i.id=inventory_id and i.shop_id=shop_id and s.status='approved' and i.status='active'));
create policy repair_part_requests_update_parties on public.repair_part_requests for update to authenticated using(exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.profile_id=(select auth.uid())) or exists(select 1 from public.auto_spares_profiles s where s.id=shop_id and s.profile_id=(select auth.uid())) or (select private.has_app_role('director'))) with check(exists(select 1 from public.mechanic_profiles m where m.id=mechanic_id and m.profile_id=(select auth.uid())) or exists(select 1 from public.auto_spares_profiles s where s.id=shop_id and s.profile_id=(select auth.uid())) or (select private.has_app_role('director')));
