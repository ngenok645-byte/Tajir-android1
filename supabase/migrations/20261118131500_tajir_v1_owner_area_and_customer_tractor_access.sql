-- Applied to the connected TAJIR Supabase project for v1.
alter table public.tractor_assets add column if not exists current_operating_area text;
alter table public.tractor_assets add column if not exists operating_area_updated_at timestamptz;

create table if not exists public.tractor_owner_profiles (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null unique references public.profiles(id) on delete cascade,
 full_name text not null, phone text not null, company_name text,
 status text not null default 'pending' check(status in ('pending','verified','rejected','suspended')),
 operating_mode text not null default 'tajir_managed' check(operating_mode in ('tajir_managed','independent_management','both')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.tractor_owner_assets (
 id uuid primary key default gen_random_uuid(),
 owner_id uuid not null references public.tractor_owner_profiles(id) on delete cascade,
 tractor_id uuid not null unique references public.tractor_assets(id) on delete cascade,
 ownership_document_path text,
 verification_status text not null default 'pending' check(verification_status in ('pending','verified','rejected')),
 verified_by uuid references public.profiles(id), verified_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.tractor_operating_area_history (
 id uuid primary key default gen_random_uuid(),
 tractor_id uuid not null references public.tractor_assets(id) on delete cascade,
 old_area text, new_area text not null, changed_by uuid references public.profiles(id),
 changed_at timestamptz not null default now(), note text
);
create index if not exists tractor_operating_area_history_tractor_time_idx on public.tractor_operating_area_history(tractor_id,changed_at desc);
create table if not exists public.worker_issue_reports (
 id uuid primary key default gen_random_uuid(),
 worker_profile_id uuid not null references public.profiles(id) on delete cascade,
 tractor_id uuid references public.tractor_assets(id) on delete set null,
 job_id uuid references public.tractor_service_jobs(id) on delete set null,
 issue_type text not null check(issue_type in ('breakdown','accident','safety','maintenance','other')),
 description text not null, attachment_paths text[] not null default '{}',
 status text not null default 'received' check(status in ('received','approved','in_progress','resolved','rejected')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

alter table public.tractor_owner_profiles enable row level security;
alter table public.tractor_owner_assets enable row level security;
alter table public.tractor_operating_area_history enable row level security;
alter table public.worker_issue_reports enable row level security;
drop policy if exists tractor_owner_profiles_self_read on public.tractor_owner_profiles;
create policy tractor_owner_profiles_self_read on public.tractor_owner_profiles for select to authenticated using(profile_id=auth.uid());
drop policy if exists tractor_owner_assets_owner_read on public.tractor_owner_assets;
create policy tractor_owner_assets_owner_read on public.tractor_owner_assets for select to authenticated using(
 exists(select 1 from public.tractor_owner_profiles o where o.id=owner_id and o.profile_id=auth.uid()));
drop policy if exists tractor_area_history_owner_read on public.tractor_operating_area_history;
create policy tractor_area_history_owner_read on public.tractor_operating_area_history for select to authenticated using(
 exists(select 1 from public.tractor_owner_assets oa join public.tractor_owner_profiles o on o.id=oa.owner_id
 where oa.tractor_id=tractor_operating_area_history.tractor_id and o.profile_id=auth.uid()));
drop policy if exists worker_issue_reports_own_read on public.worker_issue_reports;
create policy worker_issue_reports_own_read on public.worker_issue_reports for select to authenticated using(worker_profile_id=auth.uid());

create or replace function public.customer_list_tractor_services()
returns table(tractor_id uuid,selection_label text) language plpgsql stable security definer set search_path=''
as $$
begin
 if not exists(select 1 from public.customers c join public.profiles p on p.id=c.profile_id
  where c.profile_id=auth.uid() and c.active and p.status::text='active' and c.customer_type in('buyer','seller'))
 then raise exception 'An active customer account is required.'; end if;
 return query select t.id,('Tractor option '||row_number() over(order by t.created_at,t.id))::text
 from public.tractor_assets t join public.branches b on b.id=t.branch_id
 where t.status='available' and b.is_active order by t.created_at,t.id;
end; $$;

create or replace function public.customer_list_tractor_bookings()
returns table(id uuid,job_number text,service_type text,service_location text,area_acres numeric,booked_for timestamptz,status text,total_charge numeric,created_at timestamptz)
language plpgsql stable security definer set search_path=''
as $$
declare v_customer_id uuid;
begin
 select c.id into v_customer_id from public.customers c join public.profiles p on p.id=c.profile_id
 where c.profile_id=auth.uid() and c.active and p.status::text='active' and c.customer_type in('buyer','seller');
 if v_customer_id is null then raise exception 'An active customer account is required.'; end if;
 return query select j.id,j.job_number,j.service_type,j.service_location,j.area_acres,j.booked_for,j.status,j.total_charge,j.created_at
 from public.tractor_service_jobs j where j.customer_id=v_customer_id order by j.created_at desc;
end; $$;

create or replace function public.customer_book_tractor_service(p_tractor_id uuid,p_service_type text,p_service_location text,
 p_area_acres numeric default null,p_booked_for timestamptz default null,p_notes text default null)
returns table(job_id uuid,job_number text) language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype; v_tractor public.tractor_assets%rowtype; v_job_number text; v_job_id uuid;
begin
 select c.* into v_customer from public.customers c join public.profiles p on p.id=c.profile_id
 where c.profile_id=auth.uid() and c.active and p.status::text='active' and c.customer_type in('buyer','seller') for update of c;
 if v_customer.id is null then raise exception 'An active customer account is required.'; end if;
 if p_service_type not in('ploughing','planting','harrowing','transport','other') then raise exception 'Select a valid service.'; end if;
 if length(trim(coalesce(p_service_location,'')))<3 then raise exception 'Enter the farm location.'; end if;
 if p_area_acres is not null and p_area_acres<=0 then raise exception 'Acres must be greater than zero.'; end if;
 if p_booked_for is not null and p_booked_for<now() then raise exception 'Choose a future booking date.'; end if;
 select t.* into v_tractor from public.tractor_assets t join public.branches b on b.id=t.branch_id
 where t.id=p_tractor_id and t.status='available' and b.is_active for update of t;
 if v_tractor.id is null then raise exception 'This tractor is no longer available. Refresh and select another.'; end if;
 v_job_number:='TR-'||to_char(now(),'YYMMDDHH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.tractor_service_jobs(job_number,branch_id,tractor_id,customer_id,farmer_name,farmer_phone,service_type,service_location,
 area_acres,booked_for,estimated_hours,rate,total_charge,status,notes)
 values(v_job_number,v_tractor.branch_id,v_tractor.id,v_customer.id,v_customer.full_name,v_customer.phone,p_service_type,
 trim(p_service_location),p_area_acres,p_booked_for,1,0,0,'booked',nullif(trim(coalesce(p_notes,'')),'')) returning id into v_job_id;
 return query select v_job_id,v_job_number;
end; $$;

create or replace function public.owner_update_tractor_operating_area(p_tractor_id uuid,p_new_area text,p_note text default null)
returns void language plpgsql security definer set search_path=''
as $$
declare v_old_area text;
begin
 if length(trim(coalesce(p_new_area,'')))<2 then raise exception 'Enter the tractor operating area.'; end if;
 select t.current_operating_area into v_old_area from public.tractor_assets t
 join public.tractor_owner_assets oa on oa.tractor_id=t.id join public.tractor_owner_profiles op on op.id=oa.owner_id
 where t.id=p_tractor_id and op.profile_id=auth.uid() and op.status='verified' and oa.verification_status='verified' for update of t;
 if not found then
  if not exists(select 1 from public.user_role_assignments ura join public.app_roles ar on ar.id=ura.role_id
   where ura.user_id=auth.uid() and ura.is_active and ar.code in('director','branch_manager'))
  then raise exception 'You are not authorized to update this tractor area.'; end if;
  select current_operating_area into v_old_area from public.tractor_assets where id=p_tractor_id for update;
  if not found then raise exception 'Tractor not found.'; end if;
 end if;
 update public.tractor_assets set current_operating_area=trim(p_new_area),operating_area_updated_at=now(),updated_at=now() where id=p_tractor_id;
 insert into public.tractor_operating_area_history(tractor_id,old_area,new_area,changed_by,note)
 values(p_tractor_id,v_old_area,trim(p_new_area),auth.uid(),nullif(trim(coalesce(p_note,'')),''));
end; $$;
revoke all on function public.owner_update_tractor_operating_area(uuid,text,text) from public,anon;
grant execute on function public.owner_update_tractor_operating_area(uuid,text,text) to authenticated;
grant execute on function public.customer_list_tractor_services() to authenticated;
grant execute on function public.customer_list_tractor_bookings() to authenticated;
grant execute on function public.customer_book_tractor_service(uuid,text,text,numeric,timestamptz,text) to authenticated;
