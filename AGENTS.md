# AGENTS.md — AI Development Guidelines

## 1. Purpose

This document defines the rules, constraints, and development practices that AI coding agents must follow when working on the Personal Finance project.

This includes, but is not limited to:

* Claude Code
* GitHub Copilot
* OpenAI Codex
* Gemini-based coding agents
* Other autonomous or semi-autonomous development agents

This document is a project-level development contract.

AI agents must follow these rules in addition to the requirements and architecture documented in the project.

---

# 2. Project Overview

**Project Name:** FinOS Project

**Platform:** Flutter

**Initial Platforms:**

* Android
* iOS

**Architecture:** Local-first / Offline-first

**Backend:** None in V1

**Authentication:** None in V1

**Primary V1 Purpose:**

A personal finance application for tracking:

* Financial accounts
* Income
* Expenses
* Transfers
* Categories
* Budgets
* Loans
* Financial summaries
* Local backups

The long-term vision may expand into a broader personal-finance platform with:

* Cloud synchronization
* Investments
* Portfolio management
* Net worth
* AI-powered insights
* Advanced automation
* Financial integrations

Agents must not implement future functionality merely because it is mentioned in project documentation.

Future functionality must only be implemented when explicitly requested or when the current roadmap authorizes it.

---

# 3. Source of Truth

Agents must understand the distinction between project documents.

| Document               | Authority                                      |
| ---------------------- | ---------------------------------------------- |
| `docs/REQUIREMENTS.md` | What the product should do                     |
| `docs/ARCHITECTURE.md` | How the software should be structured          |
| `docs/DATA_MODEL.md`   | Financial entities and data rules              |
| `docs/UI_DESIGN.md`    | UI/UX and design-system rules                  |
| `docs/DEVELOPMENT.md`  | Development workflow and engineering practices |
| `docs/ROADMAP.md`      | Planned feature progression                    |
| `AGENTS.md`            | How AI agents must operate                     |
| `README.md`            | Human-facing project overview                  |

When documents conflict, do not silently choose one.

Stop and identify the conflict.

The agent must not modify requirements simply to make an implementation easier.

---

# 4. Fundamental Development Principles

Agents must follow these principles:

1. **Do not invent requirements.**
2. **Do not expand scope without explicit approval.**
3. **Protect financial data integrity above convenience.**
4. **Prefer simple solutions over unnecessary abstractions.**
5. **Keep the application local-first and offline-first in V1.**
6. **Do not introduce a backend unless explicitly requested.**
7. **Do not introduce authentication unless explicitly requested.**
8. **Do not introduce cloud services unless explicitly requested.**
9. **Keep financial business logic independent from UI.**
10. **Write tests for financial calculations.**
11. **Do not expose sensitive financial data through logs.**
12. **Preserve future extensibility without prematurely implementing future features.**
13. **Prefer established Flutter/Dart patterns over unnecessary custom infrastructure.**
14. **Do not make large architectural changes to solve small problems.**

---

# 5. Scope Control

Scope control is a critical requirement.

Agents must not implement features solely because they appear in:

* Future Direction
* Future Roadmap
* Architecture possibilities
* Comments
* TODOs
* Ideas
* Documentation examples

For example, the following must NOT be introduced automatically:

* Firebase
* Supabase
* Custom backend
* PostgreSQL
* Google authentication
* Facebook authentication
* Google Drive synchronization
* Bank APIs
* Investment APIs
* AI APIs
* Analytics platforms

unless explicitly requested.

If an implementation appears to require one of these technologies, the agent must explain why before introducing it.

---

# 6. V1 Constraints

The following constraints are mandatory for V1.

## 6.1 No Backend

Do not introduce:

* API servers
* Cloud databases
* Server-side authentication
* Server-side business logic

unless explicitly requested.

## 6.2 No Mandatory Authentication

The application must remain usable without:

* Login
* Signup
* Email
* Google authentication
* Apple authentication
* Facebook authentication

## 6.3 Local-First

Core functionality must work locally.

## 6.4 Offline-First

Internet connectivity must not be required for core functionality.

## 6.5 User-Owned Data

Users must be able to export and restore their financial data.

---

# 7. Financial Data Rules

Financial data must be treated as high-integrity data.

Agents must never casually modify financial calculation logic.

Before modifying financial business logic, identify:

* Existing calculation rules
* Affected entities
* Existing tests
* Potential side effects

Changes to financial calculations must include or update tests.

---

# 8. Transaction Rules

The application supports three primary transaction types:

```text
Income
Expense
Transfer
```

## 8.1 Income

Income increases the user's financial position/account balance.

## 8.2 Expense

Expense decreases the user's financial position/account balance.

