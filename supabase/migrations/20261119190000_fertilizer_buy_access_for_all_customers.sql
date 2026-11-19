-- Allow every active customer to view and request active fertilizer listings,
-- regardless of marketplace buy/sell approval. Other products remain restricted
-- to customers approved for marketplace buying.

drop policy if exists marketplace_listings_customer_read on public.marketplace_listings;
create policy marketplace_listings_customer_read
on public.marketplace_listings
for select
to authenticated
using (
  exists (
    select 1
    from public.customers c
    where c.profile_id = (select auth.uid())
      and c.active = true
      and (
        (c.id = marketplace_listings.seller_customer_id and c.marketplace_can_sell = true)
        or (
          marketplace_listings.status = 'active'
          and (
            c.marketplace_can_buy = true
            or marketplace_listings.product_name ilike '%fertilizer%'
          )
        )
      )
  )
);

drop policy if exists marketplace_requests_buyer_insert on public.marketplace_purchase_requests;
create policy marketplace_requests_buyer_insert
on public.marketplace_purchase_requests
for insert
to authenticated
with check (
  exists (
    select 1
    from public.customers c
    where c.id = marketplace_purchase_requests.buyer_customer_id
      and c.profile_id = (select auth.uid())
      and c.active = true
      and (
        c.marketplace_can_buy = true
        or exists (
          select 1
          from public.marketplace_listings l
          where l.id = marketplace_purchase_requests.listing_id
            and l.status = 'active'
            and l.product_name ilike '%fertilizer%'
        )
      )
  )
  and exists (
    select 1
    from public.marketplace_listings l
    where l.id = marketplace_purchase_requests.listing_id
      and l.status = 'active'
  )
);

drop policy if exists marketplace_requests_customer_read on public.marketplace_purchase_requests;
create policy marketplace_requests_customer_read
on public.marketplace_purchase_requests
for select
to authenticated
using (
  exists (
    select 1
    from public.customers c
    join public.marketplace_listings l on l.id = marketplace_purchase_requests.listing_id
    where c.id = marketplace_purchase_requests.buyer_customer_id
      and c.profile_id = (select auth.uid())
      and c.active = true
      and (
        c.marketplace_can_buy = true
        or l.product_name ilike '%fertilizer%'
      )
  )
  or exists (
    select 1
    from public.marketplace_listings l
    join public.customers c on c.id = l.seller_customer_id
    where l.id = marketplace_purchase_requests.listing_id
      and c.profile_id = (select auth.uid())
      and c.active = true
      and c.marketplace_can_sell = true
  )
);
