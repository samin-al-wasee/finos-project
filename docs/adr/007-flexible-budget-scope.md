# ADR-007: Flexible Budget Scope

**Status:** Accepted
**Date:** 2026-08-13

## Context

`docs/DATA_MODEL.md` §22 requires exactly one expense category per budget, a
deliberate V1 boundary tracked in `docs/ROADMAP.md` §8.3 ("Flexible budget
scope") and `docs/REQUIREMENTS.md` FR-04. Users want three shapes V1 cannot
express: a limit shared across several categories, a catch-all limit for
uncategorised spending, and a limit tied to no category at all.

`category_id` today is a required scalar foreign key, and the one invariant
every budget screen depends on — `docs/ARCHITECTURE.md` §18's "avoid
duplicating budget calculations," delivered by every screen watching
`BudgetProgress`/`budgetProgressProvider` — currently rests on a simpler fact
than it needs to: that a category has at most one active budget per period.
Once a budget's scope can be a *set* of categories, "no category," or
"every category," that fact has to become a set-overlap rule instead of an
equality check, or the same expense could move two competing budgets' bars
at once — exactly what the roadmap calls out as the risk to preserve against.

The roadmap leaves one question open before implementation can start: can a
category sit inside a multi-category budget while also carrying its own
single-category budget in the same period? Answering it decides the shape of
the overlap check below.

## Decision

### 1. Category exclusivity generalises to a set-overlap rule, uniformly

No category may be claimed by two active budgets in the same `period` value.
This was already true for the one-category case; it is now enforced as
disjointness between each pair of active budgets' resolved category sets,
with no special-casing per scope-type pair. A category cannot belong to a
multi-category budget while also carrying its own single-category budget in
the same period — that scenario is a genuine overlap (their sets intersect),
not a distinct, allowed relationship. `WHOLE_ACCOUNT`'s set is "everything,"
so it overlaps with any other budget in the same period value; two budgets
that both need to run alongside a whole-account ceiling must use a different
`period` value from it. `UNCATEGORIZED`'s set is the single "no category"
bucket, disjoint from every concrete category and from nothing else. This
keeps the invariant to one rule — set intersection — rather than four
scope types' worth of pairwise exceptions.

### 2. Scope is a `scope_type` enum plus a join table, not nullable flags

`budgets.scope_type` is one of `SINGLE_CATEGORY` / `MULTI_CATEGORY` /
`UNCATEGORIZED` / `WHOLE_ACCOUNT`. `budgets.category_id` becomes nullable and
keeps its existing meaning for `SINGLE_CATEGORY`; it is `NULL` for the other
three. A new `budget_categories(budget_id, category_id)` table holds a
`MULTI_CATEGORY` budget's member categories (≥ 2 rows) and is never touched
by any other scope type. A boolean-flags alternative can represent invalid
combinations the type system never catches; the enum cannot.

### 3. Spend is still derived at read time, generalised by IN/IS NULL/no-filter

`TransactionDao.expenseTotalForCategory` is joined by
`expenseTotalForCategories` (`category_id IN (...)`),
`expenseTotalUncategorized` (`category_id IS NULL`), and `expenseTotalAll`
(no category filter) — the same `SUM(amount_minor) WHERE type = EXPENSE AND
date IN [from, to)` shape every existing budget/report query already uses,
never cached, so `BudgetProgress` can never disagree with the transactions
behind it (mirrors ADR-004 §3 and ADR-005 §4).

### 4. `BudgetProgress` carries a resolved scope, not a single category

`BudgetProgress.category: CategoryRow` becomes `scope: BudgetScope` plus
`categories: List<CategoryRow>` (0, 1, or many, depending on scope). Its
derived getters — `limitMinor`, `remainingMinor`, `usedFraction`, `health`,
`isExceeded` — read only `budget.amountMinor` and `spentMinor` and are
untouched by this change, which is why the reports' Budget Performance
section and the dashboard's budget summary need no changes at all.

### 5. Existing budgets need no data migration, only a schema one

Every pre-existing budget becomes `SINGLE_CATEGORY` via `scope_type`'s column
default the moment the column exists; `category_id` is untouched. Nothing is
ever written into `budget_categories` for it. The only real migration cost is
structural: relaxing `category_id` from `NOT NULL` to nullable has no `ALTER
COLUMN` in SQLite, so it is done via `Migrator.alterTable` (a `TableMigration`
rebuild) — the first migration step in this codebase to rebuild a table
rather than only create one or add a column to it.

### 6. Scope is fixed at creation, exactly like category is today

Editing a budget cannot change its scope type or member categories — the
existing "category is immutable after creation, archive and recreate
instead" rule (§22) extends unchanged to scope, for the same reason and the
same precedent ADR-005 §5 sets for a credit card's account type.

## Consequences

### Positive

* One overlap rule (set intersection) covers all four scope types.
* Existing single-category budgets migrate with zero data rewriting.
* Spend computation stays derive-at-read-time for every scope type.
* Reports and the dashboard need no code changes.

### Negative / Trade-offs

* **A `WHOLE_ACCOUNT` budget excludes every other budget in its period
  value.** Direct consequence of resolving the roadmap's open question
  uniformly.
* **The `budgets` table rebuild has no self-healing safety net.** An app
  killed mid-rebuild is an accepted, if unlikely, residual risk.
* **Backup compatibility is asymmetric**, the same shape ADR-004 accepted
  for loans. A backup containing a non-`SINGLE_CATEGORY` budget cannot be
  restored by a build that predates this feature; single-category-only
  backups remain fully compatible, so the envelope version is not bumped.
* **A multi-category budget's member set is fixed at creation.**
* `docs/DATA_MODEL.md` §22 and `docs/REQUIREMENTS.md` FR-04 both describe the
  one-category-per-budget rule as current V1 fact; both need updating.

## Alternatives Considered

* **Allow a category to belong to both a multi-category budget and its own
  single-category budget in the same period.** Rejected: this is precisely
  the "two competing active budgets" scenario the roadmap warns against.
* **Nullable boolean flags instead of a `scope_type` enum.** Rejected: lets
  invalid combinations exist at the schema level.
* **A separate `budget_categories`-style row for every scope, including
  single-category ones.** Rejected in favour of leaving `SINGLE_CATEGORY` on
  the column it already uses (avoids a data migration).
* **Storing a budget's spend/remaining on the row and updating it per
  transaction.** Rejected for the same reason ADR-005 rejected it for a
  credit card's cycle figures and ADR-004 rejected it for loan outstanding.

## References

* `docs/REQUIREMENTS.md` FR-04 (Budget Management)
* `docs/ROADMAP.md` §8.3 (Advanced Budgets — "Flexible budget scope")
* `docs/DATA_MODEL.md` §22–§25 (Budget, Budget Period, Budget Calculation,
  Budget Status), §45 (Derived Data)
* `docs/ARCHITECTURE.md` §18 (Budget Architecture)
* `AGENTS.md` §9 (Account Balance Integrity)
* [ADR-004](004-loan-accounting.md) (Loan Accounting)
* [ADR-005](005-credit-card-accounts.md) (Credit Card Accounts)
* [ADR-006](006-loan-relationships.md) (Loan Relationships) — the immediately
  preceding ADR in this codebase's numbering
