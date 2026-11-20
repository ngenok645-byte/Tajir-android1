create or replace function public.get_my_account_access()
returns table (
  profile_status text,
  role_codes text[],
  is_customer boolean,
  customer_active boolean,
  tractor_owner_status text,
  mechanic_status text,
  auto_spares_status text,
  is_driver boolean
)
language sql
stable
security definer
set search_path = ''
as $function$
  select
    p.status::text,
    coalesce((
      select array_agg(distinct ar.code order by ar.code)
      from public.user_role_assignments ura
      join public.app_roles ar on ar.id = ura.role_id
      where ura.user_id = auth.uid() and ura.is_active = true
    ), array[]::text[]),
    exists(select 1 from public.customers c where c.profile_id = auth.uid()),
    coalesce((select c.active from public.customers c where c.profile_id = auth.uid() limit 1), false),
    (select o.status from public.tractor_owner_profiles o where o.profile_id = auth.uid() limit 1),
    (select m.status from public.mechanic_profiles m where m.profile_id = auth.uid() limit 1),
    (select s.status from public.auto_spares_profiles s where s.profile_id = auth.uid() limit 1),
    exists(select 1 from public.vehicles v where v.driver_id = auth.uid())
  from public.profiles p
  where p.id = auth.uid()
$function$;
