create or replace function public.tajir_director_contacts()
returns table(profile_id uuid,display_name text,phone text)
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
  select contacts.profile_id,contacts.display_name,contacts.phone
  from (
    select c.profile_id as profile_id,
           coalesce(nullif(btrim(p.display_name),''),c.display_name) as display_name,
           coalesce(nullif(btrim(p.phone),''),c.phone) as phone
    from public.tajir_director_contact_directory c
    left join public.profiles p on p.id=c.profile_id
    where c.is_active=true
      and (
        c.profile_id is null
        or (
          p.status='active'
          and exists(
            select 1 from public.user_role_assignments ura
            join public.app_roles ar on ar.id=ura.role_id
            where ura.user_id=c.profile_id and ura.is_active=true and ar.code='director'
          )
        )
      )
    union all
    select p.id as profile_id,p.display_name as display_name,p.phone as phone
    from public.user_role_assignments ura
    join public.app_roles ar on ar.id=ura.role_id
    join public.profiles p on p.id=ura.user_id
    where ura.is_active=true
      and ar.code='director'
      and p.status='active'
      and nullif(btrim(p.phone),'') is not null
      and not exists(
        select 1 from public.tajir_director_contact_directory c
        where c.is_active=true and (c.profile_id=p.id or c.phone=p.phone)
      )
  ) contacts
  order by contacts.display_name;
end;
$function$;

revoke all on function public.tajir_director_contacts() from public,anon,authenticated;
grant execute on function public.tajir_director_contacts() to authenticated;
