# FinOS — Data Model

**Document Status:** Baseline
**Version:** 1.0
**Project:** FinOS Project
**Platform:** Flutter
**Architecture:** Local-first / Offline-first

---

# 1. Purpose

This document defines the conceptual data model for FinOS.

It describes:

* Core financial entities
* Relationships between entities
* Financial semantics
* Data ownership
* Identifiers
* Monetary representation
* Transaction semantics
* Account behavior
* Budget behavior
* Loan behavior
* Recurring transaction behavior
* Import/export representation
* Data integrity rules

This document defines the **domain model**, not a specific database implementation.

The selected database technology may represent these concepts differently internally, but it must preserve the semantics defined here.

---

# 2. Core Entities

The initial FinOS domain consists of:

```text
FinancialAccount
Transaction
Category
Budget
RecurringTransaction
Loan
LoanRepayment
```

Supporting value concepts include:

```text
Money
Currency
DateRange
```

Conceptually:

```text
                         FinOS
                           │
          ┌────────────────┼────────────────┐
          │                │                │
          ▼                ▼                ▼
       Accounts       Transactions       Budgets
          │                │
          │                ├── Category
          │                │
          │                └── Recurring Transaction
          │
          └─────────────── Transfers
                           
                           │
                           ▼
                         Loans
                           │
                           ▼
                     Loan Repayments
```

---

# 3. Entity Identifiers

Every persistent entity should have a stable unique identifier.

Identifiers should:

* Be unique
* Remain stable throughout the entity's lifetime
* Not depend on database row ordering
* Not be reused after deletion
* Be suitable for future synchronization

Preferred identifier strategy:

```text
UUID / ULID / equivalent globally unique identifier
```

The final identifier technology should be decided during implementation.

Example:

```text
account_id
transaction_id
category_id
budget_id
loan_id
loan_repayment_id
```

---

# 4. Money Representation

Financial amounts must not be represented using binary floating-point numbers for persistent financial calculations.

Avoid:

```dart
double amount = 10.99;
```

for authoritative financial values.

Floating-point arithmetic can introduce precision problems.

Prefer an integer minor-unit representation or an equivalent exact decimal representation.

Example:

```text
$10.99
```

may be represented as:

```text
1099 cents
```

For currencies with different decimal conventions, the currency definition must determine the appropriate scale.

The exact implementation should support deterministic arithmetic.

---

# 5. Currency

Currency should be represented explicitly rather than inferred from formatting.

Conceptually:

```text
Currency
├── code
├── symbol
└── decimal scale
```

Example:

```text
USD
BDT
EUR
GBP
JPY
```

The currency code should preferably follow ISO 4217 where applicable.

Example:

```text
USD
BDT
EUR
```

Currency formatting belongs to the presentation layer.

Currency semantics belong to the domain/data layer.

---

# 6. Financial Account

A `FinancialAccount` represents a source or destination of money.

Examples:

* Bank account
* MFS account
* Credit card
* Debit card
* Cash
* Other financial account

Conceptually:

```text
FinancialAccount
├── id
├── name
├── type
├── currency
├── opening_balance
├── created_at
├── updated_at
└── status
```

---

# 7. Account Types

Initial account types:

```text
BANK
MFS
CREDIT_CARD
DEBIT_CARD
CASH
OTHER
```

The model should allow additional types to be introduced later.

---

# 8. Account Status

Accounts should support lifecycle state.

Initial states:

```text
ACTIVE
ARCHIVED
```

An archived account should remain available for historical transactions.

Deleting an account should therefore be restricted when it would break historical financial records.

Prefer archiving over destructive deletion.

---

# 9. Opening Balance

An account may have an opening balance.

Example:

```text
Bank Account
Opening Balance = 50,000 BDT
```

The opening balance represents the account's starting financial state when it is introduced into FinOS.

The system must define one authoritative representation for opening balance.

It must not accidentally count the opening balance as ordinary income.

---

# 10. Current Account Balance

The account's effective balance should be derived from its opening state and financial activity.

Conceptually:

```text
Current Balance
=
Opening Balance
+
Income
- Expenses
+ Incoming Transfers
- Outgoing Transfers
```

The exact calculation depends on account type and transaction semantics.

Credit cards and liability accounts may require different presentation semantics.

Credit-card-specific fields (credit limit, billing/statement date, payment due
date, statement balance) are not part of V1 — a credit card is currently
balanced exactly like any other account. This is tracked as future work in
docs/ROADMAP.md §8.6 ("Credit Card Accounts") and is not authorized for
implementation until the roadmap moves it into the current phase (AGENTS.md
§34).

