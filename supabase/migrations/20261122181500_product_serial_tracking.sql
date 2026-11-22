-- Carry the stock batch serial through product, sale, supplier/customer payments and expenses.
alter table public.purchase_items add column if not exists product_serial text;
alter table public.sale_items add column if not exists product_serials text[] not null default '{}';
alter table public.purchase_costs add column if not exists product_serial text;
alter table public.customer_payments add column if not exists product_serials text[] not null default '{}';
alter table public.supplier_payments add column if not exists product_serials text[] not null default '{}';
alter table public.expenses add column if not exists stock_batch_id uuid references public.stock_batches(id);
alter table public.expenses add column if not exists product_serials text[] not null default '{}';

create or replace function public.tajir_sync_purchase_item_serial()
returns trigger language plpgsql set search_path='' as $$
begin
 update public.purchase_items set product_serial=new.batch_code where id=new.purchase_item_id;
 update public.purchase_costs set product_serial=new.batch_code where purchase_item_id=new.purchase_item_id;
 return new;
end; $$;
drop trigger if exists tajir_sync_purchase_item_serial on public.stock_batches;
create trigger tajir_sync_purchase_item_serial after insert or update of batch_code,purchase_item_id
on public.stock_batches for each row when (new.purchase_item_id is not null)
execute function public.tajir_sync_purchase_item_serial();
update public.purchase_items pi set product_serial=sb.batch_code
from public.stock_batches sb where sb.purchase_item_id=pi.id and pi.product_serial is distinct from sb.batch_code;

create or replace function public.tajir_sync_purchase_cost_serial()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.purchase_item_id is not null then
  select pi.product_serial into new.product_serial from public.purchase_items pi where pi.id=new.purchase_item_id;
 end if;
 return new;
end; $$;
drop trigger if exists tajir_sync_purchase_cost_serial on public.purchase_costs;
create trigger tajir_sync_purchase_cost_serial before insert or update of purchase_item_id
on public.purchase_costs for each row execute function public.tajir_sync_purchase_cost_serial();
update public.purchase_costs pc set product_serial=pi.product_serial
from public.purchase_items pi where pi.id=pc.purchase_item_id and pc.product_serial is distinct from pi.product_serial;

create or replace function public.tajir_sync_sale_item_serials()
returns trigger language plpgsql set search_path='' as $$
begin
 select coalesce(array_agg(distinct sb.batch_code order by sb.batch_code),array[]::text[])
 into new.product_serials
 from public.stock_movements sm join public.stock_batches sb on sb.id=sm.batch_id
 where sm.reference_table='sales' and sm.reference_id=new.sale_id
 and sm.movement_type='sale_dispatch' and sm.product_variant_id=new.product_variant_id;
 return new;
end; $$;
drop trigger if exists tajir_sync_sale_item_serials on public.sale_items;
create trigger tajir_sync_sale_item_serials before insert or update of sale_id,product_variant_id
on public.sale_items for each row execute function public.tajir_sync_sale_item_serials();

create or replace function public.tajir_sync_customer_payment_serials()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.sale_id is not null then
  select coalesce(array_agg(distinct x.serial order by x.serial),array[]::text[])
  into new.product_serials
  from (select unnest(si.product_serials) as serial from public.sale_items si where si.sale_id=new.sale_id) x;
 end if;
 return new;
end; $$;
drop trigger if exists tajir_sync_customer_payment_serials on public.customer_payments;
create trigger tajir_sync_customer_payment_serials before insert or update of sale_id
on public.customer_payments for each row execute function public.tajir_sync_customer_payment_serials();
update public.customer_payments cp set product_serials=x.serials
from (select si.sale_id,array_agg(distinct u.serial order by u.serial) serials
      from public.sale_items si cross join lateral unnest(si.product_serials) as u(serial)
      group by si.sale_id) x
where cp.sale_id=x.sale_id and cp.product_serials is distinct from x.serials;

create or replace function public.tajir_sync_supplier_payment_serials()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.purchase_id is not null then
  select coalesce(array_agg(distinct sb.batch_code order by sb.batch_code),array[]::text[])
  into new.product_serials
  from public.stock_batches sb where sb.purchase_item_id in
   (select pi.id from public.purchase_items pi where pi.purchase_id=new.purchase_id);
 end if;
 return new;
end; $$;
drop trigger if exists tajir_sync_supplier_payment_serials on public.supplier_payments;
create trigger tajir_sync_supplier_payment_serials before insert or update of purchase_id
on public.supplier_payments for each row execute function public.tajir_sync_supplier_payment_serials();
update public.supplier_payments sp set product_serials=x.serials
from (select pi.purchase_id,array_agg(distinct sb.batch_code order by sb.batch_code) serials
      from public.stock_batches sb join public.purchase_items pi on pi.id=sb.purchase_item_id
      group by pi.purchase_id) x
where sp.purchase_id=x.purchase_id and sp.product_serials is distinct from x.serials;

create or replace function public.tajir_sync_expense_serials()
returns trigger language plpgsql set search_path='' as $$
begin
 if new.stock_batch_id is not null then
  select array[sb.batch_code] into new.product_serials from public.stock_batches sb where sb.id=new.stock_batch_id;
 elsif tg_op='UPDATE' and old.stock_batch_id is not null then
  new.product_serials:=array[]::text[];
 end if;
 return new;
end; $$;
drop trigger if exists tajir_sync_expense_serials on public.expenses;
create trigger tajir_sync_expense_serials before insert or update of stock_batch_id
on public.expenses for each row execute function public.tajir_sync_expense_serials();

create index if not exists purchase_items_product_serial_idx on public.purchase_items(product_serial);
create index if not exists sale_items_product_serials_gin_idx on public.sale_items using gin(product_serials);
create index if not exists customer_payments_product_serials_gin_idx on public.customer_payments using gin(product_serials);
create index if not exists supplier_payments_product_serials_gin_idx on public.supplier_payments using gin(product_serials);
create index if not exists expenses_product_serials_gin_idx on public.expenses using gin(product_serials);
