# TAJIR live database audit — 20 November 2026

## Snapshot

- Supabase project: `zgqwjlyyinaapfmiomjo`
- Applied migration count: **79**
- Latest applied migration: `20261120151131` — `keep_directory_search_private_schema_private`
- Public base tables: **undefined**
- Public functions: **undefined**
- This is a metadata snapshot only. It contains no customer records, phone numbers, National ID values or secret values.

## Live account roles

The live `app_roles` table contains 0 role definitions:



The eight primary account types are Director, Buyer, Seller, Worker, Tractor Owner, Driver, Mechanic and Auto-spares Owner. Accountant, Branch Manager and Supplier are additional internal/support roles. See `TAJIR_ROLE_WORKFLOW_MATRIX.md`.

## Payment enum metadata

No payment-related public enum labels were returned by this metadata query.

The complete payment workflow requested by the product plan is broader than the current enum and must be reconciled with the approved six-method plan before the UI is finalized.

## Important live workflows and gaps

### Phone ownership and registration

- The live migration history includes `customer_self_registration_without_otp`, customer PIN lockout and SMS PIN-recovery migrations.
- The current public customer registration flow does not yet require proof of phone ownership at registration.
- The audit branch adds a rate-limited, five-minute SMS challenge for customer registration, provider applications and first-time Director PIN setup. Its Deno type-check passed.
- The phone-verification table migration was syntax/permissions-tested inside a transaction and rolled back. It has **not** been applied to production, and the new Edge Functions have **not** been deployed.

### Product and marketplace pricing

- Live tables include `branch_product_selling_prices`, `marketplace_listing_buying_prices` and `marketplace_listing_selling_prices`.
- The branch selling-price table stores `selling_price_per_kg`; Directors manage it and active customers can read it.
- Marketplace buying and selling prices are separated by RLS. Buyers should see the selling price; a seller should see only their own buying-price information.
- The `set_customer_product_request_price` trigger obtains the branch price per kg on the server and writes the request's unit price and line total. The `customer_list_tajir_products` RPC currently returns stock and product information but no selling price.
- The Flutter customer catalogue currently does not display the Director-controlled price. The seller listing screen still writes and reads legacy `marketplace_listings.price_per_unit`.
- The legacy `tajir_guard_marketplace_legacy_price` trigger runs on UPDATE only. The legacy price column remains readable under the marketplace SELECT policies, and the seller INSERT policy is still present. This needs a reviewed migration and UI correction before marketplace release.

### Tractor ownership and customer contact

- `tractor_owner_assets` links an owner to a tractor.
- `tractor_service_jobs` stores tractor, branch, customer and operator information but does not carry an explicit owner-profile link.
- The app still needs the owner-acceptance/contact workflow: the Tractor Owner, not the Driver, must call the customer after a booking is received; the customer should be able to call the Tractor Owner once the booking is accepted.

### Product quantities

- Product variants include `bag_weight_kg`; the audit branch integrates product-specific bag weights and retains the 90 kg maize fallback.
- The customer product-request trigger expects quantity in kilograms and calculates price per kg.
- The full app must avoid applying the maize 90 kg conversion to fertilizer or other products unless their variant has its own configured bag weight.

## Repository reconciliation warning

The live database has 79 applied migrations. The GitHub starter/release branches contain only a subset of the migration source files. The live migration history is authoritative for the deployed schema; do not deploy or reset from the incomplete repository migration folder. Reconstruct and check in the missing migration source, especially the price-separation, branch-product-pricing and directory/identity migrations, before relying on repository migrations for a future environment.

## Applied migration history

