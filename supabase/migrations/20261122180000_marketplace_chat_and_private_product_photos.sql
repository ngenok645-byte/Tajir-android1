-- Interactive TAJIR marketplace chat with private product-photo sharing.
create table if not exists public.marketplace_chat_threads (
 id uuid primary key default gen_random_uuid(),
 listing_id uuid not null references public.marketplace_listings(id) on delete cascade,
 buyer_customer_id uuid not null references public.customers(id) on delete cascade,
 seller_customer_id uuid not null references public.customers(id) on delete cascade,
 created_at timestamptz not null default now(),
 last_message_at timestamptz not null default now(),
 constraint marketplace_chat_one_buyer_per_listing unique(listing_id,buyer_customer_id),
 constraint marketplace_chat_distinct_parties check (buyer_customer_id <> seller_customer_id)
);
create table if not exists public.marketplace_chat_messages (
 id uuid primary key default gen_random_uuid(),
 thread_id uuid not null references public.marketplace_chat_threads(id) on delete cascade,
 sender_user_id uuid not null references auth.users(id) on delete cascade,
 body text,
 image_path text,
 created_at timestamptz not null default now(),
 constraint marketplace_chat_message_has_content check (
   nullif(btrim(body),'') is not null or image_path is not null
 )
);
create index if not exists marketplace_chat_messages_thread_created_idx on public.marketplace_chat_messages(thread_id,created_at);
create index if not exists marketplace_chat_threads_last_message_idx on public.marketplace_chat_threads(last_message_at desc);
alter table public.marketplace_chat_threads enable row level security;
alter table public.marketplace_chat_messages enable row level security;
drop policy if exists marketplace_chat_threads_read on public.marketplace_chat_threads;
create policy marketplace_chat_threads_read on public.marketplace_chat_threads for select to authenticated using (
 private.is_director() or exists(select 1 from public.customers c where c.id in (buyer_customer_id,seller_customer_id) and c.profile_id=auth.uid() and c.active=true and c.deleted_at is null)
);
drop policy if exists marketplace_chat_threads_create on public.marketplace_chat_threads;
create policy marketplace_chat_threads_create on public.marketplace_chat_threads for insert to authenticated with check (
 buyer_customer_id in (select c.id from public.customers c where c.profile_id=auth.uid() and c.active=true and c.deleted_at is null and c.marketplace_can_buy=true)
 and exists(select 1 from public.marketplace_listings l where l.id=listing_id and l.seller_customer_id=seller_customer_id and l.status='active')
 and buyer_customer_id<>seller_customer_id
);
drop policy if exists marketplace_chat_messages_read on public.marketplace_chat_messages;
create policy marketplace_chat_messages_read on public.marketplace_chat_messages for select to authenticated using (
 private.is_director() or exists(select 1 from public.marketplace_chat_threads t join public.customers c on c.id in (t.buyer_customer_id,t.seller_customer_id) where t.id=thread_id and c.profile_id=auth.uid() and c.active=true and c.deleted_at is null)
);
drop policy if exists marketplace_chat_messages_send on public.marketplace_chat_messages;
create policy marketplace_chat_messages_send on public.marketplace_chat_messages for insert to authenticated with check (
 sender_user_id=auth.uid() and (private.is_director() or exists(select 1 from public.marketplace_chat_threads t join public.customers c on c.id in (t.buyer_customer_id,t.seller_customer_id) where t.id=thread_id and c.profile_id=auth.uid() and c.active=true and c.deleted_at is null))
);
create or replace function public.tajir_block_marketplace_phone_numbers()
returns trigger language plpgsql set search_path='' as $$
begin
 if coalesce(new.body,'') ~* '(^|[^0-9])(?:\\+?254|0)?[ -]?(?:7|1)[0-9 -]{7,12}($|[^0-9])' then
  raise exception 'Phone numbers cannot be shared in marketplace chat. Use TAJIR chat instead.' using errcode='22023';
 end if;
 return new;
end; $$;
drop trigger if exists tajir_block_marketplace_phone_numbers on public.marketplace_chat_messages;
create trigger tajir_block_marketplace_phone_numbers before insert or update of body on public.marketplace_chat_messages for each row execute function public.tajir_block_marketplace_phone_numbers();
insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values('tajir-marketplace-chat','tajir-marketplace-chat',false,5242880,array['image/jpeg','image/png','image/webp'])
on conflict(id) do update set public=false,file_size_limit=5242880,allowed_mime_types=array['image/jpeg','image/png','image/webp'];
drop policy if exists tajir_marketplace_chat_image_read on storage.objects;
create policy tajir_marketplace_chat_image_read on storage.objects for select to authenticated using (
 bucket_id='tajir-marketplace-chat' and (private.is_director() or exists(
 select 1 from public.marketplace_chat_threads t join public.customers c on c.id in (t.buyer_customer_id,t.seller_customer_id)
 where t.id=(storage.foldername(name))[1]::uuid and c.profile_id=auth.uid() and c.active=true and c.deleted_at is null))
);
drop policy if exists tajir_marketplace_chat_image_upload on storage.objects;
create policy tajir_marketplace_chat_image_upload on storage.objects for insert to authenticated with check (
 bucket_id='tajir-marketplace-chat' and (private.is_director() or exists(
 select 1 from public.marketplace_chat_threads t join public.customers c on c.id in (t.buyer_customer_id,t.seller_customer_id)
 where t.id=(storage.foldername(name))[1]::uuid and c.profile_id=auth.uid() and c.active=true and c.deleted_at is null))
);
