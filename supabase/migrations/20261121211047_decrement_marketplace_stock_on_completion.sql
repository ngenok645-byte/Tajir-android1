create or replace function public.set_marketplace_purchase_request_price()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_listing public.marketplace_listings%rowtype;
  v_price numeric(14,2);
  v_reserved numeric(14,3);
begin
  if tg_op = 'INSERT' then
    select * into v_listing
    from public.marketplace_listings
    where id = new.listing_id and status = 'active'
    for update;

    if not found then
      raise exception 'This marketplace listing is no longer available.';
    end if;

    if new.quantity is null or new.quantity <= 0 then
      raise exception 'Requested quantity must be greater than zero.';
    end if;

    select coalesce(sum(r.quantity), 0)
      into v_reserved
    from public.marketplace_purchase_requests r
    where r.listing_id = new.listing_id
      and r.status in ('pending','accepted');

    if v_reserved + new.quantity > v_listing.quantity then
      raise exception 'Requested quantity exceeds the remaining available quantity.';
    end if;

    select p.selling_price_kes into v_price
    from public.marketplace_listing_selling_prices p
    where p.listing_id = new.listing_id;

    if v_price is null or v_price <= 0 then
      raise exception 'The TAJIR Director has not set an official selling price for this listing.';
    end if;

    new.unit_price_kes := v_price;
    new.line_total_kes := round(new.quantity * v_price, 2);
    new.updated_at := now();
    return new;
  end if;

  if new.listing_id is distinct from old.listing_id
     or new.buyer_customer_id is distinct from old.buyer_customer_id
     or new.quantity is distinct from old.quantity
     or new.unit_price_kes is distinct from old.unit_price_kes
     or new.line_total_kes is distinct from old.line_total_kes
     or new.created_at is distinct from old.created_at then
    raise exception 'Marketplace request quantity and official price are locked after submission.';
  end if;

  if old.status = 'pending' and new.status not in ('pending','accepted','declined') then
    raise exception 'A pending request can only be accepted or declined.';
  elsif old.status = 'accepted' and new.status not in ('accepted','completed') then
    raise exception 'An accepted request can only be completed.';
  elsif old.status in ('declined','completed') and new.status is distinct from old.status then
    raise exception 'This marketplace request is already closed.';
  end if;

  if old.status = 'accepted' and new.status = 'completed' then
    update public.marketplace_listings l
    set quantity = l.quantity - new.quantity,
        status = case when l.quantity - new.quantity <= 0 then 'sold' else l.status end,
        updated_at = now()
    where l.id = new.listing_id
      and l.quantity >= new.quantity;

    if not found then
      raise exception 'The listing no longer has enough quantity to complete this sale.';
    end if;
  end if;

  new.updated_at := now();
  return new;
end;
$function$;

revoke all on function public.set_marketplace_purchase_request_price() from public, anon, authenticated;
