create table if not exists public.tajir_staff_pin_resets (
 id uuid primary key default gen_random_uuid(),
 profile_id uuid not null references public.profiles(id) on delete cascade,
 phone_e164 text not null,
 code_hash text not null,
 expires_at timestamptz not null,
 attempts integer not null default 0 check (attempts >= 0 and attempts <= 6),
 consumed_at timestamptz,
 created_at timestamptz not null default now()
);
create index if not exists tajir_staff_pin_resets_profile_created_idx
 on public.tajir_staff_pin_resets(profile_id, created_at desc);
alter table public.tajir_staff_pin_resets enable row level security;
revoke all on public.tajir_staff_pin_resets from anon, authenticated;
grant all on public.tajir_staff_pin_resets to service_role;