drop trigger if exists tajir_audit_changes on public.suppliers;
create trigger tajir_audit_changes after insert or update or delete on public.suppliers for each row execute function public.tajir_audit_row_change();
