-- Expose only active Director contact details to authenticated TAJIR dashboards.
-- Other profile phone numbers remain protected by the existing profile RLS policies.
create or replace function public.tajir_director_contacts()
returns table (
  profile_id uuid,
  display_name text,
  phone text
)
language plpgsql
stable
security definer
set search_path = ''
as $function$
begin
  if auth.uid() is null then
    raise exception 'An authenticated TAJIR account is required.'
      using errcode = '42501';
  end if;

  return query
  select p.id, p.display_name, p.phone
  from public.user_role_assignments ura
  join public.app_roles ar on ar.id = ura.role_id
  join public.profiles p on p.id = ura.user_id
  where ura.is_active = true
    and ar.code = 'director'
    and p.status = 'active'
    and nullif(btrim(p.phone), '') is not null
  order by p.display_name;
end;
$function$;

revoke all on function public.tajir_director_contacts() from public, anon;
grant execute on function public.tajir_director_contacts() to authenticated;
