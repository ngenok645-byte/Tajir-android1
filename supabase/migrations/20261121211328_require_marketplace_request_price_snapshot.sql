alter table public.marketplace_purchase_requests
  alter column unit_price_kes set not null,
  alter column line_total_kes set not null;

alter table public.marketplace_purchase_requests
  add constraint marketplace_purchase_requests_price_positive
  check (unit_price_kes > 0 and line_total_kes >= 0);
