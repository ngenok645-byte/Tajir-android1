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

drop constraint if exists marketplace_listings_price_per_unit_check
  on public.marketplace_listings;

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

commit;
