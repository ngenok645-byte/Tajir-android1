begin;

-- Legacy marketplace_listings.price_per_unit is publicly readable.
-- The Director-managed selling/buying price tables are now the only price source.
alter table public.marketplace_listings
  alter column price_per_unit set default 0;

update public.marketplace_listings
set price_per_unit = 0
where price_per_unit <> 0;

drop trigger if exists trg_tajir_guard_marketplace_legacy_price
  on public.marketplace_listings;

create or replace function public.tajir_zero_legacy_marketplace_price()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.price_per_unit := 0;
  return new;
end;
$$;

alter table public.marketplace_listings
  drop constraint if exists marketplace_listings_price_per_unit_check;

alter table public.marketplace_listings
  add constraint marketplace_listings_legacy_price_zero_check
  check (price_per_unit = 0);

create trigger trg_tajir_zero_legacy_marketplace_price
before insert or update of price_per_unit
on public.marketplace_listings
for each row
execute function public.tajir_zero_legacy_marketplace_price();

comment on column public.marketplace_listings.price_per_unit is
  'Legacy field retained for compatibility only; always zero. Use Director-managed marketplace_listing_buying_prices and marketplace_listing_selling_prices.';

-- Lock the approved selling price at the moment a buyer submits a request.
alter table public.marketplace_purchase_requests
  add column if not exists selling_price_kes_snapshot numeric(14,2),
  add column if not exists line_total_kes_snapshot numeric(14,2);

create or replace function public.tajir_snapshot_marketplace_request_price()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price numeric(14,2);
begin
  select p.selling_price_kes
    into v_price
  from public.marketplace_listing_selling_prices p
  where p.listing_id = new.listing_id;

  if v_price is null or v_price <= 0 then
    raise exception 'This listing is not yet priced by TAJIR. Please contact the Director.';
  end if;

  new.selling_price_kes_snapshot := v_price;
  new.line_total_kes_snapshot := round(new.quantity * v_price, 2);
  return new;
end;
$$;

drop trigger if exists trg_tajir_snapshot_marketplace_request_price
  on public.marketplace_purchase_requests;

create trigger trg_tajir_snapshot_marketplace_request_price
before insert
on public.marketplace_purchase_requests
for each row
execute function public.tajir_snapshot_marketplace_request_price();

comment on column public.marketplace_purchase_requests.selling_price_kes_snapshot is
  'Director-approved selling price per listing unit, snapshotted when the buyer submits the request.';
comment on column public.marketplace_purchase_requests.line_total_kes_snapshot is
  'Server-calculated quantity multiplied by the snapshotted Director-approved selling price.';

-- Atomically set both private marketplace prices. Only an active Director may do this.
create or replace function public.director_set_marketplace_listing_prices(
  p_listing_id uuid,
  p_buying_price_kes numeric,
  p_selling_price_kes numeric
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null or not exists (
    select 1
    from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = auth.uid()
      and ura.is_active
      and ar.code = 'director'
  ) then
    raise exception 'Only an active Director can set marketplace prices.';
  end if;

  if p_buying_price_kes is null or p_buying_price_kes <= 0
     or p_selling_price_kes is null or p_selling_price_kes <= 0 then
    raise exception 'Both buying and selling prices must be greater than zero.';
  end if;

  if not exists (select 1 from public.marketplace_listings where id = p_listing_id) then
    raise exception 'Marketplace listing not found.';
  end if;

  insert into public.marketplace_listing_buying_prices
    (listing_id, buying_price_kes, updated_by, updated_at)
  values
    (p_listing_id, p_buying_price_kes, auth.uid(), now())
  on conflict (listing_id) do update
    set buying_price_kes = excluded.buying_price_kes,
        updated_by = excluded.updated_by,
        updated_at = now();

  insert into public.marketplace_listing_selling_prices
    (listing_id, selling_price_kes, updated_by, updated_at)
  values
    (p_listing_id, p_selling_price_kes, auth.uid(), now())
  on conflict (listing_id) do update
    set selling_price_kes = excluded.selling_price_kes,
        updated_by = excluded.updated_by,
        updated_at = now();
end;
$$;

revoke all on function public.director_set_marketplace_listing_prices(uuid, numeric, numeric) from public, anon;
grant execute on function public.director_set_marketplace_listing_prices(uuid, numeric, numeric) to authenticated;

commit;
