# ADR-005: Credit Card Accounts

**Status:** Accepted
**Date:** 2026-08-13

## Context

`AccountType.creditCard` (`docs/DATA_MODEL.md` §7) has existed since V1 as a
label only: a credit-card account is stored and balanced exactly like a bank
account, with no credit limit, no billing cycle, and no available credit or
statement balance. `docs/ROADMAP.md` §8.6 tracks this as deliberately
deferred, flagging the same shape question ADR-004 resolved for loans: does
credit-card-specific data live as nullable columns on `financial_accounts`,
or as a separate table? `AGENTS.md` §34 requires either explicit roadmap
promotion or an explicit user request before building a listed future
feature; this was authorized directly by the user picking it, the same route
quick entry took (`docs/ROADMAP.md` §8.8).

A credit card is not a plain cash account: real correctness questions
(available credit, whether a payment is overdue) depend on a billing cycle
that a bank account has no concept of. Unlike a loan, though, a credit card
genuinely *is* a `financial_accounts` row — it appears in the accounts list,
holds a balance, and receives ordinary income/expense/transfer transactions
exactly like any other account. The design question is narrower than
ADR-004's: not *whether* transactions stay the single source of truth (they
already are, for every account), but *where the extra billing fields live*
and *how much of the billing cycle is derived rather than stored*.

## Decision

### 1. A separate `credit_card_details` table, one-to-one with the account

`credit_card_details.account_id` is a unique foreign key into
`financial_accounts`. This mirrors `loans`' relationship to an account
(ADR-004) rather than adding nullable columns to `financial_accounts`
itself: every non-credit-card account (the large majority) would otherwise
carry three meaningless null columns, and the derived-cycle logic below
would have no natural table to belong to.

### 2. Payment due is an offset in days, not a second day-of-month

The billing details store `statement_day` (1–31, the day of the month the
statement closes) and `payment_due_offset_days` (how many days after that
close payment is due) — not a second absolute day-of-month for the due date.
Two independent day-of-month fields are ambiguous the moment the due day is
numerically less than the statement day: does due-day-5 mean five days into
the *same* month as the statement, or the *next* one? An offset
(`statement_date + N days`) has exactly one answer regardless of how the two
numbers compare, and matches how a real statement actually states it ("due
21 days after the statement closes").

### 3. The statement date is a clamped day-of-month, derived each read

`statement_day` names a day of the month, but not every month has that many
days. The statement date for a given month is `min(statement_day,
last_day_of_that_month)` — day 31 becomes the 28th/29th/30th in a shorter
month — computed fresh from `DateTime` arithmetic (`credit_card_cycle.dart`),
the same normalization idiom `docs/DATA_MODEL.md` §23's monthly budget
window already relies on for month/year rollover.

### 4. Everything about the current cycle is derived, never stored

```text
outstanding        = max(0, −current balance)
available credit   = max(0, credit limit − outstanding)
previous statement = the most recent statement_day on or before today
statement balance  = max(0, −(balance as of the previous statement date))
payment due date    = previous statement date + payment_due_offset_days
```

None of this is a column on `credit_card_details`. It is recomputed at read
time from the billing details plus the account's transactions
(`CreditCardController.cycleFor`), the same rule ADR-004 §3 applies to a
loan's outstanding amount: deriving it makes it impossible for available
credit to disagree with the spending behind it. The "balance as of a past
date" figure needed for the previous statement's locked-in balance is a new
`TransactionDao.balanceImpactForBefore` query — the existing
`balanceImpactFor` CASE logic with an added `date < ?` bound, the same
shape `docs/DATA_MODEL.md` §24's budget-window queries already take for a
bounded range instead of an unbounded one.

### 5. The account form gains conditional fields rather than a second screen

Loans needed their own form and details screen because a loan isn't a
`financial_accounts` row at all (ADR-004). A credit card is one, so
`AccountFormScreen` reveals three extra fields (credit limit, statement day,
payment-due offset) only when `AccountType.creditCard` is selected, and
`AccountDetailsScreen` grows one conditional card showing the cycle figures
— rather than introducing a parallel `CreditCardFormScreen` /
`CreditCardDetailsScreen` that would duplicate the name/currency/opening-
balance fields and the archive/restore actions every account already has.
One consequence: whether an account *is* a credit card is fixed at creation
and cannot be changed by editing it afterward (the type dropdown offers only
`Credit Card` when editing an existing one, and never offers it when editing
anything else) — converting an existing account's type into or out of being
a credit card is not supported, avoiding a retroactive "create billing
details for an account that already exists" code path for a scenario the
roadmap does not ask for.

## Consequences

### Positive

* One source of truth for account balances is preserved — nothing here adds
  a second place a balance can be read from.
* Available credit and the statement balance can never drift from the
  transactions behind them, by construction.
* No changes to quick entry: its `account` command already routes every
  submission through `AccountFormScreen` for review before saving
  (`docs/ROADMAP.md` §8.8), so the new conditional fields are reachable from
  quick entry for free.
* The dashboard's total balance calculation is untouched — a credit card's
  balance already participates in the naive sum the same way every other
  account's does.

### Negative / Trade-offs

* **Type is immutable once chosen.** An account created as a bank account
  cannot later become a credit card by editing, and vice versa. This is a
  deliberate V1 boundary (§5 above), not an oversight.
* **No interest, minimum payment, or rewards modelling.** `docs/ROADMAP.md`
  §8.6 lists only credit limit, billing/due dates, and available credit as
  V1 scope; none of the rest is built.
* **Only the two most recent cycles are visible** (the current, still-open
  one and the immediately preceding, closed one) — there is no browsable
  statement history beyond that.
* **The dashboard has no liability-aware treatment.** A credit card's
  negative balance is summed into net worth exactly like any other
  account's; there is no separate "liabilities" grouping. Revisiting this is
  a larger, `docs/ROADMAP.md` Phase 3 (net worth) question, not this one.

## Alternatives Considered

* **Nullable columns on `financial_accounts`.** Smaller migration, but
  leaves every non-credit-card row (the majority of accounts) with three
  permanently-null columns, and gives the derived-cycle logic no natural
  home — the same objection ADR-004 raised against a nullable-column
  approach for loans.
* **A second day-of-month for the payment due date**, instead of an offset.
  Reads slightly more like a physical statement ("due on the 25th") but is
  ambiguous about which month it falls in once the due day is less than the
  statement day; rejected for that ambiguity alone.
* **Storing the current cycle's derived figures** (outstanding, available
  credit) on `credit_card_details` and updating them alongside each
  transaction. Would avoid recomputing on every read, but reintroduces
  exactly the "two competing sources of truth" problem `AGENTS.md` §9
  forbids, and ADR-004 already rejected the equivalent choice for a loan's
  outstanding balance.
* **A dedicated `CreditCardFormScreen` / `CreditCardDetailsScreen`**, mirroring
  the loan feature's fully separate screens. Rejected because a credit card,
  unlike a loan, already is a `financial_accounts` row — forking the form
  and details screen would duplicate every field and action the generic
  account screens already provide, for no benefit a conditional section
  doesn't already give.

## References

* `docs/ROADMAP.md` §8.6 (Credit Card Accounts)
* `docs/DATA_MODEL.md` §7 (Account Types), §10 (Current Account Balance),
  §23–§24 (Budget Period Window, V1 Consumption Rule), §45 (Derived Data),
  §60 (Credit Card Accounts)
* `AGENTS.md` §9 (Account Balance Integrity), §34 (Future Features)
* [ADR-004](004-loan-accounting.md) (Loan Accounting) — the direct precedent
  for a one-to-one details table and derive-don't-store cycle figures
