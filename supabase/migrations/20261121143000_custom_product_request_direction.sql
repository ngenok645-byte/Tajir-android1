-- Keep the customer's trade direction explicit and never expose stock availability.
alter table public.customer_custom_product_requests
  add column if not exists request_direction text not null default 'BUY_FROM_TAJIR';
alter table public.customer_custom_product_requests
  drop constraint if exists customer_custom_product_requests_direction_check;
alter table public.customer_custom_product_requests
  add constraint customer_custom_product_requests_direction_check
  check (request_direction in ('BUY_FROM_TAJIR','SELL_TO_TAJIR'));
comment on column public.customer_custom_product_requests.request_direction is
  'Customer request direction. Proposed price is indicative only and is not an official TAJIR price.';

-- The customer catalogue must list active products configured for sale, not
-- inventory quantities. A zero balance must never hide a product or leak to clients.
drop function if exists public.customer_list_tajir_products();
create function public.customer_list_tajir_products()
returns table(
  branch_id uuid,
  branch_name text,
  product_id uuid,
  product_name text,
  product_variant_id uuid,
  variant_name text,
  unit text,
  official_buy_price_per_kg numeric
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null or not exists (
    select 1 from public.customers c
    where c.profile_id = auth.uid() and c.active = true
  ) then
    raise exception 'An active customer account is required to view the TAJIR catalogue.';
  end if;

  return query
  select b.id, b.name::text, p.id, p.name::text, pv.id, pv.variant_name::text,
         pv.base_unit::text, prices.selling_price_per_kg
  from public.products p
  join public.product_variants pv on pv.product_id = p.id and pv.is_active = true
  cross join public.branches b
  left join public.branch_product_settings bps
    on bps.branch_id = b.id and bps.product_variant_id = pv.id
  left join public.branch_product_selling_prices prices
    on prices.branch_id = b.id and prices.product_variant_id = pv.id
  where p.is_active = true
    and b.is_active = true
    and coalesce(bps.is_available_for_sale, true) = true
  order by b.name, p.name, pv.variant_name;
end;
$function$;
revoke all on function public.customer_list_tajir_products() from public, anon;
grant execute on function public.customer_list_tajir_products() to authenticated;
