
alter table public.purchases add column if not exists invoice_total numeric(14,2) not null default 0;
alter table public.purchases add column if not exists payment_mode text not null default 'credit';
do $$ begin
  if not exists(select 1 from pg_constraint where conrelid='public.purchases'::regclass and conname='purchases_payment_mode_check') then
    alter table public.purchases add constraint purchases_payment_mode_check check(payment_mode in ('cash','mpesa','bank_transfer','credit','split','other'));
  end if;
end $$;
update public.purchases p
set invoice_total=coalesce((select sum(pi.quantity*pi.buying_price_per_unit) from public.purchase_items pi where pi.purchase_id=p.id),0)
 +coalesce((select sum(pc.amount) from public.purchase_costs pc where pc.purchase_id=p.id),0)
where p.invoice_total=0;

CREATE OR REPLACE FUNCTION public.record_purchase(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_branch uuid:=(p_payload->>'branch_id')::uuid;
 v_purchase uuid;
 v_item jsonb;
 v_variant uuid;
 v_qty numeric;
 v_cost numeric;
 v_unit public.stock_unit;
 v_item_id uuid;
 v_batch uuid;
 v_payer text:=nullif(p_payload->>'payer','');
 v_number text;
 v_ok boolean;
 v_expense jsonb;
 v_amount numeric;
 v_extra_total numeric;
 v_supplier_name text:=nullif(btrim(p_payload->>'supplier_name'),'');
 v_supplier_id uuid:=nullif(p_payload->>'supplier_id','')::uuid;
 v_invoice_total numeric:=0;
begin
 if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and status='active') then raise exception 'Active sign-in required'; end if;
 select private.has_app_role('director') or private.has_app_role('branch_manager') or private.has_app_role('buyer') into v_ok;
 if not coalesce(v_ok,false) then raise exception 'Not authorized to record purchases'; end if;
 if v_branch is null or not private.has_branch_access(v_branch) or not exists(select 1 from public.branches where id=v_branch and is_active) then raise exception 'Branch access denied or branch inactive'; end if;
 if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items')=0 then raise exception 'At least one item is required'; end if;
 if v_payer is not null and v_payer not in ('Mercy','Edu') then raise exception 'Paid by must be Mercy or Edu'; end if;
 if v_supplier_name is null then raise exception 'Supplier name is required for every purchase.'; end if;
 if v_supplier_id is not null and not exists(select 1 from public.suppliers where id=v_supplier_id and approval_status in ('pending','active')) then
   raise exception 'Selected supplier is unavailable or suspended.';
 end if;
 if v_supplier_id is null then
   select id into v_supplier_id from public.suppliers
   where lower(trim(business_name))=lower(v_supplier_name) and approval_status in ('pending','active')
   order by case when approval_status='active' and is_active then 0 else 1 end, created_at limit 1;
 end if;
 if v_supplier_id is null then
   insert into public.suppliers(supplier_code,business_name,approval_status,is_active,created_by,notes)
   values('SUP-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8)),v_supplier_name,'pending',false,v_uid,
     'Created from a purchase entry; awaiting Director approval.')
   returning id into v_supplier_id;
 end if;
 v_number:='PUR-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.purchases(purchase_number,branch_id,supplier_id,supplier_name,purchase_date,status,paid_by_owner,recorded_by,notes,submitted_at,received_at)
 values(v_number,v_branch,v_supplier_id,v_supplier_name,coalesce(nullif(p_payload->>'purchase_date','')::date,current_date),'quality_pending',v_payer,v_uid,nullif(p_payload->>'notes',''),now(),now())
 returning id into v_purchase;
 for v_item in select value from jsonb_array_elements(p_payload->'items') loop
  v_variant:=nullif(v_item->>'product_variant_id','')::uuid;
  v_qty:=(v_item->>'quantity')::numeric;
  v_cost:=coalesce(nullif(v_item->>'unit_cost','')::numeric,nullif(v_item->>'buying_price_per_unit','')::numeric);
  if v_variant is null or v_qty is null or v_qty<=0 or v_cost is null or v_cost<0 then raise exception 'Invalid purchase item'; end if;
  select base_unit into v_unit from public.product_variants where id=v_variant and is_active;
  if not found then raise exception 'Product variant unavailable'; end if;
  insert into public.purchase_items(purchase_id,product_variant_id,quantity,unit,buying_price_per_unit,selling_price_per_unit)
  values(v_purchase,v_variant,v_qty,v_unit,v_cost,nullif(v_item->>'selling_price_per_unit','')::numeric) returning id into v_item_id;
  v_extra_total:=0;
  for v_expense in select value from jsonb_array_elements(coalesce(v_item->'expenses','[]'::jsonb)) loop
   v_amount:=coalesce(nullif(v_expense->>'amount','')::numeric,0);
   if v_amount<0 then raise exception 'Purchase expense cannot be negative'; end if;
   if v_amount>0 then
    if nullif(trim(v_expense->>'cost_type'),'') is null then raise exception 'Purchase expense type is required'; end if;
    insert into public.purchase_costs(purchase_id,purchase_item_id,cost_type,amount,paid_by_owner,description,incurred_at,created_by)
    values(v_purchase,v_item_id,trim(v_expense->>'cost_type'),v_amount,v_payer,nullif(v_expense->>'description',''),coalesce(nullif(p_payload->>'purchase_date','')::date,current_date),v_uid);
    v_extra_total:=v_extra_total+v_amount;
   end if;
  end loop;
  v_invoice_total:=v_invoice_total+(v_qty*v_cost)+v_extra_total;
  v_batch:=gen_random_uuid();
  insert into public.stock_batches(id,branch_id,product_variant_id,purchase_item_id,batch_code,received_quantity,accepted_quantity,remaining_quantity,unit,landed_cost_total,landed_cost_per_unit,status)
  values(v_batch,v_branch,v_variant,v_item_id,'B-'||upper(substr(replace(v_batch::text,'-',''),1,12)),v_qty,0,0,v_unit,(v_qty*v_cost)+v_extra_total,case when v_qty>0 then v_cost+(v_extra_total/v_qty) else v_cost end,'quarantined');
 end loop;
 update public.purchases set invoice_total=round(v_invoice_total,2) where id=v_purchase;
 return jsonb_build_object('purchase_id',v_purchase,'purchase_number',v_number,'status','quality_pending','invoice_total',round(v_invoice_total,2));
