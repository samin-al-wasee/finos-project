import 'package:drift/drift.dart';

import '../../categories/data/category_table.dart';
import 'budget_table.dart';

/// Join table holding a `MULTI_CATEGORY` budget's member categories
/// (docs/DATA_MODEL.md §22, docs/adr/007-flexible-budget-scope.md).
///
/// Only ever populated when [Budgets.scopeType] is `MULTI_CATEGORY`, with at
/// least two rows per budget — a single-row "multi" budget is indistinguishable
/// from `SINGLE_CATEGORY` and is rejected by validation
/// (`BudgetController`). `SINGLE_CATEGORY`/`UNCATEGORIZED`/`WHOLE_ACCOUNT`
/// budgets never have rows here.
@DataClassName('BudgetCategoryRow')
class BudgetCategories extends Table {
  TextColumn get budgetId => text().references(Budgets, #id)();
  TextColumn get categoryId => text().references(Categories, #id)();

  @override
  Set<Column<Object>> get primaryKey => {budgetId, categoryId};
}
