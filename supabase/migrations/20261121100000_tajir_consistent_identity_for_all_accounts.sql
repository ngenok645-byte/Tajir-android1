-- TAJIR: consistent National ID number + ID-printed full name for every account.
-- The existing customer-only identity table is retained for backward compatibility.
-- This table becomes the common identity store for customers and all staff/provider roles.
alter table private.tajir_customer_identity
  add column if not exists national_id_hmac bytea;

create table if not exists private.tajir_account_identity (
  profile_id uuid primary key references auth.users(id) on delete cascade,
  national_id_hmac bytea not null unique,
  national_id_last4 text not null check (national_id_last4 ~ '^[0-9]{4}$'),
  id_full_name text not null check (length(trim(id_full_name)) between 2 and 100),
  national_id_ciphertext bytea not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
revoke all on private.tajir_account_identity from public, anon, authenticated;

create or replace function public.register_my_tajir_identity(
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
  v_name text := regexp_replace(trim(coalesce(p_id_full_name, '')), '\\s+', ' ', 'g');
  v_secret bytea;
  v_key text;
  v_hash bytea;
begin
  if v_user_id is null then
    raise exception 'Please sign in before submitting identity details.';
  end if;
  if v_id !~ '^[0-9]{7,8}$' then
    raise exception 'Enter a valid Kenyan National ID number (7 or 8 digits).';
  end if;
  if length(v_name) < 2 or length(v_name) > 100 then
    raise exception 'Enter your full name exactly as printed on your National ID.';
  end if;
  select secret into v_secret from private.tajir_identity_secret where singleton = true;
  select decrypted_secret into v_key from vault.decrypted_secrets
    where name = 'tajir_national_id_encryption_key';
  if v_secret is null or v_key is null then
    raise exception 'Secure identity storage is not configured. Contact TAJIR support.';
  end if;
  v_hash := extensions.hmac(convert_to(v_id, 'UTF8'), v_secret, 'sha256');

  if exists (
    select 1 from private.tajir_customer_identity c
    where c.national_id_hmac = v_hash and c.profile_id <> v_user_id
  ) then
    raise exception 'This National ID is already registered with TAJIR.';
  end if;

  if exists (select 1 from private.tajir_account_identity i where i.profile_id = v_user_id) then
    if not exists (
      select 1 from private.tajir_account_identity i
      where i.profile_id = v_user_id and i.national_id_hmac = v_hash
    ) then
      raise exception 'Your National ID is already registered. Contact a TAJIR Director for a correction.';
    end if;
    update private.tajir_account_identity
       set id_full_name = v_name, updated_at = now()
     where profile_id = v_user_id;
    return;
  end if;

  insert into private.tajir_account_identity
    (profile_id, national_id_hmac, national_id_last4, id_full_name, national_id_ciphertext)
  values
    (v_user_id, v_hash, right(v_id, 4), v_name,
     extensions.pgp_sym_encrypt(v_id, v_key, 'cipher-algo=aes256,compress-algo=0'));
exception
  when unique_violation then
    raise exception 'This National ID is already registered with TAJIR.';
end;
$$;

create or replace function public.get_my_tajir_identity(p_profile_id uuid default auth.uid())
returns table (
  profile_id uuid,
  national_id text,
  id_full_name text,
  national_id_last4 text
)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_caller uuid := auth.uid();
  v_key text;
begin
  if v_caller is null then
    raise exception 'Please sign in to view identity details.';
  end if;
  if p_profile_id is null or (v_caller <> p_profile_id and not private.is_director()) then
    raise exception 'You are not authorised to view this identity.';
  end if;
  select decrypted_secret into v_key from vault.decrypted_secrets
    where name = 'tajir_national_id_encryption_key';
  if v_key is null then
    raise exception 'Secure identity access is temporarily unavailable.';
  end if;
  return query
    select i.profile_id,
      extensions.pgp_sym_decrypt(i.national_id_ciphertext, v_key),
      i.id_full_name,
      i.national_id_last4
    from private.tajir_account_identity i
    where i.profile_id = p_profile_id;
end;
$$;

revoke all on function public.register_my_tajir_identity(text, text) from public, anon;
revoke all on function public.get_my_tajir_identity(uuid) from public, anon;
grant execute on function public.register_my_tajir_identity(text, text) to authenticated;
grant execute on function public.get_my_tajir_identity(uuid) to authenticated;
