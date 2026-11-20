create or replace function public.update_my_assigned_tractor_job(
  p_job_id uuid,
  p_status text,
  p_hours_worked numeric default null
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_current_status text;
begin
  if v_user is null or not private.has_app_role('driver') then
    raise exception 'Only an authorised signed-in driver can update an assigned tractor job.';
  end if;

  select j.status into v_current_status
  from public.tractor_service_jobs j
  where j.id = p_job_id
    and j.operator_id = v_user
  for update;

  if not found then
    raise exception 'This tractor job is not assigned to your account.';
  end if;

  if v_current_status = 'confirmed' and p_status = 'in_progress' then
    update public.tractor_service_jobs
    set status = 'in_progress',
        started_at = coalesce(started_at, now())
    where id = p_job_id and operator_id = v_user;
    return true;
  end if;

  if v_current_status = 'in_progress' and p_status = 'completed' then
    if p_hours_worked is null or p_hours_worked <= 0 or p_hours_worked > 720 then
      raise exception 'Enter actual working hours greater than zero and no more than 720.';
    end if;
    update public.tractor_service_jobs
    set status = 'completed',
        completed_at = now(),
        hours_worked = p_hours_worked
    where id = p_job_id and operator_id = v_user;
    return true;
  end if;

  raise exception 'This driver job status change is not allowed.';
end;
$$;

revoke all on function public.update_my_assigned_tractor_job(uuid,text,numeric) from public, anon;
grant execute on function public.update_my_assigned_tractor_job(uuid,text,numeric) to authenticated;
