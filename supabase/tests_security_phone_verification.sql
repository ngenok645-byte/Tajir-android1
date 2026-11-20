-- Run after 20261120200000_tajir_phone_ownership_verification.sql.
do $$
begin
  if not exists (
    select 1 from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public'
      and c.relname = 'tajir_phone_verifications'
      and c.relrowsecurity
  ) then
    raise exception 'Phone verification table must have RLS enabled';
  end if;

  if exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'tajir_phone_verifications'
  ) then
    raise exception 'Phone verification table must not expose client policies';
  end if;

  if has_table_privilege('anon', 'public.tajir_phone_verifications', 'select')
     or has_table_privilege('authenticated', 'public.tajir_phone_verifications', 'select') then
    raise exception 'Anonymous/authenticated roles must not read phone verification challenges';
  end if;

  if not has_table_privilege('service_role', 'public.tajir_phone_verifications', 'select')
     or not has_table_privilege('service_role', 'public.tajir_phone_verifications', 'insert')
     or not has_table_privilege('service_role', 'public.tajir_phone_verifications', 'update') then
    raise exception 'Service role must be able to manage phone verification challenges';
  end if;
end
$$;
