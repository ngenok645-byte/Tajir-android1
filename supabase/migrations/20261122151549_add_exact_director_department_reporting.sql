-- Return exact company-wide totals to the Director without exposing them to ordinary roles.
create or replace function public.tajir_director_master_oversight_summary()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $function$
declare
  v_uid uuid := auth.uid();
  v_result jsonb;
begin
  if v_uid is null or not private.is_director() then
    raise exception 'Only an authorised TAJIR Director can view company-wide oversight.';
  end if;

  select jsonb_build_object(
    'profiles_total',(select count(*) from public.profiles),
    'profiles_active',(select count(*) from public.profiles where status::text='active'),
    'profiles_pending',(select count(*) from public.profiles where status::text='pending'),
    'profiles_suspended',(select count(*) from public.profiles where status::text in ('suspended','disabled')),
    'department_accounts',coalesce((
      select jsonb_object_agg(ar.code,coalesce(x.account_count,0))
      from public.app_roles ar
      left join lateral (
        select count(distinct ura.user_id) as account_count
        from public.user_role_assignments ura
        where ura.role_id=ar.id and ura.is_active=true
      ) x on true
      where ar.code in ('director','buyer','seller','worker','tractor_owner','driver','mechanic','auto_spares_owner')
    ),'{}'::jsonb),
    'activity',jsonb_build_object(
      'sales',(select count(*) from public.sales),
      'purchases',(select count(*) from public.purchases),
      'customer_payments',(select count(*) from public.customer_payments),
      'sales_orders',(select count(*) from public.sales_orders),
      'marketplace_listing_offers',(select count(*) from public.marketplace_listing_offers),
      'marketplace_listings',(select count(*) from public.marketplace_listings),
      'staff_tasks',(select count(*) from public.staff_tasks),
      'staff_activity_reports',(select count(*) from public.staff_activity_reports),
      'tractor_service_jobs',(select count(*) from public.tractor_service_jobs),
      'deliveries',(select count(*) from public.deliveries),
      'tractor_repair_jobs',(select count(*) from public.tractor_repair_jobs),
      'repair_part_requests',(select count(*) from public.repair_part_requests),
      'auto_spares_inventory',(select count(*) from public.auto_spares_inventory)
    )
  ) into v_result;
  return v_result;
end;
$function$;

revoke execute on function public.tajir_director_master_oversight_summary() from public, anon;
grant execute on function public.tajir_director_master_oversight_summary() to authenticated;
