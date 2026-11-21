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
  unit text
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
         pv.base_unit::text
  from public.products p
  join public.product_variants pv on pv.product_id = p.id and pv.is_active = true
  cross join public.branches b
  left join public.branch_product_settings bps
    on bps.branch_id = b.id and bps.product_variant_id = pv.id
  where p.is_active = true
    and b.is_active = true
    and coalesce(bps.is_available_for_sale, true) = true
  order by b.name, p.name, pv.variant_name;
end;
$function$;
revoke all on function public.customer_list_tajir_products() from public, anon;
grant execute on function public.customer_list_tajir_products() to authenticated;

-- Track the customer's explicit acceptance of the Director-approved custom quote.
alter table public.customer_custom_product_requests
  add column if not exists customer_confirmed_at timestamptz;

create or replace function public.customer_confirm_custom_product_request(p_request_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'Sign in with your customer account to continue.';
  end if;

  update public.customer_custom_product_requests r
  set customer_confirmed_at = now(), updated_at = now()
  where r.id = p_request_id
    and r.status = 'approved'
    and r.customer_confirmed_at is null
    and exists (
      select 1 from public.customers c
      where c.id = r.customer_id
        and c.profile_id = auth.uid()
        and c.active = true
    );

  if not found then
    raise exception 'This request is not approved, is already confirmed, or does not belong to your account.';
  end if;
end;
$function$;

revoke all on function public.customer_confirm_custom_product_request(uuid) from public, anon;
grant execute on function public.customer_confirm_custom_product_request(uuid) to authenticated;
