create or replace function public.staff_get_branch_sale_price(
  p_branch_id uuid,
  p_product_variant_id uuid
)
returns numeric
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_price numeric;
begin
  if auth.uid() is null
     or not exists(select 1 from public.profiles p where p.id=auth.uid() and p.status='active') then
    raise exception 'Active staff sign-in required.';
  end if;

  if not (
    private.has_app_role('director')
    or private.has_app_role('branch_manager')
    or private.has_app_role('seller')
  ) then
    raise exception 'Not authorised to view branch sale prices.';
  end if;

  if not private.has_branch_access(p_branch_id) then
    raise exception 'Branch access denied.';
  end if;

  select bp.selling_price_per_kg into v_price
  from public.branch_product_selling_prices bp
  where bp.branch_id=p_branch_id
    and bp.product_variant_id=p_product_variant_id;

  return v_price;
end;
$function$;

revoke all on function public.staff_get_branch_sale_price(uuid,uuid) from public,anon,authenticated;
grant execute on function public.staff_get_branch_sale_price(uuid,uuid) to authenticated;
