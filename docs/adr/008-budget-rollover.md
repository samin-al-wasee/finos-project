# ADR-008: Budget Rollover

**Status:** Accepted
**Date:** 2026-08-13

## Context

`docs/ROADMAP.md` §8.3 lists budget rollover as a potential addition to
Advanced Budgets, but flags it deliberately unbuilt: "rollover would change
budget accounting itself and needs a deliberate design decision first."
Budget performance is entirely derived at read time (`docs/DATA_MODEL.md`
§24–§25, §45) — spent, remaining, percentage, and health all come from
summing transactions against a budget's limit on every read, and every
screen renders from the single `BudgetProgress` shape (`docs/ARCHITECTURE.md`
§18). [ADR-007](007-flexible-budget-scope.md) generalized what "spend" means
per budget from a single category to one of four scopes; this ADR builds on
that generalization rather than the original single-category model.

Rollover means a period's own unspent (or overspent) amount changes what the
*next* period's limit effectively is. That is a genuine change to budget
accounting, not a display tweak, and the project's precedent for exactly this
kind of question is already set twice: loan outstanding (ADR-004) and
credit-card available credit (ADR-005) are both derived fresh from the
transaction ledger rather than stored and incrementally updated, specifically
to avoid "two competing sources of truth" (`AGENTS.md` §9).

## Decision

### 1. Rollover is opt-in per budget, off by default

A new `budgets.rollover_enabled` boolean column, defaulting to `false`.
Every existing budget's effective limit is unchanged unless its owner
explicitly turns rollover on. Unlike `category_id`/`period`/`scope_type`,
which are fixed at creation because changing them would reinterpret past
readings of the budget, `rollover_enabled` is editable in place.

### 2. The carried-in amount is derived at read time, not stored

```text
effective_limit(N) = amount_minor + carry_in(N)
carry_in(N)         = effective_limit(N-1) − spent(N-1)     [0 if N-1 doesn't qualify]
```

This follows ADR-004 §3 and ADR-005 §4 directly. `spent(N-1)` is computed
through the scope-aware dispatcher ADR-007 introduced, so rollover applies
uniformly to a `SINGLE_CATEGORY`, `MULTI_CATEGORY`, `UNCATEGORIZED`, or
`WHOLE_ACCOUNT` budget alike — the carry-in algorithm never inspects a
budget's scope itself, only a spend total for a window, so ADR-007's spend
generalization composes with rollover for free.

### 3. The lookback is capped at the same horizon as budget history

The carry-in computation walks backward at most `rolloverLookbackLimit`
periods (currently 6) — deliberately the *same* constant as
`budgetHistoryLength`. Older surplus or deficit is not accumulated past that
horizon. The walk is iterative (oldest eligible period first), stops early
at the budget's own `start_date` exactly as `budgetHistoryProvider` already
does, and returns zero for `BudgetPeriod.custom`.

### 4. Overspend rolls forward as a deficit, unclamped

A period's own remainder — positive or negative — carries into the next
period's effective limit with no floor at zero. This is the conventional
meaning of "rollover" and is the simpler formula: an unclamped running fold,
versus a clamp-at-every-step variant that would also quietly absorb
overspending signal.

### 5. `BudgetProgress.limitMinor` becomes the effective limit

A new `carriedInMinor` field is added; `limitMinor` changes from returning
`budget.amount_minor` directly to `budget.amount_minor + carriedInMinor`.
`remainingMinor`, `usedFraction`, and `health` are untouched.

### 6. History shows each past period's own rollover-adjusted limit

`budgetHistoryProvider` computes each past period's carry-in the same way
the current period's is computed, rather than showing a flatter "no
rollover in history" figure.

## Consequences

### Positive

* Every existing budget's numbers are unchanged until a user opts in.
* No new source of truth for balances/limits.
* Turning rollover off and back on loses nothing and needs no repair.
* No consumer screen needs rollover-aware logic of its own.
* Composes with all four ADR-007 scope types with no special-casing.

### Negative / Trade-offs

* **Bounded lookback, not "since the beginning of time."**
* **Editing a budget's limit is retroactive**, same as it already is for
  history.
* **Archive/restore gaps aren't special-cased.**
* **A deficit can genuinely compound** across several bad periods before the
  cap kicks in. The UI surfaces the carry explicitly rather than folding it
  silently into the displayed limit.

## Alternatives Considered

* **Stored `carryover_minor`, updated incrementally.** Rejected for the same
  reason ADR-005 rejected storing a credit card's available credit.
* **Unbounded backward walk to `start_date`.** Rejected in favour of the
  bounded, history-consistent cap.
* **Positive-only rollover (overspend resets to zero next period).**
  Rejected in favour of the symmetric, unclamped formula.
* **Global always-on rollover for all recurring-period budgets.** Rejected
  in favour of a per-budget opt-in defaulting to off.
* **History shows only "own limit," ignoring rollover.** Rejected — makes
  the current period and its own history disagree about what a period's
  limit was.
* **Restricting rollover to `SINGLE_CATEGORY` budgets only**, leaving
  multi-category/uncategorized/whole-account budgets out of scope for
  rollover. Rejected once the spend lookup was generalized to be
  scope-agnostic (§2 above) — there was no remaining reason to special-case
  or exclude the other three scope types.

## References

* `docs/ROADMAP.md` §8.3 (Advanced Budgets — Budget rollover)
* `docs/DATA_MODEL.md` §22–§25 (Budget, Budget Period, Budget Calculation,
  Budget Status), §45 (Derived Data)
* `docs/ARCHITECTURE.md` §18 (Budget Architecture)
* `AGENTS.md` §9 (Account Balance Integrity)
* [ADR-004](004-loan-accounting.md) (Loan Accounting)
* [ADR-005](005-credit-card-accounts.md) (Credit Card Accounts)
* [ADR-007](007-flexible-budget-scope.md) (Flexible Budget Scope) — the
  scope-aware spend dispatcher this design reuses without modification
