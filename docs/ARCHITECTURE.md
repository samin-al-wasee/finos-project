# FinOS Project — Architecture

**Document Status:** Baseline
**Version:** 1.0
**Project:** FinOS Project
**Platform:** Flutter
**Target Platforms:** Android, iOS
**Architecture Style:** Local-first / Offline-first
**Backend:** None in V1
**Authentication:** None in V1

---

# 1. Purpose

This document defines the technical architecture of the FinOS Project.

It establishes:

* Application structure
* Layer boundaries
* Dependency direction
* Data flow
* Local persistence strategy
* State management responsibilities
* Domain boundaries
* Integration boundaries
* Testing boundaries
* Future extensibility requirements

The architecture should remain intentionally simple for V1 while providing a clean foundation for future capabilities.

---

# 2. Architectural Goals

The architecture must prioritize:

1. Local-first operation
2. Offline-first functionality
3. Financial data integrity
4. Maintainability
5. Testability
6. Privacy
7. Low operational cost
8. Clear separation of concerns
9. Incremental extensibility
10. Minimal unnecessary infrastructure

The architecture should support future functionality without requiring the V1 application to implement that functionality prematurely.

---

# 3. Architectural Principles

## 3.1 Local-First

Local storage is the primary source of application data in V1.

The application must not depend on a remote server for core functionality.

---

## 3.2 Offline-First

All core financial operations should work without network connectivity.

Network access should be treated as an optional capability rather than a core dependency.

---

## 3.3 Domain-First

Financial rules should be modeled independently from Flutter UI concerns.

The domain layer should not depend directly on:

* Flutter widgets
* Android APIs
* iOS APIs
* Database implementation details
* HTTP clients
* Cloud providers

---

## 3.4 Dependency Direction

Dependencies should flow toward stable business concepts.

Preferred direction:

```text
Presentation
     ↓
Application
     ↓
Domain
     ↓
Data
```

Infrastructure-specific implementations should not leak into the domain layer.

---

## 3.5 Single Responsibility

Each layer and component should have a clear responsibility.

Avoid classes that simultaneously handle:

* UI
* Business logic
* Database access
* Serialization
* Networking
* Navigation

---

## 3.6 Explicit Data Flow

Data should move through well-defined boundaries.

A typical operation should follow:

```text
User Interaction
       ↓
UI
       ↓
Application / State
       ↓
Use Case
       ↓
Repository
       ↓
Local Data Source
       ↓
Database
```

The result should flow back through the appropriate layers.

---

# 4. High-Level Architecture

The initial architecture is:

```text
┌─────────────────────────────────────────────┐
│                 Presentation                │
│                                             │
│ Screens / Pages / Widgets / UI Components  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│                 Application                 │
│                                             │
│ State / Controllers / Use Cases / Commands  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│                    Domain                   │
│                                             │
│ Entities / Value Objects / Business Rules  │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│                     Data                    │
│                                             │
│ Repositories / Local Data Sources / DTOs   │
└──────────────────────┬──────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────┐
│                Local Storage                │
│                                             │
│             Local Database                  │
└─────────────────────────────────────────────┘
```

The state-management and local-persistence technologies were selected in
[ADR-002](adr/002-local-database.md) (Drift) and
[ADR-003](adr/003-state-management.md) (Riverpod).

---

# 5. Layer Responsibilities

## 5.1 Presentation Layer

The presentation layer is responsible for displaying information and receiving user interaction.

Responsibilities include:

* Screens
* Pages
* Widgets
* Forms
* Navigation
* User interaction
* Visual states
* Accessibility
* Theme application
* Formatting data for presentation

The presentation layer must not contain core financial business rules.

### Example

Avoid:

```dart
class TransactionScreen extends StatelessWidget {
  double calculateBalance(...) {
    // financial business logic
  }
}
```

Prefer:

```text
TransactionScreen
       ↓
TransactionController
       ↓
CalculateAccountBalanceUseCase
```

---

# 6. Application Layer

The application layer coordinates user actions with domain functionality.

Responsibilities include:

* Application state
* Controllers
* View models where appropriate
* Use-case orchestration
* User commands
* Loading/error/success state management
* Coordination between domain and repositories

The application layer should not contain persistence implementation details.

Example:

```text
CreateTransaction
       ↓
Validate Transaction
       ↓
Create Transaction Domain Object
       ↓
Repository.save()
       ↓
Update Application State
```

---

# 7. Domain Layer

The domain layer contains the application's financial concepts and business rules.

This is one of the most important layers in FinOS.

Potential domain entities include:

```text
FinancialAccount
Transaction
Category
Budget
RecurringTransaction
Loan
LoanRepayment
```

