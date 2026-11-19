-- Prevent provider accounts from self-approving; Director alone can approve/suspend.
drop policy if exists mechanic_profiles_update_self on public.mechanic_profiles;
create policy mechanic_profiles_update_self on public.mechanic_profiles for update to authenticated
using(profile_id=(select auth.uid())) with check(profile_id=(select auth.uid()) and status='pending');
create policy mechanic_profiles_director_update on public.mechanic_profiles for update to authenticated
using((select private.has_app_role('director'))) with check((select private.has_app_role('director')));
drop policy if exists auto_spares_profiles_update_self on public.auto_spares_profiles;
create policy auto_spares_profiles_update_self on public.auto_spares_profiles for update to authenticated
using(profile_id=(select auth.uid())) with check(profile_id=(select auth.uid()) and status='pending');
create policy auto_spares_profiles_director_update on public.auto_spares_profiles for update to authenticated
using((select private.has_app_role('director'))) with check((select private.has_app_role('director')));
