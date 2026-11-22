alter table public.notifications
  add column if not exists sender_user_id uuid references auth.users(id) on delete set null;

create or replace function public.set_notification_sender()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.sender_user_id is null then
    new.sender_user_id := auth.uid();
  end if;
  return new;
end;
$$;

drop trigger if exists notifications_set_sender on public.notifications;
create trigger notifications_set_sender
before insert on public.notifications
for each row execute function public.set_notification_sender();

create table if not exists public.notification_replies (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.notifications(id) on delete cascade,
  sender_user_id uuid not null references auth.users(id) on delete cascade,
  recipient_user_id uuid not null references auth.users(id) on delete cascade,
  message text not null check (char_length(trim(message)) between 1 and 3000),
  created_at timestamptz not null default now(),
  constraint notification_reply_distinct_participants check (sender_user_id <> recipient_user_id)
);

create index if not exists notification_replies_thread_created_idx
  on public.notification_replies(notification_id, created_at);

alter table public.notification_replies enable row level security;

drop policy if exists notification_replies_participant_read on public.notification_replies;
create policy notification_replies_participant_read
on public.notification_replies for select to authenticated
using ((select auth.uid()) = sender_user_id or (select auth.uid()) = recipient_user_id);

drop policy if exists notification_replies_participant_insert on public.notification_replies;
create policy notification_replies_participant_insert
on public.notification_replies for insert to authenticated
with check (
  sender_user_id = (select auth.uid())
  and exists (
    select 1 from public.notifications n
    where n.id = notification_id
      and (
        (n.sender_user_id = (select auth.uid()) and n.recipient_user_id = recipient_user_id)
        or
        (n.recipient_user_id = (select auth.uid()) and n.sender_user_id = recipient_user_id)
      )
  )
);

grant select, insert on public.notification_replies to authenticated;