## 8.3 Transfer

A transfer moves money between financial accounts.

Example:

```text
Bank Account
    ↓
Cash
```

must NOT be interpreted as:

```text
Income + Cash
Expense - Bank Account
```

Transfers must not artificially inflate:

* Income
* Expenses
* Net income
* Spending analytics

Any change to transaction semantics requires corresponding tests.

---

# 9. Account Balance Integrity

Account balances must remain consistent with the underlying transactions.

Conceptually:

```text
Current Balance
=
Opening Balance
+
Income
- Expenses
± Transfers
```

The exact implementation must follow the domain model defined in `docs/DATA_MODEL.md`.

Agents must not introduce multiple competing sources of truth for balances without an explicit architectural decision.

---

# 10. Loan Integrity

Loans must distinguish between:

* Money lent
* Money borrowed

Loan repayments must correctly affect outstanding balances.

Agents must not treat loan principal as ordinary income or expense unless the domain model explicitly requires it.

Changes to loan accounting must include tests for:

* Initial principal
* Partial repayment
* Full repayment
* Overpayment handling
* Outstanding balance
* Status transitions

where applicable.

---

# 11. Budget Integrity

Budget calculations must be deterministic.

Agents must clearly define which transaction types are included in budget calculations.

Transfers should generally not count as expenses.

Changes to budget calculation rules must be documented and tested.

---

# 12. Database Rules

The database is a critical part of the application.

Agents must:

* Keep database access isolated from UI.
* Use migrations when required by the chosen database technology.
* Avoid destructive schema changes without explicit approval.
* Preserve existing user data during schema evolution.
* Provide migration paths for existing data.
* Validate database operations.
* Prefer atomic operations for related financial changes.

Agents must not delete or recreate the entire local database as a shortcut for schema changes.

---

# 13. Data Migration Rules

When modifying persistent data structures:

1. Identify existing stored data.
2. Determine whether migration is required.
3. Implement a safe migration.
4. Test migration behavior.
5. Verify backward/forward compatibility where applicable.
6. Update `docs/DATA_MODEL.md`.

Never assume the database is disposable merely because the project is still under development.

---

# 14. Import / Export Rules

Import/export is part of the user's data ownership model.

Agents must:

* Validate imported data.
* Reject malformed data safely.
* Avoid partial imports.
* Preserve existing data when import fails.
* Version export formats.
* Handle schema evolution.

A failed import must never leave the user's existing database in a corrupted or partially modified state.

---

# 15. Privacy Rules

Financial information is sensitive.

Agents must never log:

* Transaction amounts unnecessarily
* Account balances
* Account numbers
* Loan details
* Financial descriptions
* Imported financial records
* Exported financial data

Avoid logging entire domain objects.

Bad:

```dart
debugPrint(transaction.toString());
```

Preferred:

```dart
debugPrint('Transaction creation failed');
```

If diagnostic information is required, log only the minimum non-sensitive context.

---

# 16. Security Rules

Agents must:

* Never commit secrets.
* Never hardcode API keys.
* Never commit credentials.
* Never commit OAuth secrets.
* Never commit private certificates.
* Never store passwords in source code.
* Follow platform security practices.

If a secret is accidentally exposed, treat it as compromised and recommend rotation rather than simply deleting it from the latest commit.

---

# 17. Architecture Rules

The application should maintain clear separation between:

```text
Presentation
    ↓
Application
    ↓
Domain
    ↓
Data
```

The exact architecture should be documented in:

```text
docs/ARCHITECTURE.md
```

Agents should not place substantial business logic directly inside:

* Widgets
* Screens
* Pages
* UI callbacks

Business rules belong in appropriate application/domain layers.

---

# 18. Dependency Rules

Before adding a new dependency, agents should evaluate:

1. Is it actually necessary?
2. Does Flutter/Dart already provide the capability?
3. Is the package actively maintained?
4. Is it compatible with Android and iOS?
5. Does it introduce unnecessary native/platform complexity?
6. Does it introduce privacy or security concerns?
7. Does it increase application size significantly?
8. Is there a simpler alternative?

Do not add dependencies merely for convenience.

If a dependency is added, explain its purpose in the relevant architectural documentation when the dependency has meaningful architectural impact.

---

# 19. Flutter Rules

Follow standard Dart and Flutter conventions.

Prefer:

* Strong typing
* Small focused classes
* Composition
* Immutable state where practical
* Clear widget boundaries
* Reusable components
* Dependency injection where justified
* Testable business logic

Avoid:

* Massive widgets
* God classes
* Excessive global state
* Business logic in UI
* Excessive inheritance
* Premature abstractions
* Duplicate business rules

---

