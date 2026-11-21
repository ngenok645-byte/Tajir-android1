create table if not exists public.customer_custom_product_request_reviews (
 id uuid primary key default gen_random_uuid(),
 request_id uuid not null references public.customer_custom_product_requests(id) on delete cascade,
 actor_user_id uuid not null references auth.users(id),
 old_status text,
 new_status text not null,
 old_agreed_price_kes numeric(14,2),
 new_agreed_price_kes numeric(14,2),
 director_response text,
 created_at timestamptz not null default now()
);
alter table public.customer_custom_product_request_reviews enable row level security;
drop policy if exists custom_request_review_director_read on public.customer_custom_product_request_reviews;
create policy custom_request_review_director_read on public.customer_custom_product_request_reviews
 for select to authenticated using ((select private.is_director()));
revoke all on public.customer_custom_product_request_reviews from public, anon;
grant select on public.customer_custom_product_request_reviews to authenticated;

create or replace function public.audit_customer_custom_product_request_review()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if not (select private.is_director()) then
  raise exception 'Only an authorised Director can review a custom product request.';
 end if;
 if new.status not in ('pending','under_review','approved','rejected','negotiation') then
  raise exception 'Invalid custom product request status.';
 end if;
 if new.status in ('approved','negotiation') and (new.agreed_unit_price_kes is null or new.agreed_unit_price_kes<=0) then
  raise exception 'An approved or negotiated request requires a positive agreed unit price.';
 end if;
 new.reviewed_by:=auth.uid();
 new.reviewed_at:=now();
 new.updated_at:=now();
 insert into public.customer_custom_product_request_reviews(
  request_id,actor_user_id,old_status,new_status,old_agreed_price_kes,new_agreed_price_kes,director_response
 ) values (
  old.id,auth.uid(),old.status,new.status,old.agreed_unit_price_kes,new.agreed_unit_price_kes,new.director_response
 );
 return new;
end;
$$;
drop trigger if exists trg_audit_customer_custom_product_request_review on public.customer_custom_product_requests;
create trigger trg_audit_customer_custom_product_request_review
 before update on public.customer_custom_product_requests
 for each row execute function public.audit_customer_custom_product_request_review();
