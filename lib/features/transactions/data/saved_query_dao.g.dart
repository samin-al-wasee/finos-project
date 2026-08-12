// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'saved_query_dao.dart';

// ignore_for_file: type=lint
mixin _$SavedQueryDaoMixin on DatabaseAccessor<AppDatabase> {
  $SavedQueriesTable get savedQueries => attachedDatabase.savedQueries;
  SavedQueryDaoManager get managers => SavedQueryDaoManager(this);
}

class SavedQueryDaoManager {
  final _$SavedQueryDaoMixin _db;
  SavedQueryDaoManager(this._db);
  $$SavedQueriesTableTableManager get savedQueries =>
      $$SavedQueriesTableTableManager(_db.attachedDatabase, _db.savedQueries);
}
