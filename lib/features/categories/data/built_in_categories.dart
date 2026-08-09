import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../domain/category_origin.dart';
import '../domain/category_status.dart';
import '../domain/category_type.dart';

/// The built-in categories FinOS provides (docs/DATA_MODEL.md §20).
///
/// Seeded once when the database is created or upgraded. IDs are deterministic
/// slugs so seeding is idempotent and references in tests stay stable. System
/// categories are protected from rename and destructive deletion.
final List<CategoriesCompanion> builtInCategories = [
  // Expense categories.
  CategoriesCompanion.insert(
    id: 'cat-food',
    name: 'Food',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('restaurant'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-transport',
    name: 'Transport',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('directions_car'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-rent',
    name: 'Rent',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('home'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-shopping',
    name: 'Shopping',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('shopping_bag'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-entertainment',
    name: 'Entertainment',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('movie'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-utilities',
    name: 'Utilities',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('bolt'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-health',
    name: 'Health',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('favorite'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-education',
    name: 'Education',
    type: CategoryType.expense,
    origin: Value(CategoryOrigin.system),
    icon: Value('school'),
    status: Value(CategoryStatus.active),
  ),
  // Income categories.
  CategoriesCompanion.insert(
    id: 'cat-salary',
    name: 'Salary',
    type: CategoryType.income,
    origin: Value(CategoryOrigin.system),
    icon: Value('payments'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-freelance',
    name: 'Freelance',
    type: CategoryType.income,
    origin: Value(CategoryOrigin.system),
    icon: Value('design_services'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-gift',
    name: 'Gift',
    type: CategoryType.income,
    origin: Value(CategoryOrigin.system),
    icon: Value('card_giftcard'),
    status: Value(CategoryStatus.active),
  ),
  CategoriesCompanion.insert(
    id: 'cat-investment',
    name: 'Investment',
    type: CategoryType.income,
    origin: Value(CategoryOrigin.system),
    icon: Value('trending_up'),
    status: Value(CategoryStatus.active),
  ),
];
