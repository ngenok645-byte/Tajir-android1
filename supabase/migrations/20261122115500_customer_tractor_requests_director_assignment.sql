-- Allow customer tractor requests to enter the Director queue before a tractor is assigned.
alter table public.tractor_service_jobs
  alter column tractor_id drop not null;

alter table public.tractor_service_jobs
  drop constraint if exists tractor_service_jobs_status_check;

alter table public.tractor_service_jobs
  add constraint tractor_service_jobs_status_check
  check (status = any (array[
    'awaiting_director_assignment'::text,
    'booked'::text,
    'confirmed'::text,
    'in_progress'::text,
    'completed'::text,
    'cancelled'::text
  ]));

create or replace function public.customer_book_tractor_service(
  p_tractor_id uuid default null,
  p_service_type text default null,
  p_service_location text default null,
  p_area_acres numeric default null,
  p_booked_for timestamp with time zone default null,
  p_notes text default null
)
returns table(job_id uuid, job_number text)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_customer public.customers%rowtype;
  v_tractor public.tractor_assets%rowtype;
  v_branch_id uuid;
  v_job_number text;
  v_job_id uuid;
  v_status text;
begin
  select c.* into v_customer
  from public.customers c
  join public.profiles p on p.id=c.profile_id
  where c.profile_id=auth.uid()
    and c.active=true
    and p.status::text='active'
    and c.customer_type in ('buyer','seller','both')
  for update of c;

  if v_customer.id is null then
    raise exception 'An active customer account is required.';
  end if;
  if p_service_type not in ('ploughing','planting','harrowing','transport','other') then
    raise exception 'Select a valid service.';
  end if;
  if length(trim(coalesce(p_service_location,'')))<3 then
    raise exception 'Enter the farm location.';
  end if;
  if p_area_acres is not null and p_area_acres<=0 then
    raise exception 'Acres must be greater than zero.';
  end if;
  if p_booked_for is not null and p_booked_for<now() then
    raise exception 'Choose a future booking date.';
  end if;

  v_branch_id := v_customer.default_branch_id;
  if v_branch_id is null or not exists (
    select 1 from public.branches b where b.id=v_branch_id and b.is_active=true
  ) then
    select b.id into v_branch_id
    from public.branches b where b.is_active=true
    order by b.name limit 1;
  end if;
  if v_branch_id is null then
    raise exception 'TAJIR is temporarily unable to route this request. Please contact the Director.';
  end if;

  if p_tractor_id is null then
    v_status := 'awaiting_director_assignment';
  else
    select t.* into v_tractor
    from public.tractor_assets t
    join public.branches b on b.id=t.branch_id and b.is_active=true
    where t.id=p_tractor_id
      and t.status='available'
      and t.branch_id=v_branch_id
    for update of t;

    if v_tractor.id is null then
      -- A tractor may become unavailable between catalogue load and submit.
      -- Preserve the booking as an assignment request instead of rejecting it.
      v_status := 'awaiting_director_assignment';
    else
      v_status := 'booked';
    end if;
  end if;

  v_job_number := 'TR-' || to_char(now(),'YYMMDDHH24MISS') || '-' ||
    upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.tractor_service_jobs(
    job_number,branch_id,tractor_id,customer_id,farmer_name,farmer_phone,
    service_type,service_location,area_acres,booked_for,estimated_hours,
    rate,total_charge,status,notes,recorded_by
  ) values (
    v_job_number,v_branch_id,
    case when v_status='booked' then v_tractor.id else null end,
    v_customer.id,v_customer.full_name,v_customer.phone,
    p_service_type,trim(p_service_location),p_area_acres,p_booked_for,1,
    0,0,v_status,nullif(trim(coalesce(p_notes,'')),''),auth.uid()
  ) returning id into v_job_id;

  return query select v_job_id,v_job_number;
end;
$function$;

grant execute on function public.customer_book_tractor_service(uuid,text,text,numeric,timestamptz,text) to authenticated;

-- Only the Director may allocate a fleet tractor to an unassigned customer request.
create or replace function public.director_assign_tractor_to_service_job(
  p_job_id uuid,
  p_tractor_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_job public.tractor_service_jobs%rowtype;
  v_tractor public.tractor_assets%rowtype;
begin
  if not private.has_app_role('director'::text) then
    raise exception 'Only the TAJIR Director can assign a tractor to this booking.';
  end if;

  select * into v_job
  from public.tractor_service_jobs
  where id=p_job_id
    and status='awaiting_director_assignment'
    and tractor_id is null
  for update;

  if v_job.id is null then
    raise exception 'This booking is no longer awaiting tractor assignment.';
  end if;

  select * into v_tractor
  from public.tractor_assets
  where id=p_tractor_id
    and branch_id=v_job.branch_id
    and status='available'
  for update;

  if v_tractor.id is null then
    raise exception 'Choose an available tractor assigned to this branch.';
  end if;

  update public.tractor_service_jobs
  set tractor_id=v_tractor.id,status='booked',updated_at=now()
  where id=v_job.id;
end;
$function$;

grant execute on function public.director_assign_tractor_to_service_job(uuid,uuid) to authenticated;
