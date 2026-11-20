-- Keep the two customer-facing trade prices independent and director-managed.
alter table public.branch_product_selling_prices add column if not exists buying_price_per_kg numeric(14,2);
alter table public.branch_product_selling_prices add constraint branch_product_prices_nonnegative check (selling_price_per_kg >= 0 and (buying_price_per_kg is null or buying_price_per_kg >= 0));
create unique index if not exists branch_product_selling_prices_branch_variant_uidx on public.branch_product_selling_prices(branch_id, product_variant_id);
alter table public.customer_product_requests add column if not exists quantity_unit text not null default 'BAG', add column if not exists quantity_kg numeric(14,3);
alter table public.customer_product_requests add constraint customer_product_requests_quantity_unit_check check (quantity_unit in ('KG','BAG'));
alter table public.marketplace_listings add column if not exists product_variant_id uuid references public.product_variants(id), add column if not exists branch_id uuid references public.branches(id), add column if not exists quantity_kg numeric(14,3);
create index if not exists marketplace_listings_variant_idx on public.marketplace_listings(product_variant_id);

create or replace function public.set_customer_tajir_buy_request_price() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_customer public.customers%rowtype; v_branch uuid; v_price numeric(14,2);
begin
 select * into v_customer from public.customers where id=new.customer_id and profile_id=auth.uid() and active=true;
 if not found then raise exception 'An active signed-in customer account is required.'; end if;
 if new.quantity_requested<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 if new.quantity_unit not in ('KG','BAG') then raise exception 'Choose KG or bags.'; end if;
 v_branch:=coalesce(new.branch_id,v_customer.default_branch_id);
 if v_branch is null then select id into v_branch from public.branches where is_active order by name limit 1; end if;
 if v_branch is null then raise exception 'No active TAJIR branch is available.'; end if;
 select selling_price_per_kg into v_price from public.branch_product_selling_prices where branch_id=v_branch and product_variant_id=new.product_variant_id;
 if v_price is null then raise exception 'TAJIR Director has not set the BUY price for this product at the selected branch.'; end if;
 new.branch_id:=v_branch;
 new.quantity_kg:=case when new.quantity_unit='BAG' then new.quantity_requested*90 else new.quantity_requested end;
 new.unit_price_per_kg:=v_price; new.line_total_kes:=round(new.quantity_kg*v_price,2);
 return new;
end; $$;
drop trigger if exists trg_customer_tajir_buy_request_price on public.customer_product_requests;
create trigger trg_customer_tajir_buy_request_price before insert on public.customer_product_requests for each row execute function public.set_customer_tajir_buy_request_price();

create or replace function public.set_marketplace_tajir_sell_price() returns trigger language plpgsql security definer set search_path = '' as $$
declare v_customer public.customers%rowtype; v_branch uuid; v_price numeric(14,2); v_name text;
begin
 select * into v_customer from public.customers where id=new.seller_customer_id and profile_id=auth.uid() and active=true and marketplace_can_sell=true;
 if not found then raise exception 'An active customer with SELL permission is required.'; end if;
 if new.product_variant_id is null then raise exception 'Choose a TAJIR product from the catalogue before listing it.'; end if;
 if new.quantity<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 if upper(new.unit) in ('BAG','BAGS') then new.unit:='BAG'; new.quantity_kg:=new.quantity*90;
 elsif upper(new.unit) in ('KG','KGS','KILOGRAM','KILOGRAMS') then new.unit:='KG'; new.quantity_kg:=new.quantity;
 else raise exception 'Unit must be KG or BAG.'; end if;
 v_branch:=coalesce(new.branch_id,v_customer.default_branch_id);
 if v_branch is null then select id into v_branch from public.branches where is_active order by name limit 1; end if;
 select bp.buying_price_per_kg,p.name || ' • ' || pv.variant_name into v_price,v_name
 from public.branch_product_selling_prices bp join public.product_variants pv on pv.id=bp.product_variant_id join public.products p on p.id=pv.product_id
 where bp.branch_id=v_branch and bp.product_variant_id=new.product_variant_id and p.is_active and pv.is_active;
 if v_price is null then raise exception 'TAJIR Director has not set the SELL price for this product at the selected branch.'; end if;
 new.branch_id:=v_branch; new.product_name:=left(v_name,100); new.price_per_unit:=case when new.unit='BAG' then v_price*90 else v_price end;
 return new;
end; $$;
drop trigger if exists trg_marketplace_tajir_sell_price on public.marketplace_listings;
create trigger trg_marketplace_tajir_sell_price before insert or update on public.marketplace_listings for each row execute function public.set_marketplace_tajir_sell_price();
revoke all on function public.set_customer_tajir_buy_request_price() from public,anon,authenticated;
revoke all on function public.set_marketplace_tajir_sell_price() from public,anon,authenticated;
comment on column public.branch_product_selling_prices.selling_price_per_kg is 'BUY price: KES per KG customer pays TAJIR when buying from TAJIR.';
comment on column public.branch_product_selling_prices.buying_price_per_kg is 'SELL price: KES per KG TAJIR pays customer when buying customer produce.';
