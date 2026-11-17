create table if not exists private.tajir_registration_rate_limits (
  bucket_key text primary key,
  window_started_at timestamptz not null,
  attempts integer not null default 0
);
create or replace function private.consume_tajir_registration_attempt(p_phone text, p_ip text)
returns boolean language plpgsql security definer set search_path = ''
as $function$
declare v_phone_attempts integer; v_ip_attempts integer; v_now timestamptz := now();
begin
 insert into private.tajir_registration_rate_limits(bucket_key,window_started_at,attempts)
 values ('phone:'||md5(coalesce(p_phone,'')),v_now,1)
 on conflict(bucket_key) do update set
 attempts=case when private.tajir_registration_rate_limits.window_started_at < v_now-interval '1 day' then 1 else private.tajir_registration_rate_limits.attempts+1 end,
 window_started_at=case when private.tajir_registration_rate_limits.window_started_at < v_now-interval '1 day' then v_now else private.tajir_registration_rate_limits.window_started_at end
 returning attempts into v_phone_attempts;
 insert into private.tajir_registration_rate_limits(bucket_key,window_started_at,attempts)
 values ('ip:'||md5(coalesce(p_ip,'')),v_now,1)
 on conflict(bucket_key) do update set
 attempts=case when private.tajir_registration_rate_limits.window_started_at < v_now-interval '1 hour' then 1 else private.tajir_registration_rate_limits.attempts+1 end,
 window_started_at=case when private.tajir_registration_rate_limits.window_started_at < v_now-interval '1 hour' then v_now else private.tajir_registration_rate_limits.window_started_at end
 returning attempts into v_ip_attempts;
 return v_phone_attempts<=3 and v_ip_attempts<=20;
end;
$function$;
revoke all on function private.consume_tajir_registration_attempt(text,text) from public, anon, authenticated;
grant execute on function private.consume_tajir_registration_attempt(text,text) to service_role;