Potential value objects include:

```text
Money
Currency
DateRange
AccountId
TransactionId
CategoryId
LoanId
```

The domain layer should contain rules such as:

* Transaction validity
* Account balance calculation
* Transfer semantics
* Budget calculations
* Loan balance calculations
* Recurring transaction rules

The domain layer must remain independent of Flutter and infrastructure.

---

# 8. Data Layer

The data layer translates between application/domain concepts and persistence mechanisms.

Responsibilities include:

* Repository implementations
* Database access
* Data models
* Serialization
* Deserialization
* Local persistence
* Import/export
* Data migrations

The data layer may depend on:

* Local database libraries
* Serialization libraries
* File system APIs

The domain layer must not depend on these implementations.

---

# 9. Repository Pattern

Repositories provide an abstraction between the domain/application layers and data sources.

Example:

```dart
abstract class TransactionRepository {
  Future<Transaction> create(Transaction transaction);

  Future<Transaction?> findById(TransactionId id);

  Future<List<Transaction>> findAll();

  Future<void> update(Transaction transaction);

  Future<void> delete(TransactionId id);
}
```

The implementation may use a local database:

```text
TransactionRepository
        │
        ▼
LocalTransactionRepository
        │
        ▼
Local Database
```

This allows the data source to change without forcing changes throughout the application.

---

# 10. Local-First Data Architecture

V1 uses local persistence as the primary data source.

```text
                FinOS Application
                       │
                       ▼
                 Repository
                       │
                       ▼
                Local Database
                       │
                       ▼
                  Device Storage
```

There is no required server-side data path.

---

# 11. Future Synchronization Architecture

Cloud synchronization is not part of V1.

However, the architecture should avoid making synchronization impossible later.

A future architecture may become:

```text
                    Repository
                        │
             ┌──────────┴──────────┐
             │                     │
             ▼                     ▼
       Local Data Source     Remote Data Source
             │                     │
             ▼                     ▼
       Local Database        Cloud Storage
```

Synchronization logic should be introduced as a separate concern.

It should not be embedded throughout the application.

---

# 12. Local Database

FinOS requires a persistent local database for financial records.

The selected database technology should support:

* Transactions
* Queries
* Indexing
* Migrations
* Reliable persistence
* Reasonable performance for large transaction histories

The database technology must support Android and iOS.

The database choice is documented in [ADR-002](adr/002-local-database.md).

---

# 13. Database Transaction Integrity

Operations that modify multiple related records should use database transactions where appropriate.

Example:

Creating a transfer may require updating multiple pieces of state.

Conceptually:

```text
BEGIN TRANSACTION

Create transfer
Update source account state
Update destination account state

COMMIT
```

If any operation fails:

```text
ROLLBACK
```

The exact implementation depends on the selected database architecture.

---

# 14. Source of Truth

FinOS should avoid maintaining multiple independent sources of truth for financial data.

For example, the system should avoid storing:

```text
Account.balance
```

and separately maintaining another unrelated balance cache unless there is a clear reason.

When derived values are stored for performance reasons, the architecture must define:

* How they are updated
* How they are validated
* How they are rebuilt
* Which value is authoritative

Financial correctness takes priority over optimization.

---

# 15. Transaction Architecture

Transactions are a central domain concept.

A transaction should conceptually contain:

```text
Transaction
├── id
├── type
├── amount
├── date
├── account
├── category
├── description
└── metadata
```

Transaction types:

```text
Income
Expense
Transfer
```

The exact representation belongs in `docs/DATA_MODEL.md`.

---

# 16. Transfer Architecture

Transfers require special handling because they affect two accounts without representing income or expense.

Example:

```text
Account A
   │
   │  $500
   ▼
Account B
```

The system must preserve the relationship between the two sides of the transfer.

The architecture should prevent the following incorrect interpretation:

```text
Income = $500
Expense = $500
```

when the user simply moved their own money.

---

# 17. Account Architecture

A financial account represents a source or destination of funds.

Potential account types include:

```text
Bank
MFS / Digital Wallet
Credit Card
Debit Card
Cash
Other
```

The account domain model should not assume that every account behaves identically.

For example:

* Cash normally has a positive balance.
* A credit card may represent a liability.
* A bank account may represent an asset.
* A loan account may represent a liability or receivable.

The exact financial semantics should be defined in `docs/DATA_MODEL.md`.

---

# 18. Budget Architecture

Budgets should be modeled independently from transactions.

Conceptually:

```text
Budget
├── category
├── period
├── limit
└── calculation rules
```

Budget status should be derived from relevant financial activity.

Example:

