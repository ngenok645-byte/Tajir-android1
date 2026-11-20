create table if not exists public.tajir_pin_reset_otps (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles(id) on delete cascade,
  phone_digits text not null,
  code_hash text not null,
  expires_at timestamptz not null,
  attempts integer not null default 0 check (attempts >= 0 and attempts <= 5),
  consumed_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists tajir_pin_reset_otps_profile_created_idx
  on public.tajir_pin_reset_otps(profile_id, created_at desc);
alter table public.tajir_pin_reset_otps enable row level security;
revoke all on public.tajir_pin_reset_otps from anon, authenticated;
grant all on public.tajir_pin_reset_otps to service_role;

create or replace function public.tajir_find_customer_for_pin_reset(p_phone_digits text)
returns table(profile_id uuid, registered_phone text)
language plpgsql
security definer
set search_path = ''
as $$
begin
  if p_phone_digits is null or p_phone_digits !~ '^254[17][0-9]{8}$' then
    return;
  end if;

  return query
  with matches as (
    select p.id, p.phone
    from public.profiles p
    join public.customers c on c.profile_id = p.id
    where p.status::text = 'active'
      and c.active = true
      and c.deleted_at is null
      and case
        when length(regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g')) = 10
          and left(regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g'),1) = '0'
        then '254' || substr(regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g'),2)
        when length(regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g')) = 9
          and left(regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g'),1) in ('7','1')
        then '254' || regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g')
        else regexp_replace(coalesce(p.phone,''), '[^0-9]', '', 'g')
      end = p_phone_digits
    limit 2
  )
  select m.id, m.phone from matches m;
end;
$$;
revoke all on function public.tajir_find_customer_for_pin_reset(text) from public, anon, authenticated;
grant execute on function public.tajir_find_customer_for_pin_reset(text) to service_role;
