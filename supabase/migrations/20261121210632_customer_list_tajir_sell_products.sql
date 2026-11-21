-- Return only products/branches with an official TAJIR BUY price for customers who may sell.
-- The price is read from the Director-managed buying_price_per_kg field.
create or replace function public.customer_list_tajir_sell_products()
returns table (
  branch_id uuid,
  branch_name text,
  product_id uuid,
  product_name text,
  product_variant_id uuid,
  variant_name text,
  official_tajir_buy_price_per_kg numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if not exists (
    select 1
    from public.customers c
    join public.profiles p on p.id = c.profile_id
    where c.profile_id = auth.uid()
      and c.active = true
      and c.marketplace_can_sell = true
      and p.status = 'active'
  ) then
    raise exception 'An active customer account with Sell permission is required.'
      using errcode = '42501';
  end if;

  return query
  select b.id, b.name, p.id, p.name, pv.id, pv.variant_name, bp.buying_price_per_kg
  from public.branch_product_selling_prices bp
  join public.branches b on b.id = bp.branch_id and b.is_active = true
  join public.product_variants pv on pv.id = bp.product_variant_id and pv.is_active = true
  join public.products p on p.id = pv.product_id and p.is_active = true
  where bp.buying_price_per_kg is not null and bp.buying_price_per_kg > 0
  order by b.name, p.name, pv.variant_name;
end;
$function$;

revoke all on function public.customer_list_tajir_sell_products() from public, anon;
grant execute on function public.customer_list_tajir_sell_products() to authenticated;
