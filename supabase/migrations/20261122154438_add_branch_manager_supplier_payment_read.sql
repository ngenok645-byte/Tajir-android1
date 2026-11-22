drop policy if exists manager_read_supplier_payments on public.supplier_payments;
create policy manager_read_supplier_payments on public.supplier_payments for select to authenticated using (private.has_app_role('branch_manager') and private.has_branch_access(branch_id));
drop policy if exists manager_read_suppliers on public.suppliers;
create policy manager_read_suppliers on public.suppliers for select to authenticated using (private.has_app_role('branch_manager'));