# TAJIR Master Application Integration Plan

## Purpose

Integrate the existing TAJIR Android application and the agreed business requirements into one professional, reliable, accessible application. Preserve verified working functionality and production data. Do not replace the current application or merge untested changes into `main`.

This document is a delivery and acceptance plan, not a claim that the features below have already been implemented.

## Product structure

TAJIR is one application with two connected business pillars:

1. **TAJIR Trading** — head office, branches, branch managers and owners, suppliers, customers, purchasing, receiving, stock, transfers, sales, dispatch, payments, expenses, reconciliation and reporting.
2. **TAJIR Farming Services** — clients, tractor owners, drivers, mechanics, workers, tractor/service listings, job requests, assignment, service delivery, maintenance, attendance, payments and history.

Both pillars share identity, company governance, contact directory, notifications, audit history, settings and reporting where appropriate. Access is role- and branch-scoped.

## Product experience and visual standard

- Create a consistent TAJIR design system: typography, spacing, colour, icon style, cards, forms, buttons, empty states, loading states and error states.
- Professional, modern, uncluttered screens with strong visual hierarchy and responsive layouts for common Android phones.
- Clear icons and short labels on every navigation tab and key action; icons must remain visible in all themes and states.
- Role-specific dashboards with useful summaries and clear primary actions; avoid presenting every role with the same crowded dashboard.
- Farmer-friendly flows: large touch targets, picture-led choices, plain language, one task at a time, visible progress and confirmation before consequential actions.
- English and Kiswahili are the recommended initial language set; keep translation architecture ready for additional Kenyan languages. Confirm final launch-language scope before release.
- Optional voice assistance: user-initiated microphone, Kiswahili speech input and spoken guidance where device/platform support permits. Voice is never compulsory. Financial, booking, dispatch and other consequential actions require on-screen confirmation. Provide a non-voice route for every task.
- Design for low bandwidth and intermittent connectivity. Clearly label cached/pending/synced data; queue only safe, idempotent actions; never imply an offline payment or stock change is confirmed before server acknowledgement.
- Accessibility: readable contrast, scalable text, clear focus and touch targets, helpful validation and no reliance on colour alone.

## Dashboard-by-dashboard visual specification

Use a shared TAJIR visual language, but give each role a dashboard designed around its real daily tasks. Pictures are purposeful visual guides, not decoration that slows the app or hides information. Prefer optimised local illustrations/icons for core navigation and compressed, cached photos for optional feature cards; show a graceful placeholder when an image is unavailable or the device is offline.

- **Director:** company overview with clear branch, trading and service summaries; visual cards for approvals, financial oversight, staff/accounts, reports and alerts. Use an agricultural business/warehouse hero image sparingly. Sensitive controls remain clearly separated and permission-checked.
- **Client:** welcoming service and product discovery with clear pictures of tractors, ploughing, planting and available goods; prominent Request a Tractor, Track My Job, Shop Products, Orders/Receipts and Contact actions.
- **Tractor owner:** tractor/equipment imagery and status cards for machines, availability, incoming requests, assigned drivers, active jobs, maintenance and earnings. Make the owner-to-client contact action prominent after a job is awarded.
- **Tractor driver:** simple, high-contrast job screen with tractor/field visual cue, today's assigned job, location/details, call owner/client where authorised, start job and complete job actions. Avoid complex charts and unrelated financial/admin controls.
- **Mechanic:** machinery and spare-part imagery with repair queue, assigned work, fault details, parts used, service history and job completion actions.
- **Worker:** friendly task/field illustrations, today's duties, branch, large check-in/check-out controls and attendance history. Keep the screen focused on assigned work.
- **Auto-spares provider:** clear product-category pictures/icons and inventory cards for parts, stock levels, requests, sales and order fulfilment; support search and readable part names/quantities.

Every role dashboard must have: a clear welcome/identity area; one obvious primary action; consistent labelled navigation with a visible icon on every tab; large touch targets; readable status labels; helpful empty/loading/error/offline states; and a persistent route to approved support/director contacts. Do not show a dashboard card or shortcut unless its action is implemented and the user's role is authorised to use it.

Image and icon acceptance checks: verify every role on a small Android screen and a larger screen; verify all tabs and item categories have meaningful icons; verify pictures load/cached and have offline placeholders; verify text contrast and scaling; verify no image is stretched, misleading, or blocks task completion. Avoid external image downloads for essential workflow controls.

## Shared identity, roles and governance

