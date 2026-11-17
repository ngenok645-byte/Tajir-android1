create or replace function public.register_customer_account(p_full_name text, p_phone text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user_id uuid := auth.uid();
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_auth_phone text;
  v_customer_id uuid;
begin
  if v_user_id is null then
    raise exception 'You must be signed in to register a customer account';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 then
    raise exception 'Enter your full name';
  end if;
  if v_phone like '0%' and length(v_phone) = 10 then
    v_phone := '254' || substr(v_phone, 2);
  end if;
  if length(v_phone) <> 12 or v_phone not like '254%' then
    raise exception 'Enter a valid Kenyan phone number';
  end if;

  select regexp_replace(coalesce(u.phone, ''), '[^0-9]', '', 'g')
    into v_auth_phone
    from auth.users u
   where u.id = v_user_id;

  if v_auth_phone is null then
    raise exception 'Phone-based sign-in is required';
  end if;
  if v_auth_phone like '0%' and length(v_auth_phone) = 10 then
    v_auth_phone := '254' || substr(v_auth_phone, 2);
  end if;
  if v_auth_phone <> v_phone then
    raise exception 'The registered phone number does not match the signed-in account';
  end if;

  if exists (
    select 1 from public.customers c
    where regexp_replace(c.phone, '[^0-9]', '', 'g') in (v_phone, '0' || substr(v_phone, 4))
      and c.profile_id is distinct from v_user_id
  ) then
    raise exception 'This phone number is already registered';
  end if;

  insert into public.profiles (id, display_name, phone, status)
  values (v_user_id, trim(p_full_name), '+' || v_phone, 'pending')
  on conflict (id) do update
    set display_name = excluded.display_name,
        phone = excluded.phone,
        status = 'pending',
        updated_at = now();

  insert into public.customers
    (profile_id, customer_type, full_name, phone, active)
  values
    (v_user_id, 'buyer', trim(p_full_name), '+' || v_phone, false)
  on conflict (profile_id) do update
    set full_name = excluded.full_name,
        phone = excluded.phone,
        active = false
  returning id into v_customer_id;

  return v_customer_id;
end;
$$;

revoke all on function public.register_customer_account(text, text) from public, anon;
grant execute on function public.register_customer_account(text, text) to authenticated;

create or replace function public.get_my_account_status()
returns table(account_status text, is_customer boolean, customer_active boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select p.status::text,
         exists(select 1 from public.customers c where c.profile_id = auth.uid()),
         coalesce((select c.active from public.customers c where c.profile_id = auth.uid()), false)
  from public.profiles p
  where p.id = auth.uid()
$$;

revoke all on function public.get_my_account_status() from public, anon;
grant execute on function public.get_my_account_status() to authenticated;

drop policy if exists profile_read_own on public.profiles;
create policy profile_read_own on public.profiles
for select to authenticated
using (id = auth.uid());