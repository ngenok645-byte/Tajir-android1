-- Server-verified tractor booking: select the applicable service/location rate,
-- calculate the charge, and persist the exact rate and quantity snapshot.
create or replace function public.customer_book_tractor_service_priced(
 p_tractor_id uuid default null,p_service_type text default null,p_service_location text default null,
 p_county text default null,p_region text default null,p_village text default null,
 p_quantity numeric default null,p_pricing_unit text default null,
 p_booked_for timestamptz default null,p_notes text default null
) returns table(job_id uuid,job_number text,unit_rate numeric,pricing_unit text,total_charge numeric)
language plpgsql security definer set search_path=''
as $$
declare v_customer public.customers%rowtype;v_tractor public.tractor_assets%rowtype;
 v_branch_id uuid;v_job_number text;v_job_id uuid;v_status text;v_rate public.tractor_service_rates%rowtype;v_total numeric(14,2);
begin
 select c.* into v_customer from public.customers c join public.profiles p on p.id=c.profile_id
 where c.profile_id=auth.uid() and c.active=true and p.status::text='active'
 and c.customer_type in ('buyer','seller','both') for update of c;
 if v_customer.id is null then raise exception 'An active customer account is required.'; end if;
 if p_service_type not in ('ploughing','harrowing','planting','transport','other') then raise exception 'Select a valid service.'; end if;
 if length(trim(coalesce(p_service_location,'')))<3 then raise exception 'Enter the farm location.'; end if;
 if p_quantity is null or p_quantity<=0 then raise exception 'Enter a valid service quantity.'; end if;
 if p_booked_for is not null and p_booked_for<now() then raise exception 'Choose a future booking date.'; end if;
 select r.* into v_rate from public.tractor_service_rates r where r.is_active and r.service_type=p_service_type
 and (r.county is null or lower(trim(r.county))=lower(trim(coalesce(p_county,''))))
 and (r.region is null or lower(trim(r.region))=lower(trim(coalesce(p_region,''))))
 and (r.village is null or lower(trim(r.village))=lower(trim(coalesce(p_village,''))))
 and (p_service_type<>'transport' or r.pricing_unit=p_pricing_unit)
 order by (case when r.village is not null then 4 else 0 end+case when r.region is not null then 2 else 0 end+case when r.county is not null then 1 else 0 end) desc,r.updated_at desc limit 1;
 if v_rate.id is null then raise exception 'No Director-approved rate is configured for this service and location yet.'; end if;
 if p_pricing_unit is not null and p_pricing_unit<>v_rate.pricing_unit then raise exception 'Selected pricing unit does not match the approved rate.'; end if;
 if p_service_type<>'transport' and v_rate.pricing_unit<>'per_acre' then raise exception 'This service must be priced per acre.'; end if;
 v_total:=round(v_rate.rate*p_quantity,2);v_branch_id:=v_customer.default_branch_id;
 if v_branch_id is null or not exists(select 1 from public.branches b where b.id=v_branch_id and b.is_active=true) then select b.id into v_branch_id from public.branches b where b.is_active=true order by b.name limit 1; end if;
 if v_branch_id is null then raise exception 'TAJIR is temporarily unable to route this request. Please contact the Director.'; end if;
 if p_tractor_id is null then v_status:='awaiting_director_assignment';
 else
  select t.* into v_tractor from public.tractor_assets t join public.branches b on b.id=t.branch_id and b.is_active=true
  where t.id=p_tractor_id and t.status='available' and t.branch_id=v_branch_id for update of t;
  if v_tractor.id is null then v_status:='awaiting_director_assignment'; else v_status:='booked'; end if;
 end if;
 v_job_number:='TR-'||to_char(now(),'YYMMDDHH24MISS')||'-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,6));
 insert into public.tractor_service_jobs(job_number,branch_id,tractor_id,customer_id,farmer_name,farmer_phone,service_type,service_location,area_acres,booked_for,estimated_hours,rate,total_charge,status,notes,recorded_by,pricing_unit,pricing_quantity,rate_id,county,region,village)
 values(v_job_number,v_branch_id,case when v_status='booked' then v_tractor.id else null end,v_customer.id,v_customer.full_name,v_customer.phone,p_service_type,trim(p_service_location),case when v_rate.pricing_unit='per_acre' then p_quantity else null end,p_booked_for,1,v_rate.rate,v_total,v_status,nullif(trim(coalesce(p_notes,'')),''),auth.uid(),v_rate.pricing_unit,p_quantity,v_rate.id,nullif(trim(coalesce(p_county,'')),''),nullif(trim(coalesce(p_region,'')),''),nullif(trim(coalesce(p_village,'')),''))
 returning id into v_job_id;
 return query select v_job_id,v_job_number,v_rate.rate,v_rate.pricing_unit,v_total;
end; $$;
revoke all on function public.customer_book_tractor_service_priced(uuid,text,text,text,text,text,numeric,text,timestamptz,text) from public;
grant execute on function public.customer_book_tractor_service_priced(uuid,text,text,text,text,text,numeric,text,timestamptz,text) to authenticated;