end;
$function$
;
CREATE OR REPLACE FUNCTION public.record_supplier_purchase_payments(p_purchase_id uuid, p_payment_mode text, p_payments jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_purchase public.purchases%rowtype;
  v_supplier public.suppliers%rowtype;
  v_payment jsonb;
  v_amount numeric;
  v_method text;
  v_reference text;
  v_notes text;
  v_new_total numeric:=0;
  v_verified numeric:=0;
  v_pending numeric:=0;
  v_distinct_new integer:=0;
  v_distinct_all integer:=0;
  v_final_mode text;
begin
  if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and status::text='active') then
    raise exception 'Active sign-in required.';
  end if;
  if not (private.has_app_role('director') or private.has_app_role('accountant') or private.has_app_role('branch_manager')) then
    raise exception 'Only the Director, Accountant or authorised Branch Manager can record supplier payments.';
  end if;
  select * into v_purchase from public.purchases where id=p_purchase_id for update;
  if not found or not private.has_branch_access(v_purchase.branch_id) then
    raise exception 'Purchase is unavailable for this branch.';
  end if;
  if v_purchase.supplier_id is null then raise exception 'This purchase has no linked supplier. Contact the Director.'; end if;
  select * into v_supplier from public.suppliers where id=v_purchase.supplier_id for update;
  if not found or v_supplier.approval_status::text<>'active' or not v_supplier.is_active then
    raise exception 'Supplier must be approved and active before payment can be recorded.';
  end if;
  if v_purchase.invoice_total<=0 then raise exception 'Purchase invoice total is missing. Refresh the purchase record first.'; end if;
  if p_payment_mode not in ('cash','mpesa','bank_transfer','credit','split','other') then
    raise exception 'Choose one of the six supported payment modes.';
  end if;
  select coalesce(sum(amount) filter(where status='verified'),0),
         coalesce(sum(amount) filter(where status='pending'),0)
  into v_verified,v_pending
  from public.supplier_payments where purchase_id=p_purchase_id;

  if p_payment_mode='credit' then
    if jsonb_typeof(coalesce(p_payments,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_payments,'[]'::jsonb))<>0 then
      raise exception 'Credit records the outstanding supplier balance without an immediate payment entry.';
    end if;
    if v_verified+v_pending>0 then raise exception 'This purchase already has payment entries; add another payment instead of changing it to credit.'; end if;
    update public.purchases set payment_mode='credit',updated_at=now() where id=p_purchase_id;
    return jsonb_build_object('payment_mode','credit','invoice_total',v_purchase.invoice_total,'verified_paid',v_verified,'pending_paid',v_pending,'outstanding_balance',v_purchase.invoice_total-v_verified);
  end if;

  if jsonb_typeof(p_payments) is distinct from 'array' then raise exception 'Payment entries must be supplied as a list.'; end if;
  if p_payment_mode='split' then
    if jsonb_array_length(p_payments)<2 then raise exception 'Split payment requires at least two payment entries.'; end if;
  elsif jsonb_array_length(p_payments)<>1 then
    raise exception 'A single payment mode requires exactly one payment entry.';
  end if;

  select count(distinct lower(coalesce(value->>'method',''))) into v_distinct_new
  from jsonb_array_elements(p_payments);
  if p_payment_mode='split' and v_distinct_new<2 then raise exception 'Split payment must combine at least two different methods.'; end if;

  for v_payment in select value from jsonb_array_elements(p_payments) loop
    v_amount:=coalesce(nullif(v_payment->>'amount','')::numeric,0);
    v_method:=coalesce(v_payment->>'method','');
    v_reference:=nullif(btrim(v_payment->>'reference'),'');
    v_notes:=nullif(btrim(v_payment->>'notes'),'');
    if v_amount<=0 then raise exception 'Every supplier payment amount must be greater than zero.'; end if;
    if v_method not in ('cash','mpesa','bank_transfer','other') then raise exception 'Invalid supplier payment method.'; end if;
    if p_payment_mode<>'split' and v_method<>p_payment_mode then raise exception 'Payment entry method does not match the selected payment mode.'; end if;
    if v_method in ('mpesa','bank_transfer','other') and v_reference is null then
      raise exception 'M-Pesa, bank transfer and other/manual supplier payments require a transaction reference or receipt note.';
    end if;
    v_new_total:=v_new_total+v_amount;
  end loop;

  if v_new_total>greatest(v_purchase.invoice_total-v_verified-v_pending,0)+0.009 then
    raise exception 'Supplier payments cannot exceed the remaining uncommitted invoice balance.';
  end if;

  for v_payment in select value from jsonb_array_elements(p_payments) loop
    v_amount:=(v_payment->>'amount')::numeric;
    v_method:=v_payment->>'method';
    v_reference:=nullif(btrim(v_payment->>'reference'),'');
    v_notes:=nullif(btrim(v_payment->>'notes'),'');
    insert into public.supplier_payments(
      supplier_id,purchase_id,branch_id,payment_date,amount,method,status,transaction_reference,
      recorded_by,verified_by,verified_at,notes
    ) values(
      v_purchase.supplier_id,p_purchase_id,v_purchase.branch_id,current_date,v_amount,
      v_method::public.payment_method,
      case when v_method='cash' then 'verified'::public.payment_status else 'pending'::public.payment_status end,
      v_reference,v_uid,case when v_method='cash' then v_uid else null end,
      case when v_method='cash' then now() else null end,v_notes
    );
  end loop;

  select count(distinct method) into v_distinct_all
  from public.supplier_payments where purchase_id=p_purchase_id;
  if v_distinct_all>1 then v_final_mode:='split';
  else select method::text into v_final_mode from public.supplier_payments where purchase_id=p_purchase_id order by created_at limit 1;
  end if;
  update public.purchases set payment_mode=coalesce(v_final_mode,p_payment_mode),updated_at=now() where id=p_purchase_id;

  select coalesce(sum(amount) filter(where status='verified'),0),
         coalesce(sum(amount) filter(where status='pending'),0)
  into v_verified,v_pending
  from public.supplier_payments where purchase_id=p_purchase_id;

  return jsonb_build_object(
    'payment_mode',coalesce(v_final_mode,p_payment_mode),
    'invoice_total',v_purchase.invoice_total,
    'verified_paid',v_verified,
    'pending_paid',v_pending,
    'outstanding_balance',greatest(v_purchase.invoice_total-v_verified,0),
    'uncommitted_balance',greatest(v_purchase.invoice_total-v_verified-v_pending,0)
  );
