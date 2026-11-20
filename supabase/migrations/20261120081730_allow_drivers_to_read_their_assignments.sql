alter table public.vehicles enable row level security;
alter table public.tractor_service_jobs enable row level security;

drop policy if exists driver_read_assigned_vehicles on public.vehicles;
create policy driver_read_assigned_vehicles
on public.vehicles
for select
to authenticated
using (driver_id = (select auth.uid()));

drop policy if exists driver_read_assigned_service_jobs on public.tractor_service_jobs;
create policy driver_read_assigned_service_jobs
on public.tractor_service_jobs
for select
to authenticated
using (operator_id = (select auth.uid()));
