-- Complete Director access to review third-party marketplace listings.
drop policy if exists marketplace_listings_director_read on public.marketplace_listings;
create policy marketplace_listings_director_read
  on public.marketplace_listings for select to authenticated
  using (
    exists (
      select 1
      from public.user_role_assignments ura
      join public.app_roles ar on ar.id = ura.role_id
      where ura.user_id = (select auth.uid())
        and ura.is_active = true
        and ar.code = 'director'
    )
  );

-- Legacy price_per_unit remains temporarily for older installed clients.
-- Prevent a seller from changing that legacy price after a listing is created;
-- the new client uses the Director-controlled price tables instead.
create or replace function public.tajir_guard_marketplace_legacy_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.price_per_unit is distinct from old.price_per_unit
     and not exists (
       select 1
       from public.user_role_assignments ura
       join public.app_roles ar on ar.id = ura.role_id
       where ura.user_id = auth.uid()
         and ura.is_active = true
         and ar.code = 'director'
     ) then
    raise exception 'Marketplace prices are managed by the TAJIR Director.';
  end if;
  return new;
end;
$$;
revoke all on function public.tajir_guard_marketplace_legacy_price() from public, anon, authenticated;
drop trigger if exists tajir_guard_marketplace_legacy_price on public.marketplace_listings;
create trigger tajir_guard_marketplace_legacy_price
before update of price_per_unit on public.marketplace_listings
for each row execute function public.tajir_guard_marketplace_legacy_price();