end;
$function$
;
CREATE OR REPLACE FUNCTION public.verify_supplier_purchase_payment(p_payment_id uuid, p_transaction_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_payment public.supplier_payments%rowtype;
  v_reference text:=nullif(btrim(p_transaction_reference),'');
begin
  if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and status::text='active') then
    raise exception 'Active sign-in required.';
  end if;
  if not (private.has_app_role('director') or private.has_app_role('accountant') or private.has_app_role('branch_manager')) then
    raise exception 'Only the Director, Accountant or authorised Branch Manager can verify supplier payments.';
  end if;
  select * into v_payment from public.supplier_payments where id=p_payment_id for update;
  if not found or not private.has_branch_access(v_payment.branch_id) then
    raise exception 'Supplier payment is unavailable for this branch.';
  end if;
  if v_payment.status<>'pending' then raise exception 'Only pending supplier payments can be verified.'; end if;
  if v_payment.method in ('mpesa','bank_transfer','other') and coalesce(v_reference,nullif(btrim(v_payment.transaction_reference),'')) is null then
    raise exception 'Check and enter the transaction reference or manual receipt note before verification.';
  end if;
  update public.supplier_payments
  set status='verified',verified_by=v_uid,verified_at=now(),
      transaction_reference=coalesce(v_reference,transaction_reference)
  where id=p_payment_id;
  return jsonb_build_object('payment_id',p_payment_id,'status','verified');
