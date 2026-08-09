# FinOS — AI Development Workflow

**Document Status:** Baseline
**Version:** 1.0
**Project:** FinOS Project
**Primary Development:** AI-assisted
**Framework:** Flutter

---

# 1. Purpose

This document defines how AI coding agents should be used to develop FinOS.

FinOS may be developed with tools such as:

* Claude Code
* GitHub Copilot
* OpenAI coding agents
* Other AI coding assistants

AI agents are considered development tools, not autonomous decision-makers.

The purpose of this document is to ensure AI-assisted development remains:

* Predictable
* Reviewable
* Testable
* Consistent
* Architecture-aware
* Safe for financial data

---

# 2. Relationship With AGENTS.md

`AGENTS.md` and this document serve different purposes.

### `AGENTS.md`

Defines:

> **Rules AI agents must obey.**

### `docs/AI_WORKFLOW.md`

Defines:

> **How AI agents should be used to develop FinOS.**

If there is a conflict, `AGENTS.md` takes precedence.

---

# 3. Core Principle

AI should accelerate development, not replace engineering judgment.

The preferred workflow is:

```text
Requirement
    ↓
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
Validate
    ↓
Commit
```

Agents should not skip directly from:

```text
"Build X"
```

to:

```text
"Modify files"
```

without first understanding the existing system.

---

# 4. Source of Truth Hierarchy

When deciding what to implement, agents should use the following priority order:

```text
1. Explicit current user/developer requirement
2. AGENTS.md
3. Relevant architectural/design documentation
4. Existing implementation
5. ROADMAP.md
6. AI assumptions
```

The lower items must not override the higher items.

---

# 5. Current Requirements vs Future Roadmap

The roadmap describes future intentions.

It does not authorize implementation.

For example:

```text
ROADMAP.md

Phase 4:
AI Financial Insights
```

does not mean an agent working on Phase 1 should:

```text
Install an AI SDK
Create an AI service
Create AI database tables
Add AI screens
```

unless explicitly requested.

Roadmap items are **future context**, not implicit tasks.

---

# 6. Task Classification

Before beginning work, the agent should classify the task.

Typical categories:

```text
Feature
Bug Fix
Refactor
UI Change
Database Change
Architecture Change
Testing
Documentation
Performance
Build / Tooling
```

This classification determines which documentation and validation steps are relevant.

---

# 7. Task Size

Tasks should generally be classified as:

### Small

Examples:

```text
Fix a validation message
Change button text
Fix a UI spacing issue
Add a simple unit test
```

### Medium

Examples:

```text
Add transaction filtering
Add budget creation
Add account editing
Implement import validation
```

### Large

Examples:

```text
Change database architecture
Implement cloud synchronization
Introduce investment tracking
Redesign navigation
Change state management
```

Large tasks require more investigation and planning.

---

# 8. Requirement Understanding

Before implementation, the agent should determine:

```text
What is being requested?
Why is it needed?
What existing functionality does it affect?
What are the expected inputs?
What are the expected outputs?
What edge cases exist?
```

If the requirement is ambiguous and the ambiguity affects correctness, the agent should ask for clarification rather than inventing behavior.

---

# 9. Repository Investigation

Before modifying code, inspect the relevant repository structure.

At minimum, determine:

```text
Relevant feature
Relevant screens
Relevant domain models
Relevant repositories
Relevant tests
Relevant theme/components
Relevant database code
```

The agent should search for existing implementations before creating new ones.

---

# 10. Reuse Before Creation

Before creating a new:

* Widget
* Service
* Repository
* Utility
* Formatter
* Validator
* Model
* Theme component

search the repository for an existing equivalent.

Preferred:

```text
Reuse existing abstraction
```

over:

```text
Create a second abstraction that does the same thing
```

---

# 11. Planning

For medium and large tasks, the agent should formulate an implementation plan before making significant changes.

Example:

