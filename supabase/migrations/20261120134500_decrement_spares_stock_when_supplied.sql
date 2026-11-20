create or replace function public.decrement_spare_inventory_when_supplied()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if old.status = 'accepted' and new.status = 'supplied' then
    update public.auto_spares_inventory
       set quantity = quantity - new.quantity,
           status = case
             when quantity - new.quantity <= 0 then 'out_of_stock'
             else status
           end,
           updated_at = now()
     where id = new.inventory_id
       and shop_id = new.shop_id
       and quantity >= new.quantity;

    if not found then
      raise exception 'Not enough stock is available to supply this parts request.';
    end if;
  end if;
  return new;
end;
$$;

revoke all on function public.decrement_spare_inventory_when_supplied() from public, anon, authenticated;

drop trigger if exists trg_decrement_spare_inventory_when_supplied on public.repair_part_requests;
create trigger trg_decrement_spare_inventory_when_supplied
after update of status on public.repair_part_requests
for each row execute function public.decrement_spare_inventory_when_supplied();
