-- Give the Director oversight access to contacts connected to company tasks.
-- Ordinary accounts continue to receive only their own task-linked contacts.
create or replace function public.tajir_get_linked_contact_profiles()
returns table(profile_id uuid, display_name text, phone text, relationship text, reference text)
language plpgsql stable security definer set search_path = ''
as $function$
declare v_uid uuid := auth.uid(); v_is_director boolean := false;
begin
  if v_uid is null then raise exception 'Sign in to view linked contacts.'; end if;
  v_is_director := private.has_app_role('director'::text);
  return query
  with linked as (
    select case when c.profile_id=v_uid then j.operator_id else c.profile_id end as other_id,
           'Tractor service booking'::text as relation,j.job_number::text as ref
    from public.tractor_service_jobs j join public.customers c on c.id=j.customer_id
    where (c.profile_id=v_uid or j.operator_id=v_uid)
      and (case when c.profile_id=v_uid then j.operator_id else c.profile_id end) is not null
    union all
    select case when c.profile_id=v_uid then top.profile_id else c.profile_id end,
           'Tractor service / tractor owner',j.job_number::text
    from public.tractor_service_jobs j join public.customers c on c.id=j.customer_id
    join public.tractor_owner_assets toa on toa.tractor_id=j.tractor_id
    join public.tractor_owner_profiles top on top.id=toa.owner_id
    where (c.profile_id=v_uid or top.profile_id=v_uid)
      and (case when c.profile_id=v_uid then top.profile_id else c.profile_id end) is not null
    union all
    select case when j.operator_id=v_uid then top.profile_id else j.operator_id end,
           'Assigned tractor operator',j.job_number::text
    from public.tractor_service_jobs j join public.tractor_owner_assets toa on toa.tractor_id=j.tractor_id
    join public.tractor_owner_profiles top on top.id=toa.owner_id
    where j.operator_id is not null and (j.operator_id=v_uid or top.profile_id=v_uid)
      and (case when j.operator_id=v_uid then top.profile_id else j.operator_id end) is not null
    union all
    select case when j.owner_user_id=v_uid then m.profile_id else j.owner_user_id end,
           'Tractor repair job',j.job_number::text
    from public.tractor_repair_jobs j join public.mechanic_profiles m on m.id=j.mechanic_id
    where (j.owner_user_id=v_uid or m.profile_id=v_uid)
      and (case when j.owner_user_id=v_uid then m.profile_id else j.owner_user_id end) is not null
    union all
    select case when m.profile_id=v_uid then s.profile_id else m.profile_id end,
           'Repair parts request',r.id::text
    from public.repair_part_requests r join public.mechanic_profiles m on m.id=r.mechanic_id
    join public.auto_spares_profiles s on s.id=r.shop_id
    where (m.profile_id=v_uid or s.profile_id=v_uid)
      and (case when m.profile_id=v_uid then s.profile_id else m.profile_id end) is not null
    union all
    select case when c.profile_id=v_uid then d.assigned_driver_id else c.profile_id end,
           'Delivery assignment',d.delivery_number::text
    from public.deliveries d join public.sales_orders so on so.id=d.order_id
    join public.customers c on c.id=so.customer_id
    where (c.profile_id=v_uid or d.assigned_driver_id=v_uid)
      and (case when c.profile_id=v_uid then d.assigned_driver_id else c.profile_id end) is not null
    union all
    select case when buyer.profile_id=v_uid then seller.profile_id else buyer.profile_id end,
           'Marketplace purchase request',pr.id::text
    from public.marketplace_purchase_requests pr join public.customers buyer on buyer.id=pr.buyer_customer_id
    join public.marketplace_listings l on l.id=pr.listing_id join public.customers seller on seller.id=l.seller_customer_id
    where (buyer.profile_id=v_uid or seller.profile_id=v_uid)
      and (case when buyer.profile_id=v_uid then seller.profile_id else buyer.profile_id end) is not null
  ),
  director_linked as (
    select c.profile_id as other_id,'Director oversight • tractor service client'::text as relation,j.job_number::text as ref
    from public.tractor_service_jobs j join public.customers c on c.id=j.customer_id where v_is_director
    union all
    select j.operator_id,'Director oversight • assigned driver',j.job_number::text
    from public.tractor_service_jobs j where v_is_director and j.operator_id is not null
    union all
    select top.profile_id,'Director oversight • tractor owner',j.job_number::text
    from public.tractor_service_jobs j join public.tractor_owner_assets toa on toa.tractor_id=j.tractor_id
    join public.tractor_owner_profiles top on top.id=toa.owner_id where v_is_director
    union all
    select j.owner_user_id,'Director oversight • tractor owner repair',j.job_number::text
    from public.tractor_repair_jobs j where v_is_director and j.owner_user_id is not null
    union all
    select m.profile_id,'Director oversight • mechanic',j.job_number::text
    from public.tractor_repair_jobs j join public.mechanic_profiles m on m.id=j.mechanic_id where v_is_director
    union all
    select m.profile_id,'Director oversight • parts-request mechanic',r.id::text
    from public.repair_part_requests r join public.mechanic_profiles m on m.id=r.mechanic_id where v_is_director
    union all
    select s.profile_id,'Director oversight • auto-spares supplier',r.id::text
    from public.repair_part_requests r join public.auto_spares_profiles s on s.id=r.shop_id where v_is_director
    union all
    select c.profile_id,'Director oversight • delivery customer',d.delivery_number::text
    from public.deliveries d join public.sales_orders so on so.id=d.order_id
    join public.customers c on c.id=so.customer_id where v_is_director
    union all
    select d.assigned_driver_id,'Director oversight • delivery driver',d.delivery_number::text
    from public.deliveries d where v_is_director and d.assigned_driver_id is not null
    union all
    select buyer.profile_id,'Director oversight • marketplace buyer',pr.id::text
    from public.marketplace_purchase_requests pr join public.customers buyer on buyer.id=pr.buyer_customer_id where v_is_director
    union all
    select seller.profile_id,'Director oversight • marketplace seller',pr.id::text
    from public.marketplace_purchase_requests pr join public.marketplace_listings l on l.id=pr.listing_id
    join public.customers seller on seller.id=l.seller_customer_id where v_is_director
  ),
  all_linked as (select * from linked union all select * from director_linked)
  select distinct p.id,p.display_name,p.phone,all_linked.relation,all_linked.ref
  from all_linked join public.profiles p on p.id=all_linked.other_id
  where p.id<>v_uid and p.status::text='active' and coalesce(trim(p.phone),'')<>''
  order by p.display_name,all_linked.relation,all_linked.ref;
end;
$function$;
