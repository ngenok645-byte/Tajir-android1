create schema if not exists private;

create table if not exists private.tajir_identity_secret (
  singleton boolean primary key default true check (singleton),
  secret bytea not null
);
insert into private.tajir_identity_secret(singleton, secret)
values (true, extensions.gen_random_bytes(32))
on conflict (singleton) do nothing;
revoke all on private.tajir_identity_secret from public, anon, authenticated;

create table if not exists private.tajir_customer_identity (
  profile_id uuid primary key references auth.users(id) on delete cascade,
  national_id_hmac bytea not null unique,
  national_id_last4 text not null check (national_id_last4 ~ '^[0-9]{4}$'),
  created_at timestamptz not null default now()
);
revoke all on private.tajir_customer_identity from public, anon, authenticated;

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
  select secret into v_secret from private.tajir_identity_secret where singleton = true;
  v_hash := extensions.hmac(convert_to(v_id, 'UTF8'), v_secret, 'sha256');
  if exists (select 1 from private.tajir_customer_identity i where i.profile_id = v_user_id) then
    raise exception 'A National ID is already registered on this account. Contact TAJIR support if it needs correction.';
  end if;
  insert into private.tajir_customer_identity(profile_id, national_id_hmac, national_id_last4)
  values (v_user_id, v_hash, right(v_id, 4));
exception
  when unique_violation then
    raise exception 'This National ID is already registered with TAJIR.';
end;
$$;

revoke all on function public.register_my_national_id(text) from public, anon;
grant execute on function public.register_my_national_id(text) to authenticated;