```text
Budget Limit:      $500
Current Spending:  $350
Remaining:         $150
```

The application should avoid duplicating budget calculations across multiple screens.

---

# 19. Loan Architecture

Loans should be modeled independently from ordinary transactions.

Conceptually:

```text
Loan
├── type
├── principal
├── outstanding amount
├── date
├── due date
├── status
└── repayments
```

Loan types:

```text
Money Lent
Money Borrowed
```

Repayments should maintain the relationship between the loan and the corresponding financial movement.

The domain model must prevent loan calculations from being duplicated across UI screens.

---

# 20. Recurring Transaction Architecture

Recurring transactions represent rules for generating or suggesting transactions.

A recurring transaction should conceptually contain:

```text
RecurringTransaction
├── amount
├── type
├── account
├── category
├── frequency
├── start date
├── next occurrence
└── status
```

Recurring transaction logic should be isolated from ordinary transaction persistence.

The system must clearly distinguish between:

```text
Recurring transaction definition
```

and:

```text
Actual financial transaction
```

A recurring definition should not automatically be treated as an actual transaction until the appropriate business rule creates or confirms it.

---

# 21. Import / Export Architecture

Import and export should be implemented as dedicated services rather than being embedded into screens.

Conceptually:

```text
UI
 │
 ▼
Import / Export Service
 │
 ├── Serializer
 ├── Validator
 └── Repository
```

Import flow:

```text
File
 ↓
Parse
 ↓
Validate
 ↓
Transform
 ↓
Validate Domain Rules
 ↓
Database Transaction
 ↓
Commit
```

If validation or persistence fails:

```text
Rollback
```

Existing user data must remain intact.

---

# 22. Backup Format

The application backup format must be versioned.

Example:

```json
{
  "backup_version": 1,
  "accounts": [],
  "transactions": [],
  "categories": [],
  "budgets": [],
  "recurring_transactions": [],
  "loans": []
}
```

Future versions may change the structure.

The import system must be capable of identifying the backup version and applying the appropriate migration or transformation.

---

# 23. State Management

State management should be used to coordinate UI state with application/domain operations.

State management must not become the location for core financial business rules.

For example:

```text
State Management
    ↓
Calls Use Case
    ↓
Domain Logic
    ↓
Repository
```

not:

```text
State Management
    ↓
Directly calculates all financial rules
    ↓
Directly manipulates database
```

The state-management technology is documented in [ADR-003](adr/003-state-management.md).

---

# 24. Navigation Architecture

Navigation should remain within the presentation/application boundary.

Navigation should not be triggered from domain entities.

The domain layer must not know about:

* Routes
* Screens
* Navigator
* Flutter widgets
* Platform navigation APIs

---

# 25. Dependency Injection

Dependencies should be provided through explicit mechanisms.

Avoid uncontrolled global singletons.

Examples of appropriate dependency boundaries:

```text
TransactionController
       ↓
CreateTransactionUseCase
       ↓
TransactionRepository
```

The dependency graph should remain understandable.

Dependency injection should be used where it improves:

* Testability
* Replaceability
* Maintainability

Do not introduce a dependency injection framework solely because one is available.

---

# 26. External Integrations

External integrations should be isolated behind interfaces.

Future examples include:

```text
Google Drive
Google Authentication
Bank APIs
Investment APIs
AI Providers
Analytics
```

The domain layer should never directly depend on a specific external provider.

### Platform integrations in use

Backup export/import is the first feature needing platform services, and it
follows the pattern below: `BackupFileStore` is an interface, and
`PlatformBackupFileStore` is the only file in the project that touches these
packages. Everything else — serialization, validation, restore — is plain Dart and
is tested with an in-memory fake, because plugin method channels are unavailable
under `flutter test`.

| Package | Why |
| --- | --- |
| `share_plus` | Hands the exported file to the OS. On both Android and iOS the share sheet is the route to "save to Files", Drive, or email, and there is no cross-platform save dialog on mobile. |
| `file_selector` | System file picker for choosing a backup to restore. Maintained by the Flutter team. |
| `path_provider` | Locates the temporary directory the export is written to before sharing. The file is deleted afterwards so a readable copy of the user's finances does not linger in a cache. |

None of these adds a backend, an account, or network access, so the local-first
guarantee (FR-09) is unchanged.

Prefer:

```text
Domain
  ↓
Integration Interface
  ↓
Provider Implementation
```

rather than:

```text
Domain
  ↓
Google Drive SDK
```

---

# 27. AI Architecture

AI functionality is not part of the V1 core architecture.

When AI functionality is introduced, it must remain separate from deterministic financial calculations.

Preferred architecture:

