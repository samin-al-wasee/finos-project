# ADR-006: Loan Relationships

**Status:** Accepted
**Date:** 2026-08-13

## Context

`docs/ROADMAP.md` §8.7 ("Loan Relationships") and `docs/DATA_MODEL.md` §29 both
flag the same gap: every loan is an independent row, with no way to represent
that lending or borrowing with the same person is often a continuing
relationship rather than a series of unrelated events — a partial repayment
followed by another advance. Two entry points are requested: extending an
existing loan from its detail screen, and, on creating a new loan, optionally
linking it to an existing counterparty/loan instead of starting a disconnected
record.

This cannot be designed without deciding what a "loan" identifies once two
rows can describe the same relationship, because ADR-004 built every
outstanding-balance and status derivation — `outstanding = principal −
Σ(repayments)`, `PAID`/`OVERDUE` derived at read time — around one loan being
one row. The roadmap's own note is the crux: does that derivation now operate
per-row or per-group?

`AGENTS.md` §9 forbids multiple competing sources of truth for balances;
§34 forbids scope beyond what is authorized. `name` on `loans` is free text
with no dedup or autocomplete, and no `Counterparty` entity exists anywhere in
the schema.

## Decision

### 1. An extension is a new row, not a mutation of an existing one

Extending a loan creates a brand-new `Loans` row — its own principal, its own
`start_date`, its own optional origination transaction — rather than adding to
`principal_minor` on the row being extended. This is the same reasoning
ADR-004 already applied to repayments: recording a repayment as its own
transaction, rather than decrementing a stored `outstanding_amount`, is what
keeps the history of *when* each movement happened. Mutating principal on
extension would repeat exactly the mistake ADR-004 avoided on the repayment
side, just on the origination side instead.

Because an extension is fully a new loan, it reuses `LoanController.create()`
verbatim, including its atomic loan-plus-origination-transaction write. No new
transaction type is introduced: extensions move money exactly the way an
ordinary loan's origination does (`LOAN_RECEIPT`/`LOAN_PAYMENT`), because that
is what they are.

### 2. Relationships are a flat, self-referencing `group_id`, not a parent chain

`loans.group_id` is a nullable column referencing `loans.id`. When a loan is
linked to a relationship, `group_id` holds the id of that relationship's
*root* loan — the first one created — never the id of whichever specific row
it was directly extended from. Extending an already-extended loan resolves to
the same root (`groupId = parent.groupId ?? parent.id`), so a relationship of
any length is always exactly one level deep.

This directly answers the roadmap's callout question: **outstanding and
status stay entirely per-row**, computed by the unmodified ADR-004 rules.
Nothing about `LoanProgress`, the overpayment check, or the derived
`PAID`/`OVERDUE` states changes. A *group*'s outstanding, principal, and
standing are new, purely derived, read-time aggregates (`LoanGroup`) that sum
or roll up the per-row values of a relationship's active members — they are
never stored and never feed back into a row's own figures.

A flat shared id was chosen over a parent-chain (`parent_loan_id` pointing to
the immediately-extended-from row) because every group query — "all loans in
this relationship" — becomes `WHERE id = :root OR group_id = :root`, with no
recursion. A chain would need recursive traversal for the same answer, for no
benefit: the order within a relationship is already fully recoverable from
each row's own `start_date`, so nothing is lost by not also storing which
specific row an extension continued from.

### 3. Repayments keep targeting exactly one row

`LoanController.recordRepayment()` is unchanged: it still records a repayment
against one specific loan id, exactly as before. A relationship's combined
outstanding is a read-time sum across rows, but a single transaction still
reduces a single row's own balance — automatically splitting or reallocating
one repayment across multiple rows in a group is not built, and is not
required by anything the roadmap asks for.

### 4. Extending or linking requires matching direction and currency

An extension must share its parent's `LoanDirection` and `currency`, both
checked in `create()`. A relationship cannot flip from a receivable to a
liability, and mixed-currency aggregation is out of scope — this app does not
convert currencies anywhere else, and a group's combined outstanding would be
meaningless across currencies.

### 5. "Merge on creation" reuses the same mechanism, no Counterparty entity

The create form gains a picker listing existing **active** loans of the
selected direction; picking one calls the same `create(..., extendsLoanId:
...)` path as an explicit extension. No `Counterparty`/`Contact` table is
introduced: `name` stays free text exactly as it is today. Building real
identity resolution — fuzzy matching, a backing entity, migrating existing
loans onto it — is materially larger than what the roadmap asks for and is
deferred; a direction-filtered picker over the existing (typically short)
loans list gives the same practical outcome for V1.

### 6. Deleting a relationship's root is blocked while it has linked children

