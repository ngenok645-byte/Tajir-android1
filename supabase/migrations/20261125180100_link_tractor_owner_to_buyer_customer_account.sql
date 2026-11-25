-- Link each independently registered tractor owner to a TAJIR buyer account.
-- Seller access remains director-controlled and is never granted by this function.

create or replace function public.ensure_tractor_owner_customer_account()
returns uuid
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_user_id uuid := auth.uid();
  v_owner public.tractor_owner_profiles%rowtype;
  v_customer_id uuid;
  v_phone text;
begin
  if v_user_id is null then
    raise exception 'Please sign in before opening your TAJIR trading account.';
  end if;

  select * into v_owner
    from public.tractor_owner_profiles
   where profile_id = v_user_id
   for update;

  if not found then
    raise exception 'A tractor-owner account is required before linking TAJIR trading.';
  end if;

  v_phone := regexp_replace(coalesce(v_owner.phone, ''), '[^0-9]', '', 'g');
  if v_phone like '0%' and length(v_phone) = 10 then
    v_phone := '254' || substr(v_phone, 2);
  end if;
  if length(v_phone) <> 12 or v_phone not like '254%' then
    raise exception 'Update your tractor-owner phone number before linking TAJIR trading.';
  end if;

  if exists (
    select 1 from public.customers c
     where regexp_replace(c.phone, '[^0-9]', '', 'g') in (v_phone, '0' || substr(v_phone, 4))
       and c.profile_id is distinct from v_user_id
       and c.permanently_deleted_at is null
  ) then
    raise exception 'This phone number is already linked to another TAJIR customer account.';
  end if;

  select id into v_customer_id
    from public.customers
   where profile_id = v_user_id
     and permanently_deleted_at is null
     and deleted_at is null
   for update;

  if v_customer_id is null then
    if exists (select 1 from public.customers where profile_id = v_user_id) then
      raise exception 'This TAJIR customer account is archived. Contact the TAJIR director to restore it.';
    end if;
    insert into public.customers
      (profile_id, customer_type, full_name, phone, active, marketplace_can_buy, marketplace_can_sell)
    values
      (v_user_id, 'buyer', btrim(v_owner.full_name), '+' || v_phone, true, true, false)
    returning id into v_customer_id;
  else
    update public.customers
       set full_name = btrim(v_owner.full_name),
           phone = '+' || v_phone,
           active = true,
           marketplace_can_buy = true,
           customer_type = case when marketplace_can_sell then 'both' else 'buyer' end
     where id = v_customer_id;
  end if;

  return v_customer_id;
end;
$function$;

revoke all on function public.ensure_tractor_owner_customer_account() from public, anon;
grant execute on function public.ensure_tractor_owner_customer_account() to authenticated;
