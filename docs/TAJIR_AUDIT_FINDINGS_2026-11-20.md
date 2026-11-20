# TAJIR audit findings and implementation backlog

**Audit date:** 20 November 2026  
**Baseline:** `ngenok645-byte/Tajir-android1`, branch `tajir-master-integration`, commit `1e97422478bbc48b1386ef42e0c357781ae0d441`  
**Purpose:** Preserve existing work and corrections while closing verified gaps before a production release. This is an audit record, not a claim that the listed fixes are complete.

## Confirmed working baseline

- The integration branch is 25 commits ahead of `main` and includes the KG price calculation, product icons, update checks, director contacts, inactivity logout, role-oriented sign-in, customer buyer/seller registration, provider registration UI, provider review UI, and the master integration plan.
- GitHub Actions run #499 completed successfully. The APK artifact was uploaded. This verifies Flutter analysis/build execution and artifact creation only; it is not an end-to-end or device acceptance test.
- The integration branch contains a ten-minute inactivity timeout. Brief app switching, such as answering a call, is intentionally allowed without immediate sign-out.
- The app's role chooser includes team accounts, tractor owner, driver, mechanic, auto-spares provider, and customer/trader entry. Customer registration distinguishes buyer and seller. Driver accounts are described as created/linked by the owner or Director.
- The eight-role regression baseline is Director, Buyer, Seller, Worker, Tractor Owner, Driver, Mechanic and Auto-spares Owner. The live database additionally defines Accountant, Branch Manager and Supplier as supporting roles.

## Verified release blockers

### 1. Phone ownership is not verified at initial registration

The live `tajir-customer-register` Edge Function creates a customer account from a submitted Kenyan phone number and PIN without first proving control of that number by SMS. The provider-registration function in the integration branch follows the same pattern. Duplicate-number checks prevent a second account for a number already in use, but they do not prove that the first registrant owns an unregistered number.

**Required correction**
- Add SMS one-time verification before customer or provider account creation.
- Bind verification to the normalized E.164 phone number, purpose, short expiry and one-time challenge.
- Rate-limit requests and verification attempts; store only a secure code hash.
- Consume a successful challenge atomically during registration so it cannot be replayed.
- Keep recovery codes separate from registration verification.
- Do not create a login session or account until phone verification succeeds.

**Implementation started in the isolated audit branch** `tajir-audit-hardening-20261120`:
- Added a service-role-only, RLS-protected phone challenge table migration.
- Added a rate-limited SMS request/verify Edge Function with five-minute expiry, one-time challenge consumption, keyed code hashes and attempt limits.
- Added verified-phone requirements to the customer and provider registration endpoints and Director PIN setup endpoint.
- Added SMS verification steps to customer, provider and first-time Director setup screens.
- Added a SQL permissions/RLS regression check and Deno type-check steps to the branch workflow.

These changes are source-only at this stage. They have **not** been deployed to the live Supabase project, and they are not considered complete until the migration and Edge Functions pass a staging test, including expired, incorrect, replayed and wrong-phone challenge cases.

### 2. Provider functions are in GitHub but not deployed to live Supabase

The integration branch contains `tajir-provider-register` and `tajir-provider-review`. They were not present in the live project's active Edge Function list at audit time. The APK built from this branch can therefore display the provider application flow, but the live registration/review actions will fail until secure, tested functions are deployed.

**Required correction**
- Add phone verification and security tests to the provider registration endpoint before deployment.
- Test Director-only approval/rejection and role assignment against a staging database.
- Verify the different persisted approval states: tractor-owner profile approval uses `verified`; mechanic and auto-spares profiles use `approved`.
- Deploy only after the client, function and database changes are tested together.

### 3. Tractor booking is not yet a complete owner-to-client marketplace lifecycle

