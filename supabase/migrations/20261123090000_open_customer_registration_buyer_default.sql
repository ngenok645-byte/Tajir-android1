-- Open customer registration: users choose buyer or seller; only Directors grant both.
alter table public.customers
  alter column active set default true,
  alter column marketplace_can_buy set default true,
  alter column marketplace_can_sell set default false;

-- Activate only pending/non-suspended customer accounts; preserve deliberately suspended,
-- disabled, archived, and permanently anonymized accounts.
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
   and p.status is distinct from 'suspended'::public.account_status
   and p.status is distinct from 'disabled'::public.account_status;

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
  'Buyer access is selected at registration or granted by an authorised Director.';
comment on column public.customers.marketplace_can_sell is
  'Seller access is selected at registration or granted by an authorised Director; only a Director may grant both.';
