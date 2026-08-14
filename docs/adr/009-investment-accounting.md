# ADR-009: Investment Accounting (Fixed-Term Instruments)

**Status:** Accepted
**Date:** 2026-08-13

## Context

The user asked to track Bangladeshi fixed-term savings instruments — FDR
(Fixed Deposit Receipt), DPS (Deposit Pension Scheme), and Sanchayapatra
(national savings certificate) — and explicitly chose the roadmap's "Full
Investment Tracking" scope (`docs/ROADMAP.md` §9.3) as the umbrella, while the
concrete need is these three fixed-term shapes, not stocks, ETFs, crypto, or
brokerage trading.

Two existing documents might seem to already cover this and don't:

* `docs/DATA_MODEL.md` §52 ("Investment Extensibility") sketches a *future*
  brokerage-shaped schema — `InvestmentAccount`, `Security`, `Holding`,
  `Portfolio`, `PriceSnapshot`, `Dividend`. None of that applies to a locked
  deposit: there is no security, no market price, no holding to track. §52
  stays reserved for a possible future stocks/ETF phase; this ADR does not
  touch it.
* Loans (ADR-004) are the closer analog structurally — a principal, money
  moving through the transactions table, a derived outstanding figure — but
  Loans' domain shape is built around person-to-person debt (a direction
  split between money owed and money owed to the user, free-text
  counterparty names). Forcing an FDR into that would corrupt the direction
  split and the net-worth loan aggregation, which assume a counterparty is a
  person or entity, not a bank product.

So this needs its own schema, modeled on Loans' pattern (principal + derived
progress, sharing the `transactions` table) but extended with two things
Loans doesn't need: a recurring contribution schedule (DPS deposits monthly)
and a periodic payout schedule (Sanchayapatra pays profit quarterly), both of
which must never auto-create a transaction — the same rule
`docs/ARCHITECTURE.md` §20 established for Recurring Transactions: a
schedule is not itself a transaction; only explicit user confirmation creates
one.

## Decision

### 1. Investment money movements are transactions, the same pattern as ADR-004

A new `investments` table holds the instrument itself. Contributions and
payouts are recorded in the existing `transactions` table via two new
transaction types and a nullable `investment_id`:

```text
INVESTMENT_CONTRIBUTION   money leaving an account into the investment
INVESTMENT_PAYOUT         money entering an account from the investment
```

This is a near-verbatim restatement of ADR-004's core decision for loans —
loans already set the precedent that the transactions table stays the single
source of truth for balances; investments follow it rather than
re-litigating it. Like loan transactions, these carry no category, so they
cannot enter spending-by-category or budget consumption.

**Sign/direction convention.** Unlike a loan's single
`disbursement_account_id`, an investment has two account fields — a
contribution and a payout can go through different accounts — so the
direction table needs two columns instead of ADR-004's two rows:

| Type | Debits | Credits |
| --- | --- | --- |
| `INVESTMENT_CONTRIBUTION` | `source_account_id` | — |
| `INVESTMENT_PAYOUT` | — | `payout_account_id` |

A transaction's own `account_id` is always whichever of the two applies —
`source_account_id` for a contribution, `payout_account_id` for a payout —
the same way a loan movement's `account_id` is whichever account the loan's
cash moved through.

### 2. Maturity status is derived, not stored — the one place this ADR departs from a straightforward ADR-004 restatement

An early draft of this design stored `ACTIVE` / `MATURED` / `ARCHIVED`, with
a `confirmMaturity()` action that set `status = MATURED` atomically with the
final payout. A design-review pass caught the bug this creates: there was no
way back if a user confirmed maturity by mistake (wrong amount, wrong date,
or clicked before the bank had actually paid).

Loans avoid this whole class of problem by storing only `ACTIVE` /
`ARCHIVED` and deriving `PAID` / `OVERDUE` at read time (ADR-004 §4,
`LoanProgress.standing`). This ADR applies the same rule: `investments.status`
stores only `ACTIVE` / `ARCHIVED`. Whether an investment has matured is
`now >= maturity_date`, computed fresh every time. Whether its maturity
payout is still owed is derived from whether a payout transaction has been
recorded dated on or after the maturity date (`InvestmentProgress.isSettled`)
— a payout dated *before* maturity is periodic profit, not the maturity
settlement, so it doesn't count. Confirming the final maturity payout is
then just an ordinary `confirmNextPayout` call, identical in code to a
routine periodic payout; the UI only labels the button differently when the
investment has matured. There is no stored `MATURED` state to accidentally
set or need to unset — correcting a mistaken confirmation is just deleting
the transaction (`docs/DATA_MODEL.md` §47), never undoing a status.

