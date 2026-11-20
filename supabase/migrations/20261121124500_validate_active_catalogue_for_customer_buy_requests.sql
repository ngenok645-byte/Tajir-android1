create or replace function public.set_customer_tajir_buy_request_price()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_customer public.customers%rowtype; v_branch uuid; v_price numeric(14,2);
begin
 select * into v_customer from public.customers
  where id=new.customer_id and profile_id=auth.uid() and active=true;
 if not found then raise exception 'An active signed-in customer account is required.'; end if;
 if new.quantity_requested<=0 then raise exception 'Quantity must be greater than zero.'; end if;
 if new.quantity_unit not in ('KG','BAG') then raise exception 'Choose KG or bags.'; end if;
 v_branch:=coalesce(new.branch_id,v_customer.default_branch_id);
 if v_branch is null then select id into v_branch from public.branches where is_active order by name limit 1; end if;
 if v_branch is null then raise exception 'No active TAJIR branch is available.'; end if;
 select bp.selling_price_per_kg into v_price
 from public.branch_product_selling_prices bp
 join public.branches b on b.id=bp.branch_id and b.is_active=true
 join public.product_variants pv on pv.id=bp.product_variant_id and pv.is_active=true and pv.product_id=new.product_id
 join public.products p on p.id=pv.product_id and p.is_active=true
 where bp.branch_id=v_branch and bp.product_variant_id=new.product_variant_id;
 if v_price is null then raise exception 'TAJIR Director has not set the BUY price for this active product at the selected branch.'; end if;
 new.branch_id:=v_branch;
 new.quantity_kg:=case when new.quantity_unit='BAG' then new.quantity_requested*90 else new.quantity_requested end;
 new.unit_price_per_kg:=v_price; new.line_total_kes:=round(new.quantity_kg*v_price,2);
 return new;
end; $$;