The live `customer_list_tractor_services()` RPC returns only a tractor ID and generic selection label. `customer_book_tractor_service()` creates a branch-linked `tractor_service_jobs` row in `booked` status, but does not link the job to a tractor-owner profile/user. `customer_list_tractor_bookings()` does not return an owner contact. The tractor-owner workspace currently loads owner assets and repair jobs, but not the customer's tractor service bookings. The driver workflow is separate and updates assigned jobs.

**Required correction**
- Link every bookable tractor to its verified owner (or explicitly identify it as a TAJIR/company fleet asset).
- Deliver a new booking to the responsible tractor owner's dashboard.
- Add server-validated owner accept, decline and quote/confirmation transitions.
- After the owner accepts, expose the owner's verified contact to that customer and show a one-tap call action.
- Keep the driver as the assigned operator, not the customer-facing owner contact. Expose driver contact only where the job relationship permits it.
- Notify the owner on new requests and the customer on acceptance, schedule/price changes and completion.
- Keep the existing company-fleet branch workflow working separately.

### 4. Database migration history is incomplete in source control

The live Supabase project reports 78 applied migration versions. The integration branch currently contains 17 migration files. The repository therefore cannot reproduce the full live schema from its checked-in migrations alone.

**Required correction**
- Reconcile every live migration version with a checked-in source file or a documented baseline snapshot.
- Record any intentionally unavailable historical SQL and generate a reviewed schema baseline from the live project.
- Verify migration order, function definitions, RLS policies, grants, triggers and enum values.
- Test forward migration and rollback/restore strategy on staging before production changes.
- Never reset or overwrite production data to make repository history appear consistent.

### 5. Payment model does not yet support all six agreed payment options

The live `payment_method` enum currently contains only `mpesa`, `cash`, `bank_transfer` and `other`. The agreed six options are Cash, M-Pesa, Bank transfer, Credit, Split payment and Other/manual.

**Required correction**
- Support the six user-facing payment choices without treating credit or split as ordinary tender types.
- Store split payments as multiple linked payment entries against one invoice/order.
- Store credit as an approved outstanding balance/credit obligation, not as money received.
- Keep payment status, payer/receiver, date, branch, references, verification and audit trail on each actual payment entry.
- Do not count pending or manually recorded but unverified funds as verified receipts.
- Require Director/authorised credit approval and enforce the agreed stock-release/payment rule server-side.
- Reconcile partial payments and outstanding balances without duplicate posting.

### 6. Maize and fertilizer trading cost fields are incomplete in the app

The saved workbooks define additional fields not present as explicit fields in the current purchase form.

**Maize fields to preserve**
- Date, quantity, buying price, Broka, Bag Price, transport, labour, drying expense, loading, Hema, payer (Edu/Mercy), total cost and profit.
- Treat Bag Price as the selling price per bag, not as a cost. Correct calculation:  
  `total cost = buying amount + Broka + transport + labour + drying + loading + Hema`  
  `sales revenue = quantity in bags × Bag Price`  
  `profit = sales revenue − total cost`
- Do not add Bag Price to total cost or subtract costs twice.

**Fertilizer fields to preserve**
- Date, quantity, buying price, voucher price, transport 1, transport 2, loading, payer (Edu/Mercy), selling price, food/accommodation, total cost and profit.
- Correct calculation:  
  `total cost = buying amount + voucher + transport 1 + transport 2 + loading + food/accommodation`  
  `profit = recorded selling revenue − total cost`

Use itemised cost records linked to the purchase/batch and preserve the payer field. Reconcile these transaction-level records with the stock/FIFO ledger so expenses are included exactly once.

### 7. Kilogram and bag conversion must use product/branch configuration

The original Flutter source contained a global `kgPerBag = 90.0` constant. The audit branch now carries the later product-specific conversion fix: maize retains a 90 kg fallback, while product variants can provide their own `bag_weight_kg`. The live database also has a `branch_product_kg_pricing` migration. The remaining work is to verify every product/branch path and ensure no legacy stock/report screen still assumes 90 kg.

