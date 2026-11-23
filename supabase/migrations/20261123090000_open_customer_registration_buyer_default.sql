-- Open customer self-registration: buyer access is automatic; seller access remains Director-controlled.
alter table public.customers
  alter column active set default true,
  alter column marketplace_can_buy set default true,
  alter column marketplace_can_sell set default false;

-- Release existing pending customer accounts without reviving accounts deliberately suspended
-- by a Director or accounts that have been archived/permanently anonymized.
update public.customers c
   set active = true,
       marketplace_can_buy = true,
       customer_type = case
         when c.marketplace_can_sell then 'both'::public.customer_type
         else 'buyer'::public.customer_type
       end
  from public.profiles p
 where p.id = c.profile_id
   and c.deleted_at is null
   and c.permanently_deleted_at is null
   and p.status is distinct from 'suspended';

update public.profiles p
   set status = 'active',
       updated_at = now()
 where p.status = 'pending'
   and exists (
     select 1
       from public.customers c
      where c.profile_id = p.id
        and c.active = true
        and c.deleted_at is null
        and c.permanently_deleted_at is null
   );

comment on column public.customers.marketplace_can_buy is
  'Buyer access is granted automatically at customer registration; Directors may manage access.';
comment on column public.customers.marketplace_can_sell is
  'Seller access is granted only by an authorised Director; true enables both buyer and seller access.';
