# ADR-002: Local Database Technology

**Status:** Accepted
**Date:** 2026-08-09

## Context

FinOS is a local-first, offline-first personal finance application targeting
Android and iOS. V1 has no backend and the device database is the primary
source of truth for financial records.

The architecture requires the database to support (see `docs/ARCHITECTURE.md`
§12 and `docs/DEVELOPMENT.md` §14):

* Reliable offline persistence
* Transactions / atomic operations (e.g. a transfer touching two accounts)
* Queries, indexing, and reasonable performance for large transaction histories
* Schema migrations without destructive changes
* Android and iOS support

## Decision

Use **Drift** (the `drift` Dart package, plus `drift_flutter` for native setup)
as the local persistence layer, backed by SQLite.

Selected supporting decisions:

* **Database file / native wiring:** `drift_flutter` provides the SQLite native
  libraries for Android and iOS and resolves the application database file
  location via `path_provider`.
* **Money representation:** amounts are stored as integer minor units
  (e.g. cents / paisa), never as binary floating point, per
  `docs/DATA_MODEL.md` §4.
* **Schema evolution:** all tables are registered in a single
  `AppDatabase` class with an explicit `MigrationStrategy`; migrations are
  additive and preserve existing user data.
* **Identifiers:** persistent entities use stable, globally unique text
  identifiers, per `docs/DATA_MODEL.md` §3.

## Consequences

### Positive

* Compile-time checked SQL with a typed query API; the database is strongly
  typed against the Dart domain model.
* First-class migration support and a stream-based query API that integrates
  naturally with reactive UI state.
* Single codebase for both Android and iOS; no separate schema files to keep in
  sync.
* Drift is actively maintained and widely used, and it does not add a backend
  or network dependency.

### Negative / Trade-offs

* SQLite/Drift requires code generation (`drift_dev` + `build_runner`); schema
  changes must be followed by regeneration.
* SQLite enforces column types at write time; additional validation lives in
  the domain/application layers rather than the database.
* Table and index design must be reviewed as transaction volumes grow.

## Alternatives Considered

* **sqflite** — direct SQLite access with minimal abstraction, but manual SQL
  and migration code with weaker compile-time safety.
* **Isar** — fast NoSQL embedded store, but a weaker relational/migration story
  for the structured financial model in `docs/DATA_MODEL.md`.
* **Hive** — simple key-value store, unsuitable for the relational queries the
  financial model requires.

## References

* `docs/ARCHITECTURE.md` §12 (Local Database), §13 (Database Transaction Integrity)
* `docs/DATA_MODEL.md` §3–§10 (Identifiers, Money, Currency, Financial Account)
* `docs/DEVELOPMENT.md` §14 (Database), §34 (Migration Testing)
