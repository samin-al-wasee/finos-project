# FinOS — Product Roadmap

**Document Status:** Baseline
**Version:** 1.0
**Project:** FinOS Project
**Platform:** Flutter
**Target Platforms:** Android, iOS

---

# 1. Purpose

This document defines the planned evolution of FinOS from a personal expense tracker into a broader personal finance platform.

The roadmap is intentionally staged.

FinOS should not attempt to build:

* Expense tracking
* Budgeting
* Loans
* Investments
* Portfolio management
* AI
* Automation
* Cloud synchronization
* Financial integrations

all at once.

The product should first establish a reliable financial foundation and then expand from that foundation.

---

# 2. Product Vision

The long-term vision for FinOS is:

> **A single, intelligent hub for managing personal finances.**

The eventual product may bring together:

```text
Money
│
├── Accounts
├── Transactions
├── Budgets
├── Loans
├── Savings
├── Investments
├── Portfolio
├── Net Worth
├── Financial Goals
├── Automation
└── AI Insights
```

However, the initial product is intentionally much smaller.

---

# 3. Roadmap Philosophy

FinOS follows these principles:

### 3.1 Build the Core First

The financial data model must become reliable before advanced features are introduced.

### 3.2 Validate Before Expanding

A feature should ideally demonstrate real user value before becoming a major subsystem.

### 3.3 Avoid Premature Infrastructure

Do not build:

* Backend servers
* Complex synchronization systems
* Microservices
* Payment infrastructure
* Large AI infrastructure

until there is a concrete product requirement.

### 3.4 Keep the Application Useful Offline

Core financial tracking should remain local-first.

### 3.5 Monetization Comes After Utility

The application should first become useful enough that users voluntarily want to support or upgrade it.

---

# 4. Phase Overview

```text
Phase 0
Foundation
    ↓
Phase 1
Core Expense Tracker
    ↓
Phase 1.5
Polish & Validation
    ↓
Phase 2
Smart Finance
    ↓
Phase 3
Personal Finance Hub
    ↓
Phase 4
AI & Automation
    ↓
Phase 5
Scale & Monetization
```

The phases are not necessarily tied to calendar dates.

A phase should be considered complete based on product readiness rather than an arbitrary deadline.

---

# 5. Phase 0 — Foundation

## Goal

Establish a stable technical foundation for FinOS.

### Scope

* Flutter project setup
* Android support
* iOS support
* Application architecture
* Local database
* Data model
* State management
* Routing/navigation
* Theme system
* Design system
* Basic error handling
* Testing infrastructure
* Import/export foundation

### Documentation

The following documents should exist before significant feature development:

```text
AGENTS.md
docs/ARCHITECTURE.md
docs/DATA_MODEL.md
docs/DEVELOPMENT.md
docs/REQUIREMENTS.md
docs/UI_DESIGN.md
docs/ROADMAP.md
```

### Exit Criteria

```text
[ ] Project builds on Android
[ ] Project builds on iOS
[ ] Database initializes correctly
[ ] Basic architecture is established
[ ] Tests can run
[ ] Static analysis works
[ ] Theme system works
[ ] Basic navigation works
```

---

# 6. Phase 1 — Core Expense Tracker

## Goal

Create a genuinely useful offline personal expense tracker.

This is the first meaningful product release.

---

## 6.1 Financial Sources

Users can create:

* Bank accounts
* Mobile financial service accounts
* Credit cards
* Debit cards
* Cash
* Other financial sources

Examples:

```text
Main Bank
bKash
Cash
Visa Card
Savings Account
```

---

## 6.2 Transactions

Users can:

* Add income
* Add expenses
* Create transfers
* Edit transactions
* Delete transactions
* View transaction history
* Filter transactions
* Search transactions

---

## 6.3 Categories

Support:

* Built-in categories
* Custom categories
* Category icons
* Category management

---

## 6.4 Dashboard

The dashboard should provide:

* Total balance
* Income
* Expenses
* Recent transactions
* Basic spending overview

The dashboard should prioritize clarity over analytics.

