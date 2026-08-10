# FinOS — Development Guide

**Document Status:** Baseline
**Version:** 1.0
**Project:** FinOS Project
**Platform:** Flutter
**Target Platforms:** Android, iOS

---

# 1. Purpose

This document defines the development standards and workflow for FinOS.

It is intended for:

* Human developers
* Claude Code
* GitHub Copilot
* Other AI coding agents
* Automated development tools

The purpose is to ensure that the project remains:

* Maintainable
* Testable
* Consistent
* Modular
* Understandable
* Safe for financial data
* Easy to extend

This document complements `AGENTS.md`.

`AGENTS.md` defines **how AI agents should behave**.

This document defines **how FinOS should be developed**.

---

# 2. Technology Stack

The initial technology stack is:

```text
Language:
Dart

Framework:
Flutter

Platforms:
Android
iOS
```

The application is initially:

```text
Local-first
Offline-first
No FinOS backend
```

Cloud synchronization is a future capability.

## 2.1 Local environment

Work either directly on a host with the Flutter SDK installed, or in the dev
containers under `.devcontainer/`. Both are pinned to the Flutter revision
recorded in `.metadata`, so they agree with each other.

```text
.devcontainer/                 analysis, tests, codegen   (default)
.devcontainer/android/         the above plus APK builds
```

The containers deliberately cannot do everything:

* **iOS needs macOS and Xcode**, so it cannot run in a Linux container at all.
  Since iOS is a first-class target, a container is a supplement to a Mac
  checkout rather than a replacement for one.
* An Android **emulator** needs nested virtualisation, which a container does not
  have. Use a device, or an emulator on the host.
* On an **arm64 host** (Apple Silicon) the Android variant builds but cannot
  produce an APK, because Google ships the Linux NDK and `adb` as x86-64 only.
  `flutter doctor` reports the toolchain as healthy regardless, so the failure
  surfaces late and looks unrelated. Build that image for `linux/amd64` instead.
* The **share sheet and file picker** used by backup export/import need a real
  mobile runtime; in tests they are replaced by a fake.

See `.devcontainer/README.md` for the pinned versions, the caches, and why a C
toolchain is required even to run the test suite.

---

# 3. Development Philosophy

FinOS should follow:

```text
Simple before complex
Explicit before magical
Correctness before optimization
Reusable before duplicated
Tested before trusted
```

Do not introduce infrastructure merely because it may become useful later.

---

# 4. Architecture

The application should maintain clear separation between:

```text
Presentation
    ↓
Application / State
    ↓
Domain
    ↓
Data
```

Conceptually:

```text
┌────────────────────────────┐
│ Presentation               │
│ Flutter Widgets / Screens  │
└─────────────┬──────────────┘
              ↓
┌────────────────────────────┐
│ Application / State        │
│ Controllers / Notifiers    │
└─────────────┬──────────────┘
              ↓
┌────────────────────────────┐
│ Domain                     │
│ Entities / Use Cases       │
│ Financial Rules            │
└─────────────┬──────────────┘
              ↓
┌────────────────────────────┐
│ Data                       │
│ Repositories / Database    │
└────────────────────────────┘
```

The exact Flutter packages used to implement these layers should be documented when selected.

---

# 5. Dependency Direction

Dependencies should generally flow inward:

```text
UI
 ↓
Application
 ↓
Domain
 ↓
Data
```

Lower-level layers should not depend on higher-level UI concerns.

For example:

```text
Domain
```

must not import Flutter UI widgets.

Avoid:

```dart
import 'package:flutter/material.dart';
```

inside domain models or financial calculation logic.

---

# 6. Domain Layer

The domain layer contains financial concepts and rules.

Examples:

```text
Account
Transaction
Category
Budget
Loan
LoanRepayment
RecurringTransaction
```

It should contain logic such as:

* Balance calculation
* Transaction validation
* Budget calculations
* Loan calculations
* Transfer rules
* Financial invariants

The domain layer should be independently testable.

---

# 7. Application Layer

The application layer coordinates user actions and domain operations.

Examples:

```text
AddTransaction
EditTransaction
DeleteTransaction
CreateAccount
TransferMoney
CreateBudget
RecordLoanRepayment
ExportData
ImportData
```

Application logic should orchestrate domain and repositories.

It should not contain large amounts of UI-specific logic.

---

# 8. Data Layer

The data layer handles persistence and external data sources.

Responsibilities include:

* Database access
* Serialization
* Deserialization
* Import
* Export
* Future cloud synchronization
* Future external integrations