```text
Financial Domain
       │
       ▼
Financial Data / Derived Insights
       │
       ▼
AI Analysis Layer
       │
       ▼
AI Provider
       │
       ▼
Generated Insight
       │
       ▼
Presentation
```

The AI layer must not become the source of truth for:

* Account balances
* Transaction totals
* Budget calculations
* Loan balances
* Financial accounting

The deterministic domain remains authoritative.

---

# 28. Privacy Architecture

V1 should minimize data leaving the device.

The architecture should therefore avoid unnecessary external services.

Conceptually:

```text
                    Device
┌───────────────────────────────────────────┐
│                                           │
│ UI → Application → Domain → Local DB     │
│                                           │
└───────────────────────────────────────────┘
```

No remote data path is required for core functionality.

Future external integrations must be introduced deliberately.

---

# 29. Analytics

Analytics are not required for V1.

If analytics are introduced later, they must be designed carefully around financial privacy.

Analytics should preferably capture application behavior rather than financial content.

Example of acceptable telemetry:

```text
transaction_create_screen_opened
```

Avoid:

```text
transaction_created:
  amount: 125000
  category: salary
  account: bank_account_123
```

Financial information must never be unnecessarily transmitted to analytics services.

---

# 30. Project Structure

The exact project structure may evolve, but the intended organization is:

```text
finos/
│
├── README.md
├── AGENTS.md
├── pubspec.yaml
│
├── docs/
│   ├── REQUIREMENTS.md
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── UI_DESIGN.md
│   ├── DEVELOPMENT.md
│   └── ROADMAP.md
│
├── lib/
│   ├── core/
│   ├── features/
│   └── ...
│
├── test/
│
├── assets/
│
├── android/
│
└── ios/
```

The exact internal `lib/` structure should be finalized after the chosen architecture and state-management approach are confirmed.

---

# 31. Feature-Oriented Organization

Where practical, functionality should be organized around features rather than purely technical categories.

Potential structure:

```text
lib/
├── core/
│
├── features/
│   ├── accounts/
│   ├── transactions/
│   ├── categories/
│   ├── budgets/
│   ├── recurring_transactions/
│   ├── loans/
│   ├── dashboard/
│   └── settings/
│
└── app/
```

A feature may contain its own:

```text
presentation/
application/
domain/
data/
```

when the feature is sufficiently complex.

Do not force every small feature into excessive folder depth.

Features implemented so far:

- **accounts** — Account management (FR-01)
- **categories** — Category management with built-in seed data (FR-03)
- **transactions** — Income/expense/transfer entry, listing, balance impact, and search/filter, including the docs/ROADMAP.md §8.5 "advanced" search (FR-02, built ahead of its Phase 2 slot with explicit authorization). `TransactionFilter` is a pure predicate over already-loaded rows — text search, account, category, type, date range, and an amount range all combine with AND — so "food transactions between ৳500 and ৳2,000 in July" is several ordinary criteria at once, not a distinct compound-query feature. A saved-query/report builder remains out of scope.
- **budgets** — Per-category spending limits with derived spent/remaining/health (FR-04), plus history over past periods (docs/ROADMAP.md §8.3, built ahead of its Phase 2 slot with explicit authorization). History reuses `BudgetProgress` for a past window exactly as the live card does for the current one via `shiftedBudgetWindow` (an offset generalisation of `budgetWindow`) — a custom-period budget has no repeating window, so it returns no history, and a window that predates the budget's own start date is never shown. Rollover and spending-based recommendations remain out of scope; recommendations in particular overlaps with the more specific Phase 4 "AI & Automation" framing (docs/ROADMAP.md §10.3).
- **settings** — Theme and default-currency preferences, plus the entry points to category management and backup (docs/ROADMAP.md §6.8). Preferences live in a key-value `preferences` table so a new setting needs no schema migration; `AppSettings` is the typed facade over it.
- **backup** — Versioned JSON export and atomic replace-restore (FR-08, docs/DATA_MODEL.md §48). Serialization, validation, and restore are plain Dart; all platform file handling sits behind the `BackupFileStore` interface (see §26). Also exports a human-readable CSV of every transaction, with account/category ids resolved to names — read-only, so it needs none of the restore safeguards.
- **loans** — Money lent and borrowed, with repayments and derived outstanding/paid/overdue state (FR-06, [ADR-004](adr/004-loan-accounting.md)). Loan cash movements are transactions under two directional types, so account balances stay derived from one table; the loan record itself holds no outstanding amount. Loan transactions are read-only in the transaction list — they are created and removed only through this feature.
- **dashboard** — Financial overview with balances, this-month spending by category, a combined budget-status summary, and recent activity (FR-07). The budget summary aggregates every active budget's own current window into one card — total limit, total spent, and how many are near or over limit — rather than duplicating the Budgets tab's per-category detail.
- **reports** — Income vs expense and expense-by-category for a selected calendar period, compared against the immediately preceding period (docs/ROADMAP.md §8.4, built ahead of its Phase 2 slot with explicit authorization). Fixed periods only (this/last month, this/last year) — a custom date-range picker and per-account cash flow are deferred. Reuses the transaction DAO's existing period-aggregation queries rather than adding new ones.

