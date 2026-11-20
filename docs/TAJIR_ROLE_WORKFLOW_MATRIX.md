# TAJIR role and workflow matrix

This is the consolidated product-level role model. It distinguishes the eight primary account types requested for the marketplace from additional internal/support roles already present in the live database.

## 1. Account types

| Primary account | Main purpose | Core dashboard access |
|---|---|---|
| Director | Own and govern TAJIR; approve accounts, branches, prices, finance and operations | Full oversight, approvals, director-controlled prices, reports, contacts and release controls |
| Buyer | Purchase TAJIR products and approved marketplace listings | Product catalogue, branch prices, requests, orders, payments and fulfilment status |
| Seller | Offer produce/products to TAJIR and manage marketplace listings | Own listings, requests/offers, delivery and payment status; private buying-price information only |
| Worker | Perform assigned branch operations | Assigned tasks, purchase/stock operations allowed by role, attendance and task history |
| Tractor Owner | Own/manage tractors and tractor-service bookings | Own tractors, service listings, customer bookings, customer contact, driver assignment, maintenance and earnings |
| Driver | Carry out jobs assigned by a tractor owner | Assigned tractor/job details, job progress, work hours and job history; no owner-only commercial controls |
| Mechanic | Diagnose and repair tractors/equipment | Assigned repair jobs, inspection, repair updates, parts requests and maintenance history |
| Auto-spares Owner | Supply spare parts and manage a spare-parts shop | Own parts inventory, requests, fulfilment, stock movements and sales |

Buyer and Seller are separate account choices. A person who needs both capabilities must have both permissions assigned; choosing one must not silently grant the other.

## 2. Additional internal/support roles

The live database also contains three support roles. They are not a replacement for the eight primary account types:

- **Accountant:** financial records, reconciliations and reports; no unrestricted operational or identity access.
- **Branch Manager:** operational management limited to assigned branch scope.
- **Supplier:** approved supplier portal access and supplier-side fulfilment information.

These roles should be created or assigned by an authorized Director, not by a public self-registration choice.

## 3. Registration and approval rules

| Account | Onboarding rule |
|---|---|
| Buyer / Seller | Customer registration, verified control of the phone number, PIN setup and National ID checks |
| Tractor Owner | Apply with verified phone; Director approves the provider profile and branch/access assignment |
| Mechanic | Apply with verified phone; Director approves the provider profile and service access |
| Auto-spares Owner | Apply with verified phone; Director approves the shop and branch/access assignment |
| Driver | Intended to be invited/linked by the Tractor Owner or authorized Director, then assigned to a tractor/job. Driver invitation and owner-to-driver assignment UI/RPC are still pending. |
| Worker | Created/assigned by the Director or authorized Branch Manager |
| Accountant / Branch Manager / Supplier | Provisioned or approved by the Director |
| Director | Only the two authorized Director identities; first-time PIN setup must prove control of the registered phone |

The backend is authoritative for role grants. A role selected in the app is a registration request, not permission to access that role's dashboard. Every protected operation must re-check the authenticated user, active role assignment, branch scope and record ownership on the server.

## 4. Tractor-service booking workflow

1. A customer browses only active, approved tractor services and verified tractor-owner listings.
2. The customer selects the service, location, date/time and requested work, then submits a booking.
3. The booking is linked to the tractor and its owning Tractor Owner.
4. The Tractor Owner receives the booking and accepts or declines it. The owner is the customer-facing contact.
5. On acceptance, the Tractor Owner calls the customer, confirms the work and price, and assigns a Driver if needed.
6. The Driver sees the assigned job and updates operational progress and actual hours. The Driver does not replace the Tractor Owner as the person responsible for contacting the customer.
7. The Tractor Owner records completion, charges, expenses and earnings; the customer sees the booking status and approved contact details.

A booking must retain the owner/tractor relationship so that the customer can call the Tractor Owner, and the owner can call the customer. Do not expose private ownership documents, serial numbers or sensitive registration information in public listings.

## 5. Repair and spare-parts traceability workflow

