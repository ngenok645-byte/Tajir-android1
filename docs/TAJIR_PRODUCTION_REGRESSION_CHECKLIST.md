# TAJIR Production Regression Checklist

This checklist is the acceptance baseline for every production change. A feature is not complete because code was committed: it must pass the relevant checks below and the release APK must build successfully.

## Release gate
- [ ] GitHub Actions release build completes successfully.
- [ ] APK artifact exists and is downloadable.
- [ ] Versioned GitHub release is published and contains the same APK.
- [ ] Fresh install launches without a crash and reaches the correct sign-in screen.
- [ ] Existing installation upgrades without losing the signed-in user's business records.
- [ ] Supabase connectivity works on mobile data and Wi-Fi.
- [ ] No test/demo records are mixed into production data.

## Authentication and account security
- [ ] Phone number normalization is consistent for Kenyan numbers (+254).
- [ ] Correct phone + four-digit PIN signs in to the matching active account.
- [ ] Incorrect PIN gives a clear error; repeated attempts trigger a timed lockout.
- [ ] Rate limiting and lockout errors are not misreported as a wrong PIN.
- [ ] Customer login opens the customer portal directly.
- [ ] Staff login opens the dashboard authorized for that staff member's role.
- [ ] Change PIN works after authentication.
- [ ] Forgot/reset PIN is self-service, verifies control of the registered phone, and does not require Director intervention.
- [ ] A phone number that is not registered cannot sign in or create an authenticated session.
- [ ] Sign out clears the session; backgrounding or locking the phone does not unexpectedly sign the user out.
- [ ] Expired/revoked sessions return safely to sign-in.

## Roles and permissions
- [ ] Director
- [ ] Client / Buyer
- [ ] Client / Seller
- [ ] Worker
- [ ] Tractor Owner
- [ ] Driver
- [ ] Mechanic
- [ ] Auto-spares Owner
- [ ] Every role opens its own dashboard and only sees authorized navigation/actions.
- [ ] Server-side RLS/RPC permissions enforce access; hiding a button is not treated as security.
- [ ] Director cross-account oversight is read-only, scoped, and audited; it does not silently impersonate users.
- [ ] Director can create clearly labelled demo accounts for role previews without polluting production transactions.

## Director operations
- [ ] Company-wide overview covers all authorized branches and roles.
- [ ] Branch selection/filtering is consistent across stock, sales, purchases, expenses, and reports.
- [ ] Approvals show pending items, status, and an audit trail.
- [ ] Reports reconcile sales, purchase costs, expenses, payments, stock, and profit.
- [ ] Stock and financial totals use consistent date ranges and branch scopes.
- [ ] Staff/account administration does not expose PINs or credentials.
- [ ] Director can inspect authorized account records in read-only mode.

## Buyer and seller marketplace
- [ ] Buyer catalogue shows active products without disclosing internal stock quantities, branch stock, or in/out-of-stock status.
- [ ] Buyer can select any displayed product, enter a positive quantity, and submit a request.
- [ ] Buyer can view their own request history and status only.
- [ ] Staff can process requests with correct authorization and status transitions.
- [ ] Seller can create and manage listings with product name, description, price, quantity/unit, and location.
- [ ] Seller listings appear in the buyer catalogue only when active and permitted.
- [ ] Buyer and seller permissions are independently respected for dual-role accounts.


## Director-controlled client product pricing (KG / bags)
- [ ] Only Director-authorised users can create or change official TAJIR product/variant selling prices.
- [ ] Client product selection offers only the units enabled for that product (KG, bag, or both).
- [ ] Client enters quantity only; there is no client control to edit official unit price, discount or payable total.
- [ ] Client sees current approved unit price, selected unit, quantity and correctly calculated KES total.
- [ ] Per-product/per-branch bag weight and unit conversion are respected; no universal 90 kg assumption is applied to every product.
- [ ] Server recalculates the order total from authoritative price and quantity; altered client-submitted price/total is rejected or ignored.
- [ ] Price edits are role-protected, audited and effective-dated; accepted orders retain their original price snapshot.
- [ ] Missing, inactive, stale or unsupported pricing blocks order submission rather than creating a zero-price order.
- [ ] Totals and rounding match between client, server order, director dashboard and receipt.

## Business workflows
- [ ] Purchases validate quantities, prices, suppliers, and totals.
- [ ] Purchase-related expenses are itemized and included exactly once in costs.
- [ ] Sales validate quantities, prices, customer, and totals.
- [ ] Stock movements reconcile purchases, sales, adjustments, and branch transfers.
- [ ] Profit is calculated from the correct sales revenue and all attributable costs.
- [ ] Customer and supplier payments reconcile with outstanding balances.
- [ ] Tractor owner can manage tractors, bookings, drivers, maintenance, and earnings.
- [ ] Driver sees assigned jobs, tractor details, and work history only.
- [ ] Mechanic sees assigned repair requests, maintenance jobs, and service records only.
- [ ] Auto-spares owner manages spare-parts inventory, orders, and sales.
- [ ] Worker sees assigned duties, attendance, and work records only.

## Offline, updates, and usability
- [ ] Cached data is clearly marked and never presented as newly synced data.
- [ ] Offline writes queue safely and sync once; retries do not duplicate transactions.
- [ ] Conflicts are detected and resolved without silently overwriting newer server data.
- [ ] App checks for a newer signed release and presents a clear update action.
- [ ] Android installation approval is explained; the app does not claim to silently install an APK.
- [ ] Manual update check is available and reports current/up-to-date status accurately.
- [ ] Loading, empty, permission-denied, network-error, and server-error states are clear.
- [ ] Forms validate required fields and prevent accidental duplicate submissions.
- [ ] Navigation, back button, refresh, and logout work on common Android screen sizes.

## Regression rule
For every fix, rerun the directly affected checks plus authentication, role routing, purchases, sales, stock, and APK build checks. Record failures and their causes before making another code change. Never mark an item passed without a real test result.


## National ID consistency regression checks

- [ ] Customer and service-provider registration capture account name separately from National ID number and exact full ID name.
- [ ] Director, branch manager, accountant, worker and driver can add/view only their own ID details from Account Security.
- [ ] Every ID form validates 7–8 digits and a 2–100 character full ID name; the server repeats validation.
- [ ] National ID number and full ID name are encrypted at rest; no plaintext is available through ordinary profile/table reads.
- [ ] User can view their own ID details; only an authorised Director can view another user's details; all other cross-account reads are rejected.
- [ ] Duplicate IDs are rejected across both legacy customer records and the all-role identity store.
- [ ] Legacy customer ID number is preserved; user must supply the exact ID name rather than having TAJIR assume it from the account name.
- [ ] A different ID number cannot overwrite an existing identity; correction is escalated to the authorised correction workflow.
- [ ] Missing Vault key or encryption secret blocks identity writes/reads with a safe user-facing error.
- [ ] UI clearly states that TAJIR does not verify identity against government records unless a verification integration is added.
