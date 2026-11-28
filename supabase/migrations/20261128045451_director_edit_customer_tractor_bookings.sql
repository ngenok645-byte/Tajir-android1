-- Allow TAJIR directors to edit tractor bookings linked to a selected customer.
-- The function still checks private.is_director() and scopes every update to
-- the selected account profile. No provider or customer permissions are widened.
do $migration$
declare
  v_definition text;
  v_updated text;
  v_old_booking text := $old_booking$v_scope := 'exists (select 1 from public.tractor_owner_profiles o where o.id=t.owner_profile_id and o.profile_id=$2)';$old_booking$;
  v_new_booking text := $new_booking$v_scope := '(exists (select 1 from public.tractor_owner_profiles o where o.id=t.owner_profile_id and o.profile_id=$2) or exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2))';$new_booking$;
  v_old_job text := $old_job$v_scope := '(t.operator_id=$2 or exists (select 1 from public.tractor_owner_assets a where a.tractor_id=t.tractor_id and exists (select 1 from public.tractor_owner_profiles o where o.id=a.owner_id and o.profile_id=$2)))';$old_job$;
  v_new_job text := $new_job$v_scope := '(t.operator_id=$2 or exists (select 1 from public.tractor_owner_assets a where a.tractor_id=t.tractor_id and exists (select 1 from public.tractor_owner_profiles o where o.id=a.owner_id and o.profile_id=$2)) or exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2))';$new_job$;
begin
  select pg_get_functiondef('public.tajir_director_update_account_record(text,uuid,uuid,jsonb)'::regprocedure)
    into v_definition;

  if position(v_old_booking in v_definition)=0 then
    raise exception 'Expected tractor_owner_service_bookings scope not found; migration aborted';
  end if;
  if position(v_old_job in v_definition)=0 then
    raise exception 'Expected tractor_service_jobs scope not found; migration aborted';
  end if;

  v_updated := replace(v_definition,v_old_booking,v_new_booking);
  v_updated := replace(v_updated,v_old_job,v_new_job);
  execute v_updated;
end;
$migration$;
