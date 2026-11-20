revoke all on function public.get_my_account_access() from public;
revoke all on function public.get_my_account_access() from anon;
grant execute on function public.get_my_account_access() to authenticated;
