-- Retain the linked Auth profile while a customer is archived so a Director can safely restore access.
-- Permanent deletion anonymizes the customer row instead of deleting it, because sales,
-- orders, payments and other financial records reference customers.id.
alter table public.customers
  add column if not exists archived_profile_id uuid,
  add column if not exists permanently_deleted_at timestamptz,
  add column if not exists permanently_deleted_by uuid references auth.users(id) on delete set null;

comment on column public.customers.archived_profile_id is
  'Original auth profile id retained only to allow director-approved restore from archive; cleared on permanent anonymization.';
comment on column public.customers.permanently_deleted_at is
  'Timestamp when customer personal data and login were permanently removed; customer row remains as a financial-history tombstone.';
