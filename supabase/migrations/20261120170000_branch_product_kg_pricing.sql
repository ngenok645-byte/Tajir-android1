-- Director-controlled branch selling prices, expressed per kilogram.
create table if not exists public.branch_product_selling_prices (
  id uuid primary key default gen_random_uuid(),
  branch_id uuid not null references public.branches(id) on delete cascade,
  product_variant_id uuid not null references public.product_variants(id) on delete cascade,
  selling_price_per_kg numeric(14,2) not null check (selling_price_per_kg > 0),
  updated_by uuid references auth.users(id),
  updated_at timestamptz not null default now(),
  unique (branch_id, product_variant_id)
);
alter table public.branch_product_selling_prices enable row level security;
revoke all on public.branch_product_selling_prices from anon, authenticated;
grant select, insert, update, delete on public.branch_product_selling_prices to authenticated;
create policy branch_product_selling_prices_customer_read
 on public.branch_product_selling_prices for select to authenticated
 using (exists (select 1 from public.customers c where c.profile_id=auth.uid() and c.active=true));
create policy branch_product_selling_prices_director_manage
 on public.branch_product_selling_prices for all to authenticated
 using (private.is_director()) with check (private.is_director());

alter table public.customer_product_requests
 add column if not exists branch_id uuid references public.branches(id),
 add column if not exists unit_price_per_kg numeric(14,2),
 add column if not exists line_total_kes numeric(14,2);

create or replace function public.set_customer_product_request_price()
returns trigger language plpgsql security definer set search_path=public,auth
as $$
declare v_price numeric(14,2);
begin
 if auth.uid() is null or not exists (
   select 1 from public.customers c
   where c.id=new.customer_id and c.profile_id=auth.uid() and c.active=true
 ) then
   raise exception 'An active customer account is required.';
 end if;
 if new.branch_id is null or new.product_variant_id is null or new.quantity_requested is null or new.quantity_requested<=0 then
   raise exception 'Select a branch, product and a quantity in kilograms greater than zero.';
 end if;
 select p.selling_price_per_kg into v_price
 from public.branch_product_selling_prices p
 where p.branch_id=new.branch_id and p.product_variant_id=new.product_variant_id;
 if v_price is null then
   raise exception 'This product does not have a selling price yet. Please contact the branch.';
 end if;
 new.unit_price_per_kg:=v_price;
 new.line_total_kes:=round(new.quantity_requested*v_price,2);
 return new;
end;
$$;
drop trigger if exists trg_customer_product_request_price on public.customer_product_requests;
create trigger trg_customer_product_request_price
 before insert on public.customer_product_requests
 for each row execute function public.set_customer_product_request_price();

drop policy if exists customer_product_requests_customer_insert on public.customer_product_requests;
create policy customer_product_requests_customer_insert
 on public.customer_product_requests for insert to authenticated
 with check (exists (select 1 from public.customers c where c.id=customer_id and c.profile_id=auth.uid() and c.active=true));
drop policy if exists customer_product_requests_customer_read on public.customer_product_requests;
create policy customer_product_requests_customer_read
 on public.customer_product_requests for select to authenticated
 using (exists (select 1 from public.customers c where c.id=customer_id and c.profile_id=auth.uid() and c.active=true) or private.is_director());
drop policy if exists customer_product_requests_director_update on public.customer_product_requests;
create policy customer_product_requests_director_update
 on public.customer_product_requests for update to authenticated
 using (private.is_director()) with check (private.is_director());
grant select, insert on public.customer_product_requests to authenticated;
grant update on public.customer_product_requests to authenticated;
