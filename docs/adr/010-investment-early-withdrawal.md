# ADR-010: Investment Early Withdrawal

**Status:** Accepted
**Date:** 2026-08-14

## Context

ADR-009 §7 explicitly named "early encashment or partial withdrawal before
maturity" as deferred scope. The user has now asked for it, as the last of
three fast-follows to investment tracking (the other two — a Dashboard
summary card and a Reports section — already shipped as additive UI/read
paths that touched no derivation logic). This one is different: it changes
what "how much of an investment's principal is still locked" means, which
[ADR-009](009-investment-accounting.md) §4 already built load-bearing logic
around (`isSettled`, and the net-worth asset value). That combination — a
new kind of money movement plus a change to already-fragile derived state —
is exactly the bar `docs/ARCHITECTURE.md` §35 sets for writing an ADR, the
same bar credit cards (ADR-005) and loan relationships (ADR-006) cleared.

Three decisions were confirmed with the user before design:

1. Both **partial and full** early withdrawal are in scope — not full-only.
2. It is recorded as a **new transaction type**, not by overloading
   `INVESTMENT_PAYOUT` with a flag or inferring intent from date — keeping
   ADR-009 §2's "a payout's date decides profit vs. principal" rule intact
   rather than adding a second, competing way to reach the same conclusion.
3. Fully withdrawing an investment's principal early does **not**
   auto-archive it — the investment's `status` stays `ACTIVE` until the user
   explicitly archives it, the same as a fully-paid loan
   (`LoanController.archive` is a separate, optional, reversible action from
   `LoanProgress.isPaid` becoming true).

## Decision

### 1. A third transaction type: `INVESTMENT_WITHDRAWAL`

```text
INVESTMENT_WITHDRAWAL   money entering an account from the investment,
                        returning principal rather than paying profit
```

Direction is the same as `INVESTMENT_PAYOUT` — it credits
`payout_account_id` — but its *meaning* is different: a payout is profit the
instrument has earned; a withdrawal is a return of contributed principal,
early. Keeping them as separate types (rather than one type with a
"withdrawal" flag) means every existing `WHEN type = ...` `CASE` branch that
already handles `INVESTMENT_PAYOUT` (balance impact, report totals, movement
history) needed one parallel branch added, never a change to its existing
logic — the same reasoning ADR-009 §1 gave for not folding investment
movements into loan movements.

Like every investment movement, a withdrawal carries no category (excluded
from spending/budgets) and is never user-creatable directly
(`userCreatableTransactionTypes` stays unchanged) — created only through
`InvestmentController.confirmWithdrawal`.

### 2. Remaining principal is derived, following ADR-009 §2's rule, not a new stored field

```text
withdrawnMinor          = Σ(INVESTMENT_WITHDRAWAL transactions)
remainingPrincipalMinor = contributedMinor − withdrawnMinor, clamped at 0
```

