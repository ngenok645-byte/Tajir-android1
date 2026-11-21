-- Client-submitted products that are not yet in the official TAJIR catalogue.
-- A proposed price is a negotiation request, never an official catalogue price.
create table if not exists public.customer_custom_product_requests (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete restrict,
  branch_id uuid references public.branches(id) on delete set null,
  product_name text not null check (char_length(trim(product_name)) between 2 and 120),
  description text,
  quantity numeric(14,3) not null check (quantity > 0),
  quantity_unit text not null check (quantity_unit in ('KG','BAG')),
  proposed_unit_price_kes numeric(14,2) not null check (proposed_unit_price_kes > 0),
  status text not null default 'pending' check (status in ('pending','under_review','approved','rejected','negotiation')),
  director_response text,
  agreed_unit_price_kes numeric(14,2) check (agreed_unit_price_kes is null or agreed_unit_price_kes > 0),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists customer_custom_product_requests_customer_created_idx
  on public.customer_custom_product_requests(customer_id, created_at desc);
alter table public.customer_custom_product_requests enable row level security;
drop policy if exists custom_product_requests_customer_read on public.customer_custom_product_requests;
create policy custom_product_requests_customer_read on public.customer_custom_product_requests
 for select to authenticated using (
  exists (select 1 from public.customers c where c.id=customer_id and c.profile_id=auth.uid())
  or (select private.is_director())
 );
drop policy if exists custom_product_requests_customer_insert on public.customer_custom_product_requests;
create policy custom_product_requests_customer_insert on public.customer_custom_product_requests
 for insert to authenticated with check (
  status='pending' and reviewed_by is null and reviewed_at is null
  and agreed_unit_price_kes is null
  and exists (select 1 from public.customers c where c.id=customer_id and c.profile_id=auth.uid() and c.active=true)
 );
drop policy if exists custom_product_requests_director_update on public.customer_custom_product_requests;
create policy custom_product_requests_director_update on public.customer_custom_product_requests
 for update to authenticated using (
  (select private.is_director())
 ) with check (
  exists (select 1 from public.profiles p where p.id=auth.uid() and lower(coalesce(p.role,'')) in ('director','owner'))
 );
grant select, insert on public.customer_custom_product_requests to authenticated;
grant update on public.customer_custom_product_requests to authenticated;
