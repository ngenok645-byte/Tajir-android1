create or replace function public.record_customer_sale_payment(
  p_sale_id uuid,
  p_amount numeric,
  p_method text,
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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
  if v_method in ('mpesa','bank_transfer') and v_reference is null then
    raise exception 'M-Pesa and bank transfer payments require a reference.';
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
$function$;

revoke all on function public.record_customer_sale_payment(uuid,numeric,text,text) from public,anon;
grant execute on function public.record_customer_sale_payment(uuid,numeric,text,text) to authenticated;
