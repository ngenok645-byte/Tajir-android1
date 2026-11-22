-- Adds explicit route-distance results to the existing GPS land-measurement records.
-- Existing records remain area measurements through the default value.
alter table public.land_measurements
  add column if not exists measurement_type text not null default 'area',
  add column if not exists distance_m double precision not null default 0,
  add column if not exists distance_km double precision not null default 0;

alter table public.land_measurements
  drop constraint if exists land_measurements_measurement_type_check;
alter table public.land_measurements
  add constraint land_measurements_measurement_type_check
  check (measurement_type in ('area','distance'));

comment on column public.land_measurements.measurement_type is 'area records a closed farm boundary; distance records an open GPS route.';
comment on column public.land_measurements.distance_m is 'Sum of consecutive GPS segment distances in metres; route is not closed.';
comment on column public.land_measurements.distance_km is 'Sum of consecutive GPS segment distances in kilometres.';