> **V1 revision (at user request):** every section below the balance is
> exactly one tappable summary card — never a per-item list — so the
> Dashboard never duplicates the Accounts or Transactions tab's own list.
> "Recent transactions" became a Recent Activity card (a this-period count
> plus the single latest transaction's preview); the per-account list
> became an Accounts card (a count); "Spending by category" became a card
> showing only the single highest-spend category plus how many more there
> are. Each card taps through to the relevant full screen
> (`AccountsListScreen`, `TransactionsListScreen`, `BudgetsListScreen`, or
> `ReportsScreen` for Income/Expense/Category) rather than switching the
> bottom navigation tab — no mechanism exists today for a nested screen to
> request that, and building one was out of scope here. Separately, the
> Total Balance card is now pinned at a constant height
> (`SliverPersistentHeader`) while everything else scrolls underneath it;
> Income and Expense scroll away with the rest rather than staying pinned
> alongside it, since Balance is the single dominant figure this document's
> own mockup already treats as more important than the two supporting ones.

---

## 6.5 Budgets

Users should be able to:

* Create budgets
* Assign budgets to categories
* Set budget limits
* Track budget usage
* See remaining budget

---

## 6.6 Loans

Support both:

### Money I Owe

Examples:

* Bank loans
* Personal loans
* Credit owed

### Money Owed to Me

Examples:

* Money lent to friends
* Family loans
* Personal receivables

Users should be able to record repayments.

---

## 6.7 Data Management

Users should be able to:

* Export data locally
* Import data locally
* Restore from a backup

The backup format should be versioned.

---

## 6.8 Basic Settings

Initial settings may include:

* Currency
* Theme
* Categories
* Data management
* About

---

## Phase 1 Exit Criteria

```text
[ ] User can create financial accounts
[ ] User can create income
[ ] User can create expenses
[ ] User can create transfers
[ ] User can categorize transactions
[ ] User can edit/delete transactions
[ ] User can create budgets
[ ] User can manage loans
[ ] User can export data
[ ] User can import data
[ ] Dashboard provides useful overview
[ ] Core functionality works offline
[ ] Financial calculations are tested
[ ] Android build is stable
[ ] iOS build is stable
```

---

# 7. Phase 1.5 — Polish & Validation

## Goal

Turn the functional application into something people would actually want to use.

This phase is intentionally separate from adding major functionality.

---

## Scope

### UX

* Improve transaction entry speed
* Improve navigation
* Improve empty states
* Improve error states
* Improve loading states
* Improve accessibility
* Improve dark mode
* Improve animations where useful

### Performance

* Optimize transaction lists
* Optimize database queries
* Optimize dashboard calculations
* Reduce unnecessary rebuilds

### Reliability

* Improve import/export
* Test corrupted backups
* Test large datasets
* Test database migrations
* Test edge cases

### Product Validation

Use the application personally.

Track:

* How frequently transactions are recorded
* Which screens are used
* Which workflows are annoying
* Which features are rarely used
* Where data entry becomes tedious

---

# 8. Phase 2 — Smart Finance

## Goal

Make FinOS more useful than a conventional expense tracker.

The application should start helping users understand their finances rather than merely recording them.

---

## 8.1 Recurring Transactions

> **Status:** Implemented, ahead of this phase's normal sequence, with
> explicit authorization (see docs/ARCHITECTURE.md, "recurring"). A rule never
> creates a transaction automatically — the user explicitly confirms or skips
> each due occurrence, a deliberate design decision made when this was
> authorized. Custom (arbitrary N-day/week/month) recurrence is not built;
> only the four fixed patterns below are.

Support recurring financial events:

```text
Salary
Rent
Internet
Subscriptions
Utilities
Loan repayments
```

Potential recurrence patterns:

```text
Daily
Weekly
Monthly
Yearly
Custom
```

---

## 8.2 Automatic Transaction Templates

> **Status:** Implemented, ahead of this phase's normal sequence, with
> explicit authorization (see docs/ARCHITECTURE.md, "templates"). Despite the
> section title, a template never creates a transaction automatically — it
> only pre-fills the entry form, which is what "speed up transaction entry"
> below actually describes. Automatic generation is recurring transactions
> (§8.1) — also implemented, but likewise requiring confirmation rather than
> generating unattended.

Users should be able to create templates.

Example:

```text
Every month

Netflix
Entertainment
৳X
Credit Card
```

The system can use the template to speed up transaction entry.

---

## 8.3 Advanced Budgets

> **Status:** Budget history is implemented, ahead of this phase's normal
> sequence, with explicit authorization (see docs/ARCHITECTURE.md,
> "budgets"). Multiple budget periods were already supported before this
> phase. Budget rollover is now built too (see below); budget
> recommendations are not — that overlaps with the Phase 4 "AI &
> Automation" framing (§10.3).

Potential additions:

* Multiple budget periods
* Budget rollover — see below
* Budget history
* Spending trends
* Budget recommendations
* Flexible budget scope — see below

### Flexible budget scope

> **Status:** Built ([ADR-007](adr/007-flexible-budget-scope.md)). A budget's
> scope is now one of four shapes, not just a single category; see below for
> what each means and how the open question below was resolved.

A budget's scope is one of four shapes:

* **Single category** (`SINGLE_CATEGORY`) — the original V1 shape: one limit
  for one expense category.
* **Multi-category budgets** (`MULTI_CATEGORY`) — one limit shared across a
  chosen set of categories (e.g. a single "Going Out" limit covering Dining +
  Entertainment), at least two categories.
* **Category-less budgets** (`UNCATEGORIZED`) — a catch-all limit for
  uncategorised expenses.
* **Whole-account or whole-portfolio budgets** (`WHOLE_ACCOUNT`) — a limit
  that isn't tied to any category at all, e.g. "spend no more than X this
  month, period."

This moved `category_id` from a required scalar foreign key to something
that can mean "many," "none," or "everything" (nullable, plus a new
`scope_type` column and a `budget_categories` join table for the
multi-category case), and it preserves the existing invariant that spending
is never attributed to two competing active budgets at once
(docs/DATA_MODEL.md §22) by generalising it to a set-overlap rule. The design
decision this needed (parallel to [ADR-004](adr/004-loan-accounting.md)) is
recorded in [ADR-007](adr/007-flexible-budget-scope.md); its answer to the
open question — whether a category can belong to a multi-category budget
while also having its own single-category budget in the same period — is
**no**: that is a genuine overlap, not an allowed relationship. A
`WHOLE_ACCOUNT` budget consequently excludes every other active budget in its
period value, so a user wanting both a whole-account ceiling and per-category
budgets needs to give the ceiling a different `period` value.

### Budget rollover

> **Status:** Built ([ADR-008](adr/008-budget-rollover.md)). A budget can opt
> into carrying its own unused or overspent amount into the next period; see
> below for what that means and how it composes with flexible scope above.

A budget may opt into rollover via a new `rollover_enabled` flag, off by
default so every existing budget's numbers are unchanged unless its owner
turns it on. When enabled, a period's own remainder — positive (unspent) or
negative (overspent) — carries forward, unclamped, into the next period's
effective limit:

```text
effective_limit(N) = amount_minor + carry_in(N)
carry_in(N)         = effective_limit(N-1) − spent(N-1)
```

The carried-in amount is derived at read time, never stored — the same
precedent as loan outstanding (ADR-004) and credit-card available credit
(ADR-005) — and the backward walk is capped at `rolloverLookbackLimit`
(currently 6, the same constant `budgetHistoryProvider` already uses), so the
carry a user sees is always fully explained by the periods visible on the
History screen. Rollover is not offered for a `CUSTOM` period, which has no
next period to carry into.

The design decision this needed (parallel to ADR-004/ADR-005) is recorded in
[ADR-008](adr/008-budget-rollover.md). Because the spend a rollover period's
remainder is measured against already goes through the scope-aware
dispatcher [ADR-007](adr/007-flexible-budget-scope.md) introduced, rollover
composes with every one of the four scope types above with no
special-casing — a `MULTI_CATEGORY` or `WHOLE_ACCOUNT` budget can enable
rollover exactly as a `SINGLE_CATEGORY` one can.

---

## 8.4 Financial Reports

> **Status:** All five listed reports — Monthly Spending, income vs expense,
> category spending, account cash flow, and budget performance — plus a
> custom date-range picker are implemented, ahead of this phase's normal
> sequence, with explicit authorization (see docs/ARCHITECTURE.md, "reports").
> Budget performance shows each budget in its own current window rather than
> the report's selected period, since a budget's own period
> (weekly/monthly/yearly/custom) is independent of it. Account cash flow
> reuses the report's selected window like the rest of the screen — one net
> figure per active account with activity that period, compared against its
> own net for the immediately preceding period, with no percentage (a
> period-over-period percent change on a signed net figure is undefined once
> the sign flips between periods). Monthly Spending is a fixed trailing
> six-month trend, independent of the period selector — a multi-month trend
> doesn't fit the "this period vs previous period" shape the other sections
> share. The date-range picker uses Flutter's built-in
> `showDateRangePicker` — a new UI idiom for this app (elsewhere, two
> `showDatePicker` calls are used for from/to filtering), deliberate here
> because it is the standard widget for exactly this interaction. A
> custom range's "previous period" comparison is the immediately preceding
> range of equal length. Year-over-year comparison remains unimplemented.

Introduce reports such as:

```text
Monthly Spending
Income vs Expense
Category Spending
Account Cash Flow
Budget Performance
```

Users should be able to compare:

```text
This month
vs
Last month
```

and eventually:

```text
This year
vs
Last year
```

---

## 8.5 Search & Filtering

> **Status:** Implemented, ahead of this phase's normal sequence, with
> explicit authorization (see docs/ARCHITECTURE.md, "transactions"),
> including a saved-query/report builder: a saved query stores the
> structured filter criteria (account, category, type, date range, amount
> range) under a name, but never the free-text search box, which is typed
> continuously rather than configured. Applying one loads its criteria into
> the filter sheet for review before the user presses Apply.

Advanced transaction discovery:

```text
Date
Amount
Account
Category
Transaction type
Notes
```

Example:

```text
Food transactions
between
৳500 and ৳2,000
during July
```

---

## 8.6 Credit Card Accounts

> **Status:** Implemented, ahead of this phase's normal sequence, with
> explicit authorization (see docs/ARCHITECTURE.md §40, ADR-005) — the user
> picked this directly from the remaining open Phase 2 items. Credit limit,
> billing/statement day, payment-due offset, available credit, and the most
> recently closed statement's balance are all built; everything about the
> current cycle is derived from the account's transactions at read time,
> never stored, the same rule ADR-004 applies to a loan's outstanding
> amount. Deliberately not built: interest/APR, minimum payment, rewards,
> multi-cycle statement history beyond the current and immediately preceding
> cycle, and any liability-aware treatment in the dashboard's net worth
> total — a credit card's balance is summed into it exactly like any other
> account's. Also deliberately fixed: whether an account is a credit card is
> set at creation and cannot be changed by editing it afterward (ADR-005).

A credit card is not a plain cash account: it needs its own cycle.

Potential additions:

* Credit limit
* Billing/statement date
* Payment due date
* Available credit (limit minus current outstanding)
* A statement balance that closes on the billing date and stays separate from
  the next cycle's new spending

The statement-closing behavior is conceptually the same shape as a budget's
period derivation — spend is computed over a window from the transaction
table rather than stored (docs/DATA_MODEL.md §23–§24) — so that pattern should
be reused rather than reinvented.

This needs a design decision before implementation: whether credit-card
specifics live in a separate one-to-one `credit_card_details`-style table (the
same shape loans took relative to accounts — see
[ADR-004](adr/004-loan-accounting.md)) or as nullable columns on
`financial_accounts`, and how the derived statement balance interacts with
`AGENTS.md` §9's single-source-of-truth rule for account balances.

---

## 8.7 Loan Relationships

> **Status:** Implemented ([ADR-006](adr/006-loan-relationships.md)).
> "Extend an existing loan" and "merge on creation" both funnel through
> `LoanController.create(..., extendsLoanId:)` — one code path for both entry
> points. Relationships are a flat, self-referencing `loans.group_id`
> pointing at the relationship's root loan, never a parent chain, so grouping
> is always a single flat query with no recursion. Outstanding and status
> stay entirely per-row, computed by the unmodified ADR-004 rules; a new
> read-only `LoanGroup` aggregates per-row `LoanProgress` figures for display
> only. Deliberately not built: cross-row automatic repayment allocation (a
> repayment still targets exactly one loan row) and a `Counterparty`/`Contact`
> entity (`name` stays free text; the create form's picker is simply
> direction-filtered over existing active loans).

In practice, lending or borrowing with the same person is often a continuing
relationship, not a series of unrelated events: a partial repayment followed by
another advance, for example. Two entry points for this:

* **Extend an existing loan** — from a loan's detail screen, add more
  principal to it (an "extend" action) instead of only recording repayments.
* **Merge on creation** — when creating a new loan, optionally pick an
  existing counterparty/loan so the new one is linked as an extension rather
  than starting a disconnected record.

This needs a design decision (parallel to
[ADR-004](adr/004-loan-accounting.md)) before implementation, because it
changes what a "loan" identifies:

* Treating an extension as **more principal on the same row** is simplest, but
  loses the history of when each top-up happened relative to repayments
  already made — the same reason repayments are individual transactions
  rather than direct adjustments to `principalMinor`.
* Treating it as **multiple linked loan rows** (e.g. a nullable
  self-referencing `parent_loan_id` or shared group id) preserves that
  history and lets the UI show one relationship thread, but every
  outstanding-balance and status derivation (ADR-004 §3–§4) then needs to
  decide whether it operates per-row or per-group.

---

## 8.8 Quick Entry (Global Shortcut Bar)

> **Status:** Implemented, built directly at user request rather than from
> anything sketched elsewhere in this document (see docs/ARCHITECTURE.md,
> "quick entry") — the roadmap didn't anticipate this one, so there is no
> earlier phase it's "ahead of." It cuts across every write operation the app
> has, not one feature area, which is why it lives here rather than folded
> into §8.5's search grammar.

A terminal-style single line, pinned to the bottom of the Transactions tab,
for recording any write operation without leaving that screen:

```text
income 500 today "Main Bank" Salary
expense 500 today "Main Bank" Groceries lunch
transfer 1000 today "Main Bank" Cash
lent 20000 today Alice
repay John
account Savings
budget Groceries 10000 Weekly
```

The first word picks the operation; typing `@` opens a filterable suggestion
list for whichever slot the cursor is in — every operation the bar supports
when none is chosen yet, live account/category/loan names once one is, a
date picker for a date field, or the fixed values a field like "period"
accepts. Submitting never saves anything by itself: it opens the exact
screen (or, for a loan repayment, dialog) that operation already uses,
pre-filled, for the user to review and save — the same shape as choosing a
template or applying a saved filter (§8.2, §8.5).

---

## 8.9 Accounts Card View

> **Status:** Implemented, built directly at user request rather than from
> anything sketched elsewhere in this document. An `AppBar` toggle on the
> Accounts tab switches between the existing list and a swipeable single-
> account card (`PageView`, one account per page, not a peeking carousel),
> additive to the list rather than replacing it. Below the current card, a
> live feed shows that account's transactions and transfers, reusing the
> existing `TransactionFilter`/`TransactionTile` machinery the Transactions
> tab already uses — no new query layer. Loan repayments need no special
> casing: they are ordinary transactions with `accountId` set (ADR-004), so
> they already appear in the same feed. Tapping a card opens the existing
> `AccountDetailsScreen` unchanged — card view is an additional way to browse
> accounts, not a replacement for that screen's edit/archive actions. The
> toggle is hidden when there are no active accounts; archived accounts
> remain reachable only through the list.

---

## 8.10 Loans Card View

> **Status:** Implemented, the same pattern as §8.9 applied to Loans. An
> `AppBar` toggle switches between the existing list and a swipeable
> single-relationship card, one `LoanGroup` per page, ordered "I Owe" before
> "Owed to Me" — the same order the list already uses, so the direction
> split (docs/UI_DESIGN.md §21) is never mixed even though it's one
> sequence rather than two separate tabs; each card also carries an
> explicit direction icon and label. Below the current card, a live feed
> shows that loan's repayment activity via the existing `loanMovementsProvider`
> (`TransactionDao.forLoan`) — already scoped to one loan, so unlike Accounts
> this needed no new filtering step. Tapping a card opens the existing
> `LoanDetailsScreen` unchanged — record payment/receipt and extend stay
> there. The toggle is hidden when there are no active loans; the small dot
> page-indicator was promoted out of the Accounts card view into a shared
> `core/widgets/page_indicator.dart` rather than duplicated.

---

## 8.11 Budgets Card View

> **Status:** Implemented, completing the list⇄card pattern (§8.9–§8.10)
> across all three tabs that have it. Unlike Accounts/Loans, this one filled
> a real gap: `budget_details_screen.dart` had no transaction-level feed
> before this, only aggregate numbers. A budget's spend depends on its
> flexible scope (ADR-007: single-category, multi-category, uncategorized,
> whole-account), so a new pure predicate, `budgetScopeMatches(BudgetScope,
> TransactionRow)`, was added next to the existing `budgetScopesOverlap` in
> `budget_scope.dart`, combined with `BudgetProgress.window.contains(date)`
> and an expense-type check to build the live feed — no new DAO query or
> provider. The `AppBar` toggle switches between the existing list and a
> swipeable single-budget card, ordered by period the same way the list
> groups them (period isn't a safety-relevant distinction the way loans'
> direction split is, so no special per-card badge was needed). Tapping a
> card opens the existing `BudgetDetailsScreen` unchanged; edit/archive/
> delete remain reachable only through the list's own per-card menu, since
> the details screen never had one.
>
> **Update:** the list/card toggle on all three tabs (§8.9–§8.11) now persists
> across app restarts, at the user's request — previously each screen held its
> choice in local `State` only, so relaunching the app always reset to list
> view. Each tab's choice is stored under its own key
> (`accounts_view_mode`/`loans_view_mode`/`budgets_view_mode`) in the existing
> `preferences` key-value table, following the same pattern as
> `theme_preference` (`ListViewMode` in
> `lib/features/settings/domain/list_view_mode.dart`, read via
> `AppSettings`/`appSettingsProvider` and written via
> `SettingsController.set*ViewMode`). The three tabs remember their view modes
> independently rather than sharing one setting.

---

# 9. Phase 3 — Personal Finance Hub

## Goal

Expand FinOS beyond expense tracking.

This is where the application begins moving toward the long-term product vision.

---

# 9.1 Net Worth

> **Status:** Implemented, ahead of the normal Phase 2 → Phase 3 sequence,
> at the user's explicit request. Reached from Settings → Insights,
> alongside Reports — a new screen, not a change to the Dashboard, following
> the same "derived cross-feature aggregate" precedent Reports already
> established. Assets are every active non-credit-card account's live
> balance plus every non-archived `lent` loan's outstanding amount;
> liabilities are every active credit card's owed amount (`max(0,
> -balance)`, the same sign convention `CreditCardCycle` already documents)
> plus every non-archived `borrowed` loan's outstanding amount. Everything
> is computed by a pure `computeNetWorth` function reusing
> `accountBalancesProvider` and `loanProgressProvider` — no new DAO methods,
> no schema changes, nothing stored. An overdrawn non-credit account shows
> as a negative asset entry rather than being reclassified as a liability —
> a deliberate simplification.
>
> **Update:** `computeNetWorth` now also folds in `investmentProgressProvider`
> (§9.3, [ADR-009](adr/009-investment-accounting.md)): an active, unsettled
> investment contributes its full contributed principal as an asset — never
> `contributed − payout received`, since a periodic profit payout (e.g.
> Sanchayapatra's quarterly profit) is new income already reflected in its
> own payout account, not a return of principal. Brokerage-style holdings
> and Cash/Bank/Receivables beyond what Accounts, Loans, and now Investments
> already model are still not built; this is exactly the "Assets −
> Liabilities" figure below, no more.

Introduce:

```text
Assets
-
Liabilities
=
Net Worth
```

Potential assets:

* Cash
* Bank balances
* Investments
* Receivables

Potential liabilities:

* Loans
* Credit card balances
* Other debt

---

# 9.2 Savings Goals

Users can create financial goals.

Examples:

```text
Emergency Fund
New Laptop
Travel
Car
House
Education
```

Each goal can contain:

```text
Target Amount
Current Amount
Deadline
Progress
```

---

# 9.3 Investment Tracking

> **Status:** The "Fixed Deposits" slice is implemented, at the user's
> explicit request, ahead of this phase's normal sequence — see
> [ADR-009](adr/009-investment-accounting.md). Scope is FDR (Fixed Deposit
> Receipt), DPS (Deposit Pension Scheme), and Sanchayapatra (national
> savings certificate): a lump-sum or recurring-monthly principal, an
> optional periodic profit payout (e.g. Sanchayapatra's quarterly profit),
> and a required maturity date. Reached from Settings, alongside Templates
> and Recurring Transactions — a CRUD feature like those, not a read-only
> aggregate like Reports/Net Worth. Contributions and payouts are ordinary
> transactions (two new types, `INVESTMENT_CONTRIBUTION`/`INVESTMENT_PAYOUT`)
> the same way loan movements are (ADR-004), never created automatically —
> the user always confirms or skips a due one, the same rule Recurring
> Transactions (§8.1) follows. Net Worth (§9.1) now includes an active
> investment's contributed principal as an asset. Deliberately not built:
> any interest-rate field or calculated expected payout (a real amount is
> always entered by the user when confirmed), early encashment/partial
> withdrawal, a Dashboard summary card, and Reports integration — all
> possible fast-follows. **Stocks, Bonds, Mutual Funds, ETFs, Crypto, and
> brokerage-style holdings below remain entirely unbuilt** — the rest of
> this section describes that unbuilt future scope.

Introduce investment accounts and holdings.

Potential asset classes:

```text
Stocks
Bonds
Mutual Funds
ETFs
Crypto
Fixed Deposits
Other Investments
```

The first version should focus on **tracking**, not executing trades.

FinOS should not become a brokerage platform.

---

# 9.4 Portfolio

Users should be able to view:

```text
Portfolio Value
Asset Allocation
Individual Holdings
Gain/Loss
Historical Performance
```

Example:

```text
Portfolio