**Required correction**
- Use configured bag weight and effective dates for purchase, sale, stock, transfer, marketplace, reports and history.
- Preserve original entered unit/quantity and the normalized ledger quantity.
- Test 90 kg = 1 maize bag, partial bags, decimal quantities, per-kg pricing, and non-maize product settings.

### 8. Director contacts are embedded in the Flutter client

The integration plan and source review identify hardcoded director phone contacts. The required contacts are currently displayed on the dashboards, but changing a number requires an app release.

**Required correction**
- Move active Director/support contacts into a Director-managed company settings/contact record.
- Keep the contacts visible on every dashboard as requested.
- Use validated phone numbers and a dialler action; audit who changes the contact details.

### 9. Build success is not full release acceptance

Run #499 completed successfully and uploaded an APK. Its workflow:
- extracts the Flutter project from `TAJIR_flutter_app.zip`, then overwrites the app entry point with root `main.dart`;
- runs `flutter analyze --no-fatal-infos --no-fatal-warnings` (the older run reported 208 info-level findings; audit run #44832442624 reported 13 warnings, 199 informational findings and zero analyzer errors);
- disables Android `lintVital` tasks because of a toolchain issue;
- builds a release-mode APK and uploads it;
- publishes a GitHub release only when manually dispatched on `main` with the explicit publish input enabled.

The workflow does not run a TAJIR-specific automated test suite. The supplied release-signing bundle is not wired into this workflow, so production signing identity and upgrade compatibility have not been verified.

**Required correction**
- Establish one canonical, version-controlled Flutter project tree; do not let a ZIP archive silently replace source files.
- Add unit, widget, RPC contract, permission and end-to-end workflow tests.
- Resolve or explicitly track analyzer findings; restore meaningful Android lint checks when the toolchain permits.
- Configure release signing through protected CI secrets without committing keystores or passwords.
- Verify package ID, signing certificate, version code, fresh install and upgrade from the current installed APK.
- Keep update checking, version publication and Android's user-confirmed installation flow accurate. Do not claim silent installation.

## Additional findings from the full project review

### Verified audit-branch build

CI run `44832442624` completed successfully:
- Deno type-check passed for phone verification, customer registration, provider registration and Director setup Edge Functions.
- Flutter analysis reported **0 errors, 13 warnings and 199 informational findings**.
- Android APK build passed.
- Package/launcher verification passed: `com.tajir.tajir_app` and `TAJIR`.
- APK v2 signature verification passed.

The artifact is **test-only**, not a production update, because protected signing secrets are not configured. Do not distribute it as the final release.

### Android signing continuity

The saved project APK `TAJIR.apk` uses the same package ID as the new build. The package ID is therefore not the update blocker. However, the saved APK, earlier CI APK and the only available new release keystore have different signing certificates. The original private signing key used for the saved APK was not found in the project files. Android will reject an update signed by a different key.

If the original key cannot be recovered, the first stable release signed with the new protected key will require a one-time uninstall/reinstall. Supabase-backed accounts and records remain server-side; unsynced local-only data could be lost. The workflow now uses these protected GitHub Actions secrets when configured: `TAJIR_KEYSTORE_BASE64`, `TAJIR_KEYSTORE_PASSWORD`, `TAJIR_KEY_ALIAS` and `TAJIR_KEY_PASSWORD`. Without them, builds remain test-only and production publishing is blocked.

### Live schema and workflow gaps confirmed

- The live database has **79 applied migrations, 74 public base tables and 42 public functions**. The repository contains only a subset of the applied migration sources.
- The live price-separation tables are now integrated in the audit branch: customers see Director-controlled branch prices per kg and bag equivalent; buyers browse priced seller listings; sellers see their own private buying price; and Directors have a price-management screen.
- The seller form no longer accepts a public price and writes only a zero legacy placeholder. The new migration `20261121120000_marketplace_director_price_guard_and_request_snapshot.sql` forces the legacy field to zero and snapshots request prices server-side. It is syntax-tested but not deployed.
- Until that migration is applied, the live legacy price column and INSERT path remain a release blocker.
- The customer product-request trigger calculates price server-side from the branch price per kg. Keep this as the source of truth.
- The live payment-method enum has four labels; the product plan calls for six payment workflows. Split payments and credit balances must be modelled without pretending they are additional tender types.
- The new migration `20261121130000_tractor_owner_booking_contact_workflow.sql` links service jobs to verified owners and adds owner accept/decline, quotes, contact logging and scoped booking RPCs. The audit-branch app now has the owner booking inbox, owner-to-customer call action and customer-to-owner call button after acceptance. The migration is syntax-tested but not deployed.
- The live owner profile status is `verified`, not `approved`; the earlier app guard would have blocked verified owners. The audit branch now accepts the live status.
- Driver invitation and owner-to-driver assignment remain to be implemented; the Driver still must not receive the customer-contact role.
- The full National ID migration for all roles is preserved in source control, but the corresponding registration UI and Vault-key checks remain pending.
- The PWA is a local-storage prototype, not the secure production app. Its maize profit formula also needs correction before reuse.

### Unresolved maize field

The meaning of the maize `Bag Price` spreadsheet field is not confirmed. It must be identified as either a selling/revenue price or a packaging/bag expense before profit calculations are finalized. Do not count it as both revenue and cost.

## Security advisory items to review

Supabase Security Advisor reported:
- RLS-enabled PIN/recovery tables with no client policies (expected to remain inaccessible directly; verify grants and service-role-only access).
- Multiple publicly or authenticated-callable SECURITY DEFINER functions. Review each function's grants, auth checks, fixed search path and input validation; do not revoke legitimate application RPCs blindly.
- Leaked-password protection disabled in Supabase Auth.

Resolve findings by inspecting the actual function/table permissions and testing both allowed and denied access. A linter warning alone is not proof of an exploitable vulnerability.

## Implementation order

1. Phone ownership verification and role-safe registration/login.
2. Canonical migration/schema reconciliation and deployable Edge Function source.
3. Complete tractor-owner booking/acceptance/contact/driver lifecycle.
4. Maize/fertilizer cost fields and reconciled six-option payment accounting.
5. Product/branch-specific unit conversion and director-managed contact settings.
6. CI test suite, production signing, update/upgrade verification and real-device acceptance.

## Release status at audit time

- [x] Integration branch identified and isolated from `main`.
- [x] Successful CI build #499 located; APK artifact downloaded and SHA-256 checked.
- [x] Live role catalog, migration history, payment enum, key RPCs, relevant RLS policies and active Edge Functions inspected.
- [x] Phone ownership verification code, migration, registration UI and security-check source added to isolated audit branch.
- [x] Product-specific bag-weight conversion code integrated; maize retains the 90 kg fallback.
- [x] Updated master plan and regression checklist with Director-controlled KG/bag pricing requirements.
- [x] Full encrypted National ID migration for all roles preserved in source control; client/provider UI integration and Vault-key checks remain pending.
- [x] Phone ownership verification Edge Functions pass Deno type-check; Flutter app builds successfully in CI.
- [ ] Phone verification staging end-to-end tests passed.
- [ ] Phone verification migration and Edge Functions deployed to live Supabase.
- [ ] Provider functions deployed and tested.
- [ ] Tractor-owner booking lifecycle implemented end-to-end.
- [ ] Six-option accounting and all workbook cost fields implemented.
- [ ] All live migrations reconciled to source control.
- [ ] Original APK signing key recovered or one-time reinstall approved; protected production-signing secrets configured.
- [ ] Production-signed release and real-device upgrade tested.

**Do not publish the audit-baseline APK as the final production release until the unchecked release blockers are resolved.**
