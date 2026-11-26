-- Director-only row access for account operational records. Credential and National ID tables are excluded.
do $$
declare t text;
begin
  foreach t in array array[
    'customer_product_requests','customer_custom_product_requests','customer_payments',
    'sales_orders','sales','marketplace_listings',
    'staff_tasks','staff_attendance','staff_activity_reports','worker_issue_reports',
    'tractor_owner_profiles','tractor_owner_assets','tractor_owner_service_fleet',
    'tractor_owner_service_bookings','tractor_repair_jobs','tractor_service_jobs',
    'tractor_job_expenses','tractor_job_payments','tractor_maintenance_records','tractor_assets',
    'mechanic_profiles','repair_part_requests','auto_spares_profiles','auto_spares_inventory',
    'vehicles','vehicle_records'
  ] loop
    execute format('drop policy if exists %I on public.%I', 'director_manage_'||t, t);
    execute format('create policy %I on public.%I for all to authenticated using (private.is_director()) with check (private.is_director())',
      'director_manage_'||t, t);
  end loop;
end $$;

CREATE OR REPLACE FUNCTION public.tajir_director_update_account_record(p_table text, p_record_id uuid, p_profile_id uuid, p_patch jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY INVOKER
 SET search_path TO ''
AS $function$
declare
  v_allowed text[];
  v_scope text;
  v_patch jsonb;
  v_set text;
  v_key text;
  v_before jsonb;
  v_after jsonb;
begin
  if auth.uid() is null or not private.is_director() then
    raise exception 'Director access required';
  end if;
  if p_record_id is null or p_profile_id is null or p_patch is null
     or jsonb_typeof(p_patch) <> 'object' or p_patch = '{}'::jsonb then
    raise exception 'A record and at least one change are required';
  end if;

  case p_table
    when 'profiles' then
      v_allowed := array['display_name','phone','status','preferred_language'];
      v_scope := 't.id = $2';
    when 'customers' then
      v_allowed := array['full_name','phone','email','active','marketplace_can_buy','marketplace_can_sell','customer_type','default_branch_id'];
      v_scope := 't.profile_id = $2';
    when 'customer_product_requests' then
      v_allowed := array['quantity_requested','note','status','unit_price_per_kg','line_total_kes','quantity_unit','quantity_kg'];
      v_scope := 'exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2)';
    when 'customer_custom_product_requests' then
      v_allowed := array['product_name','description','quantity','quantity_unit','proposed_unit_price_kes','status','director_response','agreed_unit_price_kes','request_direction','customer_response'];
      v_scope := 'exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2)';
    when 'customer_payments' then
      v_allowed := array['amount','method','status','provider_reference','received_at','verified_at','verified_by'];
      v_scope := 'exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2)';
    when 'sales_orders' then
      v_allowed := array['status','fulfilment_method','delivery_address','requested_delivery_at','confirmed_delivery_at','subtotal','discount_total','delivery_fee','total_amount','customer_notes','staff_notes','payment_mode'];
      v_scope := 'exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2)';
    when 'sales' then
      v_allowed := array['sale_date','subtotal','discount_total','delivery_income','total_amount','payment_mode'];
      v_scope := 'exists (select 1 from public.customers c where c.id=t.customer_id and c.profile_id=$2)';
    when 'marketplace_listings' then
      v_allowed := array['product_name','description','quantity','unit','price_per_unit','location','status','quantity_kg','total_value_kes'];
      v_scope := 'exists (select 1 from public.customers c where c.id=t.seller_customer_id and c.profile_id=$2)';
    when 'staff_tasks' then
      v_allowed := array['title','description','due_at','status','completed_at','review_notes'];
      v_scope := 't.assigned_to = $2';
    when 'staff_attendance' then
      v_allowed := array['check_in_at','check_out_at'];
      v_scope := 't.user_id = $2';
    when 'staff_activity_reports' then
      v_allowed := array['report_date','activity_type','quantity','location','description','status','review_notes'];
      v_scope := 't.worker_id = $2';
    when 'worker_issue_reports' then
      v_allowed := array['issue_type','description','status'];
      v_scope := 't.worker_profile_id = $2';
    when 'tractor_owner_profiles' then
      v_allowed := array['full_name','phone','company_name','status','operating_mode','default_branch_id'];
      v_scope := 't.profile_id = $2';
    when 'tractor_owner_assets' then
      v_allowed := array['verification_status','verified_by','verified_at','ownership_document_path'];
      v_scope := 'exists (select 1 from public.tractor_owner_profiles o where o.id=t.owner_id and o.profile_id=$2)';
    when 'tractor_owner_service_fleet' then
      v_allowed := array['tractor_name','make_model','ownership_type','operating_county','operating_region','operating_village','services','status','notes'];
      v_scope := 'exists (select 1 from public.tractor_owner_profiles o where o.id=t.owner_profile_id and o.profile_id=$2)';
    when 'tractor_owner_service_bookings' then
      v_allowed := array['service_type','service_location','county','region','village','quantity','pricing_unit','unit_rate','total_charge','booked_for','status','notes','assigned_driver_profile_id','customer_name','customer_phone'];
      v_scope := 'exists (select 1 from public.tractor_owner_profiles o where o.id=t.owner_profile_id and o.profile_id=$2)';
    when 'tractor_repair_jobs' then
      v_allowed := array['issue_description','location','status','estimated_cost_kes','final_cost_kes','completed_at'];
      v_scope := '(t.owner_user_id=$2 or exists (select 1 from public.mechanic_profiles m where m.id=t.mechanic_id and m.profile_id=$2) or exists (select 1 from public.tractor_owner_profiles o where o.id=t.owner_profile_id and o.profile_id=$2))';
    when 'tractor_service_jobs' then
      v_allowed := array['farmer_name','farmer_phone','service_type','service_location','area_acres','booked_for','started_at','completed_at','operator_id','hours_worked','rate','total_charge','status','notes','estimated_hours','pricing_unit','pricing_quantity','county','region','village'];
      v_scope := '(t.operator_id=$2 or exists (select 1 from public.tractor_owner_assets a where a.tractor_id=t.tractor_id and exists (select 1 from public.tractor_owner_profiles o where o.id=a.owner_id and o.profile_id=$2)))';
    when 'tractor_job_expenses' then
      v_allowed := array['expense_type','description','amount','paid_by_owner'];
      v_scope := 'exists (select 1 from public.tractor_service_jobs j where j.id=t.job_id and (j.operator_id=$2 or exists (select 1 from public.tractor_owner_assets a join public.tractor_owner_profiles o on o.id=a.owner_id where a.tractor_id=j.tractor_id and o.profile_id=$2)))';
    when 'tractor_job_payments' then
      v_allowed := array['amount','method','status','provider_reference','received_at','verified_at','verified_by'];
      v_scope := 'exists (select 1 from public.tractor_service_jobs j where j.id=t.job_id and (j.operator_id=$2 or exists (select 1 from public.tractor_owner_assets a join public.tractor_owner_profiles o on o.id=a.owner_id where a.tractor_id=j.tractor_id and o.profile_id=$2)))';
    when 'tractor_maintenance_records' then
      v_allowed := array['maintenance_date','maintenance_type','description','cost','engine_hours','next_service_date'];
      v_scope := 'exists (select 1 from public.tractor_owner_assets a join public.tractor_owner_profiles o on o.id=a.owner_id where a.tractor_id=t.tractor_id and o.profile_id=$2)';
    when 'tractor_assets' then
      v_allowed := array['tractor_code','make_model','ownership_type','owner_name','status','engine_hours','notes','current_operating_area'];
      v_scope := 'exists (select 1 from public.tractor_owner_assets a join public.tractor_owner_profiles o on o.id=a.owner_id where a.tractor_id=t.id and o.profile_id=$2)';
    when 'mechanic_profiles' then
      v_allowed := array['business_name','phone','location','services','status'];
      v_scope := 't.profile_id = $2';
    when 'repair_part_requests' then
      v_allowed := array['quantity','agreed_unit_price_kes','status'];
      v_scope := '(exists (select 1 from public.mechanic_profiles m where m.id=t.mechanic_id and m.profile_id=$2) or exists (select 1 from public.auto_spares_profiles s where s.id=t.shop_id and s.profile_id=$2))';
    when 'auto_spares_profiles' then
      v_allowed := array['shop_name','phone','location','status'];
      v_scope := 't.profile_id = $2';
    when 'auto_spares_inventory' then
      v_allowed := array['part_name','part_reference','description','quantity','unit','price_kes','status'];
      v_scope := 'exists (select 1 from public.auto_spares_profiles s where s.id=t.shop_id and s.profile_id=$2)';
    when 'vehicles' then
      v_allowed := array['registration_number','make','model','driver_id','active','notes'];
      v_scope := 't.driver_id = $2';
    when 'vehicle_records' then
      v_allowed := array['record_type','record_date','destination','purpose','distance_km','odometer_km','fuel_litres','amount','station_or_provider','description'];
      v_scope := 't.driver_id = $2';
    else
      raise exception 'This record type is not enabled for director editing';
  end case;

  for v_key in select jsonb_object_keys(p_patch) loop
    if not (v_key = any(v_allowed)) then
      raise exception 'Field % is not editable through this screen', v_key;
    end if;
  end loop;

  v_patch := p_patch;
  select string_agg(format('%I = (jsonb_populate_record(t, $3)).%I', k, k), ', ')
    into v_set
    from jsonb_object_keys(v_patch) as keys(k);

  execute format('select to_jsonb(t) from public.%I t where t.id=$1 and %s', p_table, v_scope)
    into v_before using p_record_id, p_profile_id;
  if v_before is null then
    raise exception 'The selected record does not belong to this account or no longer exists';
  end if;

  execute format('update public.%I t set %s where t.id=$1 and %s returning to_jsonb(t)', p_table, v_set, v_scope)
    into v_after using p_record_id, p_profile_id, v_patch;

  insert into public.audit_logs(actor_user_id,action,entity_schema,entity_table,entity_id,reason,before_data,after_data)
  values(auth.uid(),'director_account_record_edited','public',p_table,p_record_id::text,
    'TAJIR director edited an account-linked operational record',v_before,v_after);

  return v_after;
end;
$function$

revoke all on function public.tajir_director_update_account_record(text,uuid,uuid,jsonb) from public, anon;
grant execute on function public.tajir_director_update_account_record(text,uuid,uuid,jsonb) to authenticated;
