-- Trigger functions are invoked by PostgreSQL triggers, not by client RPC calls.
-- Revoke Data API execution from all client roles while preserving trigger execution.
revoke execute on function public.audit_customer_custom_product_request_review() from public, anon, authenticated;
revoke execute on function public.set_customer_product_request_price() from public, anon, authenticated;
revoke execute on function public.ensure_pending_customer_record() from public, anon, authenticated;
revoke execute on function public.tajir_default_customer_registration_access() from public, anon, authenticated;
revoke execute on function public.tajir_prevent_duplicate_customer_phone() from public, anon, authenticated;