end;
$function$
;
revoke execute on function public.record_supplier_purchase_payments(uuid,text,jsonb) from public,anon;
grant execute on function public.record_supplier_purchase_payments(uuid,text,jsonb) to authenticated;
revoke execute on function public.verify_supplier_purchase_payment(uuid,text) from public,anon;
grant execute on function public.verify_supplier_purchase_payment(uuid,text) to authenticated;

drop view if exists public.supplier_purchase_payment_summary;
create view public.supplier_purchase_payment_summary with (security_invoker=true) as
 SELECT p.id AS purchase_id,
    p.purchase_number,
    p.supplier_id,
    COALESCE(s.business_name, p.supplier_name, 'Supplier not recorded'::text) AS supplier_name,
    p.branch_id,
    p.purchase_date,
    p.status AS purchase_status,
    p.payment_mode,
    p.invoice_total,
    COALESCE(sum(sp.amount) FILTER (WHERE sp.status = 'verified'::payment_status), 0::numeric)::numeric(14,2) AS verified_paid,
    COALESCE(sum(sp.amount) FILTER (WHERE sp.status = 'pending'::payment_status), 0::numeric)::numeric(14,2) AS pending_paid,
    GREATEST(p.invoice_total - COALESCE(sum(sp.amount) FILTER (WHERE sp.status = 'verified'::payment_status), 0::numeric), 0::numeric)::numeric(14,2) AS outstanding_balance,
    GREATEST(p.invoice_total - COALESCE(sum(sp.amount) FILTER (WHERE sp.status = ANY (ARRAY['verified'::payment_status, 'pending'::payment_status])), 0::numeric), 0::numeric)::numeric(14,2) AS uncommitted_balance,
        CASE
            WHEN COALESCE(sum(sp.amount) FILTER (WHERE sp.status = 'verified'::payment_status), 0::numeric) >= p.invoice_total AND p.invoice_total > 0::numeric THEN 'paid'::text
            WHEN COALESCE(sum(sp.amount) FILTER (WHERE sp.status = ANY (ARRAY['verified'::payment_status, 'pending'::payment_status])), 0::numeric) >= p.invoice_total AND p.invoice_total > 0::numeric THEN 'pending_verification'::text
            WHEN COALESCE(sum(sp.amount) FILTER (WHERE sp.status = 'verified'::payment_status), 0::numeric) > 0::numeric THEN 'partially_paid'::text
            ELSE 'unpaid'::text
        END AS payment_status
   FROM purchases p
     LEFT JOIN suppliers s ON s.id = p.supplier_id
     LEFT JOIN supplier_payments sp ON sp.purchase_id = p.id
  GROUP BY p.id, s.business_name;;
grant select on public.supplier_purchase_payment_summary to authenticated;
drop policy if exists finance_read_suppliers on public.suppliers;
create policy finance_read_suppliers on public.suppliers for select to authenticated using (private.is_finance_user());
