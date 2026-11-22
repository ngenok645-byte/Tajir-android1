-- Restrict service-provider directories to the connected TAJIR account categories.
-- Clients and drivers must not browse mechanic or auto-spare directories.
-- Mechanics and auto-spare owners can see only the counterpart providers they work with.
drop policy if exists mechanic_profiles_read on public.mechanic_profiles;
create policy mechanic_profiles_read
on public.mechanic_profiles
for select
to authenticated
using (
  profile_id = (select auth.uid())
  or (select private.has_app_role('director'))
  or (
    status = 'approved'
    and (
      (select private.has_app_role('tractor_owner'))
      or (select private.has_app_role('auto_spares_owner'))
    )
  )
);

drop policy if exists auto_spares_profiles_read on public.auto_spares_profiles;
create policy auto_spares_profiles_read
on public.auto_spares_profiles
for select
to authenticated
using (
  profile_id = (select auth.uid())
  or (select private.has_app_role('director'))
  or (
    status = 'approved'
    and (
      (select private.has_app_role('tractor_owner'))
      or (select private.has_app_role('mechanic'))
    )
  )
);

drop policy if exists auto_spares_inventory_read on public.auto_spares_inventory;
create policy auto_spares_inventory_read
on public.auto_spares_inventory
for select
to authenticated
using (
  exists (
    select 1
    from public.auto_spares_profiles p
    where p.id = shop_id
      and p.profile_id = (select auth.uid())
  )
  or (select private.has_app_role('director'))
  or (
    status = 'active'
    and (
      (select private.has_app_role('tractor_owner'))
      or (select private.has_app_role('mechanic'))
    )
  )
);

drop policy if exists tractor_owner_profiles_related_provider_read
on public.tractor_owner_profiles;
create policy tractor_owner_profiles_related_provider_read
on public.tractor_owner_profiles
for select
to authenticated
using (
  status = 'approved'
  and (
    (select private.has_app_role('mechanic'))
    or (select private.has_app_role('auto_spares_owner'))
  )
);
