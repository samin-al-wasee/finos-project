# FinOS

**FinOS** is a privacy-conscious, offline-first personal finance application built with Flutter.

It starts as a simple expense and financial account tracker and is designed to evolve into a broader personal finance hub covering budgeting, loans, savings, investments, portfolio tracking, automation, and AI-powered financial insights.

> **Record → Understand → Plan → Optimize → Automate → Assist**

---

## Project Status

**Status:** Early Development

FinOS is currently being developed as a personal-use-first application with the intention of eventually making it publicly available and generating revenue through:

* Advertising
* Donations
* Premium features

The initial target is approximately **USD 200–300/month** in revenue.

The product should prioritize usefulness, reliability, privacy, and low operating costs before pursuing aggressive monetization.

---

# 1. Product Vision

The long-term vision for FinOS is to become a single place where users can manage and understand their personal finances.

The eventual platform may include:

```text
FinOS
│
├── Financial Sources
├── Transactions
├── Categories
├── Budgets
├── Loans
├── Savings Goals
├── Net Worth
├── Investments
├── Portfolio
├── Automation
└── AI Financial Insights
```

The initial release will intentionally focus on a much smaller scope.

---

# 2. Initial Features

The first version of FinOS focuses on the fundamentals of personal financial tracking.

### Financial Sources

Users can create sources such as:

* Bank accounts
* Mobile financial service accounts
* Credit cards
* Debit cards
* Cash
* Other financial sources

### Transactions

Users can:

* Add income
* Add expenses
* Create transfers
* Edit transactions
* Delete transactions
* Search transactions
* Filter transactions
* View transaction history

### Categories

Support:

* Built-in categories
* Custom categories
* Category management

### Budgets

Users can:

* Create budgets
* Assign budgets to categories
* Track budget usage
* View remaining budget

### Loans

FinOS supports both:

* Money the user owes
* Money owed to the user

Loan repayments are tracked as part of the financial data model.

### Data Management

Users can:

* Export data locally
* Import data locally
* Restore data from backups

### Dashboard

The initial dashboard provides a clear overview of:

* Total balances
* Income
* Expenses
* Recent transactions
* Basic spending information

---

# 3. Long-Term Vision

The initial expense tracker is only the foundation.

Future versions may introduce:

```text
Recurring Transactions
        ↓
Advanced Budgeting
        ↓
Financial Reports
        ↓
Net Worth
        ↓
Savings Goals
        ↓
Investment Tracking
        ↓
Portfolio Management
        ↓
Automation
        ↓
AI Financial Insights
        ↓
Cloud Synchronization
```

The full roadmap is available in:

[`docs/ROADMAP.md`](docs/ROADMAP.md)

Roadmap items are future plans and should not be treated as current implementation requirements.

---

# 4. Product Principles

FinOS is built around several principles.

### Offline First

Core financial functionality should work without an internet connection.

### Privacy First

Financial data should remain under the user's control whenever possible.

### Simple First

The application should not overwhelm users with unnecessary financial complexity.

### Data Ownership

Users should be able to export their financial data.

### Trust

Financial calculations must be deterministic, testable, and transparent.

### AI as an Assistant

AI should help users understand and manage their finances rather than blindly making financial decisions for them.

### Low Infrastructure Cost

The initial product should avoid unnecessary backend infrastructure and recurring operating costs.

---

# 5. Technology Stack

## Application

* Flutter
* Dart

## Platforms

* Android
* iOS

## Data

FinOS is designed around a local-first architecture.

The specific persistence technology and domain architecture are defined in:

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

