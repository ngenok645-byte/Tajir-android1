-- TAJIR marketplace: separate public selling prices from confidential buying prices.
-- This migration is additive so it can be reviewed and deployed together with the
-- matching Flutter client update. Do not remove the legacy price_per_unit column
-- until the client no longer reads/writes it.

create table if not exists public.marketplace_listing_selling_prices (
  listing_id uuid primary key references public.marketplace_listings(id) on delete cascade,
  selling_price_kes numeric(14,2) not null check (selling_price_kes > 0),
  updated_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_listing_buying_prices (
  listing_id uuid primary key references public.marketplace_listings(id) on delete cascade,
  buying_price_kes numeric(14,2) not null check (buying_price_kes > 0),
  updated_by uuid not null default auth.uid() references auth.users(id),
  updated_at timestamptz not null default now()
);

create table if not exists public.marketplace_listing_offers (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.marketplace_listings(id) on delete cascade,
  buyer_customer_id uuid not null references public.customers(id) on delete restrict,
  quantity numeric(14,3) not null check (quantity > 0),
  offer_price_kes numeric(14,2) not null check (offer_price_kes > 0),
  message text,
  status text not null default 'pending'
    check (status in ('pending','accepted','rejected','countered','withdrawn','completed')),
  director_counter_price_kes numeric(14,2)
    check (director_counter_price_kes is null or director_counter_price_kes > 0),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists marketplace_listing_offers_listing_created_idx
  on public.marketplace_listing_offers(listing_id, created_at desc);
create index if not exists marketplace_listing_offers_buyer_created_idx
  on public.marketplace_listing_offers(buyer_customer_id, created_at desc);

alter table public.marketplace_listing_selling_prices enable row level security;
alter table public.marketplace_listing_buying_prices enable row level security;
alter table public.marketplace_listing_offers enable row level security;

-- Public selling price is visible to authenticated marketplace users.
drop policy if exists marketplace_selling_price_read on public.marketplace_listing_selling_prices;
create policy marketplace_selling_price_read
  on public.marketplace_listing_selling_prices for select to authenticated
  using (exists (
    select 1 from public.marketplace_listings l
    where l.id = listing_id and l.status = 'active'
      and exists (
        select 1 from public.customers c
        where c.profile_id = (select auth.uid()) and c.active
          and (c.marketplace_can_buy or l.product_name ilike '%fertilizer%')
      )
  ) or exists (
    select 1 from public.customers c
    where c.profile_id = (select auth.uid()) and c.id = (
      select l.seller_customer_id from public.marketplace_listings l where l.id = listing_id
    )
  ) or exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ));

drop policy if exists marketplace_selling_price_director_write on public.marketplace_listing_selling_prices;
create policy marketplace_selling_price_director_write
  on public.marketplace_listing_selling_prices for all to authenticated
  using (exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ))
  with check (exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ));

-- Buying price is confidential: only the listing's seller and an active Director can read it.
drop policy if exists marketplace_buying_price_private_read on public.marketplace_listing_buying_prices;
create policy marketplace_buying_price_private_read
  on public.marketplace_listing_buying_prices for select to authenticated
  using (
    exists (
      select 1 from public.marketplace_listings l
      join public.customers c on c.id = l.seller_customer_id
      where l.id = listing_id and c.profile_id = (select auth.uid()) and c.active
    )
    or exists (
      select 1 from public.user_role_assignments ura
      join public.app_roles ar on ar.id = ura.role_id
      where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
    )
  );

drop policy if exists marketplace_buying_price_director_write on public.marketplace_listing_buying_prices;
create policy marketplace_buying_price_director_write
  on public.marketplace_listing_buying_prices for all to authenticated
  using (exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ))
  with check (exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ));

-- Offers: buyers create and read their own; listing seller reads; Directors manage/review.
drop policy if exists marketplace_offers_buyer_insert on public.marketplace_listing_offers;
create policy marketplace_offers_buyer_insert
  on public.marketplace_listing_offers for insert to authenticated
  with check (
    exists (
      select 1 from public.customers c
      where c.id = buyer_customer_id and c.profile_id = (select auth.uid())
        and c.active and c.marketplace_can_buy
    )
    and exists (
      select 1 from public.marketplace_listings l
      where l.id = listing_id and l.status = 'active'
    )
  );

drop policy if exists marketplace_offers_parties_read on public.marketplace_listing_offers;
create policy marketplace_offers_parties_read
  on public.marketplace_listing_offers for select to authenticated
  using (
    exists (
      select 1 from public.customers c
      where c.id = buyer_customer_id and c.profile_id = (select auth.uid())
    )
    or exists (
      select 1 from public.marketplace_listings l
      join public.customers c on c.id = l.seller_customer_id
      where l.id = listing_id and c.profile_id = (select auth.uid()) and c.active
    )
    or exists (
      select 1 from public.user_role_assignments ura
      join public.app_roles ar on ar.id = ura.role_id
      where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
    )
  );

drop policy if exists marketplace_offers_director_update on public.marketplace_listing_offers;
create policy marketplace_offers_director_update
  on public.marketplace_listing_offers for update to authenticated
  using (exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ))
  with check (exists (
    select 1 from public.user_role_assignments ura
    join public.app_roles ar on ar.id = ura.role_id
    where ura.user_id = (select auth.uid()) and ura.is_active and ar.code = 'director'
  ));

-- Remove inherited/default API grants, then grant only the operations required.
revoke all on public.marketplace_listing_selling_prices from anon, authenticated;
revoke all on public.marketplace_listing_buying_prices from anon, authenticated;
revoke all on public.marketplace_listing_offers from anon, authenticated;

grant select, insert, update, delete on public.marketplace_listing_selling_prices to authenticated;
grant select, insert, update, delete on public.marketplace_listing_buying_prices to authenticated;
grant select on public.marketplace_listing_offers to authenticated;
-- Buyers can submit offer content only; they cannot set review status, director
-- counter-price, reviewer identity, timestamps, or the generated offer ID.
grant insert (listing_id, buyer_customer_id, quantity, offer_price_kes, message)
  on public.marketplace_listing_offers to authenticated;
-- RLS limits offer updates to active Directors.
grant update on public.marketplace_listing_offers to authenticated;
