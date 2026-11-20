create or replace function public.update_my_mechanic_job_status(
  p_job_id uuid,
  p_status text
)
returns boolean
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_current_status text;
  v_mechanic_id uuid;
begin
  select j.status, j.mechanic_id
    into v_current_status, v_mechanic_id
  from public.tractor_repair_jobs j
  join public.mechanic_profiles m on m.id = j.mechanic_id
  where j.id = p_job_id
    and m.profile_id = auth.uid()
    and m.status = 'approved'
  for update of j;

  if not found then
    raise exception 'Repair job not found or not assigned to your approved mechanic account.';
  end if;

  if not (
    (v_current_status = 'requested' and p_status = 'accepted') or
    (v_current_status = 'accepted' and p_status = 'in_progress') or
    (v_current_status = 'in_progress' and p_status in ('waiting_parts','completed')) or
    (v_current_status = 'waiting_parts' and p_status = 'in_progress')
  ) then
    raise exception 'This repair job status change is not allowed.';
  end if;

  update public.tractor_repair_jobs
  set status = p_status,
      completed_at = case when p_status = 'completed' then now() else completed_at end
  where id = p_job_id;

  return true;
end;
$function$;

revoke all on function public.update_my_mechanic_job_status(uuid,text) from public;
revoke all on function public.update_my_mechanic_job_status(uuid,text) from anon;
grant execute on function public.update_my_mechanic_job_status(uuid,text) to authenticated;