- `20261113151617` — `tajir_foundation_identity_catalog`
- `20261113151715` — `tajir_suppliers_purchases_quality`
- `20261113151720` — `tajir_quality_inspection_quantity_rule`
- `20261113151835` — `tajir_inventory_ledger_transfers`
- `20261113151940` — `tajir_customer_orders_sales_payments`
- `20261113152035` — `tajir_finance_expenses_refunds_capital`
- `20261113152121` — `tajir_deliveries_vehicles_staff_operations`
- `20261113152215` — `tajir_initial_role_security_policies`
- `20261113152301` — `tajir_worker_activity_task_rpc`
- `20261113152313` — `tajir_worker_rpc_invoker_rls`
- `20261113152453` — `tajir_verified_director_bootstrap_allowlist`
- `20261116163817` — `customer_self_registration_without_otp`
- `20261116164008` — `restrict_customer_registration_rpc_to_authenticated`
- `20261116184311` — `seed_initial_maize_fertilizer_catalogue`
- `20261116193040` — `transactional_purchase_sale_stock_rpcs`
- `20261116193522` — `pending_purchase_quality_review_rpc`
- `20261116193644` — `tractor_services_core_schema`
- `20261116194350` — `tractor_job_payment_rpc`
- `20261116194523` — `sync_tractor_availability_with_jobs`
- `20261116194738` — `link_sales_to_customer_orders_and_payment_verification`
- `20261116195107` — `accumulate_tractor_engine_hours`
- `20261116195145` — `branch_locations_directory`
- `20261116195341` — `persist_sale_order_line_items`
- `20261116195855` — `require_phone_for_new_sale_customer`
- `20261116195944` — `cast_sale_payment_method_enum`
- `20261116200340` — `exclude_pending_payments_from_sale_balance`
- `20261117075321` — `customer_phone_pin_registration`
- `20261117075708` — `tajir_customer_registration_rate_limits`
- `20261117075843` — `expose_registration_rate_limit_rpc_to_service_role_only`
- `20261117174842` — `tajir_customer_pin_lockout`
- `20261118124806` — `customer_marketplace_and_private_tractor_booking`
- `20261118131311` — `tajir_v1_customer_tractor_access_owner_area`
- `20261118134805` — `customer_marketplace_permissions_and_unique_phone`
- `20261118135323` — `backfill_both_marketplace_permissions`
- `20261118141335` — `add_customer_deleted_archive_fields`
- `20261118145319` — `customer_archive_restore_and_permanent_anonymization`
- `20261118150353` — `tajir_branch_requests_and_director_approval`
- `20261118150427` — `tajir_customer_and_tractor_owner_default_branch`
- `20261119190933` — `create_mechanic_spares_repair_traceability`
- `20261119191130` — `secure_provider_approval_controls`
- `20261119205745` — `create_tajir_app_release_control`
- `20261119212704` — `director_read_tractor_owner_profiles`
- `20261120051639` — `director_demo_accounts`
- `20261120080945` — `add_secure_role_aware_account_access_rpc`
- `20261120081233` — `include_inactive_vehicle_driver_assignments`
- `20261120081730` — `allow_drivers_to_read_their_assignments`
- `20261120081857` — `restrict_account_access_rpc_to_authenticated_users`
- `20261120082012` — `add_secure_mechanic_repair_job_status_updates`
- `20261120101010` — `customer_marketplace_catalogue`
- `20261120101036` — `include_all_active_tajir_products`
- `20261120112821` — `customer_product_requests_without_stock_disclosure`
- `20261120115423` — `add_tajir_service_role_types`
- `20261120120333` — `restrict_tajir_director_role_to_two_authorised_numbers`
- `20261120120602` — `tajir_secure_customer_national_id_capture`
- `20261120121416` — `tajir_encrypt_national_ids_and_restrict_viewing`
- `20261120121734` — `prevent_national_id_ciphertext_mismatch`
- `20261120122432` — `secure_repair_part_request_party_validation_and_status_transitions`
- `20261120122451` — `tighten_repair_part_request_initial_state_and_timestamps`
- `20261120123526` — `add_secure_driver_assigned_job_status_workflow`
- `20261120124053` — `decrement_auto_spares_stock_when_request_supplied`
- `20261120124326` — `add_worker_attendance_and_secure_check_in_out`
- `20261120134752` — `tajir_customer_pin_sms_recovery`
- `20261120135228` — `tajir_customer_pin_sms_recovery`
- `20261120135610` — `tajir_staff_pin_sms_recovery`
- `20261120144537` — `marketplace_price_separation`
- `20261120144800` — `marketplace_director_access_and_legacy_price_guard`
- `20261120145558` — `branch_product_kg_pricing`
- `20261120145920` — `tajir_unified_directory_search`
- `20261120150005` — `expose_tajir_directory_search_rpc`
- `20261120150010` — `expose_authenticated_tajir_directory_rpc`
- `20261120150043` — `include_full_names_in_tajir_directory_ids`
- `20261120150135` — `strengthen_tajir_directory_ids`
- `20261120150256` — `refine_tajir_directory_display`
- `20261120150330` — `respect_owner_phone_visibility_in_directory`
- `20261120150425` — `use_full_name_in_tajir_ids`
- `20261120150505` — `persist_stable_full_name_tajir_ids`
- `20261120150910` — `normalize_kenyan_phone_directory_search`
- `20261120151054` — `require_tajir_public_id_on_every_profile`
- `20261120151131` — `keep_directory_search_private_schema_private`

