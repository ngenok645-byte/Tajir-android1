# TAJIR Production Regression Checklist

This checklist is the acceptance baseline for every production change. A feature is not complete because code was committed: it must pass the relevant checks below and the release APK must build successfully.


## Additional end-to-end release tests

### Customer and seller marketplace

- [ ] Buyer can browse active listings from other Sellers and cannot see their own listing as a buyer listing.
- [ ] Buyer sees only `marketplace_listing_selling_prices.selling_price_kes`; no buying price or legacy price is exposed.
- [ ] Seller can create a listing without entering a public price.
- [ ] Seller sees only their own `marketplace_listing_buying_prices.buying_price_kes`.
- [ ] Director can set both buying and selling prices atomically.
- [ ] A listing with no Director selling price is not offered to Buyers.
- [ ] A buyer request snapshots the Director-approved unit price and line total on the server.
- [ ] Legacy `marketplace_listings.price_per_unit` remains zero on insert and update.
- [ ] Seller can accept/decline purchase requests only for their own listings; buyer sees status updates.

### Branch catalogue pricing and quantities

- [ ] Director can set branch/product-variant selling price in KES per KG.
- [ ] Customer sees the assigned branch price before requesting a product.
- [ ] Customer request quantity is entered in KG and server calculates the price from the current branch price.
- [ ] Maize 90 KG displays as 1 bag and the per-bag equivalent is correct.
- [ ] Other products use their own `bag_weight_kg`; no blanket 90 KG conversion is applied.
- [ ] A missing branch price disables the request and explains that the Director must set a price.

### Tractor Owner and Driver responsibility

- [ ] Verified Tractor Owner accounts enter the Owner dashboard using the live `verified` status.
- [ ] A customer booking is linked to the verified Tractor Owner of the selected tractor.
- [ ] The Tractor Owner sees incoming bookings and the customer's phone number.
- [ ] Owner can call the customer; the call attempt is timestamped.
- [ ] Owner can accept/decline and provide a quote.
- [ ] Customer sees the owner contact only after acceptance and can call the owner.
- [ ] Driver sees only assigned jobs and does not receive the customer's private phone number or the owner customer-contact responsibility.
- [ ] Owner can assign an eligible Driver to an accepted booking. **Not implemented yet.**
- [ ] Customer with a branch-fleet tractor and no private owner sees Director contact options.

### Identity, security and finance

- [ ] Customer, Seller, Tractor Owner, Mechanic and Auto-spares registration requires phone OTP before account creation.
- [ ] Expired, incorrect, replayed and rate-limited OTP challenges are rejected.
- [ ] A person cannot register another person's phone number without receiving its OTP.
- [ ] Director first-time setup is limited to the two authorized Director identities and verified phone ownership.
- [ ] National ID values are encrypted and never exposed in public listings, logs or ordinary staff screens.
- [ ] All six approved payment methods are supported; split payments, credit balances, refunds and reversals reconcile correctly.
- [ ] M-Pesa is marked paid only after trusted provider callback verification.
- [ ] Maize `Bag Price` meaning is confirmed as either revenue or packaging expense before profit calculation is enabled.

### Android release and update continuity

- [ ] Build package ID is `com.tajir.tajir_app` and launcher label is `TAJIR`.
- [ ] Protected production signing secrets are configured; test-only debug APKs are not published.
- [ ] Original signing key is recovered or the one-time reinstall is explicitly accepted.
- [ ] Production-signed APK installs and updates on a real Android device.
- [ ] App update check offers a compatible release and Android asks the user to approve installation.
- [ ] Logout/session expiry, login, PIN reset and role routing are tested on a real device.

## Current audit-branch status

The audit branch compiles successfully in CI. Deno type-check passed; Flutter analysis reported zero errors, 13 warnings and 199 informational findings. Two new SQL migrations for marketplace price protection and Tractor Owner booking/contact workflows were syntax-tested in a transaction and rolled back. Neither migration nor the phone-verification migration has been deployed to the live database. Real-device, staging and production-signing tests remain release gates.

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