---

# 11. Transaction

A `Transaction` represents an actual financial event.

Conceptually:

```text
Transaction
├── id
├── type
├── amount
├── currency
├── account_id
├── category_id
├── date
├── description
├── created_at
└── updated_at
```

Optional metadata may be introduced later.

---

# 12. Transaction Types

FinOS initially supports:

```text
INCOME
EXPENSE
TRANSFER
```

These types have distinct financial semantics.

### V1 implementation — loan movements

Two further types record cash moving because of a loan (ADR-004):

```text
LOAN_RECEIPT   money entering an account because of a loan
LOAN_PAYMENT   money leaving an account because of a loan
```

They exist because a loan's cash movements are recorded as transactions rather
than in a separate table, which keeps the transactions table the single source of
truth for account balances. Direction is intrinsic to the type, so a balance query
never has to join to the loan to discover the sign.

Like transfers, they are balance-sheet movements: they change account balances but
never count as income or expense (§17, §35). They always carry a null `category_id`
and a non-null `loan_id`, and they are created only through the loan feature — a
user cannot enter one directly, because editing one by hand would let a loan's
outstanding balance diverge from the movements it is derived from.

---

# 13. Income

Income represents money entering the user's financial position from an external source.

Examples:

* Salary
* Freelance payment
* Bonus
* Interest income
* Gift received

Example:

```text
Salary
Amount: 100,000 BDT
Account: Bank Account
Type: Income
```

Income should increase the relevant account balance.

---

# 14. Expense

Expense represents money leaving the user's financial position as a consumption or cost.

Examples:

* Food
* Rent
* Transportation
* Shopping
* Utilities

Example:

```text
Restaurant
Amount: 1,500 BDT
Account: Bank Account
Type: Expense
Category: Food
```

Expense should decrease the relevant account balance.

---

# 15. Transfer

A transfer represents movement of the user's own funds between financial accounts.

Example:

```text
Bank Account
    ↓
5,000 BDT
    ↓
Cash
```

A transfer must not be treated as income or expense.

---

# 16. Transfer Data Model

A transfer should preserve both sides of the movement.

Conceptually:

```text
Transfer
├── id
├── source_account_id
├── destination_account_id
├── amount
├── currency
├── date
├── description
└── created_at
```

There are two acceptable implementation approaches:

### Option A — Dedicated Transfer Entity

```text
Transfer
    ├── source account
    └── destination account
```

### Option B — Linked Transaction Records

```text
Transaction A
Type: Transfer
Account: Bank
Direction: Outgoing
Transfer ID: X

Transaction B
Type: Transfer
Account: Cash
Direction: Incoming
Transfer ID: X
```

The final implementation should choose one authoritative approach.

The UI and analytics must treat both sides as a single transfer event.

---

# 17. Transfer Invariants

For a transfer:

```text
Source Account Change = -Amount
Destination Account Change = +Amount
```

And:

```text
Income Impact = 0
Expense Impact = 0
```

A transfer must not affect:

* Income totals
* Expense totals
* Spending-by-category totals
* Budget consumption

unless a future feature explicitly defines a different semantic.

---

# 18. Categories

A `Category` classifies transactions.

Examples:

```text
Food
Transport
Rent
Shopping
Entertainment
Salary
Freelance
Utilities
```

Conceptually:

```text
Category
├── id
├── name
├── type
├── icon
├── created_at
└── status
```

---

# 19. Category Types

Categories should be associated with the transaction types they are valid for.

For example:

```text
Expense:
    Food
    Rent
    Transport

Income:
    Salary
    Freelance
    Investment Income
```

A category should not be arbitrarily assigned to an incompatible transaction type.

The exact category-type model may be refined during implementation.

---

# 20. Built-in vs Custom Categories

Categories should distinguish between:

```text
SYSTEM
USER
```

System categories are provided by FinOS.

User categories are created by the user.

System categories should not be permanently deleted by users.

They may be hidden or archived where appropriate.

---

# 21. Category Deletion

Deleting a category must not invalidate historical transactions.

If a category has associated transactions, the preferred behavior is:

```text
Archive category
```

rather than destructive deletion.

Historical transactions should retain their original category relationship.

---

# 22. Budget

A `Budget` represents a planned spending limit.

Conceptually:

