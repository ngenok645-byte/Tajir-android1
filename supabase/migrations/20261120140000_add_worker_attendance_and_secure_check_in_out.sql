create table if not exists public.staff_attendance (
  id uuid primary key default extensions.gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  branch_id uuid not null references public.branches(id),
  check_in_at timestamptz not null default now(),
  check_out_at timestamptz,
  created_at timestamptz not null default now(),
  constraint staff_attendance_checkout_after_checkin
    check (check_out_at is null or check_out_at >= check_in_at)
);

create unique index if not exists staff_attendance_one_open_shift_per_user
  on public.staff_attendance(user_id)
  where check_out_at is null;

alter table public.staff_attendance enable row level security;
revoke all on public.staff_attendance from anon, authenticated;
grant select on public.staff_attendance to authenticated;

drop policy if exists staff_attendance_read_own_or_manager on public.staff_attendance;
create policy staff_attendance_read_own_or_manager
on public.staff_attendance
for select to authenticated
using (
  user_id = (select auth.uid())
  or private.is_director()
  or (private.has_app_role('branch_manager') and private.has_branch_access(branch_id))
);

create or replace function public.staff_check_in(p_branch_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_id uuid;
begin
  if v_user is null or not private.has_app_role('worker') then
    raise exception 'Only an authorised worker can record staff attendance.';
  end if;
  if not exists (
    select 1 from public.user_branch_assignments uba
    join public.branches b on b.id = uba.branch_id
    where uba.user_id = v_user
      and uba.branch_id = p_branch_id
      and uba.ended_at is null
      and b.is_active = true
  ) then
    raise exception 'You are not assigned to this active branch.';
  end if;

  insert into public.staff_attendance(user_id, branch_id)
  values (v_user, p_branch_id)
  returning id into v_id;
  return v_id;
exception
  when unique_violation then
    raise exception 'You already have an active attendance session. Check out before starting another.';
end;
$$;

create or replace function public.staff_check_out()
returns timestamptz
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := auth.uid();
  v_time timestamptz;
begin
  if v_user is null or not private.has_app_role('worker') then
    raise exception 'Only an authorised worker can record staff attendance.';
  end if;

  update public.staff_attendance
     set check_out_at = now()
   where user_id = v_user
     and check_out_at is null
  returning check_out_at into v_time;

  if v_time is null then
    raise exception 'There is no active check-in to close.';
  end if;
  return v_time;
end;
$$;

revoke all on function public.staff_check_in(uuid) from public, anon;
revoke all on function public.staff_check_out() from public, anon;
grant execute on function public.staff_check_in(uuid) to authenticated;
grant execute on function public.staff_check_out() to authenticated;