- Review and preserve the existing account model where safe; establish a single documented source of truth for authentication and profile/role mapping.
- Support the established user types, including directors, branch managers, branch owners, customers/buyers, suppliers, tractor owners, drivers, mechanics, workers and auto-spares providers as applicable to existing schema.
- A user sees only their own data and authorised branch/company records. Enforce all permissions on the server with RLS/RPC/Edge Functions; hiding UI controls is not security.
- Director oversight is authorised, read-only by default, scoped and audited. Do not implement silent impersonation or expose PINs/secrets.
- Directors can inspect authorised account records and create clearly marked demo accounts for previews; demo activity must be isolated from production.
- Use registered contact details for calls. Manage director contacts through authorised company records rather than hardcoding phone numbers in the application.
- Self-service PIN recovery must verify control of the registered phone, be rate-limited and avoid revealing whether a number is registered.
- Session expiry/background locking must protect users without unexpectedly destroying sessions during normal app switching. Test and document the chosen behaviour.
- Audit sensitive actions, approvals, corrections, reversals, access to protected identity information and administrative operations.

## TAJIR Trading requirements

### Company, branches and governance
- One TAJIR company with head office and multiple branches; branch stock and financial records remain separately attributable.
- Each branch has assigned management and ownership arrangements approved by directors.
- Branch profit-sharing is defined by a recorded, director-approved agreement per branch. Percentages, expense deductions, loss allocation and distribution schedules are not assumed by the app.
- Directors set pricing rules, budgets, purchasing limits, approval thresholds and exception rules. Branch managers operate within those limits.

### Products, units and stock
- Configurable product catalogue and categories, including cereals, pulses, fertilizers, seeds, crop-protection products, animal feeds and other approved agricultural goods.
- Directors can add, edit, activate and deactivate products/categories without a new app release.
- Support kg, bags, tonnes, pieces, packets, litres and product-appropriate units, including partial bags.
- Bag weight is configurable by product and branch, with change history and permission controls. Do not assume one universal 90 kg bag. Preserve the historical maize 90 kg example as a configurable value, not a global constant.
- Show live quantity, unit price and total calculations. Prevent invalid quantities, unit mixing and negative stock unless explicitly authorised.
- Record original measured weight and actual received/dispatched weight.

### Purchasing and receiving
- Directors and branch managers can create purchases; managers are limited by approved budgets and buying-price limits.
- Separate purchase order, delivery, inspection/acceptance, supplier payment and stock receipt states.
- Only physically received and accepted quantities enter available stock.
- Record actual kg and bag equivalents, shortages, damage, rejected quantities and supplier resolution (balance delivery, refund or other agreed remedy).
- Optional product-specific quality checks, configurable as required, optional or not applicable.
- Supplier balances follow recorded delivery and payment terms; do not infer a debt or deduction from a shortage without an authorised resolution.

### Transfers
- Authorised transfer initiation and approval.
- Dispatching branch records goods leaving; receiving branch confirms actual received quantities and condition.
- Reconcile dispatch and receipt; preserve shortage, damage and discrepancy records. A transfer must not silently remove or duplicate stock.

### Sales and dispatch
- Support walk-in sales, app orders, quotation requests, permitted negotiation and delivery or collection.
- Customer must have an account; no guest checkout.
- No customer credit sales. Payment must be confirmed before goods are released. Quotations and reservations are not payment.
- Support cash, M-Pesa and bank transfer, including split payments for one transaction. Record confirmation, payer/receiver, reference, branch and receipt.
- Record ordered quantity, actual weighed quantity, configured bag equivalent, unit price, invoice total, weight variance, person weighing, dispatch approval, vehicle details where relevant and customer confirmation.
- Stock is reduced once at the correct fulfilment transition; distinguish reserved, committed and dispatched stock.

### Customers, suppliers and financial control
- Customer portal: catalogue, branch availability, quotation/order requests, order tracking, payment and receipt history, delivery/collection, statements, support and disputes. Customers see only their own records.
- Supplier portal: profile, purchase orders, delivery schedules, received weights, shortages, inspection outcomes, payment history, receipts and disputes. Suppliers cannot edit confirmed receiving measurements.
- Branch cash, M-Pesa and bank ledgers; itemised expenses; customer and supplier payment records; daily reconciliation; consolidated director reports.
- Record who entered, received, approved and reversed each transaction. Corrections must be auditable; no silent deletion of financial or stock history.
- Refunds/cancellations: customer request, reason, authorised approval, link to original transaction, payment reference and auditable outcome. Returned goods re-enter available stock only after physical return and inspection.

## TAJIR Farming Services requirements