```text
Budget
├── id
├── category_id
├── amount
├── currency
├── period
├── start_date
├── end_date
├── created_at
└── status
```

### V1 implementation

The `budgets` table (schema v4) follows this model directly, with these
decisions:

* `category_id` is **required** and must reference an active **expense**
  category. Budgets cap spending, and only expenses are spending (§24), so an
  income category could never consume a limit. Whole-account or category-less
  budgets are not part of V1. Multi-category, category-less, and whole-account
  budgets are tracked as future work in docs/ROADMAP.md §8.3 ("Flexible budget
  scope") and are not authorized for implementation until the roadmap moves
  them into the current phase (AGENTS.md §34).
* `amount_minor` holds the limit in integer minor units (§4).
* `status` stores only the lifecycle state `ACTIVE` / `ARCHIVED`. Budget
  performance is derived at read time, never stored (§25).
* Only **one ACTIVE budget may exist per category and period**, so spending can
  never be attributed to two competing limits at once. Archiving or deleting a
  budget frees the slot.
* The category is fixed once a budget is created. Changing it would silently
  reinterpret every past reading of that budget, so the application archives and
  recreates instead.

---

# 23. Budget Period

Initial supported budget periods may include:

```text
WEEKLY
MONTHLY
YEARLY
CUSTOM
```

The architecture should allow additional period definitions later.

### V1 window derivation

A budget is measured over a half-open calendar range `[from, to)` — `from`
included, `to` excluded — so a transaction dated exactly on a boundary belongs to
exactly one period and can never be counted twice.

The recurring periods take their window from the **calendar**, not from
`start_date`, so a monthly budget always means "this calendar month" regardless
of the day it was created on:

```text
WEEKLY    Monday 00:00 → the following Monday 00:00
MONTHLY   1st of the month → 1st of the next month
YEARLY    Jan 1 → Jan 1 of the next year
CUSTOM    start_date → end_date inclusive
```

`start_date` records when the budget takes effect and is the authoritative window
start for `CUSTOM`. `end_date` is required for `CUSTOM` and null for the
recurring periods, which have no end. Both bounds are calendar dates with the
time component discarded (§42).

---

# 24. Budget Calculation

Budget consumption should be calculated from relevant expenses.

Example:

```text
Food Budget
Limit: 10,000 BDT

Food Expenses:
2,000
1,500
1,200

Spent:
4,700 BDT

Remaining:
5,300 BDT
```

Transfers must not be included as spending.

Income must not be included as spending.

### V1 consumption rule

Spending against a budget is the sum of `amount_minor` over transactions where:

```text
type       = EXPENSE
category_id = the budget's category
date       ∈ the budget's window   (§23, half-open)
```

Income is excluded because it is not spending. Transfers are excluded because
they move the user's own money between accounts (§17); they additionally always
carry a null `category_id`, so they cannot match a budget's category at all.
Uncategorised expenses consume no budget.

Spending is recomputed from the transaction table on every read rather than
cached on the budget row (§45), so the two can never disagree.

---

# 25. Budget Status

A budget can conceptually have states such as:

```text
UNDER_LIMIT
NEAR_LIMIT
EXCEEDED
```

These states should preferably be derived rather than manually stored.

Example:

```text
Spent / Limit = 80%
```

may trigger a warning threshold.

The exact threshold should be defined in product/UI requirements rather than embedded in database semantics.

### V1 derived states

These three states are derived on read and never stored. The warning threshold
lives in the application layer (`BudgetProgress.nearLimitThreshold`), not in the
database:

```text
spent > limit            → EXCEEDED
spent / limit >= 0.80    → NEAR_LIMIT
otherwise                → UNDER_LIMIT
```

Spending exactly equal to the limit is `NEAR_LIMIT`, not `EXCEEDED` — the user has
spent their plan, not overspent it.

`remaining = limit - spent` is allowed to go negative so the UI can report how
far over budget the user is instead of clamping to zero.

---

# 26. Recurring Transaction

**Implemented** (docs/ROADMAP.md §8.1, built ahead of its Phase 2 slot with
explicit authorization; see docs/ARCHITECTURE.md, "recurring").

A `RecurringTransaction` represents a rule for repeated financial activity.

It is not itself necessarily an actual transaction.

Conceptually:

```text
RecurringTransaction
├── id
├── type
├── amount
├── account_id
├── category_id
├── frequency
├── start_date
├── next_occurrence
├── end_date
├── description
└── status
```

The V1 schema (`RecurringTransactions`, schema v8) matches this closely, with
one deliberate difference from a `TransactionTemplate` (§56): `amount` and
`account_id` are required, not nullable. A rule computes what is due
unattended, so — unlike a template, which exists precisely to leave gaps for
the user to fill in — it cannot itself be incomplete. `destination_account_id`
is also present, mirroring `Transaction`'s own transfer support.

---

# 27. Recurrence Frequency

**Implemented** (docs/ROADMAP.md §8.1).

Initial frequencies:

```text
DAILY
WEEKLY
MONTHLY
YEARLY
CUSTOM
```

`CUSTOM` (an arbitrary N-day/week/month interval) is deliberately not built —
it needs its own "every N ___" field and is a refinement on top of the four
fixed frequencies, not required for the feature to be useful.

The recurrence engine calculates the next occurrence deterministically via
`nextOccurrence()`, which clamps day-of-month rather than overflowing (e.g. a
rule dated the 31st advances to February 28th in a non-leap year, not March
2nd or 3rd).

---

# 28. Recurring Transaction vs Actual Transaction

**Implemented** (docs/ROADMAP.md §8.1).

These are separate concepts.

Example:

```text
Recurring Transaction
---------------------
Netflix
1,500 BDT
Monthly
Next occurrence: September 5
```

is the rule.

The actual September charge becomes:

```text
Transaction
------------
Netflix
1,500 BDT
September 5
Expense
```

V1 resolves this with explicit confirmation, not automatic generation: the
user reviews what is due (`dueOccurrences()`) and taps to confirm or skip
before any `Transaction` row is written — `confirmNext`/`confirmAll` create
one, `skipAll` advances `next_occurrence` without creating anything. Nothing
links a created `Transaction` back to the `RecurringTransaction` that
produced it, the same as a `TransactionTemplate` (§56) and unlike a `Loan`
(§32) — deleting the rule never touches transactions it already generated.

The application must not confuse the two.

---

# 29. Loan

A `Loan` represents money owed to the user or by the user.

Two initial loan directions:

```text
LENT
BORROWED
```

Every loan is currently an independent row: there is no relationship between
loans made with the same counterparty (no "extend an existing loan" or "merge
into an existing relationship" concept). This is tracked as future work in
docs/ROADMAP.md §8.7 ("Loan Relationships") and is not authorized for
implementation until the roadmap moves it into the current phase (AGENTS.md
§34).

---

# 30. Money Lent

A `LENT` loan represents money provided by the user to another party.

Example:

```text
User → Friend
20,000 BDT
```

This creates a receivable.

The outstanding amount represents money the user expects to receive back.

---

# 31. Money Borrowed

A `BORROWED` loan represents money the user owes to another party.

Example:

```text
Bank → User
100,000 BDT
```

This creates a liability.

The outstanding amount represents money the user still owes.

---

# 32. Loan Data Model

Conceptually:

```text
Loan
├── id
├── type
├── name
├── principal_amount
├── outstanding_amount
├── currency
├── start_date
├── due_date
├── description
├── status
├── created_at
└── updated_at
```

### V1 implementation

The `loans` table (schema v6) follows this model with three deliberate
differences, all recorded in ADR-004:

* **`outstanding_amount` is not stored.** It is derived as
  `principal − Σ(repayments)` on every read (§35, §45), so it cannot disagree with
  the movements behind it.
* **`status` stores only `ACTIVE` / `ARCHIVED`.** `PAID` and `OVERDUE` are derived
  — see §33.
* **A nullable `disbursement_account_id` is added.** It records the account the
  principal moved through when the loan was made. When set, creating the loan also
  creates the origination movement, atomically. When null, the loan pre-dates FinOS
  and moves no money today — opening state, exactly as an account's opening balance
  is (§9). Without this, a loan made today would leave the user's cash balance
  overstated until they recorded the movement by hand.

The `LoanRepayment` entity in §34 does not exist as a table. Repayments are
transactions of type `LOAN_RECEIPT` / `LOAN_PAYMENT` carrying the loan's id (§12),
so account balances stay derived from one table.

---

# 33. Loan Status

Initial states:

```text
ACTIVE
PAID
OVERDUE
ARCHIVED
```

Some states may be derived.

For example:

```text
outstanding_amount == 0
```

may imply:

```text
PAID
```

The implementation should avoid unnecessary duplicated state.

### V1 derived states

Only the lifecycle is stored. The other two are computed at read time (ADR-004):

```text
outstanding == 0                          → PAID
due_date < today AND outstanding > 0      → OVERDUE
otherwise                                 → OUTSTANDING
```

A loan with no due date is never overdue, and a fully repaid loan is never overdue
regardless of its due date. The due date is a calendar date, so a loan is not
overdue *on* its due date — the user has the whole day (§42).

---

# 34. Loan Repayment

A `LoanRepayment` represents a payment against a loan.

Conceptually:

```text
LoanRepayment
├── id
├── loan_id
├── amount
├── date
├── account_id
├── description
└── created_at
```

### V1 implementation — repayments are transactions

There is **no `loan_repayments` table**. A repayment carries exactly the fields
above, and it also moves real money through an account, so it is recorded as a
transaction (§12) with `loan_id` set:

```text
LENT      repayment received → LOAN_RECEIPT   (account balance ↑)
BORROWED  repayment paid     → LOAN_PAYMENT   (account balance ↓)
```

The origination movement always sits on the opposite side from repayments for a
given loan, so repayments are identifiable by type alone — no extra flag is needed
to tell them apart.

The reasoning is recorded in ADR-004: modelling repayments as their own entity
would make account balance a sum over two tables, which `AGENTS.md` §9 warns
against, and would keep repayments out of the transaction history where users look
for them. Deleting a repayment is deleting a transaction, which correctly raises
the loan's outstanding amount again.

---

# 35. Loan Balance

Conceptually:

```text
Outstanding Amount
=
Principal
- Total Repayments
```

The exact accounting treatment may vary depending on whether the loan is:

```text
LENT
```

or:

```text
BORROWED
```

The system must preserve the distinction.

### V1 balance effects

The distinction is preserved by which side each movement falls on, and loans affect
account balances in both directions:

| | Origination | Repayment |
| --- | --- | --- |
| `LENT` | cash out (balance ↓) | cash in (balance ↑) |
| `BORROWED` | cash in (balance ↑) | cash out (balance ↓) |

Lending money and being repaid in full therefore returns the user exactly where
they started — no income, no expense, no net change.

Note one asymmetry with transfers: transfers net to zero across all accounts, so
the whole-portfolio total ignores them. Loan movements do **not** net to zero,
because the counterparty is a person or bank outside FinOS. The portfolio total
must include them, or it would overstate the user's holdings by every rupee ever
lent out. Interest and fees are not modelled in V1, so a loan's total repayable
amount is exactly its principal.

---

# 36. Loan Repayment Integrity

A repayment must not exceed the outstanding balance unless the product explicitly supports overpayment.

Default V1 behavior should reject or clearly handle:

```text
Repayment > Outstanding Balance
```

Repayment operations should be atomic.

### V1 behaviour

Overpayment is **rejected**, not clamped, and the check runs against the live
outstanding amount so earlier repayments are accounted for. A repayment is also
refused on a fully repaid or archived loan, and through an archived account.

Creating a loan with a disbursement account writes the loan and its origination
movement in one database transaction, so neither can exist without the other.

Deleting a loan is refused once it has repayments — those are financial history, so
archiving is the way to retire it (§47). A loan with only an origination movement
can be deleted, and the movement goes with it in the same transaction.

---

# 37. Relationship Overview

The primary relationships are:

```text
FinancialAccount
      │
      ├───────────────┐
      │               │
      ▼               ▼
Transaction       LoanRepayment
      │               │
      ▼               ▼
Category             Loan
      │
      ▼
   Budget
```

### V1 implementation

Because repayments are transactions rather than their own entity (§34), the
implemented shape has a single path from accounts to money:

```text
FinancialAccount
      │
      │ 1                          ┌──────────────┐
      │ N                          │              │
      ▼                            ▼              │ disbursement
Transaction ─── loan_id ───────▶ Loan ────────────┘
      │
      ├── category_id ──▶ Category ──▶ Budget
      │
      └── destination_account_id ──▶ FinancialAccount   (transfers)
```

A loan optionally points back at the account its principal moved through, and every
loan movement points at its loan. Ordinary transactions leave `loan_id` null;
loan movements leave `category_id` null.

Recurring transactions generate or schedule actual transactions:

```text
RecurringTransaction
          │
          ▼
     Transaction
```

**Implemented** (§26, §28) as a conceptual link only — there is no foreign
key from `Transaction` back to `RecurringTransaction`, the same choice made
for `TransactionTemplate` (§56).

Transfers connect two financial accounts:

```text
Account A
   │
   ▼
Transfer
   │
   ▼
Account B
```

---

# 38. Entity Relationship Overview

Conceptually:

```text
┌─────────────────────┐
│ FinancialAccount    │
│                     │
│ id                  │
│ name                │
│ type                │
│ currency            │
└──────────┬──────────┘
           │
           │ 1
           │
           │ N
┌──────────▼──────────┐
│ Transaction         │
│                     │
│ id                  │
│ type                │
│ amount              │
│ account_id          │
│ category_id         │
└──────────┬──────────┘
           │
           │ N
           │
           │ 1
┌──────────▼──────────┐
│ Category            │
│                     │
│ id                  │
│ name                │
│ type                │
└─────────────────────┘


┌─────────────────────┐
│ Budget              │
│                     │
│ id                  │
│ category_id         │
│ limit               │
│ period              │
└──────────┬──────────┘
           │
           ▼
       Category


┌─────────────────────┐
│ Loan                │
│                     │
│ id                  │
│ type                │
│ principal           │
│ outstanding         │
└──────────┬──────────┘
           │
           │ 1
           │
           │ N
┌──────────▼──────────┐
│ LoanRepayment       │
│                     │
│ id                  │
│ loan_id             │
│ account_id          │
│ amount              │
└─────────────────────┘
```

---

# 39. Soft Deletion and Archiving

Financial records should generally not be hard-deleted if they participate in historical calculations.

Preferred approach:

```text
Active
   ↓
Archived
```

rather than:

```text
Active
   ↓
Deleted permanently
```

This is particularly important for:

* Accounts
* Categories
* Loans
* Recurring transaction definitions

Actual transaction deletion may be allowed because users may need to correct accidental entries, but deletion must be deliberate and must correctly update derived calculations.

---

# 40. Timestamps

Persistent entities should generally include:

```text
created_at
updated_at
```

Dates representing financial events should be stored separately from record metadata.

For example:

```text
Transaction:
    transaction_date
    created_at
    updated_at
```

These represent different concepts.

---

# 41. Financial Date Semantics

The system must distinguish between:

```text
Event Date
```

and:

```text
Record Creation Date
```

Example:

A user records a transaction on August 10 for a purchase that happened on August 8.

```text
transaction_date = August 8
created_at       = August 10
```

Financial reports should use the appropriate financial event date.

---

# 42. Time Zones

The application should avoid storing ambiguous local timestamps for financial events.

Where exact time is not relevant, a transaction date should be treated as a calendar date rather than an arbitrary UTC timestamp.

Where timestamps are required, the system should define a consistent timezone strategy.

The implementation should avoid situations where a transaction moves to another calendar date solely because of timezone conversion.

---

# 43. Data Validation

Domain validation should occur before persistence.

Examples:

### Transaction

```text
Amount > 0
Account exists
Category is compatible
Transaction type is valid
Currency is valid
```

### Budget

```text
Limit > 0
Category exists
Period is valid
Currency is valid
```

### Loan

```text
Principal > 0
Loan type is valid
Currency is valid
```

### Repayment

```text
Amount > 0
Loan exists
Account exists
Amount <= outstanding amount
```

---

# 44. Referential Integrity

The system must preserve relationships between entities.

Examples:

A transaction referencing:

```text
category_id
```

must not point to a nonexistent category.

A repayment referencing:

```text
loan_id
```

must point to a valid loan.

The database layer should enforce referential integrity where supported.

---

# 45. Derived Data

The following values are generally derived:

* Current account balance
* Budget spent
* Budget remaining
* Budget percentage
* Loan outstanding amount
* Net cash flow
* Total income
* Total expenses

Derived values should not be duplicated across multiple parts of the application.

Where caching is introduced for performance, the cache must have a defined invalidation/recalculation strategy.

---

# 46. Financial Invariants

The following invariants must always hold.

## Transaction

```text
amount > 0
```

The transaction type determines its financial direction.

---

## Transfer

```text
source ≠ destination
```

and:

```text
source_change + destination_change = 0
```

---

## Budget

```text
limit > 0
```

---

## Loan

```text
principal > 0
outstanding >= 0
```

---

## Repayment

```text
amount > 0
```

and by default:

```text
amount <= outstanding
```

---

# 47. Deletion Invariants

Deleting or archiving an entity must not silently invalidate financial history.

Examples:

A category with historical transactions should not cause those transactions to become invalid.

An account with historical transactions should normally be archived rather than deleted.

A loan with repayments should not be destructively deleted without an explicit data-management strategy.

---

# 48. Import/Export Data Model

The backup should represent all persistent user-owned financial information.

Conceptually:

```json id="fx3ujp"
{
  "backup_version": 1,
  "exported_at": "2026-08-09T00:00:00Z",
  "currency_metadata": [],
  "accounts": [],
  "categories": [],
  "transactions": [],
  "budgets": [],
  "recurring_transactions": [],
  "loans": [],
  "loan_repayments": []
}
```

The exact serialization format is an implementation detail.

### V1 backup format

A backup is one JSON object: a short header, then one array per table that
exists today.

```json
{
  "backup_version": 1,
  "app_schema_version": 6,
  "exported_at": "2026-08-10T14:32:00.000",
  "accounts": [],
  "categories": [],
  "loans": [],
  "transactions": [],
  "budgets": []
}
```

Tables appear parents-first: `loans` precedes `transactions` because a loan
movement references its loan.

* `backup_version` versions the **envelope**, independent of the database schema.
  Bump it only when the file's shape changes in a way an older importer could not
  read. A backup whose version this build does not know is refused outright — a
  half-understood restore is worse than none.
* `app_schema_version` records the schema that produced the data, so a future
  importer can migrate older payloads.
* Tables absent from the file are treated as empty, so a backup taken before a
  feature existed still restores — a pre-loans backup restores cleanly today.
  `transaction_templates` and `recurring_transactions` exist in the schema but
  are not yet part of the backup envelope — extending backup/restore to cover
  them remains open work, tracked the same way for both.
* The reverse is not promised: a build that predates loans cannot restore a backup
  containing `LOAN_RECEIPT` rows, and rejects it with an "unrecognised type"
  message. The envelope version is not bumped for this, because loan-free backups
  stay fully compatible and a per-record error is more useful than refusing the
  whole file.
* Rows mirror their table columns using `snake_case` keys. Amounts are the same
  integer minor units used in storage (§4) — a decimal amount is rejected on
  import, because it means precision was already lost upstream.
* Dates are ISO-8601 **local wall-clock** strings with no timezone designator,
  and are parsed back as local. A calendar date therefore survives a round trip
  unchanged rather than shifting a day across timezones (§42).
* User preferences are **not** included (§51). They describe a device, not the
  user's finances, so restoring must not silently repaint the app.

### V1 restore semantics

Restore **replaces** every financial record; it does not merge. Merging would
need a rule for every ID collision and could silently double-count transactions,
which corrupts balances.

The sequence is:

```text
parse + validate (no database access)
        ↓
confirm with the user, stating what is written and what is lost
        ↓
single transaction:  delete all → insert all
```

Validation runs to completion before any write and checks field types, enum
values, the `amount > 0` invariant (§46), duplicate IDs, and that every reference
resolves **within the backup** — a transaction cannot point at an account the
file does not contain. The whole restore then runs in one transaction, with
deletes children-first and inserts parents-first so foreign keys hold throughout
(§44). Any failure rolls back, leaving existing data untouched.

---

# 49. Schema Evolution

The data model must be designed to evolve.

When an entity changes:

```text
Old Schema
    ↓
Migration
    ↓
New Schema
```

Existing user data must remain usable.

Destructive migrations require explicit consideration and testing.

---

# 50. Multi-Currency Considerations

Multi-currency support should be possible in the data model even if advanced currency conversion is not part of V1.

Each financial amount should have an associated currency.

Example:

```text
Bank Account
Currency: BDT

Transaction
Amount: 5,000
Currency: BDT
```

Future functionality may support:

* Exchange rates
* Currency conversion
* Base currency
* Multi-currency net worth

These are outside the current V1 scope.

### V1 default-currency preference

The Settings screen stores a **default currency**, which preselects the currency
when creating a new account. It is a convenience default only:

* It never rewrites the currency stored on an existing record. Changing it would
  reinterpret a stored balance without converting it.
* It is not a base currency. Nothing converts between currencies, and totals
  (dashboard balance, budget spending) are summed in minor units without
  conversion — correct only while a user's accounts share one currency.

Transactions and budgets still take the `BDT` column default rather than this
preference, because their currency should follow the account they belong to. That
correctness question is part of real multi-currency support and stays out of V1.

---

# 51. User Preferences

Preferences are user settings, not financial records, and are stored separately
from the financial model.

```text
Preference
├── key
├── value
└── updated_at
```

The `preferences` table (schema v5) is deliberately key-value rather than one
typed column per setting: preferences are heterogeneous and keep accruing, and a
key-value table absorbs each new one without a schema migration. Type safety is
restored one layer up by `AppSettings`, the only reader of these rows.

Rules:

* **An absent row means "use the default."** Nothing is seeded, so an empty table
  is a valid fresh state and a wiped table degrades to defaults rather than
  breaking.
* **Unknown keys and unparseable values fall back rather than throwing.** The
  theme is read while the root widget builds, so a row written by a future
  version must never make the app unlaunchable.
* **Keys are schema.** Renaming one without a migration silently reverts the
  user's choice to its default.
* This table holds preferences only. Amounts, limits, and balances belong in
  their own tables where they can be typed and validated.

Current keys:

```text
theme_preference   SYSTEM | LIGHT | DARK
default_currency   ISO 4217 code from the V1 currency list
```

---

# 52. Investment Extensibility

Investment functionality is not part of V1.

However, the data model should avoid assumptions that would make future investment functionality impossible.

Future entities may include:

```text
InvestmentAccount
Security
Holding
Portfolio
InvestmentTransaction
PriceSnapshot
Dividend
```

These should not be added to V1 merely for future-proofing.

---

# 53. AI Extensibility

AI-generated insights should not become persistent financial truth.

Future AI functionality may produce:

```text
Insight
Recommendation
Warning
Summary
```

These should reference underlying financial data rather than replacing it.

Example:

```text
Transaction Data
       ↓
Financial Calculations
       ↓
AI Analysis
       ↓
"Your food spending increased 18% this month."
```

The underlying transaction data remains authoritative.

---

# 54. Data Ownership

The user owns their financial records.

FinOS should be designed so that a user can:

```text
Create data
     ↓
Store locally
     ↓
Export
     ↓
Delete / reinstall
     ↓
Import
     ↓
Restore
```

The application should not make the user dependent on a developer-controlled server for access to their own financial history in V1.

---

# 55. Privacy Boundary

The following data should be considered sensitive:

* Account names
* Account identifiers
* Balances
* Transaction amounts
* Transaction descriptions
* Categories when financially revealing
* Loan details
* Financial history
* Imported/exported backups

This data should remain local in V1 unless the user explicitly initiates a future external feature that requires data transmission.

---

# 56. Transaction Template

A `TransactionTemplate` is a preset for *manual* entry (docs/ROADMAP.md §8.2,
built ahead of its Phase 2 slot with explicit authorization). It is not a
financial record — creating, editing, or deleting one never touches a
transaction, an account balance, or a budget.

It is also not a `RecurringTransaction` (§26): a template never generates a
transaction on its own. Using one only pre-fills the transaction form for the
user to review and save, the same way any other transaction is created.

```text
TransactionTemplate
  id
  name
  type              (income | expense | transfer)
  amount_minor      (nullable)
  account_id        (nullable)
  destination_account_id  (nullable, transfers only)
  category_id       (nullable, income/expense only)
  description
  created_at
  updated_at
```

Every field but `name` and `type` is nullable. A template is a partial preset,
not a complete transaction — leaving the amount blank is the correct way to
model "the price varies each time" (e.g. a variable utility bill), and leaving
the account or category blank is correct when the template's only purpose is
to save the description or category typing.

Deleting a template has no effect on transactions previously created from it:
nothing links a transaction back to the template that pre-filled its form.

---

# 57. Data Model Evolution Rules

Any future change to the data model should answer:

1. What entity changed?
2. Why did it change?
3. What existing data is affected?
4. Is a migration required?
5. Are financial calculations affected?
6. Are import/export formats affected?
7. Are tests required?
8. Does `ARCHITECTURE.md` need updating?
9. Does `REQUIREMENTS.md` need updating?

---

# 58. Final Data Model Principle

The FinOS data model should follow one central principle:

> **Financial records are facts; derived financial views are calculations.**

For example:

```text
Transactions
     │
     ├──→ Account Balance
     ├──→ Spending
     ├──→ Budget Status
     ├──→ Cash Flow
     └──→ Financial Insights
```

The transaction data remains authoritative.

Balances, reports, budgets, dashboards, and AI insights should be derived from reliable underlying financial records.

The data model must therefore prioritize:

**correctness → integrity → recoverability → extensibility → performance.**
