-- Count the eight departments using their authoritative account tables.
-- Buyer and Seller are customer permissions; provider departments use their profile records.
create or replace function public.tajir_director_master_oversight_summary()
returns jsonb
language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := auth.uid(); v_result jsonb;
begin
  if v_uid is null or not private.is_director() then
    raise exception 'Only an authorised TAJIR Director can view company-wide oversight.';
  end if;
  select jsonb_build_object(
    'profiles_total',(select count(*) from public.profiles),
    'profiles_active',(select count(*) from public.profiles where status::text='active'),
    'profiles_pending',(select count(*) from public.profiles where status::text='pending'),
    'profiles_suspended',(select count(*) from public.profiles where status::text in ('suspended','disabled')),
    'department_accounts',jsonb_build_object(
      'director',(select count(distinct ura.user_id) from public.user_role_assignments ura join public.app_roles ar on ar.id=ura.role_id join public.profiles p on p.id=ura.user_id where ura.is_active and ar.code='director' and p.status::text='active'),
      'buyer',(select count(distinct c.profile_id) from public.customers c join public.profiles p on p.id=c.profile_id where c.active and c.deleted_at is null and c.marketplace_can_buy and p.status::text='active'),
      'seller',(select count(distinct c.profile_id) from public.customers c join public.profiles p on p.id=c.profile_id where c.active and c.deleted_at is null and c.marketplace_can_sell and p.status::text='active'),
      'worker',(select count(distinct ura.user_id) from public.user_role_assignments ura join public.app_roles ar on ar.id=ura.role_id join public.profiles p on p.id=ura.user_id where ura.is_active and ar.code='worker' and p.status::text='active'),
      'tractor_owner',(select count(distinct top.profile_id) from public.tractor_owner_profiles top join public.profiles p on p.id=top.profile_id where p.status::text='active'),
      'driver',(select count(distinct d.profile_id) from (
        select ura.user_id as profile_id from public.user_role_assignments ura join public.app_roles ar on ar.id=ura.role_id where ura.is_active and ar.code='driver'
        union select j.operator_id from public.tractor_service_jobs j where j.operator_id is not null
        union select x.assigned_driver_id from public.deliveries x where x.assigned_driver_id is not null
      ) d join public.profiles p on p.id=d.profile_id where p.status::text='active'),
      'mechanic',(select count(distinct mp.profile_id) from public.mechanic_profiles mp join public.profiles p on p.id=mp.profile_id where p.status::text='active'),
      'auto_spares_owner',(select count(distinct ap.profile_id) from public.auto_spares_profiles ap join public.profiles p on p.id=ap.profile_id where p.status::text='active')
    ),
    'activity',jsonb_build_object(
      'sales',(select count(*) from public.sales),
      'purchases',(select count(*) from public.purchases),
      'customer_payments',(select count(*) from public.customer_payments),
      'supplier_payments',(select count(*) from public.supplier_payments),
      'inventory_balances',(select count(*) from public.inventory_balances),
      'stock_movements',(select count(*) from public.stock_movements),
      'sales_orders',(select count(*) from public.sales_orders),
      'marketplace_listing_offers',(select count(*) from public.marketplace_listing_offers),
      'marketplace_purchase_requests',(select count(*) from public.marketplace_purchase_requests),
      'marketplace_listings',(select count(*) from public.marketplace_listings),
      'customer_product_requests',(select count(*) from public.customer_product_requests),
      'customer_custom_product_requests',(select count(*) from public.customer_custom_product_requests),
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
