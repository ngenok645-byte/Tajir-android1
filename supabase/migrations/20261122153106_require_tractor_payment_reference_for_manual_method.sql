CREATE OR REPLACE FUNCTION public.record_tractor_job_payment(p_job_id uuid, p_amount numeric, p_method payment_method, p_reference text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
 v_uid uuid:=auth.uid(); v_job public.tractor_service_jobs%rowtype; v_number text; v_id uuid;
begin
 if v_uid is null or not exists(select 1 from public.profiles where id=v_uid and status='active') then raise exception 'Active sign-in required'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Payment must be greater than zero'; end if;
 select * into v_job from public.tractor_service_jobs where id=p_job_id;
 if not found or not private.has_branch_access(v_job.branch_id) then raise exception 'Job unavailable for this branch'; end if;
 if not (private.has_app_role('director') or private.has_app_role('branch_manager') or private.has_app_role('accountant')) then raise exception 'Not authorized to record tractor payments'; end if;
 if p_method in ('mpesa','bank_transfer','other') and nullif(btrim(p_reference),'') is null then raise exception 'M-Pesa, bank transfer and other/manual payments require a reference or receipt note.'; end if;
 v_number:='TRP-'||to_char(clock_timestamp(),'YYYYMMDD-HH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.tractor_job_payments(job_id,branch_id,payment_number,amount,method,status,provider_reference,received_at,verified_at,verified_by)
 values(p_job_id,v_job.branch_id,v_number,p_amount,p_method,
  case when p_method='cash' then 'verified'::public.payment_status else 'pending'::public.payment_status end,
  nullif(p_reference,''),case when p_method='cash' then now() else null end,
  case when p_method='cash' then now() else null end,
  case when p_method='cash' then v_uid else null end)
 returning id into v_id;
 return jsonb_build_object('payment_id',v_id,'payment_number',v_number,'status',case when p_method='cash' then 'verified' else 'pending' end);
end $function$
;

CREATE OR REPLACE FUNCTION public.verify_tractor_job_payment(p_payment_id uuid, p_transaction_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_payment public.tractor_job_payments%rowtype;
  v_reference text := nullif(btrim(p_transaction_reference), '');
begin
  if v_uid is null or not exists (
    select 1 from public.profiles where id = v_uid and status = 'active'
  ) then
    raise exception 'Active sign-in required';
  end if;

  if not (
    private.has_app_role('director')
    or private.has_app_role('branch_manager')
    or private.has_app_role('accountant')
  ) then
    raise exception 'Not authorized to verify tractor payments';
  end if;

  select * into v_payment
  from public.tractor_job_payments
  where id = p_payment_id
  for update;

  if not found or not private.has_branch_access(v_payment.branch_id) then
    raise exception 'Payment unavailable for this branch';
  end if;

  if v_payment.status <> 'pending' then
    raise exception 'Only pending payments can be verified';
  end if;

  if v_payment.method in ('mpesa', 'bank_transfer', 'other') and v_reference is null then
    raise exception 'Enter and check the transaction reference or manual receipt note before verification';
  end if;

  update public.tractor_job_payments
  set status = 'verified',
      provider_transaction_id = coalesce(provider_transaction_id, v_reference),
      verified_at = now(),
      received_at = coalesce(received_at, now()),
      verified_by = v_uid
  where id = p_payment_id;

  return jsonb_build_object(
    'payment_id', p_payment_id,
    'payment_number', v_payment.payment_number,
    'status', 'verified'
  );
end;
$function$
;