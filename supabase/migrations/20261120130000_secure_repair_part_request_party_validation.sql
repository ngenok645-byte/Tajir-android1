-- Enforce that a repair-parts request links the assigned mechanic,
-- the mechanic's repair job, and inventory owned by the selected shop.
drop policy if exists repair_part_requests_insert_mechanic on public.repair_part_requests;
create policy repair_part_requests_insert_mechanic
on public.repair_part_requests
for insert to authenticated
with check (
  status = 'requested'
  and supplied_at is null
  and installed_at is null
  and exists (
    select 1 from public.mechanic_profiles m
    where m.id = repair_part_requests.mechanic_id
      and m.profile_id = (select auth.uid())
      and m.status = 'approved'
  )
  and exists (
    select 1 from public.tractor_repair_jobs j
    where j.id = repair_part_requests.repair_job_id
      and j.mechanic_id = repair_part_requests.mechanic_id
  )
  and exists (
    select 1
    from public.auto_spares_inventory i
    join public.auto_spares_profiles s on s.id = i.shop_id
    where i.id = repair_part_requests.inventory_id
      and i.shop_id = repair_part_requests.shop_id
      and s.status = 'approved'
      and i.status = 'active'
  )
);

create or replace function public.enforce_repair_part_request_update()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_is_director boolean := private.has_app_role('director');
  v_is_mechanic boolean;
  v_is_shop boolean;
  v_is_owner boolean;
begin
  if v_is_director then
    return new;
  end if;

  if (to_jsonb(new) - array['status','supplied_at','installed_at'])
       is distinct from
     (to_jsonb(old) - array['status','supplied_at','installed_at']) then
    raise exception 'Repair part request details cannot be changed after submission';
  end if;

  select exists (
    select 1 from public.mechanic_profiles m
    where m.id = old.mechanic_id and m.profile_id = v_uid
  ) into v_is_mechanic;

  select exists (
    select 1 from public.auto_spares_profiles s
    where s.id = old.shop_id and s.profile_id = v_uid
  ) into v_is_shop;

  select exists (
    select 1 from public.tractor_repair_jobs j
    where j.id = old.repair_job_id and j.owner_user_id = v_uid
  ) into v_is_owner;

  if v_is_shop then
    if old.status = 'requested' and new.status in ('accepted','declined') then
      new.supplied_at := old.supplied_at;
      new.installed_at := old.installed_at;
      return new;
    elsif old.status = 'accepted' and new.status = 'supplied' then
      new.supplied_at := now();
      new.installed_at := old.installed_at;
      return new;
    end if;
  elsif v_is_mechanic then
    if old.status = 'requested' and new.status = 'cancelled' then
      new.supplied_at := old.supplied_at;
      new.installed_at := old.installed_at;
      return new;
    elsif old.status = 'supplied' and new.status = 'installed' then
      new.supplied_at := old.supplied_at;
      new.installed_at := now();
      return new;
    end if;
  elsif v_is_owner and old.status = 'requested' and new.status = 'cancelled' then
    new.supplied_at := old.supplied_at;
    new.installed_at := old.installed_at;
    return new;
  end if;

  raise exception 'You are not allowed to make this repair part request status change';
end;
$$;
revoke all on function public.enforce_repair_part_request_update() from public, anon, authenticated;

drop trigger if exists trg_enforce_repair_part_request_update on public.repair_part_requests;
create trigger trg_enforce_repair_part_request_update
before update on public.repair_part_requests
for each row execute function public.enforce_repair_part_request_update();

drop policy if exists repair_part_requests_update_parties on public.repair_part_requests;
create policy repair_part_requests_update_parties
on public.repair_part_requests
for update to authenticated
using (
  exists (
    select 1 from public.tractor_repair_jobs j
    where j.id = repair_part_requests.repair_job_id
      and j.owner_user_id = (select auth.uid())
  )
  or exists (
    select 1 from public.mechanic_profiles m
    where m.id = repair_part_requests.mechanic_id
      and m.profile_id = (select auth.uid())
  )
  or exists (
    select 1 from public.auto_spares_profiles s
    where s.id = repair_part_requests.shop_id
      and s.profile_id = (select auth.uid())
  )
  or private.has_app_role('director')
)
with check (
  exists (
    select 1 from public.tractor_repair_jobs j
    where j.id = repair_part_requests.repair_job_id
      and j.owner_user_id = (select auth.uid())
  )
  or exists (
    select 1 from public.mechanic_profiles m
    where m.id = repair_part_requests.mechanic_id
      and m.profile_id = (select auth.uid())
  )
  or exists (
    select 1 from public.auto_spares_profiles s
    where s.id = repair_part_requests.shop_id
      and s.profile_id = (select auth.uid())
  )
  or private.has_app_role('director')
);