- Preserve and audit existing client, tractor owner, driver, mechanic, worker and service-provider workflows.
- Clients can discover services, request a job, track status, view job details and contact authorised parties.
- Tractor owners manage their tractors, availability, assigned drivers, bookings, maintenance and earnings.
- When a job is awarded, the tractor owner is the responsible party to contact the client; drivers receive the work assignment and relevant details.
- Drivers can view only assigned jobs and update only allowed job states; start/complete actions and working hours are validated server-side.
- Mechanics receive authorised repair/maintenance requests and maintain traceable service records.
- Workers see assigned duties and can record attendance only for an assigned active branch.
- Use registered phone numbers for calling; expose only approved contacts and respect role/record permissions.
- Record job status transitions, assignment, dates, service completion, hours, payments and disputes with an audit trail.

## Existing repository findings to resolve before feature work

- The Android workflow extracts the Flutter project from `TAJIR_flutter_app.zip` and then copies root `main.dart` over the extracted app entry point. Establish one authoritative, version-controlled Flutter source tree so fixes cannot be overwritten or hidden in an archive.
- The current root Dart source defines a fixed global `kgPerBag = 90.0`; replace only after tracing every purchase, sale, stock, report and conversion path and migrating to configured product/branch units.
- Product icon helper exists, but UI coverage must be audited across all selectors, lists, stock, dashboards and navigation.
- Director phone contacts are currently embedded in client code; move to a controlled company contact source and verify authorisation.
- The Android workflow regenerates the Android folder and suppresses some lint tasks; review why this is needed, restore meaningful static checks and make platform configuration reproducible.
- Existing update checking reads the latest GitHub release and opens an external APK link; test version comparison, signing/package continuity, install/upgrade behaviour and failure states on real devices.
- Existing Supabase functions and migrations include customer PIN authentication/recovery, National ID encryption/access, driver job status and worker attendance. Audit the complete migration chain, policies, grants and functions before altering security-sensitive code.
- Existing regression checklist is the minimum release baseline; expand it to cover both Trading and Farming Services, UI workflows, branch reconciliation, offline/idempotency, accessibility and device upgrade tests.
- Latest observed GitHub Actions run #478 completed successfully and uploaded an APK artifact. This proves CI compilation and artifact creation only, not real-device or end-to-end business correctness. Run #477 was cancelled; runs #470 and #468 failed. Inspect job logs and commits before drawing conclusions about historical changes.

## Engineering and delivery rules

1. Audit current main branch, source archives, build workflow, Supabase migrations/functions, schema and recent successful/failed/cancelled runs before code changes.
2. Establish a single source of truth and create a development branch. Do not push unreviewed work directly to production `main`.
3. Map every screen/action to its data source, server permission, validation, state transition, error handling and regression test.
4. Preserve existing production data and backward compatibility. Use additive, reversible migrations where possible; take backups and test migrations on staging before production.
5. Never put service-role keys, provider secrets, PINs or personal data in source control, client code, logs or AI prompts.
6. Build automated tests for unit conversions, totals, stock movements, permissions, authentication, status transitions and financial reconciliation.
7. Run Flutter format/analyze/tests, SQL migration checks, Edge Function checks, Android build and artifact verification. Do not disable checks merely to obtain a green build.
8. Perform device tests for fresh install, upgrade, login per role, network loss/recovery, calls, updates, voice permissions, accessibility and critical workflows.
9. Publish a release only after acceptance checks pass. Keep release notes, version, commit SHA, APK checksum and known limitations.
10. Report status truthfully: distinguish implemented, automated-test passed, build passed, device tested and production verified.

## Master acceptance gates

- [ ] One canonical Flutter source tree; archive no longer silently overrides application code.
- [ ] Full role-based login and self-service recovery work without loops or cross-account leakage.
- [ ] Each role opens the correct dashboard and sees only permitted records/actions.
- [ ] Trading purchase, receiving, stock, transfer, sale, payment, dispatch, refund and reconciliation workflows pass end-to-end.
- [ ] Product/branch-specific kg/bag conversions and live totals are correct across all screens and reports.
- [ ] Farming Services client booking, owner contact, driver assignment, work completion, mechanic and worker attendance workflows pass end-to-end.
- [ ] Director controls, branch scope, approvals, read-only oversight and audit history pass security tests.
- [ ] Icons, navigation, visual hierarchy, language selection and farmer-friendly flows are consistent.
- [ ] Optional voice assistance works where supported and every voice task has an equivalent manual route.
- [ ] Low-network/offline states do not create duplicate, misleading or unconfirmed financial/stock records.
- [ ] Update process preserves app identity and existing user data across upgrades.
- [ ] Regression suite, security checks, APK build and real-device acceptance tests pass.

## Open decisions

- Confirm initial language set for launch (recommended: English and Kiswahili, with additional Kenyan languages added through translations later).
- Confirm director/owner approval limits and branch profit-sharing agreement templates; never invent financial terms.
- Confirm exact session-lock/background behaviour and any permitted offline transactions.
- Confirm production release approval process before publishing a new APK.