[`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)

## Development

AI-assisted development is an intentional part of the project.

Potential development assistants include:

* Claude Code
* GitHub Copilot
* Other AI coding agents

AI agents must follow the project's development rules and documentation.

---

# 6. Project Structure

The repository is organized approximately as follows:

```text
FinOS/
│
├── AGENTS.md
├── README.md
│
├── docs/
│   ├── ARCHITECTURE.md
│   ├── DATA_MODEL.md
│   ├── DEVELOPMENT.md
│   ├── REQUIREMENTS.md
│   ├── UI_DESIGN.md
│   ├── ROADMAP.md
│   ├── AI_WORKFLOW.md
│   │
│   └── adr/
│       └── README.md
│
├── lib/
├── test/
└── ...
```

The exact Flutter source structure may evolve as implementation progresses.

---

# 7. Documentation

The project documentation is divided by responsibility.

| Document               | Purpose                                    |
| ---------------------- | ------------------------------------------ |
| `AGENTS.md`            | Rules governing AI agents                  |
| `docs/ARCHITECTURE.md` | System architecture                        |
| `docs/DATA_MODEL.md`   | Domain and persistence model               |
| `docs/DEVELOPMENT.md`  | Development and coding standards           |
| `docs/REQUIREMENTS.md` | Functional and non-functional requirements |
| `docs/UI_DESIGN.md`    | UI/UX and theming guidelines               |
| `docs/ROADMAP.md`      | Product roadmap                            |
| `docs/AI_WORKFLOW.md`  | AI-assisted development workflow           |
| `docs/adr/`            | Significant architectural decisions        |

Documentation should be updated when the corresponding system or decision changes.

---

# 8. Getting Started

## Prerequisites

Install:

* Flutter SDK
* Dart SDK compatible with the project's Flutter version
* Android Studio / Android SDK for Android development
* Xcode for iOS development on macOS

Verify the Flutter installation:

```bash
flutter doctor
```

---

# 9. Clone the Repository

```bash
git clone <repository-url>
cd FinOS
```

---

# 10. Install Dependencies

```bash
flutter pub get
```

---

# 11. Run the Application

List available devices:

```bash
flutter devices
```

Run the application:

```bash
flutter run
```

A specific device can be selected when multiple devices are available.

---

# 12. Development Commands

## Format

```bash
dart format .
```

## Static Analysis

```bash
dart analyze
```

## Tests

```bash
flutter test
```

## Full Basic Validation

A normal development validation cycle should include:

```bash
dart format .
dart analyze
flutter test
```

Additional platform-specific validation may be required for Android and iOS changes.

---

# 13. Development Workflow

The general development process is:

```text
Requirement
    ↓
Understand
    ↓
Inspect Existing Code
    ↓
Review Relevant Documentation
    ↓
Plan
    ↓
Implement
    ↓
Write / Update Tests
    ↓
Format
    ↓
Analyze
    ↓
Run Tests
    ↓
Review Diff
    ↓
Complete
```

For AI-assisted development, see:

[`docs/AI_WORKFLOW.md`](docs/AI_WORKFLOW.md)

---

# 14. AI-Assisted Development

AI agents are expected to be active development collaborators on FinOS.

However, agents must not treat the repository as a blank project.

Before implementing functionality, they should understand:

```text
Current requirements
        ↓
Existing architecture
        ↓
Existing data model
        ↓
Existing UI system
        ↓
Existing implementation
        ↓
Tests
```

The primary AI governance document is:

[`AGENTS.md`](AGENTS.md)

---

# 15. Requirements

The current functional and non-functional requirements are maintained in:

[`docs/REQUIREMENTS.md`](docs/REQUIREMENTS.md)

Requirements should be treated as the authoritative description of currently intended product behavior.

Future ideas belong in:

[`docs/ROADMAP.md`](docs/ROADMAP.md)

and should not automatically become implementation requirements.

---

# 16. Architecture

FinOS architecture is documented in:

[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md)

Architecture changes with meaningful long-term consequences should be documented through an Architecture Decision Record.

See:

```text
docs/adr/
```

---

# 17. Data & Financial Correctness

Financial data is fundamentally different from ordinary application data.

Changes involving:

* Transactions
* Balances
* Loans
* Budgets
* Investments
* Net worth
* Import/export

must follow the established data model.

See:

[`docs/DATA_MODEL.md`](docs/DATA_MODEL.md)

Financial calculations should have automated tests wherever practical.

---

# 18. UI & Design

FinOS supports both Android and iOS.

The UI should maintain a consistent visual language across platforms while respecting platform conventions where appropriate.

The UI design system is documented in:

[`docs/UI_DESIGN.md`](docs/UI_DESIGN.md)

---

# 19. Privacy

FinOS deals with sensitive financial information.

The project follows a privacy-conscious approach:

* Core functionality should work locally.
* Users should be able to export their data.
* External services should only receive data when explicitly required.
* Third-party integrations should be evaluated before introduction.
* AI services should not receive financial information unnecessarily.

Future cloud synchronization and AI functionality must explicitly address data privacy before implementation.

---

# 20. Monetization

FinOS is intended to remain useful as a free application.

Potential revenue sources include:

```text
Free
 │
 ├── Advertising
 └── Donations

Premium
 │
 ├── Advanced analytics
 ├── Advanced AI features
 ├── Automation
 ├── Cloud functionality
 └── Other high-value features
```

The exact monetization model will evolve based on actual user behavior and operating costs.

Monetization must not compromise user trust or the integrity of financial data.

---

# 21. Contribution

FinOS is initially being developed as a personal project.

External contribution processes may be introduced later if the project becomes open to outside contributors.

Until then, project conventions are defined by:

[`AGENTS.md`](AGENTS.md)

and:

[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)

---

# 22. Current Development Priority

The current priority is:

```text
1. Establish the technical foundation
2. Implement financial sources
3. Implement transactions
4. Implement categories
5. Implement budgets
6. Implement loans
7. Implement dashboard
8. Implement import/export
9. Test and polish the core experience
10. Validate the product with real usage
```

Do not prematurely implement advanced roadmap functionality.

---

# 23. Roadmap

The high-level roadmap is:

```text
Phase 0
Foundation
    ↓
Phase 1
Core Expense Tracker
    ↓
Phase 1.5
Polish & Validation
    ↓
Phase 2
Smart Finance
    ↓
Phase 3
Personal Finance Hub
    ↓
Phase 4
AI & Automation
    ↓
Phase 5
Cloud & Synchronization
    ↓
Phase 6
Monetization & Scale
```

See:

[`docs/ROADMAP.md`](docs/ROADMAP.md)

for the complete roadmap.

---

# 24. Project Philosophy

FinOS should grow through deliberate iterations.

The project should avoid the common failure mode of attempting to build an entire platform before validating the core product.

The intended progression is:

```text
Useful
    ↓
Reliable
    ↓
Polished
    ↓
Intelligent
    ↓
Extensible
    ↓
Monetizable
```

The initial goal is not to build the ultimate personal finance application.

The initial goal is to build a **small, reliable, genuinely useful financial tool** that users would voluntarily continue using.

---

# 25. License

License details will be defined when the project's distribution model is finalized.

Until then, the repository should not assume that its source code is freely reusable or redistributable.
