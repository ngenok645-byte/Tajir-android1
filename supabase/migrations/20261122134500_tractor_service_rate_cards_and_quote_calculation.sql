-- Director-managed tractor service tariffs and quote calculation.
-- This pricing model is independent of TAJIR product prices and company branches.
create table if not exists public.tractor_service_rates (
  id uuid primary key default gen_random_uuid(),
  service_type text not null check (service_type in ('ploughing','harrowing','planting','transport','other')),
  pricing_unit text not null check (pricing_unit in ('per_acre','per_trip','per_km','per_tonne')),
  rate numeric(14,2) not null check (rate >= 0),
  county text, region text, village text,
  is_active boolean not null default true,
  updated_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (nullif(trim(coalesce(county,'')),'') is not null or nullif(trim(coalesce(region,'')),'') is not null or nullif(trim(coalesce(village,'')),'') is not null)
);
create index if not exists tractor_service_rates_lookup_idx on public.tractor_service_rates(service_type,is_active,county,region,village);
alter table public.tractor_service_rates enable row level security;
drop policy if exists tractor_service_rates_director_manage on public.tractor_service_rates;
create policy tractor_service_rates_director_manage on public.tractor_service_rates for all to authenticated using (private.is_director()) with check (private.is_director());
drop policy if exists tractor_service_rates_customer_read on public.tractor_service_rates;
create policy tractor_service_rates_customer_read on public.tractor_service_rates for select to authenticated using (is_active=true);
alter table public.tractor_service_jobs
  add column if not exists pricing_unit text,
  add column if not exists pricing_quantity numeric(14,3),
  add column if not exists rate_id uuid references public.tractor_service_rates(id),
  add column if not exists county text,
  add column if not exists region text,
  add column if not exists village text;
create or replace function public.customer_quote_tractor_service(
 p_service_type text,p_county text default null,p_region text default null,p_village text default null,
 p_quantity numeric default null,p_pricing_unit text default null
) returns table(rate_id uuid,pricing_unit text,unit_rate numeric,quantity numeric,total_charge numeric)
language plpgsql stable security definer set search_path=''
as $$
declare v_rate public.tractor_service_rates%rowtype;
begin
 if not exists(select 1 from public.customers c join public.profiles p on p.id=c.profile_id where c.profile_id=auth.uid() and c.active=true and p.status::text='active' and c.customer_type in ('buyer','seller','both')) then raise exception 'An active customer account is required.'; end if;
 if p_service_type not in ('ploughing','harrowing','planting','transport','other') then raise exception 'Select a valid service.'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Enter a quantity greater than zero.'; end if;
 select r.* into v_rate from public.tractor_service_rates r
 where r.is_active and r.service_type=p_service_type
 and (r.county is null or lower(trim(r.county))=lower(trim(coalesce(p_county,''))))
 and (r.region is null or lower(trim(r.region))=lower(trim(coalesce(p_region,''))))
 and (r.village is null or lower(trim(r.village))=lower(trim(coalesce(p_village,''))))
 and (p_service_type<>'transport' or p_pricing_unit is null or r.pricing_unit=p_pricing_unit)
 order by (case when r.village is not null then 4 else 0 end+case when r.region is not null then 2 else 0 end+case when r.county is not null then 1 else 0 end) desc,r.updated_at desc limit 1;
 if v_rate.id is null then raise exception 'No Director-approved rate is configured for this service and location yet.'; end if;
 if p_service_type<>'transport' and v_rate.pricing_unit<>'per_acre' then raise exception 'This land service must be priced per acre.'; end if;
 if p_pricing_unit is not null and p_pricing_unit<>v_rate.pricing_unit then raise exception 'The selected pricing unit does not match the approved service rate.'; end if;
 return query select v_rate.id,v_rate.pricing_unit,v_rate.rate,p_quantity,(v_rate.rate*p_quantity)::numeric(14,2);
end; $$;
revoke all on function public.customer_quote_tractor_service(text,text,text,text,numeric,text) from public;
grant execute on function public.customer_quote_tractor_service(text,text,text,text,numeric,text) to authenticated;
comment on table public.tractor_service_rates is 'Director-controlled tractor service tariffs, independent of TAJIR product pricing and company branches. Most-specific location rate wins.';
