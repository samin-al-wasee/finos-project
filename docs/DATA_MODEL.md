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
  budgets are not part of V1.
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

---

# 27. Recurrence Frequency

Initial frequencies:

```text
DAILY
WEEKLY
MONTHLY
YEARLY
CUSTOM
```

The recurrence engine should calculate the next occurrence deterministically.

---

# 28. Recurring Transaction vs Actual Transaction

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

The application must not confuse the two.

---

# 29. Loan

A `Loan` represents money owed to the user or by the user.

Two initial loan directions:

```text
LENT
BORROWED
```

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

---

# 36. Loan Repayment Integrity

A repayment must not exceed the outstanding balance unless the product explicitly supports overpayment.

Default V1 behavior should reject or clearly handle:

```text
Repayment > Outstanding Balance
```

Repayment operations should be atomic.

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

Recurring transactions generate or schedule actual transactions:

```text
RecurringTransaction
          │
          ▼
     Transaction
```

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

# 56. Data Model Evolution Rules

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

# 57. Final Data Model Principle

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
