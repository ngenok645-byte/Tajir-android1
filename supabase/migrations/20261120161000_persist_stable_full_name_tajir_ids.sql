-- Give each profile a stable, human-readable TAJIR ID containing its registered name.
alter table public.profiles add column if not exists tajir_id text;

update public.profiles p
set tajir_id = 'TJ-' ||
  upper(trim(both '-' from regexp_replace(trim(coalesce(
    nullif(c.full_name,''),nullif(tp.full_name,''),nullif(mp.business_name,''),
    nullif(ap.shop_name,''),nullif(p.display_name,''),'USER'
  )),'[^A-Za-z0-9]+','-','g'))) ||
  '-' || upper(substr(replace(p.id::text,'-',''),1,12))
from (select id from public.profiles) x
left join public.customers c on c.profile_id=x.id
left join public.tractor_owner_profiles tp on tp.profile_id=x.id
left join public.mechanic_profiles mp on mp.profile_id=x.id
left join public.auto_spares_profiles ap on ap.profile_id=x.id
where p.id=x.id and p.tajir_id is null;

create unique index if not exists profiles_tajir_id_uidx on public.profiles(tajir_id);
alter table public.profiles alter column tajir_id set not null;

create or replace function private.assign_tajir_public_id()
returns trigger language plpgsql set search_path=pg_catalog,public
as $$
begin
 if new.tajir_id is null or btrim(new.tajir_id)='' then
  new.tajir_id := 'TJ-' ||
   upper(trim(both '-' from regexp_replace(trim(coalesce(nullif(new.display_name,''),'USER')),'[^A-Za-z0-9]+','-','g'))) ||
   '-' || upper(substr(replace(new.id::text,'-',''),1,12));
 end if;
 return new;
end;
$$;

drop trigger if exists profiles_assign_tajir_public_id on public.profiles;
create trigger profiles_assign_tajir_public_id
before insert or update of display_name on public.profiles
for each row execute function private.assign_tajir_public_id();

create or replace function private.tajir_directory_search(p_query text)
returns table (account_id uuid, tajir_id text, display_name text, account_type text, account_status text, phone_masked text)
language plpgsql security definer set search_path=pg_catalog,public,private
as $$
declare
 v_uid uuid:=auth.uid();
 v_q text:=upper(regexp_replace(coalesce(p_query,''),'[^A-Za-z0-9]','','g'));
 v_digits text:=regexp_replace(coalesce(p_query,''),'[^0-9]','','g');
 v_director boolean;
 v_allowed boolean;
begin
 if v_uid is null then raise exception 'Sign in is required to search the TAJIR directory.'; end if;
 if length(v_q)<4 then raise exception 'Enter at least 4 characters of a phone number or TAJIR ID.'; end if;
 select private.is_director() into v_director;
 select exists(select 1 from public.user_role_assignments ura join public.app_roles ar on ar.id=ura.role_id
   where ura.user_id=v_uid and ura.is_active and ar.code in ('director','branch_manager','accountant','worker','supplier','tractor_owner','driver','mechanic','auto_spares_owner')) into v_allowed;
 if not coalesce(v_allowed,false) then raise exception 'Your account is not authorised to search the TAJIR directory.'; end if;
 return query
 with role_names as (
  select ura.user_id,string_agg(distinct ar.name,', ' order by ar.name) role_name
  from public.user_role_assignments ura join public.app_roles ar on ar.id=ura.role_id
  where ura.is_active group by ura.user_id
 ), directory_rows as (
  select p.id,p.tajir_id,
   coalesce(nullif(c.full_name,''),nullif(tp.full_name,''),nullif(mp.business_name,''),nullif(ap.shop_name,''),nullif(p.display_name,''),'Unnamed account') nm,
   case when c.id is not null then coalesce(nullif(concat_ws(' / ',case when c.marketplace_can_buy then 'Buyer' end,case when c.marketplace_can_sell then 'Seller' end),''),c.customer_type::text)
    else coalesce(r.role_name,'Registered account') end typ,
   case when c.id is not null and c.deleted_at is not null then 'Archived'
    when c.id is not null and not c.active then 'Inactive' else coalesce(p.status::text,'Unknown') end stat,
   coalesce(nullif(p.phone,''),nullif(c.phone,''),nullif(tp.phone,''),nullif(mp.phone,''),nullif(ap.phone,'')) ph
  from public.profiles p
  left join public.customers c on c.profile_id=p.id
  left join public.tractor_owner_profiles tp on tp.profile_id=p.id
  left join public.mechanic_profiles mp on mp.profile_id=p.id
  left join public.auto_spares_profiles ap on ap.profile_id=p.id
  left join role_names r on r.user_id=p.id
  where c.permanently_deleted_at is null or c.id is null
 )
 select d.id,d.tajir_id,d.nm,coalesce(nullif(d.typ,''),'Registered account'),d.stat,
  case when v_director then coalesce(d.ph,'Not provided') when d.ph is null then 'Not provided'
   else '••••••'||right(regexp_replace(d.ph,'[^0-9]','','g'),3) end
 from directory_rows d
 where regexp_replace(upper(coalesce(d.tajir_id,'')),'[^A-Za-z0-9]','','g')=v_q
  or (v_digits<>'' and regexp_replace(coalesce(d.ph,''),'[^0-9]','','g') like '%'||v_digits)
 order by d.nm limit 50;
end; $$;

create or replace function public.tajir_directory_search(p_query text)
returns table (account_id uuid, tajir_id text, display_name text, account_type text, account_status text, phone_masked text)
language sql security definer set search_path=pg_catalog,public,private
as $$ select * from private.tajir_directory_search(p_query); $$;
revoke all on function private.tajir_directory_search(text) from public,anon;
grant usage on schema private to authenticated;
grant execute on function private.tajir_directory_search(text) to authenticated;
revoke all on function public.tajir_directory_search(text) from public,anon;
grant execute on function public.tajir_directory_search(text) to authenticated;
