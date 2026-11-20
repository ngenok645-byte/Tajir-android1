-- Allow Directors to see tractor-owner profiles in the Director Account Centre.
-- This is read-only access; status changes remain governed by separate audited actions.
drop policy if exists tractor_owner_profiles_director_read on public.tractor_owner_profiles;
create policy tractor_owner_profiles_director_read
on public.tractor_owner_profiles
for select
to authenticated
using (private.has_app_role('director'));
