CREATE OR REPLACE FUNCTION public.record_sale(p_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 v_uid uuid:=auth.uid();
 v_branch uuid:=(p_payload->>'branch_id')::uuid;
 v_customer uuid:=nullif(p_payload->>'customer_id','')::uuid;
 v_customer_name text:=nullif(btrim(p_payload->>'customer_name'),'');
 v_customer_phone text:=nullif(btrim(p_payload->>'customer_phone'),'');
 v_item jsonb; v_variant uuid; v_qty numeric; v_price numeric; v_unit stock_unit;
 v_remaining numeric; v_take numeric; v_cost numeric; v_line_cost numeric; v_line_revenue numeric;
 v_subtotal numeric:=0; v_total_cost numeric:=0; v_delivery numeric:=coalesce(nullif(p_payload->>'delivery_fee','')::numeric,0);
 v_sale uuid:=gen_random_uuid(); v_number text; v_order uuid:=gen_random_uuid(); v_order_number text; v_balance numeric; v_ok boolean;
 v_batch record; v_payment_amount numeric; v_method text; v_payment_number text; v_payment_mode text;
 v_payment jsonb; v_reference text; v_official_price_per_kg numeric; v_expected_price numeric;
 v_paid_total numeric:=0; v_verified_paid numeric:=0; v_distinct_methods integer:=0; v_single_payment_amount numeric:=0;
begin
 if v_uid is null or not exists(select 1 from profiles where id=v_uid and status='active') then raise exception 'Active sign-in required'; end if;
 select private.has_app_role('director') or private.has_app_role('branch_manager') or private.has_app_role('seller') into v_ok;
 if not coalesce(v_ok,false) then raise exception 'Not authorized to record sales'; end if;
 if v_branch is null or not private.has_branch_access(v_branch) or not exists(select 1 from branches where id=v_branch and is_active) then raise exception 'Branch access denied or branch inactive'; end if;
 if jsonb_typeof(p_payload->'items') is distinct from 'array' or jsonb_array_length(p_payload->'items')=0 then raise exception 'At least one item is required'; end if;
 if v_delivery<0 then raise exception 'Delivery fee cannot be negative'; end if;

 v_single_payment_amount:=coalesce(nullif(p_payload#>>'{payment,amount}','')::numeric,0);
 v_method:=coalesce(p_payload#>>'{payment,method}','cash');
 v_payment_mode:=coalesce(
   nullif(p_payload->>'payment_mode',''),
   case when jsonb_typeof(p_payload->'payments')='array' then 'split'
        when v_single_payment_amount>0 then v_method else 'credit' end
 );
 if v_payment_mode not in ('cash','mpesa','bank_transfer','credit','split','other') then
   raise exception 'Invalid payment option';
 end if;

 if v_customer is null then
  if v_customer_name is null then raise exception 'Customer name is required'; end if;
  if v_customer_phone is null then raise exception 'Customer phone number is required for a new customer'; end if;
  insert into customers(customer_type,full_name,phone,default_branch_id,active,approved_at,approved_by)
  values('buyer',v_customer_name,v_customer_phone,v_branch,true,now(),v_uid) returning id into v_customer;
 elsif not exists(select 1 from customers where id=v_customer and active) then raise exception 'Customer inactive or unavailable';
 end if;

 v_number:='SAL-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(v_sale::text,'-',''),1,6));
 v_order_number:='ORD-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(v_order::text,'-',''),1,6));

 insert into sales_orders(id,order_number,customer_id,branch_id,status,fulfilment_method,delivery_address,subtotal,discount_total,delivery_fee,total_amount,customer_notes,confirmed_by,confirmed_at,payment_mode)
 values(v_order,v_order_number,v_customer,v_branch,'confirmed'::order_status,
  case when coalesce(p_payload->>'fulfilment_mode','collection')='delivery' then 'customer_delivery'::fulfilment_method else 'branch_collection'::fulfilment_method end,
  nullif(p_payload->>'delivery_address',''),0,0,0,0,nullif(p_payload->>'customer_notes',''),v_uid,now(),v_payment_mode);

 insert into sales(id,sale_number,order_id,customer_id,branch_id,sale_date,subtotal,discount_total,delivery_income,total_amount,recorded_by,payment_mode)
 values(v_sale,v_number,v_order,v_customer,v_branch,coalesce(nullif(p_payload->>'sale_date','')::timestamptz,now()),0,0,0,0,v_uid,v_payment_mode);

 for v_item in select value from jsonb_array_elements(p_payload->'items') loop
  v_variant:=nullif(v_item->>'product_variant_id','')::uuid;
  v_qty:=(v_item->>'quantity')::numeric; v_price:=(v_item->>'unit_price')::numeric;
  if v_variant is null or v_qty is null or v_qty<=0 or v_price is null or v_price<=0 then raise exception 'Invalid sale item'; end if;
  select base_unit into v_unit from product_variants where id=v_variant and is_active;
  if not found then raise exception 'Product variant unavailable'; end if;

  select selling_price_per_kg into v_official_price_per_kg
  from branch_product_selling_prices
  where branch_id=v_branch and product_variant_id=v_variant;
  if v_official_price_per_kg is null or v_official_price_per_kg<=0 then
    raise exception 'The Director has not set an official selling price for this product at this branch.';
  end if;
  if v_unit='bag' then
    v_expected_price:=v_official_price_per_kg*90;
  elsif v_unit='kg' then
    v_expected_price:=v_official_price_per_kg;
  else
    raise exception 'Director-approved sale pricing is currently configured only for KG and 90 KG bags.';
  end if;
  if abs(v_price-v_expected_price)>0.01 then
    raise exception 'Sale price does not match the Director-approved price for this branch and product.';
  end if;

  select quantity_on_hand into v_balance from inventory_balances where branch_id=v_branch and product_variant_id=v_variant for update;
  if coalesce(v_balance,0)<v_qty then raise exception 'Insufficient approved stock'; end if;
  v_remaining:=v_qty; v_line_cost:=0;
  for v_batch in select id,remaining_quantity,landed_cost_per_unit from stock_batches
    where branch_id=v_branch and product_variant_id=v_variant and status='available' and remaining_quantity>0
    order by received_at,id for update loop
   exit when v_remaining<=0;
   v_take:=least(v_remaining,v_batch.remaining_quantity); v_cost:=v_batch.landed_cost_per_unit;
   update stock_batches set remaining_quantity=remaining_quantity-v_take,
    status=case when remaining_quantity-v_take=0 then 'depleted'::stock_batch_status else status end where id=v_batch.id;
   insert into stock_movements(branch_id,product_variant_id,batch_id,movement_type,quantity_delta,unit,unit_cost,reference_table,reference_id,reason,performed_by)
   values(v_branch,v_variant,v_batch.id,'sale_dispatch',-v_take,v_unit,v_cost,'sales',v_sale,'FIFO sale dispatch',v_uid);
   v_line_cost:=v_line_cost+v_take*v_cost; v_remaining:=v_remaining-v_take;
  end loop;
  if v_remaining>0 then raise exception 'Available batch quantities do not reconcile; sale cancelled'; end if;
  v_line_revenue:=v_qty*v_price; v_subtotal:=v_subtotal+v_line_revenue; v_total_cost:=v_total_cost+v_line_cost;
  insert into sales_order_items(order_id,product_variant_id,quantity,unit,unit_selling_price,discount_amount,line_total)
  values(v_order,v_variant,v_qty,v_unit,v_price,0,v_line_revenue);
  insert into sale_items(sale_id,product_variant_id,quantity,unit,unit_selling_price,unit_cost,line_revenue,line_cost)
  values(v_sale,v_variant,v_qty,v_unit,v_price,v_line_cost/v_qty,v_line_revenue,v_line_cost);
  update inventory_balances set quantity_on_hand=quantity_on_hand-v_qty,
   weighted_average_cost=case when quantity_on_hand-v_qty=0 then 0 else weighted_average_cost end,updated_at=now()
  where branch_id=v_branch and product_variant_id=v_variant;
 end loop;

 update sales set subtotal=v_subtotal,total_amount=v_subtotal+v_delivery,delivery_income=v_delivery where id=v_sale;
 update sales_orders set subtotal=v_subtotal,total_amount=v_subtotal+v_delivery,delivery_fee=v_delivery,updated_at=now() where id=v_order;

 if v_payment_mode='credit' then
  if v_single_payment_amount>0 or jsonb_typeof(p_payload->'payments')='array' then
    raise exception 'Credit sales cannot include an immediate payment entry.';
  end if;
 elsif v_payment_mode='split' then
  if jsonb_typeof(p_payload->'payments') is distinct from 'array' or jsonb_array_length(p_payload->'payments')<2 then
    raise exception 'Split payment requires at least two payment entries.';
  end if;
  select count(distinct lower(coalesce(value->>'method','')))
  into v_distinct_methods
  from jsonb_array_elements(p_payload->'payments');
  if v_distinct_methods<2 then raise exception 'Split payment must use at least two different payment methods.'; end if;

  for v_payment in select value from jsonb_array_elements(p_payload->'payments') loop
    v_payment_amount:=coalesce(nullif(v_payment->>'amount','')::numeric,0);
    v_method:=coalesce(v_payment->>'method','');
    v_reference:=nullif(btrim(v_payment->>'reference'),'');
    if v_payment_amount<=0 then raise exception 'Every split payment amount must be greater than zero.'; end if;
    if v_method not in ('mpesa','cash','bank_transfer','other') then raise exception 'Invalid split payment method.'; end if;
    if v_method in ('mpesa','bank_transfer','other') and v_reference is null then raise exception 'M-Pesa, bank transfer and other/manual payments require a reference or receipt note.'; end if;
    v_paid_total:=v_paid_total+v_payment_amount;
    if v_method='cash' then v_verified_paid:=v_verified_paid+v_payment_amount; end if;
    v_payment_number:='PAY-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
    insert into customer_payments(payment_number,customer_id,order_id,sale_id,branch_id,amount,method,status,provider_reference,received_at,verified_at,verified_by)
    values(v_payment_number,v_customer,v_order,v_sale,v_branch,v_payment_amount,v_method::payment_method,
      case when v_method='cash' then 'verified'::payment_status else 'pending'::payment_status end,
      v_reference,case when v_method='cash' then now() else null end,
      case when v_method='cash' then now() else null end,case when v_method='cash' then v_uid else null end);
  end loop;
  if v_paid_total>v_subtotal+v_delivery then raise exception 'Split payments cannot exceed the sale total.'; end if;
 else
  v_payment_amount:=v_single_payment_amount;
  if v_payment_amount<=0 or v_payment_amount>v_subtotal+v_delivery then raise exception 'Enter a valid positive payment amount not exceeding the sale total.'; end if;
  if v_method<>v_payment_mode then raise exception 'Payment method does not match the selected payment option.'; end if;
  v_reference:=nullif(btrim(p_payload#>>'{payment,reference}'),'');
  if v_method in ('mpesa','bank_transfer','other') and v_reference is null then raise exception 'M-Pesa, bank transfer and other/manual payments require a reference or receipt note.'; end if;
  v_paid_total:=v_payment_amount;
  if v_method='cash' then v_verified_paid:=v_payment_amount; end if;
  v_payment_number:='PAY-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
  insert into customer_payments(payment_number,customer_id,order_id,sale_id,branch_id,amount,method,status,provider_reference,received_at,verified_at,verified_by)
  values(v_payment_number,v_customer,v_order,v_sale,v_branch,v_payment_amount,v_method::payment_method,
    case when v_method='cash' then 'verified'::payment_status else 'pending'::payment_status end,
    v_reference,case when v_method='cash' then now() else null end,
    case when v_method='cash' then now() else null end,case when v_method='cash' then v_uid else null end);
 end if;

 return jsonb_build_object(
  'sale_id',v_sale,'sale_number',v_number,'order_id',v_order,'order_number',v_order_number,
  'balance',v_subtotal+v_delivery-v_verified_paid,
  'paid_total',v_paid_total,
  'pending_payment_amount',v_paid_total-v_verified_paid,
  'payment_mode',v_payment_mode,
  'profit',v_subtotal-v_total_cost
 );
end
$function$
;

CREATE OR REPLACE FUNCTION public.record_customer_sale_payment(p_sale_id uuid, p_amount numeric, p_method text, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_sale public.sales%rowtype;
  v_existing numeric:=0;
  v_verified numeric:=0;
  v_pending numeric:=0;
  v_payment_number text;
  v_reference text:=nullif(btrim(p_reference),'');
  v_method text:=lower(coalesce(p_method,''));
begin
  if v_uid is null or not exists(select 1 from public.profiles p where p.id=v_uid and p.status='active') then
    raise exception 'Active staff sign-in required.';
  end if;

  if not (
    private.has_app_role('director')
    or private.has_app_role('branch_manager')
    or private.has_app_role('seller')
    or private.has_app_role('accountant')
  ) then
    raise exception 'Not authorised to record customer payments.';
  end if;

  select * into v_sale
  from public.sales s
  where s.id=p_sale_id
  for update;

  if not found then raise exception 'Sale not found.'; end if;
  if not private.has_branch_access(v_sale.branch_id) then raise exception 'Branch access denied.'; end if;
  if p_amount is null or p_amount<=0 then raise exception 'Payment amount must be greater than zero.'; end if;
  if v_method not in ('cash','mpesa','bank_transfer','other') then raise exception 'Choose Cash, M-Pesa, Bank transfer, or Other/manual payment.'; end if;
  if v_method in ('mpesa','bank_transfer','other') and v_reference is null then
    raise exception 'M-Pesa, bank transfer and other/manual payments require a reference or receipt note.';
  end if;

  select coalesce(sum(cp.amount),0),
         coalesce(sum(cp.amount) filter (where cp.status='verified'),0),
         coalesce(sum(cp.amount) filter (where cp.status='pending'),0)
    into v_existing,v_verified,v_pending
  from public.customer_payments cp
  where cp.sale_id=p_sale_id
    and cp.status in ('pending','verified');

  if v_existing+p_amount>v_sale.total_amount then
    raise exception 'Payment exceeds the remaining amount available on this sale.';
  end if;

  v_payment_number:='PAY-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));

  insert into public.customer_payments(
    payment_number,customer_id,order_id,sale_id,branch_id,amount,method,status,
    provider_reference,received_at,verified_at,verified_by
  )
  values(
    v_payment_number,v_sale.customer_id,v_sale.order_id,v_sale.id,v_sale.branch_id,p_amount,
    v_method::public.payment_method,
    case when v_method='cash' then 'verified'::public.payment_status else 'pending'::public.payment_status end,
    v_reference,
    case when v_method='cash' then now() else null end,
    case when v_method='cash' then now() else null end,
    case when v_method='cash' then v_uid else null end
  );

  if v_method='cash' then v_verified:=v_verified+p_amount; else v_pending:=v_pending+p_amount; end if;

  return jsonb_build_object(
    'payment_number',v_payment_number,
    'sale_id',v_sale.id,
    'verified_paid',v_verified,
    'pending_paid',v_pending,
    'balance_due',greatest(v_sale.total_amount-v_verified,0),
    'unallocated_balance',greatest(v_sale.total_amount-v_verified-v_pending,0)
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.verify_customer_sale_payment(p_payment_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_uid uuid:=auth.uid();
  v_payment public.customer_payments%rowtype;
begin
  if v_uid is null or not exists(select 1 from public.profiles p where p.id=v_uid and p.status='active') then
    raise exception 'Active sign-in required.';
  end if;

  if not (private.has_app_role('director') or private.has_app_role('accountant')) then
    raise exception 'Only a Director or Accountant can verify customer payments.';
  end if;

  select * into v_payment
  from public.customer_payments p
  where p.id=p_payment_id
  for update;

  if not found then raise exception 'Customer payment not found.'; end if;
  if not private.has_branch_access(v_payment.branch_id) then raise exception 'Branch access denied.'; end if;
  if v_payment.status<>'pending' then raise exception 'Only pending customer payments can be verified.'; end if;
  if v_payment.method in ('mpesa','bank_transfer','other') and coalesce(nullif(btrim(v_payment.provider_transaction_id),''),nullif(btrim(v_payment.provider_reference),'')) is null then
    raise exception 'A verified non-cash payment requires its transaction reference or manual receipt note.';
  end if;

  update public.customer_payments
  set status='verified'::public.payment_status,
      provider_transaction_id=case when method='mpesa' then coalesce(provider_transaction_id,provider_reference) else provider_transaction_id end,
      received_at=coalesce(received_at,now()),
      verified_at=now(),
      verified_by=v_uid
  where id=p_payment_id;

  return jsonb_build_object('payment_id',p_payment_id,'status','verified','verified_by',v_uid);
end;
$function$
;