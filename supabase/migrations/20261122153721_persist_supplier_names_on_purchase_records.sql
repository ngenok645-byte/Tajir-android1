alter table public.purchases add column if not exists supplier_name text;
update public.purchases p set supplier_name=s.business_name from public.suppliers s where p.supplier_id=s.id and p.supplier_name is null;

CREATE OR REPLACE FUNCTION public.record_purchase(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 v_uid uuid:=auth.uid(); v_branch uuid:=(p_payload->>'branch_id')::uuid;
 v_purchase uuid; v_item jsonb; v_variant uuid; v_qty numeric; v_cost numeric;
 v_unit stock_unit; v_item_id uuid; v_batch uuid; v_payer text:=nullif(p_payload->>'payer','');
 v_number text; v_ok boolean; v_expense jsonb; v_amount numeric; v_extra_total numeric; v_supplier_name text:=nullif(btrim(p_payload->>'supplier_name'),''); v_supplier_id uuid:=nullif(p_payload->>'supplier_id','')::uuid;
begin
 if v_uid is null or not exists(select 1 from profiles where id=v_uid and status='active') then raise exception 'Active sign-in required'; end if;
 select private.has_app_role('director') or private.has_app_role('branch_manager') or private.has_app_role('buyer') into v_ok;
 if not coalesce(v_ok,false) then raise exception 'Not authorized to record purchases'; end if;
 if v_branch is null or not private.has_branch_access(v_branch) or not exists(select 1 from branches where id=v_branch and is_active) then raise exception 'Branch access denied or branch inactive'; end if;
 if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items')=0 then raise exception 'At least one item is required'; end if;
 if v_payer is not null and v_payer not in ('Mercy','Edu') then raise exception 'Paid by must be Mercy or Edu'; end if;
 if v_supplier_name is null then raise exception 'Supplier name is required for every purchase.'; end if;
 if v_supplier_id is not null and not exists(select 1 from suppliers where id=v_supplier_id and is_active and approval_status='approved') then
   raise exception 'Selected supplier is not approved or active.';
 end if;
 if v_supplier_id is null then
   select id into v_supplier_id from suppliers
   where lower(trim(business_name))=lower(v_supplier_name) and is_active and approval_status='approved'
   order by created_at limit 1;
 end if;
 v_number:='PUR-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into purchases(purchase_number,branch_id,supplier_id,supplier_name,purchase_date,status,paid_by_owner,recorded_by,notes,submitted_at,received_at)
 values(v_number,v_branch,v_supplier_id,v_supplier_name,coalesce(nullif(p_payload->>'purchase_date','')::date,current_date),'quality_pending',v_payer,v_uid,nullif(p_payload->>'notes',''),now(),now())
 returning id into v_purchase;
 for v_item in select value from jsonb_array_elements(p_payload->'items') loop
  v_variant:=nullif(v_item->>'product_variant_id','')::uuid;
  v_qty:=(v_item->>'quantity')::numeric;
  v_cost:=coalesce(nullif(v_item->>'unit_cost','')::numeric,nullif(v_item->>'buying_price_per_unit','')::numeric);
  if v_variant is null or v_qty is null or v_qty<=0 or v_cost is null or v_cost<0 then raise exception 'Invalid purchase item'; end if;
  select base_unit into v_unit from product_variants where id=v_variant and is_active;
  if not found then raise exception 'Product variant unavailable'; end if;
  insert into purchase_items(purchase_id,product_variant_id,quantity,unit,buying_price_per_unit,selling_price_per_unit)
  values(v_purchase,v_variant,v_qty,v_unit,v_cost,nullif(v_item->>'selling_price_per_unit','')::numeric) returning id into v_item_id;
  v_extra_total:=0;
  for v_expense in select value from jsonb_array_elements(coalesce(v_item->'expenses','[]'::jsonb)) loop
   v_amount:=coalesce(nullif(v_expense->>'amount','')::numeric,0);
   if v_amount<0 then raise exception 'Purchase expense cannot be negative'; end if;
   if v_amount>0 then
    if nullif(trim(v_expense->>'cost_type'),'') is null then raise exception 'Purchase expense type is required'; end if;
    insert into purchase_costs(purchase_id,purchase_item_id,cost_type,amount,paid_by_owner,description,incurred_at,created_by)
    values(v_purchase,v_item_id,trim(v_expense->>'cost_type'),v_amount,v_payer,nullif(v_expense->>'description',''),coalesce(nullif(p_payload->>'purchase_date','')::date,current_date),v_uid);
    v_extra_total:=v_extra_total+v_amount;
   end if;
  end loop;
  v_batch:=gen_random_uuid();
  insert into stock_batches(id,branch_id,product_variant_id,purchase_item_id,batch_code,received_quantity,accepted_quantity,remaining_quantity,unit,landed_cost_total,landed_cost_per_unit,status)
  values(v_batch,v_branch,v_variant,v_item_id,'B-'||upper(substr(replace(v_batch::text,'-',''),1,12)),v_qty,0,0,v_unit,(v_qty*v_cost)+v_extra_total,case when v_qty>0 then v_cost+(v_extra_total/v_qty) else v_cost end,'quarantined');
 end loop;
 return jsonb_build_object('purchase_id',v_purchase,'purchase_number',v_number,'status','quality_pending');
end
$function$
;
