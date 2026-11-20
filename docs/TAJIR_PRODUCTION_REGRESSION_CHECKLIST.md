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
