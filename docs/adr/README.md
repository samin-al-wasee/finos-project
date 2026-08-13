# Architecture Decision Records

This directory records significant architectural decisions for FinOS.

## Index

| ADR | Status | Title |
| --- | ------ | ----- |
| [002](002-local-database.md) | Accepted | Local database technology |
| [003](003-state-management.md) | Accepted | State management approach |
| [004](004-loan-accounting.md) | Accepted | Loan accounting |
| [005](005-credit-card-accounts.md) | Accepted | Credit card accounts |
| [006](006-loan-relationships.md) | Accepted | Loan relationships |
| [007](007-flexible-budget-scope.md) | Accepted | Flexible budget scope |
| [008](008-budget-rollover.md) | Accepted | Budget rollover |

## Conventions

* Each ADR has a stable numeric identifier.
* An ADR is created when a decision materially affects architecture, data
  integrity, privacy, or long-term maintainability.
* Minor implementation decisions do not require an ADR.
* A decision is not finalized until it is implemented and documented in the
  relevant project documents (`docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`).

ADR `001` is intentionally reserved for the local-first architecture, which is
already captured as a baseline decision in `docs/ARCHITECTURE.md`.