```text
Plan:

1. Update transaction domain model
2. Add repository method
3. Add application-layer operation
4. Update controller
5. Update UI
6. Add unit tests
7. Add widget tests
8. Run analyzer and formatter
```

The plan should remain proportional to the task.

Do not create a 30-step plan for a one-line bug fix.

---

# 12. Architectural Changes

If a task requires changing architecture, the agent must stop treating it as a normal feature implementation.

Examples:

```text
Changing database technology
Changing state-management framework
Introducing a backend
Changing synchronization strategy
Changing domain boundaries
Changing authentication architecture
```

These changes should normally be documented through an ADR.

---

# 13. Implementation

During implementation, agents should:

* Keep changes focused.
* Follow existing conventions.
* Reuse existing components.
* Avoid unrelated refactoring.
* Avoid unnecessary dependencies.
* Preserve existing behavior unless change is requested.

---

# 14. Incremental Implementation

Large tasks should be implemented incrementally.

Prefer:

```text
Domain
 ↓
Data
 ↓
Application
 ↓
UI
 ↓
Tests
```

rather than creating a large amount of untested code and attempting to fix everything afterward.

---

# 15. Financial Features Require Extra Care

Financial functionality has a higher correctness requirement than ordinary UI functionality.

For changes involving:

* Money
* Balances
* Transactions
* Budgets
* Loans
* Transfers
* Investments
* Net worth

the agent must consider:

```text
Precision
Sign/direction
Rounding
Dates
Timezones
Currency
Atomicity
Historical records
Deletion
Editing
Import/export
```

---

# 16. Money Handling

Agents must follow the money representation defined in:

```text
docs/DATA_MODEL.md
```

Do not introduce a new money representation for convenience.

For example, if the project uses integer minor units:

```text
৳125.50
```

should be represented consistently according to the project's defined model.

Never introduce `double` merely because it makes arithmetic easier.

---

# 17. Transaction Semantics

Agents must understand the difference between:

```text
Income
Expense
Transfer
```

A transfer between two accounts must not incorrectly become:

```text
Expense + Income
```

unless the domain model explicitly defines it that way.

---

# 18. Editing Historical Data

Agents must consider the effect of editing an existing transaction.

For example:

```text
Old:
Food
৳500

Changed:
Food
৳800
```

The system must correctly recalculate affected:

* Account balances
* Budget usage
* Reports
* Aggregations

where applicable.

---

# 19. Deletion

Financial records should not be treated like ordinary UI records.

Before implementing deletion, determine whether the product requires:

```text
Hard delete
Soft delete
Archive
Undo
```

Do not invent destructive behavior.

---

# 20. Database Changes

Any database change should consider:

```text
Existing users
Existing records
Migration
Rollback implications
Import/export compatibility
Tests
```

Never modify the schema without considering existing data.

---

# 21. Import/Export Changes

Changes to the data model may affect backups.

When changing persisted models, agents should determine whether:

```text
Existing exports
```

remain compatible.

If the backup format changes, versioning and migration should be considered.

---

# 22. UI Implementation

UI changes must follow:

```text
docs/UI_DESIGN.md
```

Agents should reuse:

* Theme tokens
* Components
* Typography
* Spacing
* Semantic colors
* Existing interaction patterns

Do not introduce arbitrary visual styles.

---

# 23. UI Before/After Comparison

For meaningful UI changes, agents should inspect the affected screen before modifying it.

The agent should understand:

```text
Current layout
Current interaction
Current states
Current components
```

before replacing them.

---

# 24. Responsive UI

Agents must avoid device-specific assumptions.

Avoid:

```dart
width: 390
height: 844
```

or similar fixed layouts unless there is an explicit reason.

The application must work across supported Android and iOS screen sizes.

---

# 25. Accessibility

When creating interactive UI, agents should consider:

* Semantic labels
* Touch targets
* Text scaling
* Contrast
* Screen readers
* Color-independent meaning

Accessibility should not be added only at the end of the project.

---

