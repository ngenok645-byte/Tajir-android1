-- Preserve whether an unlisted-product request is a customer BUY request
-- or an offer to SELL produce to TAJIR. The proposed price remains non-official.
alter table public.customer_custom_product_requests
  add column if not exists request_direction text not null default 'BUY_FROM_TAJIR';
alter table public.customer_custom_product_requests
  drop constraint if exists customer_custom_product_requests_direction_check;
alter table public.customer_custom_product_requests
  add constraint customer_custom_product_requests_direction_check
  check (request_direction in ('BUY_FROM_TAJIR','SELL_TO_TAJIR'));

comment on column public.customer_custom_product_requests.request_direction is
  'Customer request direction. Proposed price is indicative only and is not an official TAJIR price.';