Clamped at zero for the same reason `LoanProgress.outstandingMinor` is: a
withdrawal can never be recorded for more than what's currently derived as
remaining (enforced at write time in `confirmWithdrawal`, mirroring
`LoanController.recordRepayment`'s overpayment rejection), so a negative
value here would mean corrupt data, never a real credit.

`isFullyWithdrawn` (`remainingPrincipalMinor == 0 && contributedMinor > 0`)
is the investment analogue of `LoanProgress.isPaid` — a derived fact, not a
status. Per the user's explicit choice above, reaching it does not touch
`investments.status`; the investment stays `ACTIVE` and fully visible
(due contributions/payouts, if any, are unaffected) until archived by hand.

**Interaction with maturity/settlement (ADR-009 §2, §4).** A withdrawal is
only for *before* maturity — once `isMatured`, the existing
`confirmNextPayout` flow is how the final proceeds are recorded (that is
what `isMaturityPayoutDue`/`isSettled` already model). Allowing withdrawal
after maturity too would give two different mechanisms for returning
principal with no rule for which one is authoritative, so
`InvestmentController.confirmWithdrawal` rejects a matured investment with a
message pointing at the maturity payout flow instead. This does not block a
user from encashing an instrument exactly on its scheduled date — that is
what `confirmNextPayout` is for.

### 3. Net worth: asset value becomes `remainingPrincipalMinor`, not `contributedMinor`

ADR-009 §4's rule — full contributed principal counts as an asset until
settled, never `contributed − payoutReceived` — is refined, not reversed:
`computeNetWorth` now adds `remainingPrincipalMinor` (still gated on
`!isArchived && !isSettled`) instead of `contributedMinor`. For every
investment with no withdrawal (`withdrawnMinor == 0`, true for every
investment that predates this ADR), `remainingPrincipalMinor ==
contributedMinor`, so existing net-worth figures are unchanged. A *periodic*
profit payout still never reduces this value — that rule is untouched; only
a withdrawal (or full maturity settlement, via `isSettled`) does, because
only those two actually return principal.

### 4. Delete guard gains one more blocking movement type

`InvestmentController.delete` (ADR-009 §6) already blocks on any payout, or
(for recurring investments) any confirmed contribution. A withdrawal is
exactly as much "financial history" as a payout — a distinct, explicitly
confirmed action recording real money movement — so it blocks deletion the
same way a payout does, regardless of contribution mode.

### 5. UI: an on-demand "Withdraw" action, not a due-schedule card

Unlike a contribution installment or a periodic payout, a withdrawal has no
schedule — it's not something that becomes "due." It is surfaced as a menu
action on the investment details screen (`_InvestmentMenu`), shown only
while the investment is active, not matured, and has remaining principal
greater than zero, opening a new `InvestmentWithdrawalDialog` that mirrors
`InvestmentPayoutDialog`'s shape (amount + date) but validates the amount
against `remainingPrincipalMinor` rather than only requiring it be positive
— the same cap `RepaymentDialog` already applies via
`LoanProgress.maxRepaymentMinor` for a loan.

### 6. Reports' "Investment Activity" section gains a third figure

The section shipped as a Reports-integration fast-follow (docs/ROADMAP.md
§8.4) already sums contribution/payout per investment per period
(`TransactionDao.investmentTotalsByInvestment`). A withdrawal is exactly as
reportable as a payout — real money leaving the investment this period — so
the same grouped query gains a third summed column, and the report row
shows "Withdrawn" alongside "Contributed"/"Payout" whenever it's nonzero,
with no change to the row's existing layout logic beyond the extra line.

## Consequences

### Positive

* No new stored lifecycle state — extends ADR-009 §2's derive-don't-store
  rule to "how much principal is left" instead of introducing a competing
  source of truth.
* Existing investments (no withdrawals ever recorded) get byte-identical
  net-worth and settlement behavior — `withdrawnMinor` defaults to 0 for
  every one of them.
* A withdrawal is financial history exactly like a payout: it appears in the
  transaction ledger, blocks deletion, and is reportable — no special-cased
  "this movement doesn't count" path anywhere.

### Negative / Trade-offs

* **A third raw-SQL `CASE` branch** in `balanceImpactFor`,
  `balanceImpactForBefore`, and `totalBalanceImpact` — the same
  missed-case-fails-silently risk ADR-009's Consequences section already
  flagged for the first two investment types. Extended
  `investment_balance_impact_test.dart` coverage asserts the correct sign
  for the new type in all three queries.
* **Older builds cannot restore a backup containing `INVESTMENT_WITHDRAWAL`
  rows** — the same known, accepted limitation ADR-004 and ADR-009 recorded
  for their own new transaction types. Withdrawal-free backups are
  unaffected, so the envelope version is not bumped.
* One more transaction type the transaction list, Templates, and Recurring
  Transactions forms must render but never let a user create manually — the
  same restriction already applied to every investment/loan movement type.

## Alternatives Considered

* **Reuse `INVESTMENT_PAYOUT` with a flag, or infer "principal vs. profit"
  from whether the date is before maturity.** Rejected per the user's
  explicit choice: this would blur ADR-009 §2's rule that a payout's date
  relative to maturity is what decides profit-vs-principal, adding a second,
  competing way to reach that conclusion (an explicit flag) with no rule for
  which wins if they disagree.
* **Store a "closed early on date X" field on the investment row.** Rejected
  for the identical reason ADR-009 §2 rejected a stored `MATURED` status: no
  undo path if recorded by mistake. `remainingPrincipalMinor` is derived, so
  correcting a mistaken withdrawal is deleting its transaction — never
  undoing a status.
* **Full early encashment only, no partial withdrawal.** Rejected per the
  user's explicit choice — a partial withdrawal is meaningfully different
  from closing the instrument out, and the derived-remaining-principal model
  handles both with no extra branching (the full case is simply the one
  where `amountMinor == remainingPrincipalMinor`).
* **Auto-archive once `isFullyWithdrawn`.** Rejected per the user's explicit
  choice, mirroring how a fully-paid loan does not auto-archive — archiving
  is a distinct, reversible user action from the investment having nothing
  left to track.

## References

* `docs/ROADMAP.md` §9.3 (Investment Tracking)
* [ADR-009](009-investment-accounting.md) (Investment Accounting — the
  decision this ADR extends, in §2 for derivation, §4 for net worth, and §6
  for the delete guard)
* [ADR-004](004-loan-accounting.md) (Loan Accounting — `LoanProgress`'s
  `outstandingMinor`/`isPaid`/`maxRepaymentMinor` and
  `LoanController.recordRepayment`'s overpayment rejection, the precedent
  this ADR's `remainingPrincipalMinor`/`isFullyWithdrawn`/`confirmWithdrawal`
  mirror)
* `docs/ARCHITECTURE.md` §35 (Architecture Decision Records — the threshold
  this feature clears)
