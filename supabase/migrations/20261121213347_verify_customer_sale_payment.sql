create or replace function public.verify_customer_sale_payment(p_payment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
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

  update public.customer_payments
  set status='verified'::public.payment_status,
      received_at=coalesce(received_at,now()),
      verified_at=now(),
      verified_by=v_uid
  where id=p_payment_id;

  return jsonb_build_object('payment_id',p_payment_id,'status','verified','verified_by',v_uid);
end;
$function$;

revoke all on function public.verify_customer_sale_payment(uuid) from public,anon;
grant execute on function public.verify_customer_sale_payment(uuid) to authenticated;
