# FinOS — UI/UX Design System

**Document Status:** Baseline
**Version:** 1.0
**Project:** FinOS Project
**Platform:** Flutter
**Target Platforms:** Android, iOS

---

# 1. Purpose

This document defines the UI/UX principles and design system for FinOS.

It governs:

* Visual identity
* Navigation
* Screen structure
* Layout
* Typography
* Colors
* Components
* Forms
* Financial data presentation
* Light/dark themes
* Android/iOS adaptation
* Accessibility
* Empty/loading/error states
* Animation
* UX conventions

The goal is to create an application that feels like a polished financial product rather than a generic CRUD application.

---

# 2. Design Goals

FinOS should feel:

* Clean
* Modern
* Trustworthy
* Calm
* Fast
* Financially focused
* Easy to understand
* Information-dense without being overwhelming

The interface should prioritize clarity over decoration.

Financial information should be immediately understandable.

---

# 3. Core UX Principles

## 3.1 Fast Capture

Recording an expense should require as few interactions as reasonably possible.

The most common action should be:

```text
Open app
   ↓
Add transaction
   ↓
Enter amount
   ↓
Select/confirm category
   ↓
Save
```

The user should not have to navigate through multiple unnecessary screens for a simple expense.

---

## 3.2 Information Hierarchy

Important financial information should have stronger visual hierarchy.

Example:

```text
Total Balance

৳125,450.00

This Month

Income        Expenses
৳80,000       ৳42,500
```

The user should understand their financial position within seconds.

---

## 3.3 Progressive Disclosure

Do not display every available option at once.

Simple transactions should remain simple.

Advanced functionality should appear when needed.

For example:

```text
Basic Transaction
        ↓
Amount
Account
Category
Date
        ↓
More options
        ↓
Notes
Recurring
Additional metadata
```

---

## 3.4 Consistency

Identical concepts must behave and look consistently throughout the application.

For example:

* Add buttons
* Delete actions
* Edit actions
* Account selectors
* Category selectors
* Amount fields
* Date pickers
* Confirmation dialogs

should use consistent patterns.

---

# 4. Platform Strategy

FinOS uses Flutter with a shared design system.

The application should have:

```text
Shared Product Identity
        │
        ├── Android adaptation
        │
        └── iOS adaptation
```

The goal is not to create two completely different applications.

Instead:

* Branding remains consistent.
* Information architecture remains consistent.
* Core interaction patterns remain consistent.
* Platform conventions are respected where appropriate.

---

# 5. Material Design

Android UI should use Material 3 principles.

Prefer Flutter's Material 3 components for:

* Buttons
* Cards
* Dialogs
* Bottom sheets
* Text fields
* Navigation
* Menus
* Chips
* Snackbars
* Lists

Custom components should only be introduced when standard components do not adequately support the product experience.

---

# 6. iOS Design

iOS should respect platform conventions.

Consider:

* Safe areas
* Navigation gestures
* Modal presentation
* Keyboard behavior
* System typography settings
* Touch interactions
* Platform-specific controls

Flutter adaptive components may be used where useful.

The application should not look like an Android application awkwardly ported to iOS.

---

# 7. Navigation

The primary navigation should expose the most important areas of the application.

Initial conceptual navigation:

```text
                    FinOS
                      │
        ┌─────────────┼─────────────┐
        │             │             │
    Dashboard    Transactions    Accounts
        │
        ├─────────────┐
        │             │
     Budgets        Loans
```

A bottom navigation structure is a strong candidate for the primary mobile navigation.

Potential initial tabs:

```text
Home
Transactions
Accounts
Budgets
```

Loans may either be a dedicated destination or accessible through Accounts/More depending on the final information architecture.

The final navigation structure should prioritize usage frequency rather than forcing every feature into primary navigation.

---

# 8. Dashboard

The dashboard is the primary financial overview.

It should answer:

> "How am I doing financially?"

within a few seconds.

Potential sections:

```text
┌──────────────────────────────┐
│ Total Balance                │
│ ৳125,450                     │
└──────────────────────────────┘

Income        Expenses
৳80,000       ৳42,500

┌──────────────────────────────┐
│ Budget                       │
│ ███████████░░░ 72%           │
│ ৳14,000 remaining             │
└──────────────────────────────┘

Recent Transactions
───────────────────────────────
Food                 -৳850
Salary             +৳80,000
Transport            -৳300
```

The dashboard should remain useful without overwhelming the user with analytics.

---

# 9. Transaction Screen

Transactions are one of the primary features of FinOS.

The transaction list should provide:

* Date grouping
* Category
* Description
* Amount
* Account
* Income/expense distinction

Example:

```text
TODAY

🍔 Lunch
Food · Bank
-৳450

🚕 Uber
Transport · Card
-৳320


YESTERDAY

💰 Salary
Income · Bank
+৳80,000
```

---

# 10. Transaction Creation

Transaction creation should be optimized for speed.

Initial form:

```text
Amount
──────────────
৳ 0.00

Type
[ Expense ] [ Income ] [ Transfer ]

Account
[ Bank Account ]

Category
[ Food ]

Date
[ Today ]

Notes
[ Optional ]

             Save
```

The amount should be visually dominant.

---

# 11. Amount Input

The amount field should:

* Be easy to access
* Use appropriate numeric keyboard
* Display currency
* Avoid unnecessary decimal complexity
* Validate invalid values
* Prevent negative values when transaction direction already determines sign

The user should generally enter:

```text
500
```

rather than:

```text
-500
```

for an expense.

The transaction type determines the direction.

---

# 12. Transaction Type Selection

Transaction types:

```text
Expense
Income
Transfer
```

should be clearly distinguishable.

Do not rely only on color.

Example:

```text
[ Expense ] [ Income ] [ Transfer ]
```

The selected state should have both:

* Visual styling
* Clear semantic indication

---

# 13. Transfer UX

Transfers require a different form.

Example:

```text
Transfer

From
[ Bank Account ]

To
[ Cash ]

Amount
[ ৳5,000 ]

Date
[ Today ]

Notes
[ Optional ]

Save Transfer
```

The UI should make the direction unmistakable.

---

# 14. Account Screen

The account screen should provide a clear overview of financial sources.

Example:

```text
Accounts

Bank
৳80,000

bKash
৳12,500

Cash
৳5,000

Credit Card
-৳8,000
```

Accounts should be grouped or categorized where useful.

---

# 15. Account Details

An account details page may contain:

```text
Bank Account

৳80,000

Income
৳100,000

Expenses
৳20,000

Recent Transactions
───────────────────
...
```

The user should be able to edit/archive the account.

---

# 16. Account Creation

Account creation should support:

```text
Account Name
Account Type
Currency
Opening Balance
```

Example:

```text
Account Name
[ Main Bank ]

Type
[ Bank Account ]

Currency
[ BDT ]

Opening Balance
[ ৳50,000 ]

Create Account
```

---

# 17. Categories

Categories should be easy to recognize visually.

Potential representation:

```text
🍔 Food
🚗 Transport
🏠 Rent
🛍 Shopping
🎮 Entertainment
💡 Utilities
```

Icons should remain secondary to category names.

The application should not require users to understand an icon without text.

---

# 18. Category Management

Users should be able to:

* View categories
* Create categories
* Rename custom categories
* Archive categories
* Assign icons where supported

Built-in categories should be protected from destructive deletion.

---

# 19. Budget Screen

The budget screen should answer:

> "How much can I still spend?"

Example:

```text
Monthly Budget

Food
৳7,500 / ৳10,000
██████████████░░░
৳2,500 remaining

Transport
৳3,200 / ৳5,000
██████████░░░░░░
৳1,800 remaining
```

The user should be able to quickly identify:

* Healthy budgets
* Budgets approaching their limit
* Exceeded budgets

---

# 20. Budget States

Use multiple visual signals.

Example:

```text
Healthy
██████░░░░

Near limit
█████████░

Exceeded
██████████+
```

Do not rely solely on green/yellow/red.

Textual information should communicate the state.

---

# 21. Loan Screen

Loans should be clearly separated into:

```text
Money I Owe
Money Owed to Me
```