# 20. UI Rules

The application must follow the design system documented in:

```text
docs/UI_DESIGN.md
```

Agents must:

* Use centralized theme values.
* Avoid arbitrary colors.
* Avoid arbitrary spacing values when design tokens exist.
* Support light/dark/system themes.
* Respect Android/iOS conventions.
* Maintain accessibility.
* Avoid UI patterns that make financial information difficult to understand.

Do not introduce a new visual pattern when an existing design-system component can be reused.

---

# 21. Financial Color Semantics

Do not rely solely on color to communicate financial state.

For example:

```text
+ $1,500
- $250
```

is preferred over communicating only:

```text
Green
Red
```

Financial meaning should remain clear to users with color-vision deficiencies and accessibility settings enabled.

---

# 22. Performance Rules

Agents should consider performance when working with:

* Large transaction lists
* Dashboard calculations
* Charts
* Database queries
* Import/export
* Search/filter operations

Avoid unnecessary:

* Full database scans
* Rebuilding large widget trees
* Repeated expensive calculations
* Synchronous heavy processing on the UI isolate

Do not optimize prematurely.

Measure or identify an actual bottleneck before introducing complicated optimization.

---

# 23. Testing Requirements

Changes must include appropriate tests.

### Financial logic

Tests are mandatory for changes affecting:

* Balances
* Transactions
* Transfers
* Budgets
* Loans
* Recurring transactions
* Import/export

### UI

UI tests should be added for important user flows where appropriate.

### Regression

When fixing a bug, prefer adding a regression test that would have caught the bug.

---

# 24. Test Quality

Do not write tests merely to increase coverage percentages.

Tests should verify meaningful behavior.

Prefer:

```text
Given opening balance = 1000
When an expense of 200 is recorded
Then balance = 800
```

over tests that only verify implementation details.

Financial tests should prioritize behavior and invariants.

---

# 25. Error Handling

Errors must be:

* Predictable
* Meaningful
* Recoverable where possible
* Safe

Do not silently swallow errors.

Avoid exposing technical exceptions directly to users.

Bad:

```text
SQLiteException: UNIQUE constraint failed...
```

Prefer:

```text
We couldn't save this transaction.
Please try again.
```

Detailed technical information may remain available to developers through safe diagnostics.

---

# 26. Git Rules

Agents must keep changes focused.

Prefer:

```text
feat: add transaction creation
fix: correct transfer balance calculation
test: add budget calculation coverage
refactor: extract account repository
docs: update data model
```

Avoid combining unrelated changes in one commit.

Agents should not rewrite Git history unless explicitly instructed.

Agents must not:

* Force push
* Delete branches
* Reset user changes
* Discard uncommitted work

without explicit permission.

---

# 27. Existing User Changes

Before modifying files, agents must consider whether there are existing uncommitted changes.

Never overwrite, discard, or reset user work without explicit permission.

If an existing change conflicts with the requested implementation:

1. Preserve the user's work.
2. Explain the conflict.
3. Ask for direction if necessary.

---

# 28. Documentation Rules

Documentation should remain synchronized with implementation.

When a change affects:

* Requirements → update `docs/REQUIREMENTS.md`
* Architecture → update `docs/ARCHITECTURE.md`
* Data model → update `docs/DATA_MODEL.md`
* UI/design system → update `docs/UI_DESIGN.md`
* Development process → update `docs/DEVELOPMENT.md`
* Planned functionality → update `docs/ROADMAP.md`

Do not create duplicate documentation containing conflicting information.

---

# 29. AI Agent Workflow

For non-trivial tasks, agents should follow this workflow:

```text
1. Understand the request
        ↓
2. Inspect relevant project documentation
        ↓
3. Inspect existing implementation
        ↓
4. Identify affected components
        ↓
5. Form an implementation plan
        ↓
6. Implement the smallest appropriate change
        ↓
7. Run relevant tests
        ↓
8. Run formatting/linting
        ↓
9. Review the diff
        ↓
10. Update documentation if required
        ↓
11. Report what changed
```

Agents should not immediately start modifying code for non-trivial tasks without first understanding the existing implementation.

---

# 30. Repository Inspection

Before making architectural or cross-cutting changes, inspect:

* `README.md`
* `AGENTS.md`
* Relevant files under `docs/`
* Existing feature implementation
* Tests
* Database/schema code
* Existing dependencies

Do not make assumptions about existing architecture when the repository can be inspected.

---

# 31. Minimal Change Principle

Implement the smallest change that correctly satisfies the request.

Do not:

* Refactor unrelated code
* Rename unrelated files
* Replace working libraries
* Change architecture unnecessarily
* Rewrite existing features
* Introduce abstractions without a concrete need

