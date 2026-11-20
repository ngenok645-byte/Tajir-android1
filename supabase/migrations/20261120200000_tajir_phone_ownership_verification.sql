-- One-time proof of control for Kenyan phone numbers before account creation.
begin;

create table if not exists public.tajir_phone_verifications (
  id uuid primary key,
  phone_e164 text not null check (phone_e164 ~ '^\+254[17][0-9]{8}$'),
  purpose text not null check (purpose in ('customer_registration', 'provider_registration', 'director_setup')),
  code_hash text not null,
  attempts smallint not null default 0 check (attempts between 0 and 6),
  request_ip_hash text,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null,
  verified_at timestamptz,
  consumed_at timestamptz,
  constraint tajir_phone_verifications_expiry_after_creation
    check (expires_at > created_at)
);

create index if not exists tajir_phone_verifications_phone_purpose_created_idx
  on public.tajir_phone_verifications (phone_e164, purpose, created_at desc);

create index if not exists tajir_phone_verifications_ip_created_idx
  on public.tajir_phone_verifications (request_ip_hash, created_at desc)
  where request_ip_hash is not null;

alter table public.tajir_phone_verifications enable row level security;
revoke all on table public.tajir_phone_verifications from public, anon, authenticated;
grant select, insert, update, delete on table public.tajir_phone_verifications to service_role;

comment on table public.tajir_phone_verifications is
  'Private one-time phone ownership challenges. Service role only; codes are stored as keyed hashes and expire quickly.';

commit;