Example:

```text
Loans

I Owe
──────────────
Bank Loan
৳250,000 remaining

Friend
৳10,000 remaining


Owed to Me
──────────────
John
৳5,000 remaining
```

This avoids ambiguity.

---

# 22. Loan Details

A loan detail screen should show:

```text
John

Owed to Me

Original Amount
৳20,000

Paid
৳12,000

Remaining
৳8,000

Due
15 Sep 2026
```

Repayment history should be accessible.

---

# 23. Settings

Settings should contain configuration rather than primary financial workflows.

Potential sections:

```text
Settings

Appearance
Currency
Categories
Notifications
Data
Privacy
About
```

Future functionality may add:

```text
Cloud Sync
AI
Integrations
```

These should not appear until implemented.

---

# 24. Floating Action Button / Primary Action

The application may use a prominent global action for:

```text
+ Add Transaction
```

The exact implementation should be determined after the navigation prototype.

The primary action should remain easy to access without covering important content.

---

# 25. Color System

The final brand palette is not yet fixed.

The implementation should define colors centrally rather than scattering hex values throughout the application.

Conceptual semantic colors:

```text
Primary
Secondary
Surface
Background
Income
Expense
Transfer
Warning
Error
Success
Text
Muted Text
Border
```

Financial semantic colors must remain consistent.

---

# 26. Financial Color Semantics

A possible semantic convention:

```text
Income    → Positive semantic
Expense   → Negative semantic
Transfer  → Neutral semantic
Warning   → Warning semantic
Error     → Error semantic
```

Exact colors are intentionally not fixed in this document.

The final palette should provide sufficient contrast in both light and dark themes.

---

# 27. Dark Mode

FinOS must support:

```text
Light
Dark
System
```

Dark mode must not simply invert colors.

The design system should define dedicated dark-theme values.

Pay particular attention to:

* Financial values
* Charts
* Cards
* Dividers
* Secondary text
* Disabled states

---

# 28. Typography

Typography should provide clear hierarchy.

Conceptual levels:

```text
Display
Headline
Title
Body
Label
Caption
Financial Value
```

Large financial values should be visually prominent.

Example:

```text
TOTAL BALANCE

৳125,450
```

rather than displaying the balance with the same typography as ordinary list text.

---

# 29. Spacing

Use a consistent spacing scale.

A base spacing system should be defined centrally.

Example conceptual scale:

```text
4
8
12
16
24
32
48
```

The exact tokens may be adjusted during implementation.

Avoid arbitrary values throughout widgets.

---

# 30. Corner Radius

Use a consistent radius system.

Potential tokens:

```text
Small
Medium
Large
Full
```

The application should avoid mixing unrelated corner-radius styles.

---

# 31. Cards

Cards should be used to group meaningful information.

Good uses:

* Account summary
* Budget summary
* Financial overview
* Insight
* Loan summary

Avoid wrapping every list item in a card.

Excessive cards increase visual noise.

---

# 32. Lists

Lists should prioritize scanning.

A transaction list should expose the most important information first:

```text
Category / Description
Account / Metadata
Amount
```

Secondary information can be visually reduced.

---

# 33. Forms

Forms should:

* Use clear labels
* Provide sensible defaults
* Validate immediately where appropriate
* Avoid unnecessary fields
* Clearly indicate required fields
* Preserve user input when validation fails

Forms should not force users to fill fields that are not needed for the operation.

---

# 34. Validation

Validation messages should be human-readable.

Bad:

```text
amount.invalid
```

Better:

```text
Enter an amount greater than 0.
```

Errors should appear close to the relevant field where possible.

---

# 35. Confirmation Dialogs

Confirmation should be used for destructive or potentially irreversible actions.

Examples:

* Delete transaction
* Delete account
* Restore/import data
* Clear data

Avoid confirmation dialogs for routine actions.

For example:

```text
Add Transaction → Save
```

should not require:

```text
Are you sure?
```

after every action.

---

# 36. Empty States

Empty states should explain what the user can do next.

Bad:

```text
No data.
```

Better:

```text
No transactions yet.

Start tracking your finances
by adding your first transaction.

[ Add Transaction ]
```

