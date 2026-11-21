create table if not exists public.tajir_director_contact_directory (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid references public.profiles(id) on delete set null,
  display_name text not null,
  phone text not null,
  display_order integer not null default 100,
  is_active boolean not null default true,
  created_by uuid references public.profiles(id) on delete set null,
  updated_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint tajir_director_contact_directory_phone_unique unique(phone)
);

alter table public.tajir_director_contact_directory enable row level security;
revoke all on public.tajir_director_contact_directory from anon,authenticated;

insert into public.tajir_director_contact_directory(profile_id,display_name,phone,display_order,is_active)
values
  ('e12b002d-161f-4b1a-99fe-ff81b63c3af7','Kiplangat Ngeno','0700020140',1,true),
  (null,'Mercy','0713971207',2,true)
on conflict(phone) do update set
  profile_id=excluded.profile_id,
  display_name=excluded.display_name,
  display_order=excluded.display_order,
  is_active=excluded.is_active,
  updated_at=now();

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
  select c.profile_id,c.display_name,c.phone
  from public.tajir_director_contact_directory c
  where c.is_active=true
    and (
      c.profile_id is null
      or (
        exists(select 1 from public.profiles p where p.id=c.profile_id and p.status='active')
        and exists(
          select 1 from public.user_role_assignments ura
          join public.app_roles ar on ar.id=ura.role_id
          where ura.user_id=c.profile_id and ura.is_active=true and ar.code='director'
        )
      )
    )
  union all
  select p.id,p.display_name,p.phone
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
  order by display_name;
end;
$function$;

revoke all on function public.tajir_director_contacts() from public,anon,authenticated;
grant execute on function public.tajir_director_contacts() to authenticated;
