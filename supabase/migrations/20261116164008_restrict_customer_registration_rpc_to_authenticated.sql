revoke all on function public.register_customer_account(text, text) from public, anon;
grant execute on function public.register_customer_account(text, text) to authenticated;
revoke all on function public.get_my_account_status() from public, anon;
grant execute on function public.get_my_account_status() to authenticated;