---

# 37. Loading States

Loading indicators should be used only when work actually takes time.

For local operations, avoid unnecessary artificial loading animations.

The application should feel fast.

Skeleton loading may be useful for larger asynchronous operations.

---

# 38. Error States

Errors should:

* Explain what happened
* Avoid technical jargon
* Tell the user what they can do next

Example:

```text
Couldn't import your backup.

The file appears to be invalid or corrupted.

[ Try Again ]
```

---

# 39. Offline State

Because FinOS is offline-first, the absence of internet should generally not be treated as an error.

Do not show:

```text
No Internet Connection!
```

on every screen.

Only network-dependent functionality should communicate network state.

---

# 40. Success Feedback

Successful actions should provide lightweight confirmation where useful.

Examples:

```text
Transaction saved
```

```text
Budget updated
```

```text
Backup exported
```

Avoid intrusive dialogs for simple successful actions.

Snackbars, subtle transitions, or inline feedback may be preferred.

---

# 41. Swipe Actions

Swipe actions may be used for frequently performed operations such as:

* Archive
* Delete
* Mark/complete

However, destructive actions should not be too easy to trigger accidentally.

Critical financial actions should still have appropriate confirmation or undo mechanisms.

---

# 42. Undo

Where practical, destructive actions should provide an undo mechanism.

Example:

```text
Transaction deleted

[ Undo ]
```

Undo is preferable to unnecessary confirmation dialogs for reversible actions.

---

# 43. Accessibility

FinOS should support:

* Screen readers
* Dynamic font sizes
* Sufficient contrast
* Semantic labels
* Accessible controls
* Appropriate touch target sizes
* Non-color-based status communication

Do not encode financial meaning exclusively through:

* Color
* Icons
* Position

Use text and semantic labels where required.

---

# 44. Touch Targets

Interactive controls should have sufficiently large touch areas.

Do not create tiny icon-only buttons for important actions.

Examples of actions that require clear accessibility:

* Add transaction
* Save
* Delete
* Edit
* Account selection
* Category selection

---

# 45. Keyboard Behavior

Forms should be designed around mobile keyboards.

The application should:

* Use appropriate keyboard types
* Avoid keyboard obscuring the active field
* Provide logical focus order
* Dismiss keyboards appropriately
* Avoid unnecessary keyboard transitions

---

# 46. Animation

Animations should communicate state changes rather than exist purely for decoration.

Good examples:

* Adding a transaction
* Expanding a budget
* Navigating between related views
* Showing a new balance

Avoid:

* Long transitions
* Excessive bouncing
* Constant background animations
* Animations that delay user interaction

---

# 47. Charts

Charts may be used for:

* Spending by category
* Income vs expense
* Budget progress
* Cash flow
* Future financial analytics

Charts should supplement numerical information.

A chart must not be the only way to understand financial data.

Example:

```text
Food
৳12,500
32%
```

should accompany a visual chart.

---

# 48. Financial Information Formatting

Numbers should be formatted consistently.

Examples:

```text
৳1,500
৳25,000
৳1,250,000
```

Large numbers should remain readable.

Where appropriate:

```text
৳1.25M
```

may be used for high-level summaries, but detailed financial screens should display exact values.

---

# 49. Positive and Negative Values

The application should represent financial direction explicitly.

Examples:

```text
+৳80,000
-৳1,500
```

This is preferable to relying exclusively on color.

The exact sign convention should remain consistent throughout the application.

---

# 50. Privacy UX

Future privacy features should be compatible with the UI architecture.

Potential functionality:

```text
Hide Balances
App Lock
Privacy Mode
Mask Account Information
```

These are not required for V1 unless explicitly prioritized.

The design should not make these future capabilities impossible.

---

# 51. Notifications

Notifications are not a core V1 requirement.

Future notifications may include:

* Budget warnings
* Recurring transaction reminders
* Loan due dates
* Financial summaries

Notifications should not expose unnecessary sensitive financial information on lock screens.

For example, prefer:

```text
FinOS
You have a financial reminder.
```

over exposing:

