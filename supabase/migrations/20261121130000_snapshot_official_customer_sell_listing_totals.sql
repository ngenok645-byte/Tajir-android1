alter table public.marketplace_listings add column if not exists total_value_kes numeric(14,2);
create or replace function public.set_marketplace_tajir_sell_price()
returns trigger language plpgsql security definer set search_path = '' as $$
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
 from public.branch_product_selling_prices bp
 join public.branches b on b.id=bp.branch_id and b.is_active=true
 join public.product_variants pv on pv.id=bp.product_variant_id and pv.is_active=true
 join public.products p on p.id=pv.product_id and p.is_active=true
 where bp.branch_id=v_branch and bp.product_variant_id=new.product_variant_id;
 if v_price is null then raise exception 'TAJIR Director has not set the SELL price for this product at the selected branch.'; end if;
 new.branch_id:=v_branch; new.product_name:=left(v_name,100);
 new.price_per_unit:=case when new.unit='BAG' then v_price*90 else v_price end;
 new.total_value_kes:=round(new.quantity_kg*v_price,2);
 return new;
end; $$;
drop trigger if exists trg_marketplace_tajir_sell_price on public.marketplace_listings;
create trigger trg_marketplace_tajir_sell_price
before insert or update of product_variant_id, branch_id, quantity, unit, price_per_unit, total_value_kes
on public.marketplace_listings for each row execute function public.set_marketplace_tajir_sell_price();