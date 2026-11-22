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
  if not found or not (private.is_finance_user() or private.has_branch_access(v_purchase.branch_id)) then
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
  if not found or not (private.is_finance_user() or private.has_branch_access(v_payment.branch_id)) then
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
