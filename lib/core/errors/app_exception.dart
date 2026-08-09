/// Base class for domain-aware application errors.
///
/// Provides a user-facing [message] and concrete subtypes for the most common
/// V1 error categories (see docs/DEVELOPMENT.md §19).
sealed class AppException implements Exception {
  const AppException(this.message);

  /// A human-readable description suitable for display.
  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The submitted data failed domain or format validation.
class ValidationException extends AppException {
  const ValidationException(super.message);
}

/// A persistence (database) operation failed.
class PersistenceException extends AppException {
  const PersistenceException(super.message);
}

/// An unexpected or unrecoverable failure.
class UnexpectedException extends AppException {
  const UnexpectedException(super.message);
}

/// Maps an arbitrary [error] to a user-facing string.
///
/// Intended for use at the presentation boundary (AGENTS.md §25).
String userMessageFor(Object error) {
  if (error is AppException) return error.message;
  return 'Something went wrong. Please try again.';
}