The domain should not depend directly on a specific database implementation.

---

# 9. Repository Pattern

Repositories should abstract persistence from the rest of the application.

Example:

```dart
abstract class TransactionRepository {
  Future<List<Transaction>> getTransactions();

  Future<void> saveTransaction(Transaction transaction);

  Future<void> deleteTransaction(String id);
}
```

The implementation may later use:

```text
Local Database
Cloud Storage
Google Drive
Other Storage
```

without requiring the UI or domain logic to change.

---

# 10. Local-First Architecture

FinOS V1 is local-first.

The user's financial data should be available without internet access.

Core functionality must work offline:

```text
Create transaction
Edit transaction
Delete transaction
View transactions
View accounts
Calculate balances
Manage budgets
Manage loans
Import data
Export data
```

Internet access should not be required for these operations.

---

# 11. No FinOS Backend in V1

FinOS V1 does not require a developer-controlled backend.

Do not introduce:

```text
FinOS API
FinOS database server
FinOS authentication server
FinOS user service
```

unless the product requirements explicitly change.

Future cloud functionality should be isolated behind appropriate interfaces.

---

# 12. Authentication

Authentication is not required for local-only functionality.

If authentication is introduced for future cloud synchronization, the architecture should treat authentication separately from local financial data.

Possible future providers include:

```text
Google
Apple
Facebook
```

The exact authentication architecture will be decided when cloud functionality is implemented.

Authentication must not become a prerequisite for basic offline financial tracking unless product requirements explicitly change.

---

# 13. State Management

The project should use one consistent state-management approach.

Do not mix multiple state-management frameworks without an architectural reason.

The chosen approach must support:

* Reactive UI
* Testability
* Dependency injection
* Async operations
* Error handling
* Lifecycle management

The final package choice should be recorded in an ADR.

---

# 14. Database

FinOS requires persistent local storage.

The database should support:

* Offline operation
* Structured relationships
* Transactions/atomic operations
* Migrations
* Efficient querying
* Reliable persistence

The exact database technology should be selected based on:

1. Flutter support
2. Stability
3. Performance
4. Migration support
5. Offline capability
6. Query capability
7. Long-term maintainability

The decision should be recorded in:

```text
docs/adr/
```

---

# 15. Database Access

UI code must not directly access database APIs.

Avoid:

```text
Widget
   ↓
Database query
```

Prefer:

```text
Widget
   ↓
Controller / Use Case
   ↓
Repository
   ↓
Database
```

This keeps persistence replaceable and testable.

---

# 16. Financial Calculations

Financial calculations must use exact arithmetic.

Do not use binary floating-point arithmetic as the authoritative representation of money.

Avoid:

```dart
double balance;
```

for persistent financial values.

Use the money representation defined in:

```text
docs/DATA_MODEL.md
```

---

# 17. Financial Logic Must Be Deterministic

Given identical financial data:

```text
Input
   ↓
Financial Calculation
   ↓
Output
```

must produce the same result.

Avoid hidden dependencies such as:

* Current time
* Device locale
* Device timezone
* Network state
* Random values

unless explicitly required.

---

# 18. Transactions and Atomicity

Operations that modify multiple financial records must be atomic.

For example, a transfer:

```text
Bank
-৳5,000

Cash
+৳5,000
```

must not result in:

```text
Bank
-৳5,000

Cash
unchanged
```

because the second operation failed.

The database layer should support transactions where required.

---

# 19. Error Handling

Errors should be categorized appropriately.

Conceptually:

```text
Validation Error
Persistence Error
Import Error
Export Error
Network Error
Unexpected Error
```

Errors should be converted into user-appropriate messages at the presentation boundary.

Do not expose raw exceptions to users.

---

# 20. Logging

Logging should be useful for debugging without leaking sensitive financial information.

Avoid logging:

```text
Transaction amount
Account balance
Loan amount
Financial descriptions
Backup contents
Authentication tokens
```

unless explicitly required for development and safely controlled.

Never commit secrets or tokens to the repository.

---

# 21. Environment Configuration

Environment-specific configuration should not be hardcoded into application logic.

Examples:

```text
Development
Testing
Production
```

Secrets must not be committed to Git.

If a future integration requires API credentials, use an appropriate secret-management mechanism.

---

# 22. Code Style

Follow standard Dart and Flutter conventions.

Code should be:

* Idiomatic
* Readable
* Explicit
* Consistent

Prefer meaningful names.

Bad:

```dart
final x = repo.get();
```

