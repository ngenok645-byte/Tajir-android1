create or replace function public.register_customer_account(p_full_name text, p_phone text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_phone text := regexp_replace(coalesce(p_phone, ''), '[^0-9]', '', 'g');
  v_customer_id uuid;
begin
  if v_user_id is null then
    raise exception 'You must be signed in to register a customer account';
  end if;
  if length(trim(coalesce(p_full_name, ''))) < 2 or length(trim(p_full_name)) > 80 then
    raise exception 'Enter your full name';
  end if;
  if v_phone like '0%' and length(v_phone) = 10 then
    v_phone := '254' || substr(v_phone, 2);
  end if;
  if length(v_phone) <> 12 or v_phone not like '254%' then
    raise exception 'Enter a valid Kenyan phone number';
  end if;

  if exists (
    select 1 from public.customers c
    where regexp_replace(c.phone, '[^0-9]', '', 'g') in (v_phone, '0' || substr(v_phone, 4))
      and c.profile_id is distinct from v_user_id
  ) then
    raise exception 'This phone number is already registered';
  end if;

  update public.profiles
     set display_name = trim(p_full_name),
         phone = '+' || v_phone,
         status = 'pending',
         updated_at = now()
   where id = v_user_id;
  if not found then
    raise exception 'Customer profile was not created. Please try again.';
  end if;

  insert into public.customers (profile_id, customer_type, full_name, phone, active)
  values (v_user_id, 'buyer', trim(p_full_name), '+' || v_phone, false)
  on conflict (profile_id) do update
    set full_name = excluded.full_name,
        phone = excluded.phone,
        active = false
  returning id into v_customer_id;
  return v_customer_id;
end;
$function$;

revoke all on function public.register_customer_account(text, text) from public, anon;
grant execute on function public.register_customer_account(text, text) to authenticated;