Stocks       55%
Bonds        20%
ETF          15%
Cash         10%
```

---

# 9.5 Investment Transactions

Potential transaction types:

```text
Buy
Sell
Dividend
Interest
Fee
Deposit
Withdrawal
```

The financial model must distinguish investment transactions from ordinary spending transactions.

---

# 10. Phase 4 — AI & Automation

## Goal

Make FinOS proactive rather than passive.

The application should move from:

> "Here is what happened."

toward:

> "Here is what is happening, why it matters, and what you could consider doing."

---

# 10.1 Automatic Categorization

The application may suggest categories based on transaction information.

Example:

```text
"McDonald's"

Suggested category:
Food

[ Accept ] [ Change ]
```

The user should remain in control.

---

# 10.2 AI Financial Insights

Potential insights:

```text
Your food spending increased 24%
compared with last month.

You spent ৳3,200 more on
subscriptions this month.

You may exceed your transport
budget in approximately 6 days.
```

AI should focus on actionable insights rather than generic financial advice.

---

# 10.3 Budget Recommendations

Example:

```text
Your average food spending
over the last 3 months is ৳8,200.

Your current budget is ৳6,000.

Consider setting your budget closer
to ৳8,000.
```

Recommendations should be based on actual user data.

---

# 10.4 Financial Questions

Potential natural-language interface:

```text
How much did I spend on food
last month?
```

```text
What were my biggest expenses
this year?
```

```text
Can I afford to spend ৳20,000
this month?
```

The AI should explain calculations and reference the underlying financial data.

---

# 10.5 Financial Alerts

Potential alerts:

```text
Unusual Spending
Budget Risk
Large Transaction
Recurring Payment
Loan Due
Savings Progress
```

Users should be able to control notification frequency.

---

# 10.6 Automation

Potential automation:

```text
When:
Transaction matches condition

