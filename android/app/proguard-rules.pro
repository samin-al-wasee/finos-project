# Flutter's engine and plugin embedding ship their own consumer ProGuard rules
# via AAR metadata, so no manual keep rules are needed for the Flutter/Dart
# side. Native libraries (e.g. sqlite3) are untouched by R8 since they aren't
# JVM bytecode. Add plugin-specific keep rules here only if a release build
# crashes with a ClassNotFoundException/MissingMethodException that a debug
# build doesn't.