# 26. Testing Strategy

AI-generated functionality should be accompanied by appropriate tests.

The level of testing depends on the change.

```text
Domain logic
→ Unit tests

UI behavior
→ Widget tests

Cross-layer workflow
→ Integration tests

Import/export
→ Round-trip tests
```

---

# 27. Test-First Where Appropriate

For financial logic, writing the test before or alongside implementation is strongly encouraged.

Example:

```text
Requirement:

An expense of ৳500 should reduce
the account balance by ৳500.
```

Test:

```text
Initial balance: ৳5,000
Expense: ৳500
Expected balance: ৳4,500
```

Then implement the behavior.

---

# 28. Edge Cases

Agents should actively consider edge cases.

Examples:

```text
Zero amount
Very large amount
Negative values
Empty descriptions
Missing category
Deleted account
Deleted category
Same source and destination account
Duplicate transaction
Invalid backup
Corrupted backup
Future date
Past date
Leap year
Timezone changes
```

Not every edge case requires a special implementation, but important ones should be tested.

---

# 29. Validation

After implementation, the agent should run the appropriate validation.

At minimum where applicable:

```bash id="d1tq91"
dart format .
dart analyze
flutter test
```

Additional commands may be required for:

```text
Integration tests
Android builds
iOS builds
Database migrations
```

---

# 30. Formatting

Agents should not leave formatting issues behind.

Use:

```bash id="8tdk8v"
dart format .
```

and verify the result.

---

# 31. Static Analysis

Run:

```bash id="u1o7g6"
dart analyze
```

Existing warnings should not automatically be ignored.

If an existing warning is unrelated to the current task, the agent should avoid expanding scope solely to fix it unless requested.

---

# 32. Test Failures

If tests fail after a change, the agent must investigate.

Do not simply:

```text
Delete the failing test
```

or:

```text
Change the expected value
```

without determining whether the implementation or test is incorrect.

---

# 33. Existing Test Failures

If tests were already failing before the task:

```text
1. Identify the existing failure.
2. Determine whether the change affects it.
3. Avoid misrepresenting it as caused by the current work.
4. Report it clearly.
```

Do not silently ignore existing failures.

---

# 34. Build Failures

If the application does not build, the agent should not report the task as fully complete.

The final report should distinguish:

```text
Implementation complete
```

from:

```text
Validation complete
```

---

# 35. Self-Review

Before finishing, the agent should review its own changes.

Check:

```text
Did I modify the correct files?
Did I introduce unnecessary complexity?
Did I duplicate existing functionality?
Did I violate architecture?
Did I introduce hardcoded UI values?
Did I forget tests?
Did I break existing behavior?
Did I update documentation if necessary?
```

---

# 36. Git Diff Review

Agents should inspect the final diff.

Conceptually:

```bash id="kaw9qv"
git diff
```

The goal is to catch:

* Accidental edits
* Debug code
* Temporary files
* Unrelated changes
* Secrets
* Large accidental rewrites

---

# 37. No Debug Artifacts

Before completion, remove:

```text id="yd5m4v"
print statements
Debug logs
Temporary files
Test credentials
Hardcoded test data
Unused imports
Dead code
```

unless they are intentionally part of the implementation.

---

# 38. Dependency Addition

AI agents must not automatically add packages because a package exists for the problem.

Before adding a dependency, evaluate:

```text
Is it actually necessary?
Can Flutter/Dart solve this?
Is the package maintained?
Does it support Android?
Does it support iOS?
Does it introduce privacy/security concerns?
Does it create unnecessary coupling?
```

---

# 39. Internet Research

AI agents may research:

* Flutter documentation
* Dart documentation
* Package documentation
* Platform APIs
* Technical standards

However, external information should not automatically override FinOS architecture.

The agent must adapt external solutions to FinOS rather than blindly copying them.

---

# 40. Package Documentation

When using a third-party package, the agent should verify the current API rather than relying on potentially outdated knowledge.

