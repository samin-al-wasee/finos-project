# ADR-004: Loan Accounting

**Status:** Accepted
**Date:** 2026-08-10

## Context

Loan management (`docs/REQUIREMENTS.md` FR-06, `docs/ROADMAP.md` §6.6) is the last
unimplemented Phase 1 feature. It must support money **lent** (a receivable) and
money **borrowed** (a liability), record repayments, and maintain an outstanding
balance.

Unlike every feature built so far, loans move money that is already modelled
elsewhere. Lending ৳20,000 to a friend takes ৳20,000 out of a real account;
repaying a bank loan takes money out too. So the feature cannot be designed
without deciding how it interacts with account balances — and the project's own
documents point in two directions:

* `docs/DATA_MODEL.md` §34, §37, §38 model `LoanRepayment` as its own entity
  referencing `FinancialAccount` directly, parallel to `Transaction`. That implies
  loans are a separate subsystem and account balance becomes a sum over two
  tables.
* `AGENTS.md` §9 requires balances to stay consistent with transactions and
  forbids "multiple competing sources of truth for balances without an explicit
  architectural decision."

`AGENTS.md` §10 adds two constraints: lent and borrowed must stay distinguishable,
and loan principal must not be treated as ordinary income or expense.

That last point is the key financial insight. None of these movements is income or
expense:

```text
Lend 20,000        cash 20,000 ↓   receivable 20,000 ↑   net worth unchanged
Repayment received cash  5,000 ↑   receivable  5,000 ↓   net worth unchanged
Borrow 100,000     cash 100,000 ↑  liability 100,000 ↑   net worth unchanged
Repayment paid     cash 10,000 ↓   liability 10,000 ↓    net worth unchanged
```

They are balance-sheet movements — the same character as a transfer (§17), which
already must not inflate income, expenses, or budgets.

## Decision

### 1. Loan money movements are transactions

A new `loans` table holds the loan itself. The **cash movements** are recorded in
the existing `transactions` table via two new transaction types and a nullable
`loan_id`:

```text
LOAN_RECEIPT   money entering an account because of a loan
LOAN_PAYMENT   money leaving an account because of a loan
```

The transactions table therefore remains the single source of truth for account
balances, satisfying `AGENTS.md` §9. Loan movements also become visible in the
transaction history, which answers "why did my balance drop on the 5th?".

Direction is intrinsic to the type rather than derived by joining to the loan, so
balance queries stay a flat `CASE` with no correlated subquery:

| Loan type | Origination | Repayment |
| --- | --- | --- |
| `LENT` | `LOAN_PAYMENT` (cash out) | `LOAN_RECEIPT` (cash in) |
| `BORROWED` | `LOAN_RECEIPT` (cash in) | `LOAN_PAYMENT` (cash out) |

Because origination and repayment always sit on opposite sides for a given loan,
repayments are identifiable without an extra flag: for a `LENT` loan they are its
`LOAN_RECEIPT` rows, and for a `BORROWED` loan its `LOAN_PAYMENT` rows.

Like transfers, loan transactions carry **no category**, so they cannot enter
spending-by-category or budget consumption.

### 2. Disbursement is optional

`loans.disbursement_account_id` is nullable:

* **Set** — the loan is being made now. Creating it also creates the origination
  transaction, atomically, so the cash movement is recorded.
* **Null** — the loan pre-dates FinOS (an existing bank loan). No transaction is
  created; the loan is opening state, exactly as an account's opening balance is
  (§9).

Without this, a loan made today would leave the user's cash balance overstated
until they recorded the movement by hand.

### 3. Outstanding is derived, never stored

```text
outstanding = principal − Σ(repayment transactions for the loan)
```

`docs/DATA_MODEL.md` §32 lists `outstanding_amount` as a field, but §45 lists
"Loan outstanding amount" as derived data, and derived-not-duplicated is already
how balances and budget consumption work. Deriving it makes it impossible for the
outstanding amount to disagree with the repayments behind it.

### 4. Status is partly derived