```text
Your loan payment of ৳25,000 is due tomorrow.
```

unless the user explicitly chooses such detail.

---

# 52. Design Tokens

All reusable design values should be centralized.

Potential structure:

```text
Design Tokens
├── Colors
├── Typography
├── Spacing
├── Radius
├── Elevation
├── Icons
└── Motion
```

Widgets should consume tokens rather than hardcoding visual values.

---

# 53. Component Library

Reusable components should be created for repeated product patterns.

Potential components:

```text
FinOSButton
FinOSCard
MoneyText
AccountTile
TransactionTile
CategoryIcon
BudgetProgress
LoanSummary
EmptyState
ErrorState
```

The component library should grow organically.

Do not create custom components for one-off UI elements without a clear reason.

---

# 54. Naming

UI components should use names based on product concepts rather than implementation details.

Prefer:

```text
TransactionTile
```

over:

```text
BlueRoundedListItem
```

Prefer:

```text
MoneyText
```

over:

```text
LargeGreenText
```

This allows the design system to evolve without misleading names.

---

# 55. Responsive Layout

The application should support a range of mobile screen sizes.

Layouts should avoid:

* Hardcoded screen widths
* Hardcoded absolute positioning
* Content that depends on one device size
* Text that assumes a fixed width

Use Flutter's layout system appropriately.

---

# 56. Tablet Considerations

Tablet optimization is not a V1 priority.

However, the architecture should not prevent future adaptive layouts.

Future tablet UI may use:

```text
Navigation Rail
Split View
Master / Detail
Expanded Dashboard
```

The mobile information architecture should remain the source of truth initially.

---

# 57. Design Consistency Rules for AI Agents

AI agents must:

* Reuse existing components.
* Reuse theme tokens.
* Follow existing spacing.
* Follow established navigation patterns.
* Follow existing typography.
* Avoid introducing arbitrary colors.
* Avoid introducing arbitrary shadows.
* Avoid introducing new interaction patterns without justification.
* Check existing screens before creating similar components.

Before creating a new component, agents should search the codebase for an existing component that can be reused.

---

# 58. UI Implementation Rules

Agents should separate:

```text
UI
↓
State
↓
Domain
```

UI widgets should not:

* Perform database queries directly
* Calculate financial balances
* Implement budget logic
* Modify loans directly
* Parse backup files
* Call external APIs directly

Instead:

```text
Widget
   ↓
Controller / Application Layer
   ↓
Use Case
   ↓
Repository / Service
```

---

# 59. Visual Regression Awareness

When modifying shared components, agents should consider the impact on all screens using those components.

A change to:

```text
MoneyText
```

may affect:

* Dashboard
* Transactions
* Accounts
* Budgets
* Loans

Shared UI changes should therefore be reviewed across the application.

---

# 60. V1 Screen Inventory

The initial application should be designed around these screens:

```text
Core
├── Dashboard
├── Transactions
├── Transaction Details
├── Add Transaction
├── Edit Transaction
├── Accounts
├── Account Details
├── Add Account
├── Edit Account
├── Categories
├── Budgets
├── Budget Details
├── Loans
├── Loan Details
└── Settings
```

Additional screens should be introduced only when justified by requirements.

---

# 61. V1 UX Priority

When deciding between two UX implementations, prioritize:

```text
1. Correctness
2. User comprehension
3. Speed of common actions
4. Accessibility
5. Consistency
6. Visual polish
7. Animation
```

Visual novelty should never compromise financial clarity.

---

# 62. Future Product UX

FinOS may eventually expand into:

```text
Transactions
     │
     ├── Budgets
     ├── Loans
     ├── Investments
     ├── Portfolio
     ├── Net Worth
     ├── Automation
     └── AI Insights
```

The V1 UI should establish a foundation that can accommodate these features without placing them into the interface prematurely.

---

# 63. Final Design Principle

FinOS should follow this principle:

> **Make financial information effortless to record, effortless to understand, and difficult to misunderstand.**

The interface should not attempt to impress users with complexity.

It should make users feel that their finances are:

* Organized
* Understandable
* Under control

while keeping the application fast, private, and trustworthy.