Then:
Perform action
```

Examples:

```text
If merchant contains "Netflix"
→ Categorize as Entertainment
```

```text
If income is received
→ Allocate X% toward Savings Goal
```

```text
If category exceeds budget threshold
→ Notify user
```

Automation should initially remain simple and understandable.

---

# 11. Phase 5 — Cloud & Synchronization

## Goal

Allow users to safely access their FinOS data across devices.

This phase should only begin when there is a validated need.

---

# 11.1 Cloud Backup

Potential providers:

```text
Google Drive
iCloud
Other cloud storage
```

The initial implementation should prefer services that minimize developer infrastructure costs.

---

# 11.2 Multi-Device Sync

Eventually:

```text
Phone A
   ↕
Cloud
   ↕
Phone B
```

Changes should synchronize without requiring the user to manually export/import data.

---

# 11.3 Conflict Resolution

Synchronization requires explicit conflict handling.

Potential model:

```text
Local Changes
      ↓
Sync Engine
      ↓
Conflict Detection
      ↓
Resolution
```

This must be designed carefully before implementation.

---

# 11.4 Authentication

Cloud functionality may require authentication.

Potential providers:

```text
Google
Apple
Facebook
```

The authentication architecture should be decided when cloud sync becomes a real requirement.

---

# 12. Phase 6 — Monetization

## Goal

Generate sustainable revenue without making the free version unusable.

The initial target is modest:

> **Approximately USD 200–300/month.**

The monetization strategy should therefore prioritize low operating costs and a large enough free user base.

---

# 12.1 Advertising

Ads may be introduced into the free tier.

Potential locations:

```text
Non-critical screens
Reports
Settings
Selected dashboard areas
```

Avoid placing ads:

```text
During transaction entry
Over financial values
Inside critical confirmation flows
In ways that resemble financial recommendations
```

The product should never compromise trust for ad revenue.

---

# 12.2 Donations

A lightweight support mechanism may be offered.

Example:

```text
Enjoying FinOS?

