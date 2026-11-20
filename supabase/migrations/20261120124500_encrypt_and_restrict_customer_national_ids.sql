-- Encrypt the complete National ID with a key stored in Supabase Vault.
-- The HMAC remains the duplicate-detection key; plaintext is never stored.
alter table private.tajir_customer_identity
  add column if not exists national_id_ciphertext bytea;

do $$
begin
  if not exists (
    select 1 from vault.secrets
    where name = 'tajir_national_id_encryption_key'
  ) then
    perform vault.create_secret(
      encode(extensions.gen_random_bytes(32), 'base64'),
      'tajir_national_id_encryption_key',
      'AES-256 encryption key for TAJIR customer National IDs'
    );
  end if;
end;
$$;

create or replace function public.register_my_national_id(p_national_id text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_id text := regexp_replace(coalesce(p_national_id, ''), '[^0-9]', '', 'g');
  v_secret bytea;
  v_hash bytea;
  v_encryption_key text;
  v_existing_hash bytea;
begin
  if v_user_id is null then
    raise exception 'Please sign in before submitting your National ID.';
  end if;
  if v_id !~ '^[0-9]{7,8}$' then
    raise exception 'Enter a valid Kenyan National ID number (7 or 8 digits).';
  end if;
  if not exists (select 1 from public.customers c where c.profile_id = v_user_id) then
    raise exception 'A customer account is required before adding a National ID.';
  end if;

  select secret into v_secret
  from private.tajir_identity_secret where singleton = true;
  select decrypted_secret into v_encryption_key
  from vault.decrypted_secrets
  where name = 'tajir_national_id_encryption_key';

  if v_secret is null or v_encryption_key is null then
    raise exception 'Secure identity storage is not configured. Please contact TAJIR support.';
  end if;

  v_hash := extensions.hmac(convert_to(v_id, 'UTF8'), v_secret, 'sha256');

  select national_id_hmac into v_existing_hash
  from private.tajir_customer_identity
  where profile_id = v_user_id
  for update;

  if v_existing_hash is not null then
    if v_existing_hash <> v_hash then
      raise exception 'A different National ID is already registered on this account. Contact TAJIR support if it needs correction.';
    end if;
    update private.tajir_customer_identity
       set national_id_ciphertext = coalesce(
         national_id_ciphertext,
         extensions.pgp_sym_encrypt(v_id, v_encryption_key, 'cipher-algo=aes256,compress-algo=0')
       )
     where profile_id = v_user_id;
    return;
  end if;

  insert into private.tajir_customer_identity
    (profile_id, national_id_hmac, national_id_last4, national_id_ciphertext)
  values
    (v_user_id, v_hash, right(v_id, 4),
     extensions.pgp_sym_encrypt(v_id, v_encryption_key, 'cipher-algo=aes256,compress-algo=0'));
exception
  when unique_violation then
    raise exception 'This National ID is already registered with TAJIR.';
end;
$$;

create or replace function public.get_tajir_national_id(p_profile_id uuid default auth.uid())
returns text
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_key text;
  v_ciphertext bytea;
begin
  if v_caller is null then
    raise exception 'Please sign in to view this National ID.';
  end if;
  if p_profile_id is null then
    raise exception 'Account not found.';
  end if;
  if v_caller <> p_profile_id and not private.is_director() then
    raise exception 'You are not authorised to view this National ID.';
  end if;

  select i.national_id_ciphertext into v_ciphertext
  from private.tajir_customer_identity i
  where i.profile_id = p_profile_id;

  if v_ciphertext is null then
    return null;
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name = 'tajir_national_id_encryption_key';

  if v_key is null then
    raise exception 'Secure identity access is temporarily unavailable.';
  end if;

  return extensions.pgp_sym_decrypt(v_ciphertext, v_key);
end;
$$;

revoke all on function public.register_my_national_id(text) from public, anon;
revoke all on function public.get_tajir_national_id(uuid) from public, anon;
grant execute on function public.register_my_national_id(text) to authenticated;
grant execute on function public.get_tajir_national_id(uuid) to authenticated;
revoke all on private.tajir_customer_identity from public, anon, authenticated;
