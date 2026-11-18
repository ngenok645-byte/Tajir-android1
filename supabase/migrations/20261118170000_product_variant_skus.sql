-- Assign stable, human-readable SKUs to each product variant.
alter table public.product_variants add column if not exists sku text;

with numbered as (
  select pv.id, p.name as product_name, pv.variant_name,
         row_number() over (partition by pv.product_id order by pv.variant_name, pv.id) as seq
  from public.product_variants pv
  join public.products p on p.id = pv.product_id
)
update public.product_variants pv
set sku = case
  when lower(n.product_name) = 'maize' then 'MAI-' || lpad(n.seq::text, 3, '0')
  when lower(n.product_name) = 'fertilizer' then 'FER-' || regexp_replace(upper(n.variant_name), '[^A-Z0-9]+', '-', 'g') || '-' || lpad(n.seq::text, 3, '0')
  when lower(n.product_name) = 'beans' then 'BEA-' || regexp_replace(upper(n.variant_name), '[^A-Z0-9]+', '-', 'g') || '-' || lpad(n.seq::text, 3, '0')
  else upper(regexp_replace(n.product_name, '[^A-Za-z0-9]+', '-', 'g')) || '-' || lpad(n.seq::text, 3, '0')
end
from numbered n
where pv.id = n.id and pv.sku is null;

alter table public.product_variants alter column sku set not null;
create unique index if not exists product_variants_sku_uidx on public.product_variants (sku);

create or replace function public.assign_product_variant_sku()
returns trigger
language plpgsql
set search_path = public
as $$
declare
  product_name text;
  prefix text;
  next_no integer;
begin
  if new.sku is not null and btrim(new.sku) <> '' then
    return new;
  end if;
  select name into product_name from public.products where id = new.product_id;
  if lower(product_name) = 'maize' then
    prefix := 'MAI';
  elsif lower(product_name) = 'fertilizer' then
    prefix := 'FER-' || regexp_replace(upper(new.variant_name), '[^A-Z0-9]+', '-', 'g');
  elsif lower(product_name) = 'beans' then
    prefix := 'BEA-' || regexp_replace(upper(new.variant_name), '[^A-Z0-9]+', '-', 'g');
  else
    prefix := upper(regexp_replace(product_name, '[^A-Za-z0-9]+', '-', 'g'));
  end if;
  perform pg_advisory_xact_lock(hashtext(new.product_id::text));
  select coalesce(max(nullif(regexp_replace(sku, '^.*-([0-9]+)$', '\\1'), sku)::integer), 0) + 1
    into next_no
    from public.product_variants
   where sku like prefix || '-%';
  new.sku := prefix || '-' || lpad(next_no::text, 3, '0');
  return new;
end;
$$;

drop trigger if exists trg_product_variant_sku on public.product_variants;
create trigger trg_product_variant_sku
before insert on public.product_variants
for each row execute function public.assign_product_variant_sku();
