# Architecture Decision Records

This directory records significant architectural decisions for FinOS.

## Index

| ADR | Status | Title |
| --- | ------ | ----- |
| [002](002-local-database.md) | Accepted | Local database technology |
| [003](003-state-management.md) | Accepted | State management approach |

## Conventions

* Each ADR has a stable numeric identifier.
* An ADR is created when a decision materially affects architecture, data
  integrity, privacy, or long-term maintainability.
* Minor implementation decisions do not require an ADR.
* A decision is not finalized until it is implemented and documented in the
  relevant project documents (`docs/ARCHITECTURE.md`, `docs/DATA_MODEL.md`).

ADR `001` is intentionally reserved for the local-first architecture, which is
already captured as a baseline decision in `docs/ARCHITECTURE.md`.
