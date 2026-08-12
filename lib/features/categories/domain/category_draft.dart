import 'category_type.dart';

/// A partial, unsaved set of pre-fill values for [CategoryFormScreen]'s
/// create flow.
class CategoryDraft {
  const CategoryDraft({this.name = '', this.type = CategoryType.expense});

  final String name;
  final CategoryType type;
}