### 3. Recurring/periodic schedules reuse `RecurrenceFrequency`, extended with `quarterly`

`lib/features/recurring/domain/recurrence_frequency.dart` already has pure,
tested, database-free `nextOccurrence`/`RecurrenceFrequency` and
`dueOccurrences` (`due_occurrences.dart`) — exactly the "advance a schedule,
never auto-create" logic this feature needs for both:

* DPS's recurring monthly contribution schedule (`nextContributionDue`,
  frequency hardcoded to monthly — that is what DPS means), and
* a periodic payout schedule (`nextPayoutDue`) when an instrument pays
  profit before maturity, e.g. Sanchayapatra's quarterly profit.

`RecurrenceFrequency` gained one new value, `quarterly` (storage
`QUARTERLY`), rather than this feature forking its own parallel enum and
re-deriving the same day-of-month-clamping date math
(`AGENTS.md` §4's "prefer simple solutions over unnecessary abstractions").
This is small, additive, and backward compatible — existing stored data and
behavior for Recurring Transactions and Templates are unaffected; they simply
gain one more valid frequency choice as a side effect.

**Boundary rule.** Investments depends only on the pure files
`recurrence_frequency.dart` and `due_occurrences.dart` — never
`RecurringTransactionDao` or `RecurringTransactionController`. The two
features' persistence layers must never become coupled.

**`InvestmentPayoutFrequency` wraps `RecurrenceFrequency`, rather than adding
a fifth value to it.** "No periodic payout, only at maturity" is the absence
of a recurrence, not a recurrence itself, and conflating the two would force
every other `RecurrenceFrequency` consumer to handle a case that means
something different in their context. `InvestmentPayoutFrequency` is its own
small type: `atMaturity`, or `periodic(RecurrenceFrequency)` — restricted at
the form layer to monthly/quarterly/yearly, since daily or weekly profit
payouts don't occur for these instruments.

A contribution's first due date is the investment's own start date — "a rule
effective today is due today," the same convention Recurring Transactions'
own `create()` uses. A **payout's** first due date is deliberately *not* the
start date, but the first occurrence after it: unlike a bill, profit has not
had time to accrue on day one, so it cannot plausibly be due immediately.

### 4. Net worth: full contributed principal until settled, never `contributed − payout received`

An investment contributes its full `contributedMinor` as a net-worth asset
until `isSettled` (§2), at which point it contributes nothing. This was the
second thing an early draft got wrong: it computed the asset value as
`contributed − payoutReceived`, reasoning that a periodic payout is cash
already reflected in the destination account and must not be double-counted.
That reasoning is correct, but the fix was wrong — a periodic profit payout
(Sanchayapatra's quarterly profit) is *new* income credited to the payout
account, not a return of principal, so it must not reduce the locked
principal's own value at all. Subtracting it mid-term understated the
position (e.g. a ৳10,00,000 Sanchayapatra with ৳45,000 of profit already
withdrawn would have shown as worth ৳9,55,000, when the locked principal is
still the full ৳10,00,000). The corrected rule: only the maturity settlement
— which actually returns the principal — zeroes out the entry; a periodic
payout never touches it. This is covered by a dedicated unit test
(`net_worth_data_test.dart`) proving a mid-term Sanchayapatra with profit
already withdrawn still nets to exactly its original principal.

### 5. No interest-rate field, no calculated expected payouts

The user was asked explicitly and chose to omit this. Real bank-computed
interest (compounding, tax deducted at source, product-specific rules) can't
be reliably reproduced, and a wrong number next to real money is a worse
outcome than no number at all. `confirmNextPayout` always takes a
user-entered amount — unlike Recurring Transactions' fixed-amount confirm,
where the amount is a deliberate choice the user made when creating the
rule, an investment payout's amount is a fact reported by the bank, which
the app cannot predict.

### 6. Delete guard mirrors Loans' asymmetric rule, not a blanket "any movement" block

A first draft blocked deletion once *any* transaction existed — which would
have made every lump-sum investment (FDR, Sanchayapatra) permanently
undeletable seconds after creation, since `create()` immediately records one
contribution. Loans avoid this: `LoanController.delete` only blocks on
repayment-type movements, not the origination transaction, because
origination is automatic (part of `create()`), not a separate confirmed
action. The corrected rule for investments: deletion is blocked by any
payout (always a distinct confirmed action), or — for a recurring (DPS)
investment — any contribution (each one is a distinct confirmed action,
unlike a lump sum's single automatic one). A lump-sum investment with only
its automatic origination contribution and no payout can still be deleted
outright, exactly as a loan with only its origination movement can.

### 7. Explicit scope boundary

Not built, and not silently assumed to be coming:

* Interest-rate / expected-payout calculation (§5).
* Early encashment or partial withdrawal before maturity.
* Stocks, ETFs, mutual funds, crypto, brokerage trading (`docs/DATA_MODEL.md`
  §52's sketch stays reserved for that possible future phase).
* A Dashboard summary card or Reports integration — can follow later, the
  same "additive, not required on first ship" pattern Accounts/Loans/Budgets'
  card views followed.
* A dashboard notification badge for due items — Recurring Transactions
  doesn't have one either; there is no existing precedent to reuse.
* Quick Entry (`docs/ROADMAP.md` §8.8) integration.

## Consequences

### Positive

* One source of truth for account balances; investments never need a second
  balance-impact code path.
* Contributions and payouts appear in the transaction ledger where users
  look for them.
* Contributed/paid-out totals and maturity status cannot drift from the
  underlying records.
* No stored status that can disagree with reality — correcting a mistake is
  always "delete the transaction," never "undo a status."
* `RecurrenceFrequency` reuse means the due-schedule math (including
  month-end clamping) is already tested; extending it added one enum value
  and one test group rather than a parallel implementation.

### Negative / Trade-offs

* **Touches the same highest-risk financial logic ADR-004 flagged.**
  `balanceImpactFor`, `balanceImpactForBefore`, and `totalBalanceImpact` are
  raw interpolated SQL `CASE` blocks, not a Dart `switch` — a missed case
  fails silently (transaction exists, balance doesn't move, no compiler
  error). Dedicated tests (`investment_balance_impact_test.dart`) assert the
  correct sign for both new types.
* **Two more transaction types** the transaction list, Templates, and
  Recurring Transactions forms must render but never let a user create
  manually — investment transactions are created only through the
  investment feature, the same restriction loan transactions already have.
* **Older builds cannot restore newer backups containing investments.** A
  backup with `INVESTMENT_CONTRIBUTION`/`INVESTMENT_PAYOUT` rows is rejected
  by a build that predates them, with an "unrecognised type" message —
  the same known limitation ADR-004 recorded for loans. Investment-free
  backups stay fully compatible, so the envelope version is not bumped.
* Deleting an investment that has a payout, or a recurring instrument with
  any confirmed contribution, must be blocked in favour of archiving — one
  more lifecycle rule to enforce, mirroring ADR-004's loan-repayment guard.

## Alternatives Considered

* **Model as a `financial_accounts` row** (like a credit card's one-to-one
  details table, ADR-005). Rejected: an investment's principal is locked
  away, not a spendable balance driven by the user's own transactions the
  way every other account is — Accounts' whole model doesn't fit.
* **Fold into Loans** (treat contributions/payouts as loan movements).
  Rejected in the original design discussion: Loans' direction split (money
  owed / owed to the user) and free-text counterparty don't describe "locked
  with a bank, earning fixed or periodic interest" without corrupting that
  split and the loan-based net-worth aggregation.
* **Store `MATURED` as a third lifecycle status.** Rejected after the design
  review caught the undo problem it creates (§2) — derive it instead,
  mirroring Loans' own `PAID`/`OVERDUE` derivation.
* **A separate `InvestmentPayoutFrequency`-only date-math implementation**
  instead of extending `RecurrenceFrequency`. Rejected as needless
  duplication of already-tested logic (§3).
* **Interest-rate field for display only, never used in calculation.**
  Considered and explicitly declined by the user (§5) — even a
  purely-informational rate risks being read as authoritative next to real
  money.

## References

* `docs/ROADMAP.md` §9.3 (Investment Tracking)
* `docs/DATA_MODEL.md` §52 (Investment Extensibility — brokerage-shaped,
  explicitly untouched by this ADR)
* `docs/ARCHITECTURE.md` §20 (Recurring Transaction Architecture — "never
  auto-create" rule this ADR's contribution/payout schedules follow)
* `AGENTS.md` §9 (Account Balance Integrity), §14 (Financial Data Rules)
* [ADR-004](004-loan-accounting.md) (Loan Accounting — the precedent this
  ADR restates and departs from, explicitly, in §2, §4, and §6)
* [ADR-005](005-credit-card-accounts.md) (Credit Card Accounts — the
  one-to-one-details-table pattern considered and rejected)