Better:

```dart
final transactions = repository.getTransactions();
```

---

# 23. Naming Conventions

Use standard Dart naming conventions.

### Classes

```dart
TransactionRepository
AccountDetailsScreen
BudgetController
```

### Variables

```dart
transactionAmount
accountBalance
```

### Methods

```dart
calculateBalance()
createTransaction()
deleteAccount()
```

### Constants

Follow Dart conventions appropriate to their scope.

---

# 24. File Organization

Files should generally have one primary responsibility.

Avoid large files containing unrelated:

```text
Widgets
Models
Repositories
Business logic
Utilities
```

Prefer focused files.

Example:

```text
transaction.dart
transaction_repository.dart
transaction_repository_impl.dart
add_transaction_controller.dart
add_transaction_screen.dart
```

---

# 25. Feature-Oriented Organization

As the project grows, organize code around features rather than only technical layers.

A potential structure:

```text
lib/
├── app/
├── core/
│
├── features/
│   ├── transactions/
│   ├── accounts/
│   ├── categories/
│   ├── budgets/
│   ├── loans/
│   └── dashboard/
│
└── main.dart
```

Each feature may contain:

```text
presentation/
application/
domain/
data/
```

where justified.

---

# 26. Core Directory

The `core/` directory should contain genuinely shared functionality.

Examples:

```text
core/
├── theme/
├── routing/
├── errors/
├── utilities/
├── database/
└── formatting/
```

Do not put arbitrary feature code into `core/`.

If something belongs specifically to transactions, keep it under the transactions feature.

---

# 27. Reuse

Before creating a new:

* Widget
* Utility
* Formatter
* Repository method
* Validation helper

check whether an existing implementation already serves the purpose.

Avoid unnecessary duplication.

---

# 28. Over-Abstraction

Do not abstract code merely because abstraction is theoretically possible.

Avoid:

```text
GenericRepositoryFactoryProviderManager
```

when a simple repository is sufficient.

Abstraction should solve a real problem:

* Reuse
* Testability
* Replaceability
* Separation of concerns

---

# 29. Testing Strategy

FinOS should use multiple levels of testing.

```text
Unit Tests
Integration Tests
Widget Tests
End-to-End Tests
```

Each level serves a different purpose.

---

# 30. Unit Tests

Unit tests should cover financial logic extensively.

Examples:

```text
Transaction calculations
Balance calculations
Budget calculations
Loan calculations
Transfer rules
Money arithmetic
Date calculations
Recurring transaction rules
```

Financial logic should have strong unit-test coverage.

---

# 31. Widget Tests

Widget tests should verify important UI behavior.

Examples:

```text
Add transaction form
Validation
Account selection
Category selection
Budget display
Loan repayment flow
Empty states
Error states
```

Do not attempt to test every visual pixel through widget tests.

---

# 32. Integration Tests

Integration tests should verify important workflows.

Examples:

```text
Create account
    ↓
Create transaction
    ↓
Balance changes correctly
```

Another:

```text
Create budget
    ↓
Create expense
    ↓
Budget consumption updates
```

Another:

```text
Create loan
    ↓
Record repayment
    ↓
Outstanding balance changes
```

---

# 33. Import/Export Testing

Import/export is critical because it protects user data.

Tests should verify:

```text
Create data
    ↓
Export
    ↓
Clear test database
    ↓
Import
    ↓
Data matches original
```

The system should also test:

* Invalid files
* Corrupted files
* Older backup versions
* Missing fields
* Unknown fields
* Duplicate identifiers

---

# 34. Migration Testing

Every database migration should have tests where appropriate.

Test:

```text
Old database
     ↓
Migration
     ↓
New database
```

and verify that existing financial records remain correct.

---

# 35. Test Naming

Tests should clearly describe behavior.

Prefer:

```dart
test(
  'calculates remaining budget after expense',
  () {},
);
```

over:

```dart
test(
  'budgetTest1',
  () {},
);
```

---

# 36. Test Data

Tests should use deterministic data.

Avoid relying on:

```text
Current device date
Current timezone
Random values
Production data
```

unless specifically testing those behaviors.

---

# 37. Static Analysis

The project should use:

```text
dart analyze
```

as part of development and CI.

Warnings and errors should not be ignored without a documented reason.

---

# 38. Formatting

Use Dart's formatter consistently.

Run:

```bash
dart format .
```

before committing significant changes.

Do not manually format code in ways that conflict with the standard formatter.

---

# 39. Tests Before Completion

