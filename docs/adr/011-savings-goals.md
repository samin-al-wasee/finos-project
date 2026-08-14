# ADR-011: Savings Goals

**Status:** Accepted
**Date:** 2026-08-14

## Context

`docs/ROADMAP.md` §9.2 sketches Savings Goals as a Phase 3 feature: a user
creates a goal (Emergency Fund, New Laptop, Travel, Car, House, Education),
each with a target amount, a current amount, an optional deadline, and a
derived progress. Nothing exists for this yet — no schema, no ADR reference,
no code (confirmed by a full search of `docs/DATA_MODEL.md`,
`docs/ARCHITECTURE.md`, and `docs/adr/*.md`).

This needs the same design decision Loans (ADR-004) and Investments (ADR-009)
both had to make explicit before implementation: **how does a new
money-tracking entity's "current amount" relate to the transactions table
that is the single source of truth for balances** (`AGENTS.md` §9)? Two
shapes were available:

* **A view over an existing account's balance** — a goal just labels a
  portion of, or points at, an account the user already tracks (e.g. "House
  Fund" pointing at a dedicated savings account); progress is that account's
  live balance. This needs no new transaction type, and must contribute
  **nothing** to Net Worth — the account's own balance already counts that
  money once (`computeNetWorth`, `lib/features/net_worth/domain/net_worth_data.dart`).
  This is the same shape Budgets already uses: a lens over transactions that
  exist for other reasons, not a balance-sheet entry of its own.
* **A standalone entity with its own contributions/withdrawals** — the same
  shape Loans and Investments use: a new table, a new transaction type (or
  types) with a nullable FK, and a derived progress figure. Money
  contributed genuinely leaves the linked account's spendable balance (the
  same way an `INVESTMENT_CONTRIBUTION` debits its source account), so the
  goal becomes its own Net Worth asset line.

The user was asked directly and chose the **standalone, Investments-style**
shape.

## Decision

### 1. A new `savings_goals` table, and two new transaction types

```text
savings_goals
  id
  name
  target_amount_minor   (> 0)
  currency
  account_id            (references FinancialAccounts — contributions debit
                          this account, withdrawals credit it back)
  start_date
  deadline_date          (nullable — not every goal has one)
  description
  status                 (ACTIVE | ARCHIVED)
  created_at
  updated_at
```

```text
SAVINGS_CONTRIBUTION   money leaving the linked account into the goal
SAVINGS_WITHDRAWAL     money entering the linked account from the goal
```

This is the same pattern ADR-004 and ADR-009 both establish: the goal record
holds the agreement, and money moving is recorded as ordinary rows in
`transactions` via a nullable `savings_goal_id`, carrying no category (so a
goal contribution can never enter spending-by-category or budget
consumption, the same rule loan and investment movements already follow).

**One account field, not two.** Unlike Investments' `sourceAccountId` /
`payoutAccountId` (which can genuinely differ — an FDR's payout can land in
a different account than the one that funded it, because it is a separate
financial product), a Savings Goal is money set aside from the user's own
accounts for the user's own purpose. There is no reason contribution and
withdrawal would routinely use different accounts, so a single `accountId`
is used for both directions — a deliberate simplification, not a
limitation carried over from a more complex feature this one doesn't need.

### 2. No contribution/withdrawal schedule — every movement is on-demand

Unlike Investments (which models DPS's recurring monthly contributions and
Sanchayapatra's periodic payouts), a Savings Goal has no schedule at all.
Contributions and withdrawals are recorded on demand, exactly the way a
loan's repayments are (`LoanController.recordRepayment`) — there is no
`next_contribution_due` field, no `RecurrenceFrequency`, and no "due"
card on the details screen. This is a deliberate scope reduction: nothing
in the roadmap sketch or the user's own framing described a goal as
following a savings schedule, and Loans already proves that "on-demand
movements against a running total" doesn't need one.

### 3. Progress is derived, never stored — same rule as ADR-004 §4/ADR-009 §2

```text
contributed        = Σ(contribution transactions for the goal)
withdrawn           = Σ(withdrawal transactions for the goal)
current amount      = max(0, contributed − withdrawn)
progress fraction   = min(1.0, current amount / target amount)
is achieved         = current amount >= target amount
is overdue          = deadline_date is set AND NOT is achieved AND
                      deadline_date has passed
net worth value     = current amount (while not archived)
```

`current amount` is clamped at zero for the same reason
`LoanProgress.outstandingMinor` is: a withdrawal can never be recorded for
more than what's currently derived as saved (enforced at write time, the
same overpayment-rejection pattern `LoanController.recordRepayment` and
`InvestmentController.confirmWithdrawal` both use), so a negative value
here would mean corrupt data, never a real deficit.

**Reaching the target does not archive the goal, and does not stop
contributions.** `is achieved` is a derived fact exactly like
`LoanProgress.isPaid` — the same precedent this ADR leans on throughout:
archiving is a distinct, reversible user action, never an automatic side
effect of a derived figure crossing a threshold (this mirrors the explicit
choice already made for investment withdrawal, ADR-010). Unlike a loan
repayment (capped at the outstanding balance) or an investment withdrawal
(capped at the remaining principal), a **contribution has no upper cap** —
saving beyond the target is completely ordinary (a buffer, or rounding up),
so only withdrawals are capped, at `current amount`.

