alter table public.customer_custom_product_requests
 add column if not exists customer_confirmed_at timestamptz;

create or replace function public.audit_customer_custom_product_request_review()
returns trigger language plpgsql security definer set search_path=''
as $$
begin
 if not (select private.is_director()) then
  if auth.uid() is not null
   and new.customer_id=old.customer_id
   and new.status=old.status
   and new.agreed_unit_price_kes is not distinct from old.agreed_unit_price_kes
   and new.proposed_unit_price_kes=old.proposed_unit_price_kes
   and new.product_name=old.product_name
   and new.description is not distinct from old.description
   and new.quantity=old.quantity
   and new.quantity_unit=old.quantity_unit
   and new.request_direction=old.request_direction
   and new.director_response is not distinct from old.director_response
   and new.reviewed_by is not distinct from old.reviewed_by
   and new.reviewed_at is not distinct from old.reviewed_at
   and old.customer_confirmed_at is null
   and new.customer_confirmed_at is not null
   and exists(select 1 from public.customers c where c.id=old.customer_id and c.profile_id=auth.uid() and c.active=true)
  then new.updated_at:=now(); return new; end if;
  raise exception 'Only an authorised Director can review a custom product request.';
 end if;
 if new.status not in ('pending','under_review','approved','rejected','negotiation') then raise exception 'Invalid custom product request status.'; end if;
 if new.status in ('approved','negotiation') and (new.agreed_unit_price_kes is null or new.agreed_unit_price_kes<=0) then raise exception 'An approved or negotiated request requires a positive agreed unit price.'; end if;
 new.reviewed_by:=auth.uid(); new.reviewed_at:=now(); new.updated_at:=now();
 insert into public.customer_custom_product_request_reviews(request_id,actor_user_id,old_status,new_status,old_agreed_price_kes,new_agreed_price_kes,director_response)
 values(old.id,auth.uid(),old.status,new.status,old.agreed_unit_price_kes,new.agreed_unit_price_kes,new.director_response);
 return new;
end;
$$;
create or replace function public.customer_confirm_custom_product_request(p_request_id uuid)
returns void language plpgsql security definer set search_path=''
as $$
begin
 update public.customer_custom_product_requests r set customer_confirmed_at=now()
 where r.id=p_request_id and r.status='approved' and r.customer_confirmed_at is null
 and exists(select 1 from public.customers c where c.id=r.customer_id and c.profile_id=auth.uid() and c.active=true);
 if not found then raise exception 'This request is not approved, is already confirmed, or does not belong to your account.'; end if;
end;
$$;
revoke all on function public.customer_confirm_custom_product_request(uuid) from public,anon;
grant execute on function public.customer_confirm_custom_product_request(uuid) to authenticated;