A feature should not be considered complete merely because it compiles.

Before declaring work complete:

```text
Code
 ↓
Format
 ↓
Analyze
 ↓
Test
 ↓
Review
```

AI agents must perform the appropriate validation before reporting completion.

---

# 40. Git Workflow

## Branching

Each change lives on a dedicated branch. Branch names follow the pattern:

```text
<type>/<short-kebab-case-slug>
```

Types:

```text
feat/
fix/
chore/
docs/
test/
```

Examples:

```text
feat/transaction-management
fix/transfer-validation
docs/git-workflow
test/balance-calculation
```

## Merge Strategy

`main` is the long-lived integration branch. Feature branches merge back into
`main` using fast-forward only. If a branch has diverged, rebase onto `main`
before merging.

Merge commits are avoided to keep `main` history linear.

## Commits

Use small, focused commits.

Good:

```text
[feat] Add transaction creation
[test] Add transaction balance tests
[fix] Prevent negative budget remaining
```

Avoid:

```text
update stuff
changes
fix
misc
```

Commit messages use the format: `[type] Sentence case description`.

Types: feat, fix, test, docs, chore

---

# 41. Commit Scope

A commit should ideally represent one logical change.

Avoid combining:

```text
New transaction feature
Theme redesign
Database migration
Unrelated refactoring
```

into one commit.

---

# 42. Pull Requests

Pull requests should explain:

```text
What changed?
Why?
How was it tested?
Are migrations required?
Are there UX changes?
```

For significant changes, include screenshots where appropriate.

---

# 43. AI-Assisted Development

AI agents are first-class development tools in FinOS.

Agents may assist with:

* Implementation
* Refactoring
* Testing
* Documentation
* Debugging
* Code review
* Architecture exploration

However:

> AI-generated code is not automatically trusted code.

All AI-generated changes must follow the same engineering standards as human-written code.

---

# 44. AI Agent Workflow

AI agents should generally follow:

```text
Understand
    ↓
Inspect
    ↓
Plan
    ↓
Implement
    ↓
Test
    ↓
Review
    ↓
Report
```

Agents should not immediately modify files without understanding the surrounding implementation.

---

# 45. Before Modifying Code

AI agents should inspect:

```text
AGENTS.md
Relevant docs
Relevant feature files
Existing tests
Existing abstractions
```

Agents should search the repository before introducing new patterns.

---

# 46. Scope Control

An agent should not modify unrelated files merely because it notices potential improvements.

If asked:

```text
Fix transaction validation
```

do not automatically:

```text
Rewrite navigation
Refactor database
Redesign dashboard
Rename unrelated classes
```

Keep changes focused.

---

# 47. Requirement Conflicts

When implementation conflicts with documentation:

```text
Do not silently choose.
```

The agent should identify the conflict and determine whether:

* Documentation is outdated
* Requirement changed
* Architecture must change

Significant decisions should be recorded in an ADR.

---

# 48. Documentation Updates

When implementation changes a documented architectural behavior, update the relevant document.

Examples:

```text
Database change
→ ARCHITECTURE.md / DATA_MODEL.md

UI system change
→ UI_DESIGN.md

Development workflow change
→ DEVELOPMENT.md

Product scope change
→ REQUIREMENTS.md / ROADMAP.md
```

Documentation should describe the actual current system, not an imaginary future system.

---

# 49. Dependency Management

Do not add a package merely to solve a trivial problem.

Before adding a dependency, evaluate:

```text
Is it necessary?
Is Flutter/Dart capable of solving this natively?
Is the package maintained?
Is it compatible with Android and iOS?
Does it introduce security/privacy concerns?
Does it create architectural coupling?
```

Significant dependency decisions should be documented.

---

# 50. Package Updates

Do not perform broad dependency upgrades as part of an unrelated feature.

For example:

```text
Feature: Add transaction
```

should not automatically become:

```text
Upgrade 20 dependencies
Migrate Flutter version
Rewrite architecture
```

unless required.

---

# 51. Performance

Performance optimization should be evidence-driven.

Do not optimize prematurely.

Potential areas to monitor:

* Large transaction lists
* Database queries
* Dashboard calculations
* Charts
* Import/export
* Search
* Filtering

Correctness takes priority over micro-optimizations.

---

# 52. Large Data Sets

The architecture should eventually support users with large financial histories.

Avoid assuming:

```text
10 transactions
```

will always be the dataset size.

Users may eventually have:

```text
10,000+
transactions
```

Lists should use appropriate lazy rendering and pagination/query strategies where necessary.