### 4. Net Worth: the goal's current amount is a new asset line

Because contributing to a goal genuinely debits the linked account
(the same way an investment contribution does), `computeNetWorth` gains a
fourth loop: every non-archived goal's `currentAmountMinor` is added as an
asset. This is safe from the double-counting risk the Context section
raised precisely because the money already left the linked account's
balance — the same reasoning ADR-009 §4 gives for why an investment's
principal is a separate asset line rather than still being inside any
account's balance.

### 5. Delete guard: any movement blocks deletion — no automatic-origination exception

Unlike Loans and Investments, creating a Savings Goal never inserts a
transaction (§2 — every movement is on-demand), so there is no "automatic
origination" movement that should be exempt from the delete guard the way
ADR-004 §6/ADR-009 §6 both carve out. The rule here is simpler: deletion is
blocked by the existence of **any** contribution or withdrawal at all;
archiving is the correct way to retire a goal with history
(`docs/DATA_MODEL.md` §47).

## Consequences

### Positive

* No new stored lifecycle state beyond `ACTIVE`/`ARCHIVED` — `current
  amount`, `is achieved`, and `is overdue` are all derived, so they can
  never disagree with the contributions/withdrawals behind them.
* Reuses Loans' simpler on-demand-movement shape rather than Investments'
  schedule machinery, which this feature has no use for — no
  `RecurrenceFrequency`/`due_occurrences` dependency at all.
* A goal's linked account correctly reflects less spendable balance the
  moment money is set aside, and Net Worth correctly shows that same money
  as a distinct asset — no double-counting.

### Negative / Trade-offs

* **A third domain now touches the highest-risk raw-SQL `CASE` blocks**
  (`balanceImpactFor`, `balanceImpactForBefore`, `totalBalanceImpact`) —
  the same missed-case-fails-silently risk ADR-009's Consequences section
  already flagged twice. Dedicated balance-impact tests assert the correct
  sign for both new types, the same coverage loans and investments have.
* **Older builds cannot restore a backup containing `SAVINGS_CONTRIBUTION`/
  `SAVINGS_WITHDRAWAL` rows or a `savings_goals` table** — the same known,
  accepted limitation ADR-004/ADR-009/ADR-010 recorded for their own
  additions. Goal-free backups are unaffected, so the envelope version is
  not bumped.
* One more transaction type pair the transaction list, Templates, and
  Recurring Transactions forms must render but never let a user create
  manually — the same restriction already applied to every loan/investment
  movement type.
* A single `accountId` field means a goal cannot model "I contribute from
  my salary account but withdraw into my spending account" — accepted as
  an intentional simplification (§1), reconsiderable later if a real need
  for it shows up.

## Alternatives Considered

* **A view over an existing account's balance, Budgets-shaped.** This was
  the other option put to the user and explicitly not chosen. It would need
  no new transaction type and no Net Worth change, but a goal would then be
  indistinguishable from "an account with a label," and multiple goals could
  not share one account without ambiguity about which goal a given balance
  belongs to.
* **Reuse `INVESTMENT_CONTRIBUTION`/`INVESTMENT_PAYOUT` with a `savings_goal_id`
  instead of `investment_id`.** Rejected: a goal is not an investment
  product (no maturity, no profit, no instrument type), and overloading the
  investments table/types would force every investment-specific concept
  (maturity date, payout frequency, settlement) to become nullable/optional
  for a shape that never needs them — the same "don't force a genuinely new
  domain shape into an existing table" reasoning ADR-009 itself gives for
  not folding into Loans.
* **A contribution/withdrawal schedule, mirroring Investments' DPS
  recurring contributions.** Rejected as unrequested scope — nothing in
  the roadmap sketch describes a goal as following a schedule, and Loans
  already proves on-demand movements against a running total don't need
  one (§2).
* **Two account fields (source/destination), mirroring Investments.**
  Rejected per the user's own framing of a goal as money set aside from
  the user's own accounts, not a separate financial product with its own
  payout relationship (§1).

## References

* `docs/ROADMAP.md` §9.2 (Savings Goals)
* [ADR-004](004-loan-accounting.md) (Loan Accounting — the on-demand
  repayment pattern, `outstandingMinor`/`isPaid`/`maxRepaymentMinor`, and
  the delete guard this ADR's contribution/withdrawal model and delete rule
  are built on)
* [ADR-009](009-investment-accounting.md) (Investment Accounting — the
  transactions-table-as-source-of-truth pattern and the Net Worth
  double-counting reasoning this ADR extends to a fourth entity)
* [ADR-010](010-investment-early-withdrawal.md) (Investment Early
  Withdrawal — the "reaching zero/target doesn't auto-archive" precedent
  this ADR follows for `is achieved`)
* `docs/ARCHITECTURE.md` §35 (Architecture Decision Records — the threshold
  this feature clears)