Stored: `ACTIVE` / `ARCHIVED` — lifecycle only.
Derived: `PAID` when outstanding reaches zero; `OVERDUE` when the due date has
passed and outstanding remains. This follows §33's own note that some states may
be derived, and mirrors how budget health is derived (§25).

### 5. Overpayment is rejected

A repayment may not exceed the outstanding balance (§36). Interest and fees are
not modelled in V1 — FR-06 does not list them — so a loan's total repayable amount
is exactly its principal.

### 6. Loans stay out of income, expenses, and budgets

`LOAN_RECEIPT` and `LOAN_PAYMENT` are excluded from income totals, expense totals,
net cash flow, spending-by-category, and budget consumption. They **do** affect
account balances.

One consequence needs care: loan movements do *not* net to zero across accounts
the way transfers do, because the counterparty is outside the app. The
whole-portfolio balance calculation must therefore be extended to include them,
not just the per-account one.

## Consequences

### Positive

* One source of truth for account balances; no balance query has to consult two
  tables.
* Repayments appear in the transaction ledger where users look for them.
* Outstanding and status cannot drift from the underlying records.
* Deriving direction from the transaction type keeps balance SQL flat and cheap.
* Both a loan taken years ago and one made today are representable, correctly.

### Negative / Trade-offs

* **Deviates from `docs/DATA_MODEL.md`.** §34/§37/§38 describe a standalone
  `LoanRepayment` entity; there is no such table under this decision. §12 lists
  three transaction types; there will be five. §32 lists `outstanding_amount` as
  stored. All three sections must be updated when this is implemented.
* **Touches tested financial logic.** `balanceImpactFor` and `totalBalanceImpact`
  must both learn the new types. This is the highest-risk part of the change and
  needs tests proving loans neither leak into income/expense totals nor get lost
  from balances.
* **Two more transaction types** means the transaction list and form must handle
  rows they cannot create manually — loan transactions are created only through
  the loan feature, and editing one directly would let outstanding diverge from
  the loan.
* **Older builds cannot restore newer backups containing loans.** A backup with
  `LOAN_RECEIPT` rows is rejected by a build that predates them, with an
  "unrecognised type" message. Loan-free backups stay fully compatible, so the
  envelope version is not bumped; this is recorded as a known limitation.
* Deleting a loan that has repayment transactions must be blocked in favour of
  archiving (§47), which is one more lifecycle rule to enforce.

## Alternatives Considered

* **Standalone `loan_repayments` table** (as §37/§38 draw it). Matches the
  documented model, but makes account balance a sum over two tables — a second
  source of balance impact, which `AGENTS.md` §9 warns against. Repayments would
  also be invisible in the transaction history.
* **Loans with no balance impact at all.** Smallest change and zero risk to
  existing balance code, but a repayment would not reduce the user's bank balance;
  they would maintain the loan and the cash movement as two records that drift
  apart. Rejected as financially misleading.
* **Loans as transfer counterparties** (a transfer whose other side is a loan
  rather than an account). Conceptually elegant — a loan is effectively an asset or
  liability account — but requires transactions to have polymorphic endpoints, a
  much larger schema change than adding two enum values. Worth revisiting if
  Phase 3 net-worth work turns loans into first-class accounts.
* **One `LOAN_REPAYMENT` type, direction derived by joining to the loan.** Keeps
  the type list shorter, but every balance query gains a correlated subquery to
  discover the sign, and the origination movement still needs representing.

## References

* `docs/REQUIREMENTS.md` FR-06 (Loan Management)
* `docs/ROADMAP.md` §6.6 (Loans)
* `docs/DATA_MODEL.md` §12 (Transaction Types), §17 (Transfer Invariants),
  §29–§36 (Loans), §45 (Derived Data), §46–§47 (Invariants, Deletion)
* `docs/UI_DESIGN.md` §21–§22 (Loan Screen, Loan Details)
* `AGENTS.md` §9 (Account Balance Integrity), §10 (Loan Integrity)
* [ADR-002](002-local-database.md) (Local database technology)