---

# 32. Core Module

The `core` area should contain genuinely shared functionality.

Potential examples:

```text
core/
├── errors/
├── result/
├── formatting/
├── database/
├── utilities/
├── theme/
└── constants/
```

Avoid using `core` as a dumping ground.

A component belongs in `core` only when it is genuinely shared or infrastructure-level.

---

# 33. Feature Boundaries

Features should communicate through clear interfaces.

For example:

```text
Transactions
      │
      ▼
Accounts Repository
```

rather than directly accessing another feature's internal database implementation.

Cross-feature dependencies should be deliberate.

---

# 34. Testing Architecture

Tests should mirror architectural boundaries where useful.

Potential structure:

```text
test/
├── unit/
│   ├── domain/
│   ├── application/
│   └── data/
│
├── widget/
│
└── integration/
```

Priority should be given to domain and financial calculation tests.

---

# 35. Architecture Decision Records

Significant architectural decisions should be documented.

Examples:

* Database technology
* State management solution
* Serialization format
* Backup format
* Cloud synchronization strategy
* Authentication strategy
* AI provider architecture

For major decisions, create an Architecture Decision Record when appropriate.

Example:

```text
docs/adr/
├── 001-local-first-architecture.md
├── 002-local-database.md
└── 003-state-management.md
```

ADRs should be introduced when the number or importance of architectural decisions justifies them.

Do not create an ADR for every minor implementation decision.

---

# 36. Future Architecture Evolution

The architecture is expected to evolve.

A possible long-term architecture is:

```text
                         FinOS
                           │
        ┌──────────────────┼──────────────────┐
        │                  │                  │
        ▼                  ▼                  ▼
 Transactions          Budgets          Investments
        │                  │                  │
        └──────────────────┼──────────────────┘
                           │
                           ▼
                       Net Worth
                           │
             ┌─────────────┴─────────────┐
             │                           │
             ▼                           ▼
        Automation                       AI
             │                           │
             └─────────────┬─────────────┘
                           │
                           ▼
                 External Integrations
                           │
             ┌─────────────┼─────────────┐
             ▼             ▼             ▼
          Cloud          Banks       Investment APIs
```

This diagram represents potential future architecture only.

It does not authorize implementation.

---

# 37. Architecture Change Rules

An agent must consider an architecture change when:

* A feature cannot reasonably be implemented using the existing structure.
* Existing boundaries are causing significant duplication.
* A scalability limitation has been demonstrated.
* A security or privacy issue requires architectural changes.
* A new external integration requires a proper abstraction.

Before making a significant architecture change, the agent should:

1. Explain the problem.
2. Explain the proposed change.
3. Identify affected components.
4. Identify migration risks.
5. Update relevant documentation.

---

# 38. What the Architecture Must Avoid

FinOS should avoid:

* Premature microservices
* Backend-for-the-sake-of-backend
* Unnecessary cloud infrastructure
* Excessive abstraction
* Excessive dependency injection
* Global mutable state
* UI-driven business logic
* Database logic scattered throughout widgets
* AI-driven financial calculations
* Multiple competing sources of truth
* Unnecessary third-party services
* Architecture designed entirely around hypothetical future requirements

The application is a mobile-first local financial application first.

It should earn complexity rather than assuming complexity from day one.

---

# 39. Architectural Definition of Done

An architectural change is considered complete when:

* The dependency direction remains clear.
* Existing functionality remains intact.
* Financial integrity is preserved.
* Appropriate tests exist.
* Relevant documentation is updated.
* No unnecessary infrastructure was introduced.
* No unrelated modules were changed.
* The resulting architecture is simpler or more capable without unnecessary complexity.

---

# 40. Final Principle

The architecture of FinOS should follow one central principle:

> **Build a strong foundation, not a premature platform.**

V1 should be:

* Local
* Fast
* Private
* Reliable
* Simple
* Testable
* Maintainable

Future capabilities such as cloud synchronization, AI, investments, and financial integrations should be added as isolated capabilities when they become justified by actual product requirements.

The architecture must make future growth possible without making present development unnecessarily complicated.
