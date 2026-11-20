begin;

alter table public.tractor_service_jobs
  add column if not exists owner_profile_id uuid references public.tractor_owner_profiles(id) on delete set null,
  add column if not exists owner_response_status text not null default 'pending',
  add column if not exists owner_response_at timestamptz,
  add column if not exists owner_quote_kes numeric(14,2),
  add column if not exists owner_notes text;

alter table public.tractor_service_jobs
  add constraint tractor_service_jobs_owner_response_status_check
    check (owner_response_status in ('pending','accepted','declined')),
  add constraint tractor_service_jobs_owner_quote_check
    check (owner_quote_kes is null or owner_quote_kes >= 0);

update public.tractor_service_jobs j
set owner_profile_id = a.owner_id
from public.tractor_owner_assets a
join public.tractor_owner_profiles o on o.id = a.owner_id
where a.tractor_id = j.tractor_id
  and a.verification_status = 'verified'
  and o.status = 'verified'
  and j.owner_profile_id is null;

create index if not exists tractor_service_jobs_owner_profile_status_idx
  on public.tractor_service_jobs(owner_profile_id, status, booked_for desc);

create or replace function public.tajir_link_tractor_service_owner()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_owner_id uuid;
begin
  select a.owner_id
    into v_owner_id
  from public.tractor_owner_assets a
  join public.tractor_owner_profiles o on o.id = a.owner_id
  where a.tractor_id = new.tractor_id
    and a.verification_status = 'verified'
    and o.status = 'verified'
  limit 1;

  new.owner_profile_id := v_owner_id;
  if tg_op = 'INSERT' then
    new.owner_response_status := 'pending';
  end if;
  return new;
end;
$$;

drop trigger if exists trg_tajir_link_tractor_service_owner
  on public.tractor_service_jobs;

create trigger trg_tajir_link_tractor_service_owner
before insert or update of tractor_id
on public.tractor_service_jobs
for each row
execute function public.tajir_link_tractor_service_owner();

drop policy if exists tractor_owner_read_own_service_jobs
  on public.tractor_service_jobs;

create policy tractor_owner_read_own_service_jobs
on public.tractor_service_jobs
for select
to authenticated
using (
  exists (
    select 1
    from public.tractor_owner_profiles o
    where o.id = tractor_service_jobs.owner_profile_id
      and o.profile_id = auth.uid()
      and o.status = 'verified'
  )
);

create or replace function public.owner_respond_tractor_service_job(
  p_job_id uuid,
  p_decision text,
  p_quote_kes numeric default null,
  p_notes text default null
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_status text;
  v_response text;
begin
  if auth.uid() is null then
    raise exception 'Authentication is required.';
  end if;

  select j.status, j.owner_response_status
    into v_status, v_response
  from public.tractor_service_jobs j
  join public.tractor_owner_profiles o on o.id = j.owner_profile_id
  where j.id = p_job_id
    and o.profile_id = auth.uid()
    and o.status = 'verified'
  for update of j;

  if not found then
    raise exception 'This booking is not assigned to your verified tractor account.';
  end if;
  if v_status <> 'booked' or v_response <> 'pending' then
    raise exception 'This booking has already been processed.';
  end if;

  if p_decision = 'accept' then
    if p_quote_kes is null or p_quote_kes <= 0 then
      raise exception 'Enter a quote greater than zero.';
    end if;
    update public.tractor_service_jobs
    set owner_response_status = 'accepted',
        owner_response_at = now(),
        owner_quote_kes = p_quote_kes,
        owner_notes = nullif(trim(p_notes), ''),
        status = 'confirmed'
    where id = p_job_id;
  elsif p_decision = 'decline' then
    update public.tractor_service_jobs
    set owner_response_status = 'declined',
        owner_response_at = now(),
        owner_notes = nullif(trim(p_notes), ''),
        status = 'cancelled'
    where id = p_job_id;
  else
    raise exception 'Decision must be accept or decline.';
  end if;

  return true;
end;
$$;

revoke all on function public.owner_respond_tractor_service_job(uuid, text, numeric, text) from public, anon;
grant execute on function public.owner_respond_tractor_service_job(uuid, text, numeric, text) to authenticated;

create or replace function public.customer_list_tractor_bookings_with_owner()
returns table(
  id uuid,
  job_number text,
  service_type text,
  service_location text,
  area_acres numeric,
  booked_for timestamptz,
  status text,
  total_charge numeric,
  owner_response_status text,
  owner_quote_kes numeric,
  owner_name text,
  owner_phone text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    j.id,
    j.job_number,
    j.service_type,
    j.service_location,
    j.area_acres,
    j.booked_for,
    j.status,
    j.total_charge,
    j.owner_response_status,
    j.owner_quote_kes,
    case when j.owner_response_status = 'accepted' then o.full_name else null end,
    case when j.owner_response_status = 'accepted' then o.phone else null end,
    j.created_at
  from public.customers c
  join public.tractor_service_jobs j on j.customer_id = c.id
  left join public.tractor_owner_profiles o on o.id = j.owner_profile_id
  where c.profile_id = auth.uid()
    and c.active = true
  order by j.created_at desc;
$$;

revoke all on function public.customer_list_tractor_bookings_with_owner() from public, anon;
grant execute on function public.customer_list_tractor_bookings_with_owner() to authenticated;

comment on column public.tractor_service_jobs.owner_profile_id is
  'Verified Tractor Owner responsible for the customer relationship and service booking.';
comment on column public.tractor_service_jobs.owner_response_status is
  'Owner acceptance state. Driver assignment and job execution do not replace owner customer contact.';

commit;
