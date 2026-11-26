-- Allow authorised TAJIR directors to inspect and manage tractor-owner profiles,
-- owner-to-tractor links, and tractor service jobs across branch boundaries.
-- Access remains restricted to the private director-role predicate.
create policy director_manage_tractor_owner_profiles
on public.tractor_owner_profiles
for all
to authenticated
using (private.is_director())
with check (private.is_director());

create policy director_manage_tractor_owner_assets
on public.tractor_owner_assets
for all
to authenticated
using (private.is_director())
with check (private.is_director());

create policy director_manage_tractor_service_jobs
on public.tractor_service_jobs
for all
to authenticated
using (private.is_director())
with check (private.is_director());