Particularly important for:

* Flutter plugins
* Database packages
* Authentication
* Cloud APIs
* AI SDKs
* Platform integrations

---

# 41. AI Hallucination Protection

Agents should not invent:

* APIs
* Package methods
* Flutter classes
* Database features
* Platform capabilities

If uncertain, investigate the actual API.

Do not write plausible-looking code based solely on memory.

---

# 42. No Fake Completion

An agent must never claim:

```text
"Tests pass"
```

unless tests were actually executed and passed.

Likewise:

```text
"Android build succeeds"
```

must not be claimed unless it was actually verified.

---

# 43. No Silent Workarounds

If a proper implementation is blocked, the agent must explain the blocker.

Do not silently introduce:

```text
Temporary fake data
Hardcoded values
Mock services
Disabled validation
Ignored errors
```

unless explicitly requested or clearly isolated as a development stub.

---

# 44. Documentation-Driven Development

For significant features, the agent should identify relevant documentation before implementation.

Example:

```text
Budget feature
    ↓
REQUIREMENTS.md
DATA_MODEL.md
ARCHITECTURE.md
UI_DESIGN.md
DEVELOPMENT.md
```

The agent should use the smallest relevant set rather than reading every document for every task.

---

# 45. When to Update Documentation

Update documentation when implementation changes:

```text
Architecture
Data model
Requirements
UI system
Development process
Roadmap
```

Do not update documentation merely to create unnecessary noise.

---

# 46. Architectural Decision Records

Create an ADR when a decision has meaningful long-term consequences.

Examples:

```text
Choosing database technology
Choosing state-management solution
Choosing synchronization architecture
Choosing authentication architecture
Choosing cloud storage strategy
Choosing investment data architecture
```

Simple implementation decisions do not require ADRs.

---

# 47. Human Approval Points

AI agents may implement ordinary scoped tasks independently.

Human approval should generally be requested before:

```text
Changing architecture
Changing database technology
Deleting large amounts of data
Introducing a backend
Introducing paid infrastructure
Changing authentication
Adding major third-party services
Changing financial semantics
Changing the product scope significantly
```

---

# 48. Autonomous Work

An agent may work autonomously when:

```text
The requirement is clear
The architecture is established
The change is localized
The risk is low
Tests are available
```

Example:

```text
Fix transaction form validation
```

is suitable for autonomous work.

---

# 49. High-Risk Work

An agent should be more conservative when working on:

```text
Financial calculations
Database migrations
Import/export
Authentication
Cloud synchronization
Encryption
Investment calculations
Loan calculations
Data deletion
```

These areas require additional validation.

---

# 50. Task Completion Report

When an agent finishes a task, it should provide a concise report.

Recommended format:

```text id="k8x5rj"
## Implemented

- Added ...
- Updated ...

## Tests

- Added ...
- Updated ...

## Validation

- dart format: PASS
- dart analyze: PASS
- flutter test: PASS

## Notes

- ...
```

If something failed:

```text id="q9xwcz"
## Validation

- dart format: PASS
- dart analyze: PASS
- flutter test: FAIL

Reason:
...
```

Never hide failures.

---

# 51. Commit Guidance

AI agents may prepare changes for commit.

Commit messages should follow the project's established convention:

```text
[type] Sentence case description
```

Types: feat, fix, test, docs, chore

Examples:

```text id="x8kgjc"
[feat] Add transaction filtering
[fix] Prevent duplicate transfer records
[test] Add loan repayment tests
[chore] Extract money formatter
[docs] Update architecture guide
```

Agents should not create commits unless explicitly authorized by the development workflow or user.

---

# 52. Multi-Agent Development

Multiple AI agents may work on FinOS.

When doing so, agents should assume other agents may modify the repository.

Therefore:

* Keep changes scoped.
* Avoid unnecessary file modifications.
* Avoid broad formatting changes.
* Check current repository state before editing.
* Do not overwrite unrelated work.

