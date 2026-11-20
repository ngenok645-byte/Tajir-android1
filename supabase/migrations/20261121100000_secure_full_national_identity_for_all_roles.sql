-- Store the Kenyan ID number and the full name printed on that ID as one
-- protected identity record for every TAJIR account type.
create table if not exists private.tajir_user_identity (
  profile_id uuid primary key references auth.users(id) on delete cascade,
  national_id_hmac bytea not null unique,
  national_id_last4 text not null check (national_id_last4 ~ '^[0-9]{4}$'),
  national_id_ciphertext bytea not null,
  id_full_name_ciphertext bytea not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

revoke all on private.tajir_user_identity from public, anon, authenticated;

create or replace function public.register_my_national_identity(
  p_national_id text,
  p_id_full_name text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_id text := regexp_replace(coalesce(p_national_id, ''), '[^0-9]', '', 'g');
  v_id_name text := regexp_replace(trim(coalesce(p_id_full_name, '')), '\s+', ' ', 'g');
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
  if length(v_id_name) < 2 or length(v_id_name) > 100 then
    raise exception 'Enter the full name exactly as printed on your National ID.';
  end if;
  if not exists (select 1 from public.profiles p where p.id = v_user_id) then
    raise exception 'A registered TAJIR account is required before adding identity details.';
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
  from private.tajir_user_identity
  where profile_id = v_user_id
  for update;

  if v_existing_hash is not null then
    if v_existing_hash <> v_hash then
      raise exception 'A different National ID is already registered on this account. Contact a Director for correction.';
    end if;
    update private.tajir_user_identity
       set id_full_name_ciphertext = extensions.pgp_sym_encrypt(
             v_id_name, v_encryption_key, 'cipher-algo=aes256,compress-algo=0'),
           updated_at = now()
     where profile_id = v_user_id;
    return;
  end if;

  insert into private.tajir_user_identity
    (profile_id, national_id_hmac, national_id_last4,
     national_id_ciphertext, id_full_name_ciphertext)
  values
    (v_user_id, v_hash, right(v_id, 4),
     extensions.pgp_sym_encrypt(v_id, v_encryption_key, 'cipher-algo=aes256,compress-algo=0'),
     extensions.pgp_sym_encrypt(v_id_name, v_encryption_key, 'cipher-algo=aes256,compress-algo=0'));
exception
  when unique_violation then
    raise exception 'This National ID number is already registered with TAJIR.';
end;
$$;

create or replace function public.get_tajir_national_identity(p_profile_id uuid default auth.uid())
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_key text;
  v_number bytea;
  v_name bytea;
begin
  if v_caller is null then
    raise exception 'Please sign in to view these identity details.';
  end if;
  if p_profile_id is null then
    raise exception 'Account not found.';
  end if;
  if v_caller <> p_profile_id and not private.is_director() then
    raise exception 'You are not authorised to view these identity details.';
  end if;

  select national_id_ciphertext, id_full_name_ciphertext
    into v_number, v_name
  from private.tajir_user_identity
  where profile_id = p_profile_id;

  if v_number is null or v_name is null then
    return null;
  end if;

  select decrypted_secret into v_key
  from vault.decrypted_secrets
  where name = 'tajir_national_id_encryption_key';

  if v_key is null then
    raise exception 'Secure identity access is temporarily unavailable.';
  end if;

  return jsonb_build_object(
    'national_id', extensions.pgp_sym_decrypt(v_number, v_key),
    'id_full_name', extensions.pgp_sym_decrypt(v_name, v_key)
  );
end;
$$;

revoke all on function public.register_my_national_identity(text, text) from public, anon;
revoke all on function public.get_tajir_national_identity(uuid) from public, anon;
grant execute on function public.register_my_national_identity(text, text) to authenticated;
grant execute on function public.get_tajir_national_identity(uuid) to authenticated;
