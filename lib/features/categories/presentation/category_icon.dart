import 'package:flutter/material.dart';

/// Resolves a category's stored icon key to a Material [IconData].
///
/// Keys are stable strings (e.g. `'restaurant'`) stored in the database;
/// unknown or unset keys fall back to [Icons.label] so the UI never breaks on
/// data it doesn't recognise (docs/UI_DESIGN.md §17).
IconData categoryIcon(String key) {
  switch (key) {
    case 'restaurant':
      return Icons.restaurant;
    case 'directions_car':
      return Icons.directions_car;
    case 'home':
      return Icons.home;
    case 'shopping_bag':
      return Icons.shopping_bag;
    case 'movie':
      return Icons.movie;
    case 'bolt':
      return Icons.bolt;
    case 'favorite':
      return Icons.favorite;
    case 'school':
      return Icons.school;
    case 'payments':
      return Icons.payments;
    case 'design_services':
      return Icons.design_services;
    case 'card_giftcard':
      return Icons.card_giftcard;
    case 'trending_up':
      return Icons.trending_up;
    case 'flight':
      return Icons.flight;
    case 'local_cafe':
      return Icons.local_cafe;
    case 'pets':
      return Icons.pets;
    case 'fitness_center':
      return Icons.fitness_center;
    case 'phone_android':
      return Icons.phone_android;
    case 'savings':
      return Icons.savings;
    case 'label':
      return Icons.label;
    default:
      return Icons.label;
  }
}

/// A human-readable name for an icon key, for the icon picker's accessible
/// labels (docs/UI_DESIGN.md §43) — without this, a screen reader has no way
/// to distinguish one icon choice from another.
String categoryIconLabel(String key) {
  switch (key) {
    case 'restaurant':
      return 'Restaurant';
    case 'directions_car':
      return 'Car';
    case 'home':
      return 'Home';
    case 'shopping_bag':
      return 'Shopping';
    case 'movie':
      return 'Movie';
    case 'bolt':
      return 'Utilities';
    case 'favorite':
      return 'Health';
    case 'school':
      return 'Education';
    case 'payments':
      return 'Payments';
    case 'design_services':
      return 'Services';
    case 'card_giftcard':
      return 'Gift';
    case 'trending_up':
      return 'Investment';
    case 'flight':
      return 'Travel';
    case 'local_cafe':
      return 'Cafe';
    case 'pets':
      return 'Pets';
    case 'fitness_center':
      return 'Fitness';
    case 'phone_android':
      return 'Phone';
    case 'savings':
      return 'Savings';
    case 'label':
      return 'Label';
    default:
      return 'Label';
  }
}

/// Curated icon keys offered when creating a category.
///
/// Kept small and expressive so the picker stays usable on small screens;
/// users are not required to pick one (defaults to `'label'`).
const List<String> categoryIconKeys = [
  'restaurant',
  'directions_car',
  'home',
  'shopping_bag',
  'movie',
  'bolt',
  'favorite',
  'school',
  'payments',
  'design_services',
  'card_giftcard',
  'trending_up',
  'flight',
  'local_cafe',
  'pets',
  'fitness_center',
  'phone_android',
  'savings',
];
