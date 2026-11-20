-- A listing status update must not re-price a historic listing or require the seller session.
drop trigger if exists trg_marketplace_tajir_sell_price on public.marketplace_listings;
create trigger trg_marketplace_tajir_sell_price
before insert or update of product_variant_id, branch_id, quantity, unit, price_per_unit
on public.marketplace_listings
for each row execute function public.set_marketplace_tajir_sell_price();
