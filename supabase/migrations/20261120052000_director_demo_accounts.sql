create table if not exists public.tajir_demo_accounts (
  id uuid primary key default gen_random_uuid(),
  role_code text not null check (role_code in ('buyer','seller','worker','tractor_owner','driver','mechanic','auto_spares_owner')),
  display_name text not null check (length(trim(display_name)) between 2 and 80),
  demo_data jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id) on delete cascade,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists tajir_demo_accounts_created_by_role_idx
  on public.tajir_demo_accounts (created_by, role_code, created_at desc);
alter table public.tajir_demo_accounts enable row level security;
drop policy if exists tajir_demo_accounts_director_all on public.tajir_demo_accounts;
create policy tajir_demo_accounts_director_all
on public.tajir_demo_accounts
for all
to authenticated
using (private.has_app_role('director'))
with check (private.has_app_role('director') and created_by = auth.uid());
grant select, insert, update, delete on public.tajir_demo_accounts to authenticated;
