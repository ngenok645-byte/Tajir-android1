create table if not exists private.tajir_customer_pin_lockouts (
  phone_hash text primary key,
  failed_attempts integer not null default 0,
  locked_until timestamptz,
  updated_at timestamptz not null default now()
);

alter table private.tajir_customer_pin_lockouts enable row level security;

create or replace function public.authenticate_tajir_customer_pin(p_phone text, p_pin text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_hash text := md5(coalesce(p_phone, ''));
  v_attempts integer;
  v_locked_until timestamptz;
  v_user_id uuid;
  v_wait integer;
begin
  perform pg_advisory_xact_lock(hashtextextended(v_hash, 0));
  insert into private.tajir_customer_pin_lockouts(phone_hash)
  values (v_hash) on conflict (phone_hash) do nothing;

  select failed_attempts, locked_until into v_attempts, v_locked_until
  from private.tajir_customer_pin_lockouts where phone_hash = v_hash for update;

  if v_locked_until is not null and v_locked_until > now() then
    return jsonb_build_object('success', false, 'locked', true,
      'retry_after_seconds', greatest(1, ceil(extract(epoch from (v_locked_until - now())))::integer));
  end if;

  select c.profile_id into v_user_id
  from public.customer_pin_credentials c
  join public.profiles p on p.id = c.profile_id
  join public.customers cu on cu.profile_id = p.id and cu.active = true
  where p.phone = p_phone and p.status::text = 'active'
    and extensions.crypt(p_pin, c.pin_hash) = c.pin_hash
  limit 1;

  if v_user_id is not null then
    delete from private.tajir_customer_pin_lockouts where phone_hash = v_hash;
    return jsonb_build_object('success', true, 'user_id', v_user_id);
  end if;

  v_attempts := coalesce(v_attempts, 0) + 1;
  v_wait := case when v_attempts >= 5 then 900 when v_attempts = 4 then 300
    when v_attempts = 3 then 60 else 0 end;

  update private.tajir_customer_pin_lockouts
  set failed_attempts = v_attempts,
      locked_until = case when v_wait > 0 then now() + make_interval(secs => v_wait) else null end,
      updated_at = now()
  where phone_hash = v_hash;

  return jsonb_build_object('success', false, 'locked', v_wait > 0,
    'retry_after_seconds', v_wait, 'remaining_attempts', greatest(0, 5 - v_attempts),
    'error', 'Phone number or PIN is incorrect.');
end;
$function$;

revoke all on function public.authenticate_tajir_customer_pin(text, text) from public, anon, authenticated;
grant execute on function public.authenticate_tajir_customer_pin(text, text) to service_role;