A small feature should normally result in a small, focused change.

---

# 32. Refactoring Rules

Refactoring is allowed when it improves the requested implementation, but unrelated refactoring should be avoided.

Large refactors require explicit justification.

If a refactor is necessary because the current architecture prevents the requested feature, explain:

* Why the existing architecture is insufficient
* What will change
* What risks exist
* Why the proposed approach is preferable

---

# 33. AI-Specific Anti-Patterns

Agents must avoid the following common behaviors:

### Do not over-engineer

Do not build infrastructure for hypothetical future requirements.

### Do not gold-plate

Do not add features that were not requested.

### Do not assume SaaS architecture

This is currently a local-first mobile application, not a backend SaaS platform.

### Do not blindly follow generated suggestions

AI-generated code must be evaluated against project requirements.

### Do not optimize for code volume

The goal is correct, maintainable software—not maximum code generation.

### Do not hide uncertainty

If an implementation decision is ambiguous, state the uncertainty rather than silently choosing a potentially destructive interpretation.

---

# 34. Future Features

Future features should be implemented only when explicitly requested or when the current roadmap identifies them as active work.

Potential future features include:

* Google Drive backup
* Cloud synchronization
* Authentication
* Investments
* Portfolio management
* Net worth
* AI financial insights
* AI-powered budgeting
* Advanced automation
* Bank integrations

Their presence in documentation does not authorize implementation.

---

# 35. AI / LLM Feature Rules

When AI functionality is eventually introduced:

* Do not send sensitive financial data to external AI services without explicit product requirements and privacy review.
* Minimize the amount of financial data sent to external services.
* Avoid sending unnecessary personally identifiable information.
* Clearly separate AI-generated suggestions from deterministic financial calculations.
* AI must never silently override financial calculations.
* AI-generated financial advice must be treated as advisory rather than authoritative.
* Deterministic application logic remains the source of truth for balances, budgets, transactions, and other financial calculations.

For example:

```text
Deterministic System
        │
        ├── Balance calculation
        ├── Budget calculation
        ├── Loan calculation
        └── Transaction calculation
                    │
                    ↓
              AI Analysis
                    │
                    ↓
            User-facing Insight
```

AI may interpret data.

AI must not become the source of truth for financial accounting.

---

# 36. Definition of Done

A task is considered complete when:

* The requested behavior is implemented.
* Existing functionality remains intact.
* Relevant tests pass.
* New financial logic has appropriate test coverage.
* Code is formatted.
* Static analysis/linting passes where applicable.
* No secrets or sensitive data are introduced.
* Documentation is updated when required.
* The final diff contains no unrelated changes.

---

# 37. Final Agent Checklist

Before considering a task complete, verify:

### Requirements

* [ ] Does the implementation satisfy the requested requirement?
* [ ] Did I avoid implementing unrelated functionality?
* [ ] Did I respect V1 scope?

### Architecture

* [ ] Does the implementation follow the existing architecture?
* [ ] Did I avoid unnecessary architectural changes?
* [ ] Did I keep business logic out of UI?

### Financial Integrity

* [ ] Are calculations correct?
* [ ] Are transfers handled correctly?
* [ ] Are balances consistent?
* [ ] Are budgets consistent?
* [ ] Are loan balances consistent?

### Data

* [ ] Is user data preserved?
* [ ] Are database changes safe?
* [ ] Are import/export operations safe?

### Security & Privacy

* [ ] Did I avoid logging financial data?
* [ ] Did I avoid introducing secrets?
* [ ] Did I preserve local-first privacy?

### UI

* [ ] Does the UI follow the design system?
* [ ] Does it work in light and dark themes?
* [ ] Does it respect Android/iOS conventions?
* [ ] Is it accessible?

### Testing

* [ ] Did I add/update relevant tests?
* [ ] Did I run the relevant test suite?
* [ ] Did I check for regressions?

### Documentation

* [ ] Did I update affected documentation?
* [ ] Is the documentation consistent with the implementation?

### Final Review

* [ ] Did I inspect the final diff?
* [ ] Are there unrelated changes?
* [ ] Is the implementation simpler than necessary alternatives?

---

# 38. Authority

This file governs AI-assisted development behavior.

When an AI agent is uncertain:

1. Prefer existing project decisions over assumptions.
2. Prefer the simplest solution consistent with the requirements.
3. Preserve user data and existing work.
4. Do not expand scope.
5. Ask for clarification when a decision could materially affect architecture, data integrity, security, privacy, or product scope.

The agent's objective is not to maximize implementation.

The objective is to build **correct, maintainable, secure, privacy-conscious software that follows the project's requirements and roadmap.**