Support development ❤️
```

Donations should never be required for core functionality.

---

# 12.3 Premium

Premium should provide meaningful additional value.

Potential premium features:

```text
Advanced AI insights
Advanced analytics
Unlimited automation
Advanced portfolio analytics
Cloud synchronization
Multiple-device support
Advanced reports
Custom themes
Enhanced data tools
```

The exact premium feature set should be determined after observing actual user demand.

---

# 12.4 Monetization Principle

Do not artificially cripple the free product.

Avoid:

```text
"You can only create 20 transactions per month."
```

if the goal is to build trust and organic adoption.

Instead, premium should primarily sell:

```text
Convenience
Automation
Intelligence
Advanced analytics
Cloud features
```

---

# 13. AI Feature Monetization

AI features may have variable operating costs.

Therefore, AI functionality should be designed with cost awareness.

Potential strategies:

```text
Free limited usage
        ↓
Premium higher limits
```

or:

```text
Local intelligence
        +
Optional cloud AI
```

AI requests should not be made unnecessarily.

Caching and deterministic local calculations should be preferred when possible.

---

# 14. Feature Prioritization Framework

Future features should be evaluated using:

```text
User Value
+
Revenue Potential
+
Implementation Cost
+
Maintenance Cost
+
Risk
```

A feature with:

```text
High value
Low cost
Low risk
```

should generally be prioritized.

A feature with:

```text
Low value
High cost
High maintenance
```

should generally be rejected.

---

# 15. Explicitly Deferred Features

The following should **not** be part of the initial FinOS release:

```text
Full investment trading
Bank API integrations
Brokerage integration
Complex tax management
Cryptocurrency trading
Social finance
Financial marketplace
FinOS-owned backend
Complex multi-user accounts
Enterprise features
```

These may be reconsidered later.

---

# 16. What FinOS Should Not Become

FinOS should avoid becoming an unnecessarily complicated financial super-app.

The product should not attempt to compete directly with:

```text
Banks
Brokerages
Accounting software
Professional financial advisors
Tax platforms
```

Instead, FinOS should focus on:

> **Personal financial organization and intelligence.**

---

# 17. Success Metrics

Each phase should have measurable outcomes.

---

## Phase 1

Focus on:

```text
Successful transaction creation
Transaction retention
Weekly active users
Monthly active users
Backup/restore success
Crash-free sessions
```

---

## Phase 2

Focus on:

```text
Budget usage
Recurring transaction usage
Report usage
User retention
```

---

## Phase 3

Focus on:

```text
Net worth tracking
Savings goals
Investment tracking
Portfolio usage
```

---

## Phase 4

Focus on:

```text
AI feature usage
AI insight engagement
Automation usage
User-reported usefulness
```

---

## Phase 5

Focus on:

```text
Sync adoption
Multi-device usage
Data reliability
```

---

## Phase 6

Focus on:

```text
Ad revenue
Donation revenue
Premium conversion
ARPU
Retention
AI cost per user
Monthly operating cost
```

---

# 18. Revenue Target

The initial business objective is approximately:

```text
$200–$300 / month
```

This should be treated as a validation milestone rather than a guarantee.

The first target is not:

```text
Build a large company.
```

The first target is:

```text
Build something useful
        ↓