1. A Tractor Owner creates or receives a repair/maintenance job linked to a specific tractor.
2. The owner assigns an approved Mechanic.
3. The Mechanic records inspection, diagnosis, work performed and required parts.
4. The Mechanic submits a parts request to an Auto-spares Owner.
5. The shop accepts or rejects the request and records the supplied quantity and price.
6. Supplied stock is decremented once, with a traceable stock movement.
7. The Mechanic records which parts were actually fitted and completes the repair record.
8. The Tractor Owner reviews the repair, costs and maintenance history and closes the job.

Every repair-part record must link the repair job, tractor, owner, mechanic, shop, part, quantity, cost, status and timestamps. Rejected/cancelled requests must not reduce stock. Replaying a supply action must not decrement stock twice.

## 6. Marketplace and Director-controlled pricing

- A Seller creates a listing with product, quantity, unit, description and location. The Seller does not set the public selling price.
- The Director controls the buying and selling prices through the protected price records.
- The Seller can see the applicable private buying price for their own listing; a Buyer sees only the approved selling price.
- Internal buying costs, seller payout data and other customers' private prices must not be exposed to Buyers.
- TAJIR branch stock prices are maintained by the Director per branch and product variant, in KES per kilogram.
- Customer product requests are priced server-side from the Director-controlled branch price. The client must not be trusted to submit its own unit price.
- The displayed per-bag price is derived from the configured product-variant bag weight; the per-kilogram price remains the source of truth.

The live database already contains separate marketplace buying/selling price tables and branch selling-price records. The current Flutter screen still contains legacy listing-price code and must be brought into line with these tables before the marketplace is considered release-ready.

## 7. Maize, fertilizer and unit rules

- Quantity entry supports kilograms and bags.
- Maize uses **90 kg = 1 bag** as the agreed fallback.
- Product variants may define their own `bag_weight_kg`; do not apply the maize 90 kg rule to every product.
- Buying/selling calculations must update while quantity or unit price is edited.
- Customer requests to TAJIR are in kilograms and the server calculates the line total from the branch's current selling price per kg.
- Keep product-specific expense categories and the payer field (Edu or Mercy) in the transaction record.

### Trading-sheet fields to preserve

**Maize:** date, quantity, buying price, Broka, Bag Price, transport, labour, drying expense, loading, Hema, paid by Edu/Mercy, total and profit.

**Fertilizer:** date, quantity, buying price, voucher price, transport 1, transport 2, loading, paid by Edu/Mercy, selling price, food/accommodation, total and profit.

**Open calculation decision:** the meaning of the maize `Bag Price` field has not been confirmed. It must be identified as either a selling/revenue price or a bag/packaging expense before the app calculates profit from it. Do not count the same field as both revenue and cost.

## 8. Payments and accounting

The accounting design must support all six payment methods from the approved TAJIR payment plan, even where some are initially recorded manually. Preserve split/multiple payments, outstanding credit balances, verification status, refunds/reversals and payer attribution. The current live database payment enum is narrower than the complete requested payment workflow; do not treat the current enum as the final product specification.

M-Pesa references must be verified by a trusted provider callback before a payment is marked confirmed. A client-entered reference alone is not proof of payment.

## 9. Shared dashboard and security requirements

- Show both authorized Director contact options on every dashboard.
- Use visible, consistent icons on every tab and item category.
- Enforce role and branch permissions on the server, not only in Flutter navigation.
- Verify phone ownership during public registration and first-time Director setup; use OTP for PIN recovery.
- Apply PIN lockout/rate limiting and secure session expiry; provide a clear re-authentication path.
- Encrypt National ID values and restrict full identity access to the account holder and authorized Director workflow.
- Keep customer-visible prices separate from private buying costs and internal finance.
- Version checks may notify users and launch the Android installer; Android still requires the user to approve installation.

## 10. Release identity and signing

- Preserve the existing installed package ID: `com.tajir.tajir_app`.
- The build workflow now verifies package ID, launcher label and APK signature before upload.
- The current saved APK and the available new release keystore do not share a signing certificate. The original signing key has not been found in the available project files. Until that key is recovered or a one-time reinstall is accepted, a production update cannot be installed over the saved APK.
- Builds without the protected signing secrets are test-only and must not be published as production releases.
