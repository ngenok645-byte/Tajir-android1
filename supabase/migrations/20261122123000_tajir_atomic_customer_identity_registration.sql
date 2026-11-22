-- Require one protected Kenyan National ID per TAJIR customer identity.
-- The HMAC unique index prevents the same person from creating multiple customer profiles.
-- Registration writes identity, customer, profile and PIN in one database transaction.
create or replace function public.complete_tajir_customer_registration(
  p_user_id uuid,
  p_full_name text,
  p_phone text,
  p_pin text,
  p_national_id text,
  p_customer_type text default 'buyer'
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_name text := regexp_replace(btrim(coalesce(p_full_name, '')), '\s+', ' ', 'g');
  v_id text := regexp_replace(coalesce(p_national_id, ''), '[^0-9]', '', 'g');
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_secret bytea;
  v_hash bytea;
  v_existing_hash bytea;
  v_encryption_key text;
  v_customer_id uuid;
begin
  if coalesce(current_setting('request.jwt.claim.role', true), '') <> 'service_role' then
    raise exception 'Registration service authorization required.';
  end if;
  if p_user_id is null then raise exception 'Registration account is missing.'; end if;
  if length(v_name) < 2 or length(v_name) > 120 then
    raise exception 'Enter your full legal name as shown on your National ID.';
  end if;
  if v_id !~ '^[0-9]{7,8}$' then
    raise exception 'Enter a valid Kenyan National ID number (7 or 8 digits).';
  end if;
  if v_phone !~ '^254[0-9]{9}$' then raise exception 'Enter a valid Kenyan phone number.'; end if;
  if p_pin !~ '^[0-9]{4}$' then raise exception 'PIN must contain exactly four digits.'; end if;
  if p_customer_type not in ('buyer','seller','both') then raise exception 'Invalid customer account type.'; end if;
  if not exists (select 1 from auth.users u where u.id = p_user_id) then
    raise exception 'Registration account was not created.';
  end if;

  select secret into v_secret from private.tajir_identity_secret where singleton = true;
  select decrypted_secret into v_encryption_key from vault.decrypted_secrets
   where name = 'tajir_national_id_encryption_key';
  if v_secret is null or v_encryption_key is null then
    raise exception 'Secure identity storage is unavailable. Please contact TAJIR support.';
  end if;

  v_hash := extensions.hmac(convert_to(v_id, 'UTF8'), v_secret, 'sha256');
  select national_id_hmac into v_existing_hash from private.tajir_customer_identity
   where profile_id = p_user_id for update;
  if v_existing_hash is not null and v_existing_hash <> v_hash then
    raise exception 'A different National ID is already linked to this account. Contact TAJIR support.';
  end if;
  if v_existing_hash is null then
    insert into private.tajir_customer_identity(profile_id, national_id_hmac, national_id_last4, national_id_ciphertext)
    values (p_user_id, v_hash, right(v_id, 4),
      extensions.pgp_sym_encrypt(v_id, v_encryption_key, 'cipher-algo=aes256,compress-algo=0'));
  else
    update private.tajir_customer_identity
       set national_id_ciphertext = coalesce(national_id_ciphertext,
         extensions.pgp_sym_encrypt(v_id, v_encryption_key, 'cipher-algo=aes256,compress-algo=0'))
     where profile_id = p_user_id;
  end if;

  perform public.set_tajir_customer_pin(p_user_id, p_pin);
  update public.profiles set phone = '+' || v_phone, display_name = v_name, status = 'active', updated_at = now()
   where id = p_user_id;
  if not found then
    insert into public.profiles(id, phone, display_name, status)
    values (p_user_id, '+' || v_phone, v_name, 'active');
  end if;

  insert into public.customers(profile_id, customer_type, full_name, phone, active, marketplace_can_buy, marketplace_can_sell)
  values (p_user_id, p_customer_type::public.customer_type, v_name, '+' || v_phone, true,
    p_customer_type in ('buyer','both'), p_customer_type in ('seller','both'))
  on conflict (profile_id) do update set
    customer_type = excluded.customer_type, full_name = excluded.full_name, phone = excluded.phone,
    active = true, marketplace_can_buy = excluded.marketplace_can_buy,
    marketplace_can_sell = excluded.marketplace_can_sell
  returning id into v_customer_id;
  return v_customer_id;
exception
  when unique_violation then
    raise exception 'This National ID or phone number is already registered with TAJIR. Sign in to your existing account or contact TAJIR support.';
end;
$$;

revoke all on function public.complete_tajir_customer_registration(uuid,text,text,text,text,text) from public, anon, authenticated;
grant execute on function public.complete_tajir_customer_registration(uuid,text,text,text,text,text) to service_role;