---

# 53. Security

Security must be considered even without a backend.

Protect:

* Local financial data
* Backup files
* Authentication credentials
* API keys
* Tokens
* External integrations

Never commit:

```text
API keys
OAuth secrets
Private keys
Tokens
Production credentials
```

to Git.

---

# 54. Sensitive Data in Debugging

Do not copy real user financial information into:

* Test fixtures
* Screenshots
* Logs
* GitHub issues
* Pull requests
* AI prompts

Use synthetic data whenever possible.

---

# 55. AI Privacy

When using external AI tools, do not send real financial data unless explicitly required and appropriate.

Prefer synthetic examples:

```text
Account:
Main Bank

Balance:
৳50,000

Transaction:
Food — ৳500
```

rather than actual private financial records.

---

# 56. Localization

The architecture should not assume English is the only language.

Text should be externalized where appropriate.

Avoid hardcoding user-facing strings across widgets.

Future localization may include:

```text
English
Bangla
Other languages
```

Localization is not required to be fully implemented in V1 unless prioritized.

---

# 57. Accessibility and Localization

UI components should be designed so that:

* Text can expand
* Translations can be longer
* Font scaling does not break layouts
* Numbers can be formatted by locale
* Currency formatting is configurable

Do not build layouts that only work with one exact string length.

---

# 58. Release Builds

Before release:

```text
Format
Analyze
Unit tests
Widget tests
Integration tests
Build Android
Build iOS
Manual smoke test
```

The release checklist should eventually be automated through CI/CD.

---

# 59. CI/CD

CI/CD is not required to be fully implemented immediately.

Future CI should at minimum perform:

```text
Dependency resolution
Formatting check
Static analysis
Tests
Build validation
```

Potential future deployment targets:

```text
Google Play
Apple App Store
```

---

# 60. Definition of Done

A feature is considered complete when:

```text
[ ] Requirements are understood
[ ] Architecture is respected
[ ] Code is implemented
[ ] UI follows UI_DESIGN.md
[ ] Financial rules are tested
[ ] Relevant widget tests exist
[ ] Relevant integration tests exist
[ ] dart analyze passes
[ ] dart format passes
[ ] No unrelated changes were introduced
[ ] Documentation is updated where necessary
```

---

# 61. Definition of Done for AI Agents

An AI agent should not report:

> "Implemented successfully."

without verifying the implementation.

Instead, it should report:

```text
Implemented:
- ...
- ...

Tests:
- ...
- ...

Validation:
- dart analyze: PASS
- dart format: PASS
- tests: PASS

Notes:
- ...
```

If something could not be tested, the agent must explicitly state that.

---

# 62. Refactoring Rules

Refactoring should preserve behavior unless behavior change is explicitly requested.

Before refactoring:

```text
Understand existing behavior
Identify tests
Refactor
Run tests
Compare behavior
```

Large refactors should be broken into smaller changes.

---

# 63. Feature Flags

Feature flags should not be introduced by default.

They may be used later for:

* Experimental AI features
* Beta functionality
* Gradual rollout

Do not build a feature-flagging system before there is an actual need.

---

# 64. Experimental Features

Experimental features should be isolated from stable functionality.

Potential future examples:

```text
AI Financial Insights
Automatic Categorization
Investment Analysis
Smart Budget Suggestions
```

Experimental code should not compromise core financial functionality.

---

# 65. Future Backend

If FinOS eventually introduces a backend, the architecture should preserve the distinction between:

```text
Local Source of Truth
Remote Synchronization
```

The application should not assume that cloud availability is guaranteed.

The future synchronization layer should support:

```text
Offline
    ↓
Local Changes
    ↓
Sync
    ↓
Conflict Handling
```

The synchronization design will require a separate architecture document before implementation.

---

# 66. Development Priority

When trade-offs occur, prioritize:

```text
1. Financial correctness
2. Data safety
3. User privacy
4. Reliability
5. Maintainability
6. Testability
7. Performance
8. Visual polish
```

---

# 67. Final Development Principle

FinOS should be developed as a serious financial application even though V1 is a personal project.

The codebase should therefore avoid both extremes:

```text
Too simple:
"Just make it work."

Too complex:
"Build enterprise infrastructure before users exist."
```

The target is:

```text
Simple architecture
+
Strong financial correctness
+
Good tests
+
Clear documentation
+
Room to evolve
```

> **Build only what FinOS needs today, but build today's foundations correctly enough that tomorrow's FinOS does not require a rewrite.**