`LoanController.delete()` gains a guard, parallel to its existing
repayments guard: deleting a loan that other rows still point to via
`group_id` is refused, with archiving offered as the retirement path — the
same treatment ADR-004 already gives a loan with repayments.

## Consequences

### Positive

* Per-row correctness (outstanding, status, overpayment rejection, the
  repayments-guard on delete) is completely unchanged — every existing test
  and every existing invariant from ADR-004 keeps holding with zero
  modification.
* One new nullable, self-referencing column is the entire schema cost; no new
  table, no new transaction type, no change to balance or budget SQL.
* Extending and merge-on-creation are the same code path entered from two
  screens, rather than two parallel implementations that could drift apart.
* A relationship of any length stays a flat, single-query lookup — no
  recursive CTEs anywhere in the loans feature.
* A backup made before this change restores unchanged (every `group_id` is
  simply absent/null); a backup made after this change still restores on an
  older build, minus the linkage information, the same graceful degradation
  ADR-004 already accepted for loans in general.

### Negative / Trade-offs

* **A relationship's combined figures are pure aggregation, not a stored
  fact.** Every screen that shows a group total recomputes it from its
  members' `LoanProgress` on every read; this is deliberate (single source of
  truth) but means the loans list must group in memory rather than querying a
  pre-aggregated total.
* **No automatic repayment allocation across a group.** A repayment still
  targets one specific row; if a user wants to "just pay off the
  relationship," they must pick which underlying loan the payment reduces (a
  cross-row waterfall allocation is not built).
* **No Counterparty entity**, so nothing prevents two genuinely different
  people named "John" from being offered as merge candidates, or a single
  person's name drifting between rows in the same group if it's edited on one
  row and not another (each row's `name` stays independently editable via the
  existing `update()`). This is an accepted V1 limitation, not a data
  integrity issue — it only affects display/selection, never money.
* **`BackupService.restore()` must order loans within a batch.** Because
  `group_id` is a same-table foreign key, a naive insert order could place a
  child row before its root and fail the FK check; the restore path must sort
  root-first before its batch insert (a one-level partition, since groups are
  flat).
* Deleting a relationship's root while it still has linked children is one
  more lifecycle rule to enforce and test, alongside the existing
  repayments-guard.

## Alternatives Considered

* **More principal on the same row.** Rejected for repeating, on the
  origination side, exactly the loss-of-history problem ADR-004 already
  avoided on the repayment side.
* **A self-referencing `parent_loan_id` chain**, linking each extension to the
  specific row it continued from. Preserves slightly more lineage detail, but
  every group-wide read needs recursive traversal instead of a flat `WHERE`,
  for information (which exact row was extended) already recoverable from
  `start_date` ordering.
* **A new `LOAN_TOPUP` transaction type.** Would keep "extension" visible as
  a distinct transaction kind, but the origination movement of an extension
  is, functionally, identical to an ordinary loan's origination
  (`LOAN_RECEIPT`/`LOAN_PAYMENT`) — a new type would duplicate
  `originationTypeFor`'s direction logic for no behavioural difference.
* **A dedicated `Counterparty`/`Contact` table**, with loans referencing it
  and `name` retired. Solves identity resolution properly, but is a
  substantially larger change (a new entity, a backfill migration for every
  existing free-text loan, new CRUD/UI) than the roadmap's two requested entry
  points call for; deferred until a real need for cross-feature identity
  (e.g., shared with a future contacts/People feature) emerges.
* **Cross-row automatic repayment allocation** (a repayment against a group
  splits across its member rows, oldest-first). Would make "pay down the
  relationship" a one-step action, but requires a transaction to affect more
  than one loan id, which conflicts with `transactions.loan_id` being a
  single nullable reference, and adds an allocation policy the roadmap does
  not ask for.

## References

* `docs/ROADMAP.md` §8.7 (Loan Relationships)
* `docs/DATA_MODEL.md` §29 (Loan), §32–§33 (Loan Data Model, Loan Status),
  §36 (Loan Repayment Integrity), §45 (Derived Data), §47 (Deletion)
* `docs/ARCHITECTURE.md` §19 (Loan Architecture)
* `docs/UI_DESIGN.md` §21–§22 (Loan Screen, Loan Details)
* `AGENTS.md` §9 (Account Balance Integrity), §10 (Loan Integrity), §34
  (Future Features)
* [ADR-004](004-loan-accounting.md) (Loan Accounting) — the direct precedent
  for per-row derivation and for reusing a one-to-one-shaped structural
  pattern rather than a nullable-column shortcut
* [ADR-005](005-credit-card-accounts.md) (Credit Card Accounts) — the most
  recent precedent for deriving-not-storing aggregate figures at read time
