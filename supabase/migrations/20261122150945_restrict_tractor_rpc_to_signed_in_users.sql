-- These RPCs are intended for signed-in customers or Directors, never anonymous clients.
revoke execute on function public.customer_quote_tractor_service(text,text,text,text,numeric,text) from public, anon;
grant execute on function public.customer_quote_tractor_service(text,text,text,text,numeric,text) to authenticated;
revoke execute on function public.customer_book_tractor_service_priced(uuid,text,text,text,text,text,numeric,text,timestamptz,text) from public, anon;
grant execute on function public.customer_book_tractor_service_priced(uuid,text,text,text,text,text,numeric,text,timestamptz,text) to authenticated;
revoke execute on function public.director_assign_tractor_to_service_job(uuid,uuid) from public, anon;
grant execute on function public.director_assign_tractor_to_service_job(uuid,uuid) to authenticated;