---

# 53. Parallel Work

Independent work may be parallelized.

Example:

```text
Agent A
Transaction domain

Agent B
Transaction UI

Agent C
Transaction tests
```

However, shared files should be modified carefully.

Parallel work should not result in competing architectural implementations.

---

# 54. Agent Handoff

When handing work from one AI agent to another, provide:

```text
Current task
What was implemented
What remains
Files changed
Tests run
Known issues
Important decisions
```

This prevents the next agent from reconstructing the entire context unnecessarily.

---

# 55. Context Efficiency

AI agents should not consume large amounts of context unnecessarily.

Prefer targeted inspection:

```text
Relevant documentation
Relevant feature
Relevant tests
Relevant dependencies
```

rather than reading the entire repository for every task.

---

# 56. Avoid Context Pollution

Do not include unnecessary information in prompts.

A good task:

```text
Implement transaction filtering by category
in the existing transaction screen.

Follow the architecture and UI design docs.
Add appropriate tests.
```

A poor task:

```text
Read the entire repository, rethink everything,
and implement anything that seems useful.
```

---

# 57. AI Prompting Principle

Prompts should describe:

```text
What
Why
Constraints
Expected behavior
```

rather than prescribing every implementation detail unless the implementation is already decided.

This allows the agent to work within the established architecture.

---

# 58. Agent Should Ask Instead of Guessing

The agent should ask for clarification when ambiguity affects:

```text
Financial correctness
Data loss
Architecture
Security
Product behavior
```

For minor presentation details, the agent may use reasonable existing conventions.

---

# 59. No Scope Creep

If an agent discovers unrelated problems while working:

```text
Current task:
Add transaction filtering

Discovered:
Unrelated dashboard performance issue
```

The agent should normally:

```text
Finish filtering
Report dashboard issue
```

rather than silently fixing everything.

---

# 60. Exception: Critical Issues

If an unrelated issue creates:

* Data corruption
* Security vulnerability
* Build failure
* Serious financial calculation error

the agent should flag it immediately.

Depending on severity, implementation may need to stop.

---

# 61. AI and Product Decisions

AI agents may provide recommendations.

They should distinguish:

```text
Requirement
Decision
Recommendation
Assumption
```

For example:

```text
Requirement:
Users can export data.

Recommendation:
Use JSON as the initial backup format.

Decision:
JSON selected for V1.
```

Do not present recommendations as established requirements.

---

# 62. AI and Financial Advice

Future AI financial features must distinguish:

```text
Financial data analysis
```

from:

```text
Personalized financial advice
```

AI should not make unsupported claims.

For example:

```text
Your spending increased 22%.
```

is a data-derived observation.

Whereas:

```text
You should invest $500 in X.
```

is a substantially different and higher-risk capability.

The latter requires explicit product, safety, and legal consideration before implementation.

---

# 63. AI Cost Awareness

Future AI functionality may incur per-request costs.

Agents implementing AI features should consider:

```text
Request frequency
Token usage
Caching
Local computation
Model selection
User limits
Premium requirements
```

Do not make unnecessary AI requests when deterministic local calculations can solve the problem.

---

# 64. Privacy

FinOS handles sensitive financial information.

Agents must assume financial data is sensitive.

Do not unnecessarily send financial data to:

```text
External APIs
AI providers
Analytics systems
Logging services
Third-party integrations
```

Any future external data flow must be explicitly designed and documented.

---

# 65. Final AI Development Principle

AI agents should behave like disciplined engineering collaborators.

They should:

```text
Understand before changing.
Reuse before creating.
Test before claiming.
Verify before assuming.
Ask before making risky decisions.
Document decisions that matter.
```

The objective is not to maximize the amount of code an AI agent produces.

The objective is to maximize the amount of **correct, maintainable product progress** produced by AI assistance.

> **AI writes the code; FinOS's architecture, requirements, tests, and engineering standards decide whether that code belongs in the project.**
