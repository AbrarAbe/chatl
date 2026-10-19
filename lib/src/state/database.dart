import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'database.g.dart';

/// Sessions table — spec §Data model. `activeHeadId` points at the head
/// message of the active branch (fork-on-edit).
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get model => text()();
  TextColumn get persona => text()();
  TextColumn get activeHeadId => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

/// Messages table — spec §Data model. `parentId` links the branch chain;
/// `sources` is nullable JSON `[{url, title}]`, shipping empty in v1.
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(Sessions, #id)();
  TextColumn get parentId => text().nullable()();
  TextColumn get role => text()();
  TextColumn get content => text()();
  TextColumn get model => text().nullable()();
  IntColumn get promptTokens => integer().nullable()();
  IntColumn get completionTokens => integer().nullable()();
  TextColumn get sources => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>>? get primaryKey => {id};
}

@DriftDatabase(tables: [Sessions, Messages])
class ChatlDatabase extends _$ChatlDatabase {
  ChatlDatabase(String path) : super(NativeDatabase(File(path)));

  /// In-memory database for tests.
  ChatlDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;
}