Get real users
        ↓
Retain users
        ↓
Generate first revenue
        ↓
Reach $200–$300/month
        ↓
Determine whether scaling is worthwhile
```

---

# 19. Roadmap Changes

This roadmap is not immutable.

Features may be:

* Added
* Removed
* Delayed
* Reprioritized

based on:

* User feedback
* Usage data
* Development effort
* Market conditions
* Operating costs
* Revenue performance

However, major scope changes should be documented rather than silently changing the roadmap.

---

# 20. AI Agent Rules for Roadmap

AI agents must not implement future roadmap features simply because they appear in this document.

For example:

```text
Roadmap says:
Phase 4 → AI insights
```

This does **not** mean an agent should proactively add AI infrastructure during Phase 1.

The current development phase and explicit task always take priority.

Agents should treat roadmap items as:

> **Future intent, not current requirements.**

---

# 21. Current Product Focus

At the beginning of development, FinOS should focus exclusively on:

```text
Accounts
Transactions
Categories
Budgets
Loans
Dashboard
Import / Export
Settings
```

The immediate goal is:

> **Build the best small offline-first expense tracker we can, rather than the largest possible finance application.**

Everything else comes later.

---

# 22. Final Roadmap Principle

FinOS should evolve in this direction:

```text
Record
   ↓
Understand
   ↓
Plan
   ↓
Optimize
   ↓
Automate
   ↓
Intelligently Assist
```

The product should earn the right to become more sophisticated by first proving that the simple foundation is valuable.

> **Do not build the future version of FinOS until the current version deserves to exist.**
