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

The Flutter source still contains a global `kgPerBag = 90.0` constant. The live database also has a `branch_product_kg_pricing` migration. The 90 kg maize bag is an agreed example and must remain supported, but product/branch-specific bag weights must be read from configuration rather than assuming every product and branch uses 90 kg.

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
- runs `flutter analyze --no-fatal-infos --no-fatal-warnings` (the run reported 208 analyzer info-level findings);
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
- [ ] Phone ownership verification implemented and tested.
- [ ] Provider functions deployed and tested.
- [ ] Tractor-owner booking lifecycle implemented end-to-end.
- [ ] Six-option accounting and all workbook cost fields implemented.
- [ ] All live migrations reconciled to source control.
- [ ] Signed release and real-device upgrade tested.

**Do not publish the audit-baseline APK as the final production release until the unchecked release blockers are resolved.**
